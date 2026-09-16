#define _XOPEN_SOURCE 700
#include <regex.h>

/* Owned index storage for the bounded evaluator's value arena. */
#include <limits.h>
#include <stdint.h>
#include <stdlib.h>

typedef struct {
    int32_t *data;
    size_t count;
    size_t capacity;
} IndexBuffer;

static void *rawBufferCreate(int32_t capacity, int32_t stride)
{
    if (capacity < 0 || stride != sizeof(int32_t)
        || (size_t)capacity > SIZE_MAX / sizeof(int32_t)) return NULL;
    IndexBuffer *buffer = calloc(1, sizeof(*buffer));
    if (!buffer) abort();
    if (capacity) {
        buffer->data = malloc((size_t)capacity * sizeof(*buffer->data));
        if (!buffer->data) abort();
    }
    buffer->capacity = (size_t)capacity;
    return buffer;
}

static int32_t rawBufferAppendInt(void *opaque, int32_t value)
{
    IndexBuffer *buffer = opaque;
    if (!buffer || buffer->count >= INT32_MAX) return -1;
    if (buffer->count == buffer->capacity) {
        size_t capacity = buffer->capacity ? buffer->capacity * 2 : 16;
        if (capacity > INT32_MAX) capacity = INT32_MAX;
        if (capacity > SIZE_MAX / sizeof(*buffer->data)) return -1;
        int32_t *data = realloc(buffer->data, capacity * sizeof(*data));
        if (!data) abort();
        buffer->data = data;
        buffer->capacity = capacity;
    }
    buffer->data[buffer->count++] = value;
    return 0;
}

static int32_t rawBufferCount(void *opaque)
{
    IndexBuffer *buffer = opaque;
    return buffer ? (int32_t)buffer->count : -1;
}

static int32_t rawBufferLoadInt(void *opaque, int32_t index)
{
    IndexBuffer *buffer = opaque;
    if (!buffer || index < 0 || (size_t)index >= buffer->count) abort();
    return buffer->data[index];
}

static int32_t rawBufferStoreInt(void *opaque, int32_t index, int32_t value)
{
    IndexBuffer *buffer = opaque;
    if (!buffer || index < 0 || (size_t)index >= buffer->count) return -1;
    buffer->data[index] = value;
    return 0;
}

static int32_t rawBufferDestroy(void *opaque)
{
    IndexBuffer *buffer = opaque;
    if (!buffer) return -1;
    free(buffer->data);
    free(buffer);
    return 0;
}

/* Compiler execution kernel. Aggregates have monotonic heap identities;
 * scalars are values. The host buffers store indexes into our value arena, never
 * truncated pointers or truncated Range Ints. */
#include "model.h"
#include <inttypes.h>
#include <limits.h>
#include <setjmp.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>


typedef enum { VVoid, VInt, VBool, VObject, VMany, VEnum, VType } Kind;
typedef struct Object Object;
typedef struct { Kind kind; int64_t number; Object *object; RangeNode *type; } Value;
typedef struct Slot Slot;
struct Slot { const char *name; Value value; int mutable; Slot *next; RangeNode *declaration; int initialized; };
struct Object {
    uint64_t identity;
    Kind kind;
    RangeNode *type;
    RangeNode *variant;
    Slot *fields;
    void *buffer;
    int destroyed;
    const char *elementType;
    Object *next;
};
typedef struct Scope Scope;
struct Scope { Slot *slots; Scope *parent; Value receiver; const char *resultType; int resultFlags; };
typedef struct { Value value; int returned; } Flow;
typedef struct {
    RangeArena *arena;
    RangeNode **units;
    size_t count;
    Object *objects;
    uint64_t nextIdentity;
    Value *values;
    size_t valueCount, valueCapacity;
    uint64_t steps;
    unsigned depth;
    RangeNode **boundFunctions;
    size_t boundCount, boundCapacity;
    char *error;
    size_t errorSize;
    jmp_buf failure;
} VM;

static Value eval(VM *, Scope *, RangeNode *, const char *);
static Flow block(VM *, Scope *, RangeNode *);
static Value invoke(VM *, Scope *, RangeNode *, Value, RangeNode *, Value *);
static Value initialize(VM *, Scope *, RangeNode *);
static Value coerce(VM *, RangeNode *, Value, const char *, int);
static void bindFunction(VM *,RangeNode *);
static Value integer(int64_t n) { return (Value){.kind=VInt,.number=n}; }
static Value boolean(int n) { return (Value){.kind=VBool,.number=!!n}; }
static Value nothing(void) { return (Value){.kind=VVoid}; }
static int same(const char *a,const char *b) { return a && b && !strcmp(a,b); }

_Noreturn static void fail(VM *vm, RangeNode *at, const char *format, ...)
{
    char detail[384]; va_list args; va_start(args,format);
    vsnprintf(detail,sizeof(detail),format,args); va_end(args);
    snprintf(vm->error,vm->errorSize,"%s:%d:%d: %s",at->path,at->line,at->column,detail);
    longjmp(vm->failure,1);
}
static void annotations(VM *vm,RangeNode *node) {
    if(!node->annotations) return;
    for(size_t i=0;i<node->annotations->itemCount;i++) {
        RangeNode *a=node->annotations->items[i];
        if(a->generics) fail(vm,a,"generic specialization execution is not implemented");
        if(node->kind!=RangeNodeLocal || !same(a->name,"many") || a->itemCount)
            fail(vm,a,"annotation execution is not implemented");
    }
}
static void tick(VM *vm,RangeNode *at) {
    if (++vm->steps > UINT64_C(100000000)) fail(vm,at,"compiler execution step limit exceeded");
}
static void *allocate(VM *vm,size_t size) {
    void *p=rangeArenaAllocate(vm->arena,size); memset(p,0,size); return p;
}
static RangeNode *nominal(VM *vm,const char *name,RangeNode *at) {
    RangeNode *found=NULL;
    for(size_t u=0;u<vm->count;u++) for(size_t i=0;i<vm->units[u]->itemCount;i++) {
        RangeNode *d=vm->units[u]->items[i];
        if ((d->kind==RangeNodeConstruct || d->kind==RangeNodeEnum) && same(d->name,name)) {
            if(found) fail(vm,at,"ambiguous type '%s'",name); found=d;
        }
    }
    return found;
}
static Object *object(VM *vm,Kind kind,RangeNode *type) {
    Object *o=allocate(vm,sizeof(*o)); o->kind=kind; o->type=type;
    o->identity=++vm->nextIdentity; o->next=vm->objects; vm->objects=o; return o;
}
static Value reference(Object *o) { return (Value){.kind=o->kind,.object=o,.type=o->type}; }
static void alive(VM *vm,Value v,RangeNode *at) {
    if(v.object && v.object->destroyed) fail(vm,at,"use of destroyed aggregate #%" PRIu64,v.object->identity);
}
static Slot *slot(Slot *s,const char *name) { for(;s;s=s->next) if(same(s->name,name)) return s; return NULL; }
static Slot *lookup(Scope *s,const char *name) {
    for(;s;s=s->parent) { Slot *v=slot(s->slots,name); if(v) return v; } return NULL;
}
static void bind(VM *vm,Scope *s,const char *name,Value value,int mutable,RangeNode *at) {
    if(slot(s->slots,name)) fail(vm,at,"duplicate local '%s'",name);
    Slot *v=allocate(vm,sizeof(*v)); *v=(Slot){name,value,mutable,s->slots,at,1}; s->slots=v;
}
static int64_t number(VM *vm,Value v,RangeNode *at) {
    if(v.kind!=VInt) fail(vm,at,"expected Int"); return v.number;
}
static int truth(VM *vm,Value v,RangeNode *at) {
    if(v.kind!=VBool) fail(vm,at,"condition must be Bool"); return v.number!=0;
}
static Value many(VM *vm,RangeNode *at,const char *type,int64_t capacity) {
    if(capacity<0 || capacity>INT32_MAX) fail(vm,at,"invalid collection capacity");
    Object *o=object(vm,VMany,NULL); o->elementType=type && *type ? type:NULL;
    o->buffer=rawBufferCreate((int32_t)capacity,4);
    if(!o->buffer) fail(vm,at,"collection allocation failed"); return reference(o);
}
static int32_t save(VM *vm,Value value,RangeNode *at) {
    if(vm->valueCount==INT32_MAX) fail(vm,at,"compiler value limit exceeded");
    if(vm->valueCount==vm->valueCapacity) {
        size_t capacity=vm->valueCapacity ? vm->valueCapacity*2:256;
        Value *values=realloc(vm->values,capacity*sizeof(Value));
        if(!values) fail(vm,at,"compiler value allocation failed");
        vm->values=values; vm->valueCapacity=capacity;
    }
    vm->values[vm->valueCount]=value; return (int32_t)vm->valueCount++;
}
static int32_t count(VM *vm,Value v,RangeNode *at) {
    alive(vm,v,at); if(v.kind!=VMany) fail(vm,at,"expected @many"); return rawBufferCount(v.object->buffer);
}
static Value element(VM *vm,Value v,int64_t i,RangeNode *at) {
    int32_t n=count(vm,v,at); if(i<0 || i>=n) fail(vm,at,"collection index out of bounds");
    return vm->values[rawBufferLoadInt(v.object->buffer,(int32_t)i)];
}
static void append(VM *vm,Value v,Value item,RangeNode *at) {
    count(vm,v,at); item=coerce(vm,at,item,v.object->elementType,0);
    if(!v.object->elementType && item.type) v.object->elementType=item.type->name;
    if(rawBufferAppendInt(v.object->buffer,save(vm,item,at))) fail(vm,at,"collection append failed");
}
static Value string(VM *vm,const char *bytes,size_t length,RangeNode *at) {
    RangeNode *type=nominal(vm,"String",at);
    if(!type) fail(vm,at,"String declaration is not loaded");
    Object *o=object(vm,VObject,type); Scope fields={0}; Value data=many(vm,at,"Byte",(int64_t)length);
    for(size_t i=0;i<length;i++) append(vm,data,integer((unsigned char)bytes[i]),at);
    bind(vm,&fields,"bytes",data,1,at); o->fields=fields.slots; return reference(o);
}
static Value stringBytes(VM *vm,Value v,RangeNode *at) {
    alive(vm,v,at); if(v.kind!=VObject || !same(v.type->name,"String")) fail(vm,at,"expected String");
    Slot *s=slot(v.object->fields,"bytes"); if(!s) fail(vm,at,"String has no bytes");
    count(vm,s->value,at); return s->value;
}
static char *text(VM *vm,Value v,size_t *length,RangeNode *at) {
    Value bytes=stringBytes(vm,v,at); *length=(size_t)count(vm,bytes,at);
    char *out=allocate(vm,*length+1);
    for(size_t i=0;i<*length;i++) out[i]=(char)number(vm,element(vm,bytes,(int64_t)i,at),at);
    return out;
}
static int equal(VM *vm,Value a,Value b,RangeNode *at) {
    alive(vm,a,at); alive(vm,b,at);
    if(a.kind!=b.kind) return 0;
    if(a.kind==VInt || a.kind==VBool) return a.number==b.number;
    if(a.kind==VVoid) return 1;
    if(a.kind==VObject && a.type==b.type && same(a.type->name,"String")) {
        size_t x,y; char *p=text(vm,a,&x,at),*q=text(vm,b,&y,at); return x==y && !memcmp(p,q,x);
    }
    if(a.kind==VEnum) {
        if(a.type!=b.type || a.object->variant!=b.object->variant) return 0;
        for(Slot *s=a.object->fields;s;s=s->next) {
            Slot *other=slot(b.object->fields,s->name);
            if(!other || !equal(vm,s->value,other->value,at)) return 0;
        }
        return 1;
    }
    return a.object==b.object && a.type==b.type;
}
static Value coerce(VM *vm,RangeNode *at,Value v,const char *type,int flags) {
    alive(vm,v,at);
    if(flags & RangeFlagOptional) fail(vm,at,"optional execution is not implemented");
    if(flags & RangeFlagMany) {
        count(vm,v,at);
        if(type && *type) {
            if(v.object->elementType && !same(type,v.object->elementType)) fail(vm,at,"collection element type mismatch");
            for(int32_t i=0;i<count(vm,v,at);i++) (void)coerce(vm,at,element(vm,v,i,at),type,0);
            v.object->elementType=type;
        }
        return v;
    }
    if(!type || !*type) return v;
    if(same(type,"Int") || same(type,"Byte")) {
        number(vm,v,at); if(same(type,"Byte") && (v.number<0 || v.number>255)) fail(vm,at,"Byte out of range");
        v.type=nominal(vm,type,at); return v;
    }
    if(same(type,"Bool")) { truth(vm,v,at); v.type=nominal(vm,type,at); return v; }
    if(same(type,"Void") && v.kind==VVoid) return v;
    RangeNode *expected=nominal(vm,type,at);
    if(!expected || v.type!=expected) fail(vm,at,"value does not match type '%s'",type);
    return v;
}
static RangeNode *memberDeclaration(RangeNode *type,const char *name) {
    if(!type) return NULL;
    for(size_t i=0;i<type->itemCount;i++) {
        RangeNode *m=type->items[i]; if(m->kind==RangeNodeMember && same(m->name,name)) return m;
    }
    return NULL;
}
static Value member(VM *vm,Scope *scope,Value receiver,const char *name,RangeNode *at) {
    alive(vm,receiver,at);
    if(receiver.kind==VMany && same(name,"count")) return integer(count(vm,receiver,at));
    if(receiver.kind==VObject || receiver.kind==VEnum) {
        Slot *s=slot(receiver.object->fields,name); if(s) { alive(vm,s->value,at); return s->value; }
        RangeNode *m=memberDeclaration(receiver.type,name);
        if(m && (m->flags & RangeFlagDerived)) {
            Scope local={.parent=scope,.receiver=receiver,.resultType=m->typeName,.resultFlags=m->flags};
            Flow f=block(vm,&local,m->a); return coerce(vm,at,f.value,m->typeName,m->flags);
        }
    }
    fail(vm,at,"unknown member '%s'",name);
}
static const char *label(RangeNode *parameter) {
    return parameter->name;
}
static int labelsMatch(RangeNode *function,RangeNode *call) {
    if(function->itemCount!=call->itemCount) return 0;
    for(size_t i=0;i<call->itemCount;i++) {
        const char *a=label(function->items[i]),*b=call->items[i]->name;
        if((a || b) && !same(a,b)) return 0;
    }
    return 1;
}
static RangeNode *resolve(VM *vm,Value receiver,const char *name,RangeNode *call) {
    RangeNode *found=NULL;
    for(size_t u=0;u<vm->count;u++) for(size_t i=0;i<vm->units[u]->itemCount;i++) {
        RangeNode *d=vm->units[u]->items[i];
        if(receiver.kind!=VVoid) {
            if(d!=receiver.type) continue;
            for(size_t m=0;m<d->itemCount;m++) {
                RangeNode *f=d->items[m];
                if(f->kind==RangeNodeFunction && same(f->name,name) && labelsMatch(f,call)) {
                    if(found) fail(vm,call,"ambiguous method '%s'",name); found=f;
                }
            }
        } else if(d->kind==RangeNodeFunction && same(d->name,name) && labelsMatch(d,call)) {
            if(found) fail(vm,call,"ambiguous function '%s'",name); found=d;
        }
    }
    if(!found) fail(vm,call,"unresolved call '%s' (receiver, labels or arity)",name);
    return found;
}
static Value collectionCall(VM *vm,Value receiver,const char *name,RangeNode *call,Value *args) {
    /* These are the @many storage operations, not arbitrary method fallbacks. */
    int n=count(vm,receiver,call);
    const char *first=call->itemCount ? call->items[0]->name:NULL;
    if(same(name,"destroy") && !call->itemCount) {
        if(rawBufferDestroy(receiver.object->buffer)) fail(vm,call,"collection destroy failed");
        receiver.object->buffer=NULL; receiver.object->destroyed=1; return integer(0);
    }
    if(same(name,"element") && call->itemCount==1 && same(first,"index")) return element(vm,receiver,number(vm,args[0],call),call);
    if(same(name,"append") && call->itemCount==1 && same(first,"element")) { append(vm,receiver,args[0],call); return integer(0); }
    if(same(name,"append") && call->itemCount==1 && same(first,"contentsOf")) {
        int size=count(vm,args[0],call);
        for(int i=0;i<size;i++) append(vm,receiver,element(vm,args[0],i,call),call);
        return integer(0);
    }
    if(same(name,"update") && call->itemCount==2 && same(first,"element") && same(call->items[1]->name,"index")) {
        int64_t index=number(vm,args[1],call); (void)element(vm,receiver,index,call);
        Value v=coerce(vm,call,args[0],receiver.object->elementType,0);
        if(rawBufferStoreInt(receiver.object->buffer,(int32_t)index,save(vm,v,call))) fail(vm,call,"collection update failed");
        return integer(0);
    }
    if(same(name,"firstIndex") && call->itemCount==1 && same(first,"value")) {
        for(int i=0;i<n;i++) if(equal(vm,element(vm,receiver,i,call),args[0],call)) return integer(i);
        return integer(-1);
    }
    if(same(name,"slice") && call->itemCount==2 && same(first,"start") && same(call->items[1]->name,"end")) {
        int64_t start=number(vm,args[0],call),end=number(vm,args[1],call);
        if(start<0 || end<start || end>n) fail(vm,call,"invalid collection slice");
        Value out=many(vm,call,receiver.object->elementType,end-start);
        for(int64_t i=start;i<end;i++) append(vm,out,element(vm,receiver,i,call),call);
        return out;
    }
    fail(vm,call,"unsupported collection operation '%s' or argument labels",name);
}
static Value construct(VM *vm,Scope *scope,RangeNode *type,RangeNode *call,Value *args) {
    if(type->kind!=RangeNodeConstruct) fail(vm,call,"enum construction requires a case");
    Object *o=object(vm,VObject,type); Scope fields={.parent=scope,.receiver=reference(o)};
    size_t supplied=0;
    for(size_t i=0;i<type->itemCount;i++) {
        RangeNode *m=type->items[i]; if(m->kind!=RangeNodeMember || (m->flags & RangeFlagDerived)) continue;
        size_t match=SIZE_MAX;
        for(size_t a=0;a<call->itemCount;a++) if(same(call->items[a]->name,m->name)) {
            if(match!=SIZE_MAX) fail(vm,call,"duplicate constructor argument '%s'",m->name); match=a;
        }
        Value v;
        if(match!=SIZE_MAX) {
            const char *expected=m->typeName;
            if(m->rhsReference) {
                Value target=eval(vm,&fields,m->rhsReference,NULL);
                expected=target.type?target.type->name:target.kind==VInt?"Int":target.kind==VBool?"Bool":NULL;
            }
            v=coerce(vm,call,args[match],expected,m->flags); supplied++;
        }
        else if(m->itemCount || m->rhsReference || (m->flags & (RangeFlagMany|RangeFlagApplication))) v=initialize(vm,&fields,m);
        else fail(vm,call,"missing constructor argument '%s'",m->name);
        bind(vm,&fields,m->name,v,!!(m->flags & (RangeFlagMutable|RangeFlagBinding)),m);
        o->fields=fields.slots;
    }
    if(supplied!=call->itemCount) fail(vm,call,"unknown constructor argument");
    o->fields=fields.slots; return reference(o);
}
static Value enumeration(VM *vm,Scope *scope,RangeNode *type,const char *name,RangeNode *call) {
    if(!type || type->kind!=RangeNodeEnum) fail(vm,call,"enum case requires an unambiguous expected type");
    RangeNode *variant=NULL;
    for(size_t i=0;i<type->itemCount;i++) if(same(type->items[i]->name,name)) variant=type->items[i];
    if(!variant || variant->itemCount!=call->itemCount) fail(vm,call,"unknown enum case or payload arity '%s'",name);
    Object *o=object(vm,VEnum,type); o->variant=variant; Scope fields={0};
    for(size_t i=0;i<variant->itemCount;i++) {
        RangeNode *p=variant->items[i];
        if(!same(p->name,call->items[i]->name)) fail(vm,call,"enum payload label mismatch");
        if(!p->a || p->a->kind!=RangeNodeName) fail(vm,call,"unsupported enum payload type");
        Value v=eval(vm,scope,call->items[i]->a,p->a->name);
        bind(vm,&fields,p->name,coerce(vm,call,v,p->a->name,0),0,call);
    }
    o->fields=fields.slots; return reference(o);
}
static Value call(VM *vm,Scope *scope,RangeNode *node,const char *expected) {
    RangeNode *target=node->a;
    if(target->kind==RangeNodeCase) return enumeration(vm,scope,nominal(vm,expected,node),target->name,node);
    Value receiver=nothing(); const char *name=target->name;
    if(target->kind==RangeNodeMemberAccess) {
        receiver=eval(vm,scope,target->a,NULL);
        if(receiver.kind==VType && receiver.type->kind==RangeNodeEnum) return enumeration(vm,scope,receiver.type,name,node);
    } else if(target->kind!=RangeNodeName) fail(vm,node,"unsupported call target");
    Value *args=allocate(vm,(node->itemCount+1)*sizeof(Value));
    RangeNode *type=receiver.kind==VVoid ? nominal(vm,name,node):NULL;
    if(type && (same(name,"Int") || same(name,"Byte") || same(name,"Bool") || same(name,"String"))
        && node->itemCount==1 && (!node->items[0]->name || ((same(name,"Int") || same(name,"Byte")) && same(node->items[0]->name,"bits")))) {
        return coerce(vm,node,eval(vm,scope,node->items[0]->a,name),name,0);
    }
    RangeNode *function=NULL;
    if(!type && receiver.kind!=VMany) {
        function=node->resolvedDeclaration;
        if(!function) fail(vm,node,"call was not statically bound");
    }
    for(size_t i=0;i<node->itemCount;i++) {
        const char *argumentType=NULL;
        if(function) argumentType=function->items[i]->b->name;
        else if(type) { RangeNode *m=memberDeclaration(type,node->items[i]->name); if(m && !(m->flags&RangeFlagMany)) argumentType=m->typeName; }
        args[i]=eval(vm,scope,node->items[i]->a,argumentType);
    }
    if(type) return construct(vm,scope,type,node,args);
    if(receiver.kind==VMany) return collectionCall(vm,receiver,name,node,args);
    return invoke(vm,scope,function,receiver,node,args);
}
static Value binary(VM *vm,RangeNode *node,Value a,Value b) {
    const char *op=node->name;
    if(same(op,"==")) return boolean(equal(vm,a,b,node));
    if(same(op,"!=")) return boolean(!equal(vm,a,b,node));
    if(same(op,"+") && a.kind==VObject && same(a.type->name,"String")) {
        size_t x,y; char *p=text(vm,a,&x,node),*q=text(vm,b,&y,node),*out=allocate(vm,x+y);
        memcpy(out,p,x); memcpy(out+x,q,y); return string(vm,out,x+y,node);
    }
    int64_t x=number(vm,a,node),y=number(vm,b,node),z=0;
    if(same(op,"<")) return boolean(x<y); if(same(op,">")) return boolean(x>y);
    if(same(op,"<=")) return boolean(x<=y); if(same(op,">=")) return boolean(x>=y);
    int overflow=0;
    if(same(op,"+")) overflow=__builtin_add_overflow(x,y,&z);
    else if(same(op,"-")) overflow=__builtin_sub_overflow(x,y,&z);
    else if(same(op,"*")) overflow=__builtin_mul_overflow(x,y,&z);
    else if(same(op,"/") || same(op,"%")) {
        if(y==0 || (x==INT64_MIN && y==-1)) fail(vm,node,"invalid integer division");
        z=same(op,"/") ? x/y:x%y;
    } else fail(vm,node,"unsupported operator '%s'",op);
    if(overflow) fail(vm,node,"integer overflow"); return integer(z);
}
static Value eval(VM *vm,Scope *scope,RangeNode *node,const char *expected) {
    if(!node) return nothing(); tick(vm,node);
    switch(node->kind) {
    case RangeNodeInteger:
        if(strchr(node->name,'.')) fail(vm,node,"decimal/version literal execution is not implemented");
        return integer(node->integer);
    case RangeNodeBool: return boolean(node->integer);
    case RangeNodeName: {
        if(same(node->name,"self")) { alive(vm,scope->receiver,node); return scope->receiver; }
        Slot *s=lookup(scope,node->name); if(s) { if(!s->initialized) fail(vm,node,"read before initialization: '%s'",node->name); alive(vm,s->value,node); return s->value; }
        if(scope->receiver.kind==VObject && memberDeclaration(scope->receiver.type,node->name)) return member(vm,scope,scope->receiver,node->name,node);
        RangeNode *type=nominal(vm,node->name,node); if(type) return (Value){.kind=VType,.type=type};
        fail(vm,node,"unresolved name '%s'",node->name);
    }
    case RangeNodeMemberAccess: return member(vm,scope,eval(vm,scope,node->a,NULL),node->name,node);
    case RangeNodeCall: return call(vm,scope,node,expected);
    case RangeNodeCase: { RangeNode empty=*node; empty.itemCount=0; return enumeration(vm,scope,nominal(vm,expected,node),node->name,&empty); }
    case RangeNodeManyLiteral: {
        if(!same(node->name,"many")) fail(vm,node,"only @many storage is executable in this slice");
        int64_t capacity=0;
        if(node->itemCount) {
            if(node->itemCount!=1 || !same(node->items[0]->name,"capacity")) fail(vm,node,"unsupported @many initializer");
            capacity=number(vm,eval(vm,scope,node->items[0]->a,"Int"),node);
        }
        return many(vm,node,NULL,capacity);
    }
    case RangeNodeString: {
        Value out=string(vm,"",0,node),bytes=stringBytes(vm,out,node);
        for(size_t i=0;i<node->itemCount;i++) {
            RangeNode *p=node->items[i]; const char *data=NULL; size_t length=0; char scalar[64];
            if(p->flags & RangeFlagLiteral) { data=p->name; length=(size_t)p->integer; }
            else {
                Value v=eval(vm,scope,p->a,NULL);
                if(v.kind==VInt) { snprintf(scalar,sizeof(scalar),"%" PRId64,v.number); data=scalar; length=strlen(data); }
                else if(v.kind==VBool) { data=v.number?"true":"false"; length=strlen(data); }
                else data=text(vm,v,&length,p);
            }
            for(size_t j=0;j<length;j++) append(vm,bytes,integer((unsigned char)data[j]),p);
        }
        return out;
    }
    case RangeNodeUnary: {
        Value v=eval(vm,scope,node->a,NULL);
        if(same(node->name,"!")) return boolean(!truth(vm,v,node));
        int64_t n=number(vm,v,node); if(n==INT64_MIN) fail(vm,node,"integer overflow"); return integer(-n);
    }
    case RangeNodeBinary: {
        Value a=eval(vm,scope,node->a,NULL);
        if(same(node->name,"&&")) return boolean(truth(vm,a,node) && truth(vm,eval(vm,scope,node->b,NULL),node));
        if(same(node->name,"||")) return boolean(truth(vm,a,node) || truth(vm,eval(vm,scope,node->b,NULL),node));
        const char *type=a.type ? a.type->name:NULL;
        return binary(vm,node,a,eval(vm,scope,node->b,type));
    }
    default: fail(vm,node,"execution of %s is not implemented",rangeNodeKindName(node->kind));
    }
}
static Value initialize(VM *vm,Scope *scope,RangeNode *node) {
    if(node->generics) fail(vm,node,"generic specialization execution is not implemented");
    if(node->rhsReference && !(node->flags & RangeFlagMany)) {
        RangeNode *declaration=node->rhsReference->resolvedDeclaration;
        for(Scope *current=scope;current;current=current->parent) {
            for(Slot *s=current->slots;s;s=s->next) if(declaration && s->declaration==declaration) {
                if(!s->initialized) fail(vm,node,"read before initialization: '%s'",s->name);
                alive(vm,s->value,node); return s->value;
            }
        }
        Value value=eval(vm,scope,node->rhsReference,NULL);
        if(value.kind==VType) fail(vm,node,"local requirement '%s' has no supplied value",node->name);
        return value;
    }
    if(node->flags & RangeFlagMany) {
        if(node->itemCount==1 && !node->items[0]->name) return coerce(vm,node,eval(vm,scope,node->items[0]->a,NULL),node->typeName,node->flags);
        if(node->itemCount>1 || (node->itemCount==1 && !same(node->items[0]->name,"capacity"))) fail(vm,node,"unsupported @many declaration initializer");
        int64_t capacity=node->itemCount ? number(vm,eval(vm,scope,node->items[0]->a,"Int"),node):0;
        return many(vm,node,node->typeName,capacity);
    }
    if(node->itemCount==1 && !node->items[0]->name) return coerce(vm,node,eval(vm,scope,node->items[0]->a,node->typeName),node->typeName,node->flags);
    RangeNode *type=nominal(vm,node->typeName,node);
    if(!type) fail(vm,node,"missing or unsupported local initializer");
    Value *args=allocate(vm,(node->itemCount+1)*sizeof(Value));
    for(size_t i=0;i<node->itemCount;i++) {
        RangeNode *m=memberDeclaration(type,node->items[i]->name);
        args[i]=eval(vm,scope,node->items[i]->a,m && !(m->flags&RangeFlagMany)?m->typeName:NULL);
    }
    return construct(vm,scope,type,node,args);
}
static Flow statement(VM *vm,Scope *scope,RangeNode *node) {
    tick(vm,node);
    annotations(vm,node);
    switch(node->kind) {
    case RangeNodeLocal: {
        if(node->rhsReference && node->rhsReference->resolvedDeclaration
           && (node->rhsReference->resolvedDeclaration->kind==RangeNodeConstruct
               || node->rhsReference->resolvedDeclaration->kind==RangeNodeEnum)
           && !(node->flags&RangeFlagMany)) {
            Value v={.kind=VVoid,.type=node->rhsReference->resolvedDeclaration};
            bind(vm,scope,node->name,v,!!(node->flags&RangeFlagMutable),node);
            scope->slots->initialized=0; return (Flow){nothing(),0};
        }
        Value v=initialize(vm,scope,node); bind(vm,scope,node->name,v,!!(node->flags&RangeFlagMutable),node); return (Flow){v,0};
    }
    case RangeNodeAssign: {
        Slot *s=NULL;
        if(node->a->kind==RangeNodeName) s=lookup(scope,node->a->name);
        else if(node->a->kind==RangeNodeMemberAccess) {
            Value receiver=eval(vm,scope,node->a->a,NULL); alive(vm,receiver,node);
            if(receiver.kind==VObject) s=slot(receiver.object->fields,node->a->name);
        }
        if(!s || (!s->mutable && s->initialized)) fail(vm,node,"assignment requires mutable storage");
        Value v=eval(vm,scope,node->b,s->value.type ? s->value.type->name:NULL);
        if(s->initialized && s->value.kind!=v.kind) fail(vm,node,"assignment type mismatch");
        if(s->value.type) v=coerce(vm,node,v,s->value.type->name,0);
        s->value=v; s->initialized=1; return (Flow){v,0};
    }
    case RangeNodeReturn: return (Flow){eval(vm,scope,node->a,scope->resultType),1};
    case RangeNodeExpressionStatement: return (Flow){eval(vm,scope,node->a,NULL),0};
    case RangeNodeBlock: return block(vm,scope,node);
    case RangeNodeIf: {
        if(truth(vm,eval(vm,scope,node->a,"Bool"),node)) return block(vm,scope,node->b);
        if(node->c) return statement(vm,scope,node->c); return (Flow){nothing(),0};
    }
    case RangeNodeWhile:
        while(truth(vm,eval(vm,scope,node->a,"Bool"),node)) { tick(vm,node); Flow f=block(vm,scope,node->b); if(f.returned) return f; }
        return (Flow){nothing(),0};
    case RangeNodeSwitch: {
        Value v=eval(vm,scope,node->a,NULL); RangeNode *fallback=NULL;
        for(size_t i=0;i<node->itemCount;i++) {
            RangeNode *arm=node->items[i]; if(arm->flags&RangeFlagLiteral) { if(fallback) fail(vm,arm,"duplicate default"); fallback=arm; continue; }
            Value pattern=eval(vm,scope,arm->a,v.type?v.type->name:NULL);
            int match;
            if(arm->name) { RangeNode comparison=*arm; comparison.name=arm->name; match=truth(vm,binary(vm,&comparison,v,pattern),arm); }
            else match=equal(vm,v,pattern,arm);
            if(match) return block(vm,scope,arm->b);
        }
        if(fallback) return block(vm,scope,fallback->b);
        fail(vm,node,"no matching switch case");
    }
    default: fail(vm,node,"execution of %s is not implemented",rangeNodeKindName(node->kind));
    }
}
static Flow block(VM *vm,Scope *parent,RangeNode *node) {
    if(!node) fail(vm,vm->units[0],"missing executable body");
    Scope local={.parent=parent,.receiver=parent->receiver,.resultType=parent->resultType,.resultFlags=parent->resultFlags}; Flow result={nothing(),0};
    for(size_t i=0;i<node->itemCount;i++) { result=statement(vm,&local,node->items[i]); if(result.returned) break; }
    return result;
}
/* A closed ABI inventory, checked during binding, before any effects occur. */
static const char *externSymbol(VM *vm,RangeNode *f) {
    const char *symbol=f->name;
    for(size_t i=0;i<f->c->itemCount;i++) {
        RangeNode *a=f->c->items[i];
        if(same(a->name,"builtin") && !a->itemCount) continue;
        if(!same(a->name,"extern")) fail(vm,a,"unsupported extern annotation");
        if(!a->itemCount) continue;
        if(a->itemCount!=1 || !same(a->items[0]->name,"symbol")) fail(vm,a,"invalid extern annotation");
        RangeNode *v=a->items[0]->a;
        if(v->kind!=RangeNodeString || v->itemCount!=1 || !(v->items[0]->flags&RangeFlagLiteral)) fail(vm,a,"extern symbol must be a constant string");
        symbol=v->items[0]->name;
        if(strlen(symbol)!=(size_t)v->items[0]->integer) fail(vm,a,"extern symbol contains NUL");
    }
    int returnsInt=f->b && same(f->b->name,"Int") && !f->b->flags;
    if(same(symbol,"targetPointerBits") && !f->itemCount && returnsInt) return symbol;
    if((same(symbol,"stringPrint") || same(symbol,"stringDiagnostic")) && f->itemCount==1 && same(f->items[0]->b->name,"String") && !f->items[0]->flags && returnsInt) return symbol;
    fail(vm,f,"unbound extern '%s' or incompatible signature",symbol);
}
static Value invoke(VM *vm,Scope *caller,RangeNode *function,Value receiver,RangeNode *at,Value *args) {
    (void)caller;
    if(++vm->depth>512) fail(vm,at,"compiler call depth exceeded");
    Scope scope={.receiver=receiver,.resultType=function->b?function->b->name:NULL,.resultFlags=function->b?function->b->flags:0};
    for(size_t i=0;i<function->itemCount;i++) {
        RangeNode *p=function->items[i]; Value v=coerce(vm,at,args[i],p->b->name,p->flags);
        bind(vm,&scope,p->name,v,0,p);
    }
    Value out;
    if(function->flags & RangeFlagExtern) {
        const char *symbol=externSymbol(vm,function);
        if(same(symbol,"targetPointerBits") && !function->itemCount && function->b && same(function->b->name,"Int")) out=integer(sizeof(void *) * CHAR_BIT);
        else if((same(symbol,"stringPrint") || same(symbol,"stringDiagnostic")) && function->itemCount==1 && same(function->items[0]->b->name,"String") && function->b && same(function->b->name,"Int")) {
            size_t length; char *bytes=text(vm,args[0],&length,at);
            out=integer(same(symbol,"stringPrint") ? puts(bytes):(fprintf(stderr,"%s\n",bytes)<0 ? 74:0));
        } else fail(vm,at,"unbound extern '%s' or incompatible signature",symbol);
    } else {
        if(function->c && function->c->itemCount) fail(vm,at,"function annotation execution is not implemented");
        Flow f=block(vm,&scope,function->a); out=f.value;
        if(!f.returned && function->b && !same(function->b->name,"Void")) fail(vm,function,"function returned without an explicit return");
    }
    if(function->b) out=coerce(vm,at,out,function->b->name,function->b->flags);
    else if(out.kind!=VVoid) fail(vm,at,"function without result type returned a value");
    vm->depth--; return out;
}

/* Binding walks every branch of each reachable function before execution.
 * The resulting call edge points at the declaration, including methods; no
 * user-function selection is performed from runtime values. */
static Value typeValue(VM *vm,const char *name,int flags,RangeNode *at) {
    if(flags & RangeFlagOptional) fail(vm,at,"optional execution is not implemented");
    if(flags & RangeFlagMany) return (Value){.kind=VMany,.type=nominal(vm,name,at)};
    if(!name || !*name || same(name,"Void")) return nothing();
    RangeNode *type=nominal(vm,name,at);
    if(!type) fail(vm,at,"unresolved type '%s'",name);
    if(type->c) for(size_t i=0;i<type->c->itemCount;i++) {
        RangeNode *a=type->c->items[i];
        int primitive=(same(a->name,"integer") && (same(name,"Int") || same(name,"Byte"))) || (same(a->name,"bool") && same(name,"Bool"));
        if(!primitive || a->itemCount) fail(vm,a,"type annotation execution is not implemented");
    }
    Kind kind=same(name,"Int") || same(name,"Byte") ? VInt:same(name,"Bool")?VBool:type->kind==RangeNodeEnum?VEnum:VObject;
    return (Value){.kind=kind,.type=type};
}
static Value bindExpression(VM *,Scope *,RangeNode *,const char *);
static void bindStatements(VM *,Scope *,RangeNode *);
static Value bindMember(VM *vm,Scope *scope,Value receiver,const char *name,RangeNode *at) {
    if(receiver.kind==VMany && same(name,"count")) return typeValue(vm,"Int",0,at);
    RangeNode *m=memberDeclaration(receiver.type,name);
    if(m) {
        Value result=typeValue(vm,m->resolvedType?m->resolvedType->name:m->typeName,m->flags,at);
        if(m->flags&RangeFlagDerived) {
            Scope body={.receiver=receiver,.resultType=m->typeName,.resultFlags=m->flags}; bindStatements(vm,&body,m->a);
        }
        return result;
    }
    if(receiver.kind==VEnum) {
        Value found=nothing();
        for(size_t i=0;i<receiver.type->itemCount;i++) {
            RangeNode *variant=receiver.type->items[i];
            for(size_t j=0;j<variant->itemCount;j++) {
                RangeNode *p=variant->items[j];
                if(same(p->name,name) && p->a && p->a->kind==RangeNodeName) {
                    Value candidate=typeValue(vm,p->a->name,0,at);
                    if(found.kind!=VVoid && found.type!=candidate.type) fail(vm,at,"ambiguous enum payload member");
                    found=candidate;
                }
            }
        }
        if(found.kind!=VVoid) return found;
    }
    (void)scope; fail(vm,at,"unknown member '%s' during binding",name);
}
static int compatible(Value actual,Value expected) {
    if(actual.kind!=expected.kind) return 0;
    /* Range Byte values can flow into Int parameters. Narrowing is checked. */
    if(actual.kind==VInt) return 1;
    return !actual.type || !expected.type || actual.type==expected.type;
}
static Value bindCall(VM *vm,Scope *scope,RangeNode *node,const char *expected) {
    RangeNode *target=node->a; Value receiver=nothing(); const char *name=target->name;
    if(node->generics || target->generics) fail(vm,node,"generic specialization execution is not implemented");
    RangeNode *type=NULL;
    if(target->kind==RangeNodeMemberAccess) receiver=bindExpression(vm,scope,target->a,NULL);
    else if(target->kind==RangeNodeCase) receiver=(Value){.kind=VType,.type=nominal(vm,expected,node)};
    else if(target->kind!=RangeNodeName) fail(vm,node,"unsupported call target during binding");
    if(receiver.kind==VType) {
        if(!receiver.type || receiver.type->kind!=RangeNodeEnum) fail(vm,node,"enum call lacks expected type");
        RangeNode *variant=NULL;
        for(size_t i=0;i<receiver.type->itemCount;i++) if(same(receiver.type->items[i]->name,name)) variant=receiver.type->items[i];
        if(!variant || variant->itemCount!=node->itemCount) fail(vm,node,"unknown enum case or payload arity '%s'",name);
        for(size_t i=0;i<node->itemCount;i++) {
            RangeNode *p=variant->items[i];
            if(!same(p->name,node->items[i]->name) || !p->a || p->a->kind!=RangeNodeName) fail(vm,node,"enum payload signature mismatch");
            Value actual=bindExpression(vm,scope,node->items[i]->a,p->a->name);
            if(!compatible(actual,typeValue(vm,p->a->name,0,p))) fail(vm,node,"enum payload type mismatch");
        }
        return (Value){.kind=VEnum,.type=receiver.type};
    }
    if(receiver.kind==VVoid) type=nominal(vm,name,node);
    if(type) {
        if((same(name,"Int") || same(name,"Byte") || same(name,"Bool") || same(name,"String")) && node->itemCount==1 && (!node->items[0]->name || ((same(name,"Int") || same(name,"Byte")) && same(node->items[0]->name,"bits")))) {
            Value actual=bindExpression(vm,scope,node->items[0]->a,name),want=typeValue(vm,name,0,node);
            if(!compatible(actual,want)) fail(vm,node,"invalid scalar construction"); return want;
        }
        if(type->generics) fail(vm,node,"generic construction execution is not implemented");
        size_t supplied=0;
        Scope memberScope={.parent=scope};
        for(size_t i=0;i<type->itemCount;i++) {
            RangeNode *m=type->items[i]; if(m->kind!=RangeNodeMember || (m->flags&RangeFlagDerived)) continue;
            if(m->generics) fail(vm,m,"generic specialization execution is not implemented");
            Value expected=typeValue(vm,m->rhsReference?NULL:m->typeName,m->flags,m);
            int required=!m->itemCount && !(m->flags & (RangeFlagMany|RangeFlagApplication));
            if(m->rhsReference) {
                Value target=bindExpression(vm,&memberScope,m->rhsReference,NULL);
                required=target.kind==VType;
                expected=required?typeValue(vm,target.type->name,m->flags,m):target;
            } else if(!m->typeName && m->itemCount==1 && !m->items[0]->name) {
                expected=bindExpression(vm,&memberScope,m->items[0]->a,NULL);
            }
            int found=0;
            for(size_t a=0;a<node->itemCount;a++) if(same(node->items[a]->name,m->name)) {
                if(found++) fail(vm,node,"duplicate constructor argument"); supplied++;
                Value actual=bindExpression(vm,scope,node->items[a]->a,expected.type?expected.type->name:NULL);
                if(!compatible(actual,expected)) fail(vm,node,"constructor argument type mismatch");
            }
            if(!found && required) fail(vm,node,"missing constructor argument '%s'",m->name);
            m->resolvedType=expected.type;
            bind(vm,&memberScope,m->name,expected,!!(m->flags & (RangeFlagMutable|RangeFlagBinding)),m);
        }
        if(supplied!=node->itemCount) fail(vm,node,"unknown constructor argument");
        return typeValue(vm,name,0,node);
    }
    if(receiver.kind==VMany) {
        for(size_t i=0;i<node->itemCount;i++) (void)bindExpression(vm,scope,node->items[i]->a,NULL);
        const char *a=node->itemCount?node->items[0]->name:NULL;
        const char *b=node->itemCount>1?node->items[1]->name:NULL;
        if(same(name,"destroy") && !node->itemCount) return typeValue(vm,"Int",0,node);
        if(same(name,"slice") && node->itemCount==2 && same(a,"start") && same(b,"end")) return receiver;
        if(same(name,"element") && node->itemCount==1 && same(a,"index")) {
            if(!receiver.type) fail(vm,node,"collection element type is unresolved");
            return typeValue(vm,receiver.type->name,0,node);
        }
        if((same(name,"append") && node->itemCount==1 && (same(a,"element") || same(a,"contentsOf"))) ||
           (same(name,"update") && node->itemCount==2 && same(a,"element") && same(b,"index")) ||
           (same(name,"firstIndex") && node->itemCount==1 && same(a,"value"))) return typeValue(vm,"Int",0,node);
        fail(vm,node,"unsupported collection call during binding");
    }
    RangeNode *f=resolve(vm,receiver,name,node); node->resolvedDeclaration=f;
    for(size_t i=0;i<f->itemCount;i++) {
        RangeNode *p=f->items[i]; Value actual=bindExpression(vm,scope,node->items[i]->a,p->b->name);
        if(!compatible(actual,typeValue(vm,p->b->name,p->flags,p))) fail(vm,node,"argument type mismatch for '%s'",f->name);
    }
    bindFunction(vm,f);
    return f->b?typeValue(vm,f->b->name,f->b->flags,f):nothing();
}
static Value bindExpression(VM *vm,Scope *scope,RangeNode *node,const char *expected) {
    if(!node) return nothing();
    if(node->generics) fail(vm,node,"generic specialization execution is not implemented");
    switch(node->kind) {
    case RangeNodeInteger:
        if(strchr(node->name,'.')) fail(vm,node,"decimal/version literal execution is not implemented");
        return typeValue(vm,"Int",0,node);
    case RangeNodeBool: return typeValue(vm,"Bool",0,node);
    case RangeNodeName: {
        if(same(node->name,"self")) return scope->receiver;
        Slot *s=lookup(scope,node->name); if(s) { node->resolvedDeclaration=s->declaration; return s->value; }
        RangeNode *m=memberDeclaration(scope->receiver.type,node->name);
        if(m) { node->resolvedDeclaration=m; return bindMember(vm,scope,scope->receiver,node->name,node); }
        RangeNode *t=nominal(vm,node->name,node); if(t) { node->resolvedDeclaration=t; return (Value){.kind=VType,.type=t}; }
        fail(vm,node,"unresolved name '%s' during binding",node->name);
    }
    case RangeNodeMemberAccess: return bindMember(vm,scope,bindExpression(vm,scope,node->a,NULL),node->name,node);
    case RangeNodeCall: return bindCall(vm,scope,node,expected);
    case RangeNodeCase: {
        RangeNode callNode=*node; callNode.a=node; callNode.itemCount=0; return bindCall(vm,scope,&callNode,expected);
    }
    case RangeNodeManyLiteral:
        if(!same(node->name,"many")) fail(vm,node,"unsupported cardinality literal");
        if(node->itemCount>1 || (node->itemCount && !same(node->items[0]->name,"capacity"))) fail(vm,node,"unsupported @many initializer");
        for(size_t i=0;i<node->itemCount;i++) (void)bindExpression(vm,scope,node->items[i]->a,"Int");
        return (Value){.kind=VMany};
    case RangeNodeString:
        for(size_t i=0;i<node->itemCount;i++) if(!(node->items[i]->flags&RangeFlagLiteral)) (void)bindExpression(vm,scope,node->items[i]->a,NULL);
        return typeValue(vm,"String",0,node);
    case RangeNodeBinary: {
        Value left=bindExpression(vm,scope,node->a,NULL);
        Value right=bindExpression(vm,scope,node->b,left.type?left.type->name:NULL);
        if(!compatible(left,right)) fail(vm,node,"binary operand type mismatch");
        if(same(node->name,"+") || same(node->name,"-") || same(node->name,"*") || same(node->name,"/") || same(node->name,"%")) return left;
        return typeValue(vm,"Bool",0,node);
    }
    case RangeNodeUnary: (void)bindExpression(vm,scope,node->a,NULL); return typeValue(vm,same(node->name,"!")?"Bool":"Int",0,node);
    default: fail(vm,node,"execution of %s is not implemented",rangeNodeKindName(node->kind));
    }
}
static void bindStatements(VM *vm,Scope *parent,RangeNode *node) {
    Scope scope={.parent=parent,.receiver=parent->receiver,.resultType=parent->resultType,.resultFlags=parent->resultFlags};
    if(!node) fail(vm,vm->units[0],"missing executable body");
    if(node->kind!=RangeNodeBlock) {
        RangeNode wrapper={.kind=RangeNodeBlock,.items=&node,.itemCount=1}; bindStatements(vm,parent,&wrapper); return;
    }
    for(size_t i=0;i<node->itemCount;i++) {
        RangeNode *s=node->items[i];
        annotations(vm,s);
        if(s->generics) fail(vm,s,"generic specialization execution is not implemented");
        switch(s->kind) {
        case RangeNodeLocal: {
            if(s->rhsReference && !(s->flags & RangeFlagMany)) {
                Value actual=bindExpression(vm,&scope,s->rhsReference,NULL);
                if(actual.kind==VType) actual=typeValue(vm,actual.type->name,s->flags,s);
                bind(vm,&scope,s->name,actual,!!(s->flags&RangeFlagMutable),s);
                break;
            }
            Value actual=nothing(),declared=typeValue(vm,s->typeName,s->flags,s);
            if(s->flags&RangeFlagMany) {
                for(size_t a=0;a<s->itemCount;a++) (void)bindExpression(vm,&scope,s->items[a]->a,NULL);
                actual=declared;
            } else if(s->itemCount==1 && !s->items[0]->name) actual=bindExpression(vm,&scope,s->items[0]->a,s->typeName);
            else { RangeNode target={.kind=RangeNodeName,.name=s->typeName},callNode=*s; callNode.a=&target; actual=bindCall(vm,&scope,&callNode,s->typeName); }
            if(s->typeName && !compatible(actual,declared)) fail(vm,s,"local type mismatch");
            bind(vm,&scope,s->name,s->typeName?declared:actual,!!(s->flags&RangeFlagMutable),s); break;
        }
        case RangeNodeAssign: {
            Value left=bindExpression(vm,&scope,s->a,NULL),right=bindExpression(vm,&scope,s->b,left.type?left.type->name:NULL);
            if(!compatible(left,right)) fail(vm,s,"assignment type mismatch"); break;
        }
        case RangeNodeReturn: {
            Value actual=bindExpression(vm,&scope,s->a,scope.resultType);
            if(!compatible(actual,typeValue(vm,scope.resultType,scope.resultFlags,s))) fail(vm,s,"return type mismatch"); break;
        }
        case RangeNodeExpressionStatement: (void)bindExpression(vm,&scope,s->a,NULL); break;
        case RangeNodeBlock: bindStatements(vm,&scope,s); break;
        case RangeNodeIf: case RangeNodeWhile:
            if(bindExpression(vm,&scope,s->a,"Bool").kind!=VBool) fail(vm,s,"condition must be Bool");
            bindStatements(vm,&scope,s->b); if(s->c) bindStatements(vm,&scope,s->c); break;
        case RangeNodeSwitch: {
            Value v=bindExpression(vm,&scope,s->a,NULL);
            s->resolvedType=v.type;
            for(size_t a=0;a<s->itemCount;a++) { RangeNode *arm=s->items[a]; if(arm->a) (void)bindExpression(vm,&scope,arm->a,v.type?v.type->name:NULL); bindStatements(vm,&scope,arm->b); } break;
        }
        default: fail(vm,s,"execution of %s is not implemented",rangeNodeKindName(s->kind));
        }
    }
}
/* Definite initialization over the existing structured control flow. Bits encode
 * possible states: 1 = uninitialized, 2 = initialized. Joining paths is union.
 * This is compiler execution machinery, not an implementation of Core macros. */
typedef struct InitLocal InitLocal;
struct InitLocal { RangeNode *declaration; const char *name; int states, mutable; InitLocal *next; };
typedef struct InitScope InitScope;
struct InitScope { InitScope *parent; InitLocal *locals; };
typedef struct { InitLocal *local; int before, joined; } InitSnapshot;

static InitLocal *initLookup(InitScope *scope,RangeNode *reference) {
    for(;scope;scope=scope->parent) for(InitLocal *l=scope->locals;l;l=l->next)
        if(reference->resolvedDeclaration ? l->declaration==reference->resolvedDeclaration : same(l->name,reference->name)) return l;
    return NULL;
}
static void initDeclare(VM *vm,InitScope *scope,RangeNode *node,int states) {
    InitLocal *l=allocate(vm,sizeof(*l));
    *l=(InitLocal){node,node->name,states,!!(node->flags&RangeFlagMutable),scope->locals}; scope->locals=l;
}
static void initRead(VM *vm,InitScope *scope,RangeNode *node) {
    if(!node) return;
    if(node->kind==RangeNodeName) {
        InitLocal *l=initLookup(scope,node);
        if(l && l->states!=2) fail(vm,node,"read before initialization: '%s'",l->name);
        return;
    }
    initRead(vm,scope,node->a); initRead(vm,scope,node->b);
    for(size_t i=0;i<node->itemCount;i++) initRead(vm,scope,node->items[i]);
}
static InitSnapshot *initSnapshot(VM *vm,InitScope *scope,size_t *count) {
    *count=0;
    for(InitScope *s=scope;s;s=s->parent) for(InitLocal *l=s->locals;l;l=l->next) (*count)++;
    InitSnapshot *snapshot=allocate(vm,(*count+1)*sizeof(*snapshot)); size_t i=0;
    for(InitScope *s=scope;s;s=s->parent) for(InitLocal *l=s->locals;l;l=l->next)
        snapshot[i++]=(InitSnapshot){l,l->states,0};
    return snapshot;
}
static void initRestore(InitSnapshot *snapshot,size_t count) {
    for(size_t i=0;i<count;i++) snapshot[i].local->states=snapshot[i].before;
}
static void initJoin(InitSnapshot *snapshot,size_t count) {
    for(size_t i=0;i<count;i++) snapshot[i].joined|=snapshot[i].local->states;
}
static void initFinish(InitSnapshot *snapshot,size_t count) {
    for(size_t i=0;i<count;i++) snapshot[i].local->states=snapshot[i].joined;
}
static int initSwitchExhaustive(RangeNode *node) {
    for(size_t i=0;i<node->itemCount;i++) if(node->items[i]->flags&RangeFlagLiteral) return 1;
    RangeNode *type=node->resolvedType;
    if(type && same(type->name,"Bool")) {
        int seen=0;
        for(size_t i=0;i<node->itemCount;i++) {
            RangeNode *arm=node->items[i];
            if(!arm->name && arm->a && arm->a->kind==RangeNodeBool) seen|=arm->a->integer?2:1;
        }
        return seen==3;
    }
    if(!type || type->kind!=RangeNodeEnum || !type->itemCount) return 0;
    for(size_t c=0;c<type->itemCount;c++) {
        RangeNode *variant=type->items[c]; int seen=0;
        if(variant->itemCount) return 0; // Payload-pattern coverage is unsupported.
        for(size_t i=0;i<node->itemCount;i++) {
            RangeNode *arm=node->items[i];
            if(!arm->name && arm->a && arm->a->kind==RangeNodeCase && same(arm->a->name,variant->name)) seen=1;
        }
        if(!seen) return 0;
    }
    return 1;
}
/* Returns whether control can continue after the statement. */
static int initStatement(VM *,InitScope *,RangeNode *);
static int initBlock(VM *vm,InitScope *parent,RangeNode *node) {
    if(!node) return 1;
    InitScope scope={.parent=parent};
    if(node->kind!=RangeNodeBlock) return initStatement(vm,&scope,node);
    for(size_t i=0;i<node->itemCount;i++) if(!initStatement(vm,&scope,node->items[i])) return 0;
    return 1;
}
static int initStatement(VM *vm,InitScope *scope,RangeNode *node) {
    switch(node->kind) {
    case RangeNodeLocal: {
        RangeNode *target=node->rhsReference?node->rhsReference->resolvedDeclaration:NULL;
        int required=target && (target->kind==RangeNodeConstruct || target->kind==RangeNodeEnum)
            && !(node->flags&RangeFlagMany);
        if(!required) {
            if(!(node->flags&RangeFlagMany)) initRead(vm,scope,node->rhsReference);
            for(size_t i=0;i<node->itemCount;i++) initRead(vm,scope,node->items[i]);
        }
        initDeclare(vm,scope,node,required?1:2); return 1;
    }
    case RangeNodeAssign: {
        InitLocal *l=node->a->kind==RangeNodeName?initLookup(scope,node->a):NULL;
        // A field write reads its base object; it cannot initialize that object.
        if(!l) initRead(vm,scope,node->a);
        initRead(vm,scope,node->b);
        if(l) {
            if(!l->mutable && (l->states&2)) fail(vm,node,"immutable local '%s' may only be initialized once",l->name);
            l->states=2;
        }
        return 1;
    }
    case RangeNodeReturn: initRead(vm,scope,node->a); return 0;
    case RangeNodeExpressionStatement: initRead(vm,scope,node->a); return 1;
    case RangeNodeBlock: return initBlock(vm,scope,node);
    case RangeNodeIf: {
        initRead(vm,scope,node->a);
        size_t count; InitSnapshot *snapshot=initSnapshot(vm,scope,&count);
        int left=initBlock(vm,scope,node->b); if(left) initJoin(snapshot,count);
        initRestore(snapshot,count);
        int right=node->c?initBlock(vm,scope,node->c):1; if(right) initJoin(snapshot,count);
        initFinish(snapshot,count); return left || right;
    }
    case RangeNodeWhile: {
        initRead(vm,scope,node->a);
        size_t count; InitSnapshot *snapshot=initSnapshot(vm,scope,&count);
        int repeats=initBlock(vm,scope,node->b);
        if(repeats) {
            initJoin(snapshot,count);
            for(size_t i=0;i<count;i++) snapshot[i].local->states=snapshot[i].before|snapshot[i].joined;
            // Analyze a possible subsequent iteration. Outer let initialization
            // is rejected; body-local declarations start fresh on each iteration.
            initRead(vm,scope,node->a); (void)initBlock(vm,scope,node->b);
        }
        for(size_t i=0;i<count;i++) snapshot[i].local->states=snapshot[i].before|snapshot[i].joined;
        return 1; // A while loop can execute zero times.
    }
    case RangeNodeSwitch: {
        initRead(vm,scope,node->a);
        size_t count; InitSnapshot *snapshot=initSnapshot(vm,scope,&count);
        int exhaustive=initSwitchExhaustive(node),continues=0;
        for(size_t i=0;i<node->itemCount;i++) {
            RangeNode *arm=node->items[i]; initRestore(snapshot,count);
            if(!(arm->flags&RangeFlagLiteral)) initRead(vm,scope,arm->a);
            if(initBlock(vm,scope,arm->b)) { initJoin(snapshot,count); continues=1; }
        }
        if(!exhaustive) { initRestore(snapshot,count); initJoin(snapshot,count); continues=1; }
        initFinish(snapshot,count); return continues;
    }
    default: fail(vm,node,"initialization analysis of %s is not implemented",rangeNodeKindName(node->kind));
    }
}
static void checkInitialization(VM *vm,RangeNode *function) {
    InitScope scope={0};
    for(size_t i=0;i<function->itemCount;i++) initDeclare(vm,&scope,function->items[i],2);
    (void)initBlock(vm,&scope,function->a);
}

static void bindFunction(VM *vm,RangeNode *f) {
    if(f->generics || (f->b && f->b->generics)) fail(vm,f,"generic specialization execution is not implemented");
    for(size_t i=0;i<vm->boundCount;i++) if(vm->boundFunctions[i]==f) return;
    if(vm->boundCount==vm->boundCapacity) {
        size_t capacity=vm->boundCapacity?vm->boundCapacity*2:32;
        RangeNode **data=realloc(vm->boundFunctions,capacity*sizeof(*data));
        if(!data) fail(vm,f,"binding allocation failed"); vm->boundFunctions=data; vm->boundCapacity=capacity;
    }
    vm->boundFunctions[vm->boundCount++]=f;
    Scope scope={.resultType=f->b?f->b->name:NULL,.resultFlags=f->b?f->b->flags:0};
    if(f->typeName) scope.receiver=typeValue(vm,f->typeName,0,f);
    for(size_t i=0;i<f->itemCount;i++) {
        RangeNode *p=f->items[i];
        if(p->b && p->b->generics) fail(vm,p,"generic specialization execution is not implemented");
        if(p->flags & RangeFlagBinding) fail(vm,p,"binding input execution is not implemented");
        bind(vm,&scope,p->name,typeValue(vm,p->b->name,p->flags,p),0,p);
    }
    if(f->flags&RangeFlagExtern) { (void)externSymbol(vm,f); return; }
    if(f->c && f->c->itemCount) fail(vm,f,"function annotation execution is not implemented");
    bindStatements(vm,&scope,f->a);
    checkInitialization(vm,f);
}
static int rangeExecute(RangeArena *arena,RangeNode **units,size_t countUnits,const char *entry,int64_t *result,char *error,size_t errorSize) {
    VM *vm=calloc(1,sizeof(*vm)); if(!vm) return 0;
    vm->arena=arena; vm->units=units; vm->count=countUnits; vm->error=error; vm->errorSize=errorSize;
    int ok=0;
    if(setjmp(vm->failure)==0) {
        if(!countUnits) { snprintf(error,errorSize,"<compiler>:1:1: no sources loaded"); }
        else {
            RangeNode callNode={.kind=RangeNodeCall,.path=units[0]->path,.line=1,.column=1};
            RangeNode *function=resolve(vm,nothing(),entry,&callNode);
            bindFunction(vm,function);
            Value out=invoke(vm,NULL,function,nothing(),&callNode,NULL);
            *result=number(vm,out,function); ok=1;
        }
    }
    for(Object *o=vm->objects;o;o=o->next) if(o->buffer) rawBufferDestroy(o->buffer);
    free(vm->values); free(vm->boundFunctions); free(vm); return ok;
}

/* Resolve declaration queries without executing the macro's deferred body. */
static RangeGraphValue graphEval(VM *, RangeMacroApplication *, RangeNode *);

static RangeGraphValue graphNode(RangeNode *node)
{
    return (RangeGraphValue){.kind=node ? RangeGraphNode : RangeGraphNone,.node=node};
}

static RangeGraphValue graphBinding(VM *vm, RangeMacroApplication *app, RangeGraphBinding *binding)
{
    if (binding->state == 2) return binding->value;
    if (binding->state == 1) fail(vm,binding->definition,"cyclic graph member '%s'",binding->definition->name);
    RangeNode *rhs = rangeNodeRHS(binding->definition);
    if (!rhs) fail(vm,binding->definition,"graph member RHS is not supported yet");
    binding->state = 1;
    binding->value = graphEval(vm,app,rhs);
    binding->state = 2;
    return binding->value;
}

static RangeGraphValue graphProperty(VM *vm, RangeMacroApplication *app,
                                    RangeGraphValue receiver, const char *name, RangeNode *at)
{
    if (receiver.kind == RangeGraphNodes && same(name,"first"))
        return graphNode(receiver.count ? receiver.nodes[0] : NULL);
    if (receiver.kind != RangeGraphNode) fail(vm,at,"graph value has no property '%s'",name);
    RangeNode *node = receiver.node;
    RangeNode *field = rangeGraphField(node->graphType,name);
    if (!field) fail(vm,at,"field '%s' is not declared by @type %s",name,
        node->graphType ? node->graphType->name : rangeNodeKindName(node->kind));
    if (same(name,"target") && node == app->declaration) return graphNode(app->target);
    if (same(name,"value") && (node->kind == RangeNodeMember || node->kind == RangeNodeLocal)) {
        if (node->kind == RangeNodeLocal) {
            for (size_t i = 0; i < app->count; ++i)
                if (app->bindings[i].definition == node) return graphBinding(vm,app,&app->bindings[i]);
        }
    }
    RangeGraphValue value = rangeGraphStoredField(vm->arena,node,name);
    if (!(field->flags & RangeFlagMany) && value.kind == RangeGraphNodes)
        return graphNode(value.count ? value.nodes[0] : NULL);
    return value;
}

static const char *graphText(VM *vm, RangeGraphValue value, RangeNode *at)
{
    if (value.kind == RangeGraphText) return value.text;
    if (value.kind == RangeGraphNode && value.node->kind == RangeNodeString
        && value.node->itemCount == 1 && (value.node->items[0]->flags & RangeFlagLiteral))
        return value.node->items[0]->name;
    fail(vm,at,"graph filter requires a string name");
    return NULL;
}

static RangeGraphValue graphEval(VM *vm, RangeMacroApplication *app, RangeNode *node)
{
    switch (node->kind) {
    case RangeNodeEnvironment:
        return graphProperty(vm,app,graphNode(app->declaration),node->name,node);
    case RangeNodeMemberAccess:
        return graphProperty(vm,app,graphEval(vm,app,node->a),node->name,node);
    case RangeNodeName:
        for (size_t i = 0; i < app->count; ++i)
            if (same(app->bindings[i].definition->name,node->name))
                return graphBinding(vm,app,&app->bindings[i]);
        fail(vm,node,"unresolved graph member '%s'",node->name);
        break;
    case RangeNodeInteger: case RangeNodeBool: case RangeNodeString:
        return graphNode(node);
    case RangeNodeCall: {
        if (!node->a || node->a->kind != RangeNodeMemberAccess || !same(node->a->name,"filter")
            || node->itemCount != 1 || !same(node->items[0]->name,"named"))
            fail(vm,node,"graph resolution currently supports filter(named:) calls only");
        RangeGraphValue list = graphEval(vm,app,node->a->a);
        if (list.kind != RangeGraphNodes) fail(vm,node,"graph filter requires member nodes");
        const char *name = graphText(vm,graphEval(vm,app,node->items[0]->a),node);
        RangeGraphValue result = {.kind=RangeGraphNodes};
        result.nodes = rangeArenaAllocate(vm->arena,list.count * sizeof(*result.nodes));
        for (size_t i = 0; i < list.count; ++i)
            if (same(list.nodes[i]->name,name)) result.nodes[result.count++] = list.nodes[i];
        return result;
    }
    default: fail(vm,node,"unsupported graph expression '%s'",rangeNodeKindName(node->kind));
    }
    return (RangeGraphValue){0};
}

static void resolveGraphTarget(VM *vm, RangeNode *target)
{
    if (target->kind != RangeNodeConstruct) return;
    RangeNode *attributes = target->c;
    if (attributes) for (size_t a = 0; a < attributes->itemCount; ++a) {
        RangeNode *attribute = attributes->items[a], *macro = NULL, *unit = NULL;
        for (size_t u = 0; u < vm->count; ++u) for (size_t m = 0; m < vm->units[u]->itemCount; ++m) {
            RangeNode *candidate = vm->units[u]->items[m];
            if (candidate->kind != RangeNodeMacro || !same(candidate->name,attribute->name)) continue;
            if (macro) fail(vm,attribute,"ambiguous graph macro '%s'",attribute->name);
            macro = candidate; unit = vm->units[u];
        }
        if (!macro) fail(vm,attribute,"unresolved graph macro '%s'",attribute->name);
        if (macro->b && !same(macro->b->name,"Construct"))
            fail(vm,attribute,"macro '%s' does not target Construct",macro->name);
        if (attribute->itemCount || macro->itemCount)
            fail(vm,attribute,"parameterized macro graph resolution is not implemented");
        RangeMacroApplication *app = rangeArenaAllocate(vm->arena,sizeof(*app));
        *app = (RangeMacroApplication){.declaration=macro,.target=target,.unit=unit};
        if (macro->a) {
            app->bindings = rangeArenaAllocate(vm->arena,macro->a->itemCount * sizeof(*app->bindings));
            for (size_t i = 0; i < macro->a->itemCount; ++i) {
                RangeNode *member = macro->a->items[i];
                if (member->kind != RangeNodeLocal) continue;
                for (size_t j = 0; j < app->count; ++j)
                    if (same(app->bindings[j].definition->name,member->name))
                        fail(vm,member,"duplicate graph member '%s'",member->name);
                app->bindings[app->count++] = (RangeGraphBinding){.definition=member};
            }
        }
        attribute->resolvedDeclaration = macro;
        attribute->macroApplication = app;
        for (size_t i = 0; i < app->count; ++i)
            if (rangeNodeHasContextReference(app->bindings[i].definition))
                (void)graphBinding(vm,app,&app->bindings[i]);
    }
    for (size_t i = 0; i < target->itemCount; ++i) resolveGraphTarget(vm,target->items[i]);
}

static size_t graphValueCount(RangeGraphValue value)
{
    return value.kind == RangeGraphNone ? 0 : value.kind == RangeGraphNodes ? value.count : 1;
}

static void validateGraphShape(VM *vm, RangeNode *node, const char *source)
{
    if (!node) return;
    if (node->kind == RangeNodeUnit) source = node->source;
    else node->source = source;
    const char *type = node->kind == RangeNodeMacro ? "Macro"
        : node->kind == RangeNodeConstruct ? "Construct"
        : node->kind == RangeNodeFunction ? "Function"
        : node->kind == RangeNodeReturn ? "Return"
        : (node->kind == RangeNodeLocal || node->kind == RangeNodeMember) ? "Member" : NULL;
    if (type) {
        node->graphType = rangeGraphType(vm->arena,type);
        if (!node->graphType) fail(vm,node,"missing @type %s",type);
    }
    if (node->graphType) {
        type = node->graphType->name;
        /* These are physical storage adapters, not a list of permitted fields. */
        static const char *const storage[] = {"name","target","members","environment","macros","generics","value",
            "receiver","parameters","output","body"};
        for (size_t i = 0; i < sizeof(storage)/sizeof(*storage); ++i) {
            RangeGraphValue value = rangeGraphStoredField(vm->arena,node,storage[i]);
            if (graphValueCount(value) && !rangeGraphField(node->graphType,storage[i]))
                fail(vm,node,"field '%s' is not declared by @type %s",storage[i],type);
        }
        for (size_t i = 0; i < node->graphType->itemCount; ++i) {
            RangeNode *field = node->graphType->items[i];
            RangeGraphValue value = rangeGraphStoredField(vm->arena,node,field->name);
            size_t count = graphValueCount(value);
            if (!count && !(field->flags & RangeFlagOptional))
                fail(vm,node,"@type %s requires field '%s'",type,field->name);
            if (count > 1 && !(field->flags & RangeFlagMany))
                fail(vm,node,"@type %s field '%s' allows at most one value",type,field->name);
            if ((field->flags & RangeFlagMany) && count && value.kind != RangeGraphNodes)
                fail(vm,node,"@type %s field '%s' requires many-value storage",type,field->name);
            if (field->a && value.kind == RangeGraphNode) value.node->graphType = field->a;
            else if (field->a && value.kind == RangeGraphNodes)
                for (size_t j = 0; j < value.count; ++j) value.nodes[j]->graphType = field->a;
            else if (field->a && count) fail(vm,node,"@type %s field '%s' requires node storage",type,field->name);
        }
    }
    validateGraphShape(vm,node->a,source); validateGraphShape(vm,node->b,source); validateGraphShape(vm,node->c,source);
    validateGraphShape(vm,node->generics,source); validateGraphShape(vm,node->annotations,source);
    for (size_t i = 0; i < node->itemCount; ++i) validateGraphShape(vm,node->items[i],source);
}

/* Bootstrap literal recognition: Core supplies patterns; C supplies regex. */
static const char *literalString(VM *vm, RangeNode *node)
{
    if (!node || node->kind != RangeNodeString || node->itemCount != 1
        || !(node->items[0]->flags & RangeFlagLiteral))
        fail(vm,node,"literal pattern requires a non-interpolated string");
    return node->items[0]->name;
}

static int literalMatch(VM *vm, RangeNode *at, const char *pattern, const char *input)
{
    regex_t regex;
    int code = regcomp(&regex,pattern,REG_EXTENDED);
    char detail[256];
    if (code) {
        regerror(code,&regex,detail,sizeof(detail));
        fail(vm,at,"invalid literal regex: %s",detail);
    }
    regmatch_t match;
    code = input ? regexec(&regex,input,1,&match,0) : REG_NOMATCH;
    if (code && code != REG_NOMATCH) {
        regerror(code,&regex,detail,sizeof(detail));
        regfree(&regex);
        fail(vm,at,"literal regex matching failed: %s",detail);
    }
    int matched = !code && match.rm_so == 0 && match.rm_eo >= 0
        && (size_t)match.rm_eo == strlen(input);
    regfree(&regex);
    return matched;
}

static int literalBuiltin(RangeNode *node)
{
    if (node->kind != RangeNodeMacro || !node->c) return 0;
    for (size_t i = 0; i < node->c->itemCount; ++i) {
        RangeNode *a = node->c->items[i];
        if (!same(a->name,"builtin") || a->itemCount != 1) continue;
        RangeNode *s = a->items[0]->a;
        if (s && s->kind == RangeNodeString && s->itemCount == 1
            && (s->items[0]->flags & RangeFlagLiteral) && same(s->items[0]->name,"literal")) return 1;
    }
    return 0;
}

static void registerLiteralRules(VM *vm)
{
    RangeNode *builtin = NULL;
    for (size_t u = 0; u < vm->count; ++u) for (size_t i = 0; i < vm->units[u]->itemCount; ++i) {
        RangeNode *node = vm->units[u]->items[i];
        if (!literalBuiltin(node)) continue;
        if (builtin) fail(vm,node,"ambiguous literal builtin");
        if (!node->b || !same(node->b->name,"Macro") || node->itemCount != 1
            || !node->items[0]->b || !same(node->items[0]->b->name,"String") || node->a)
            fail(vm,node,"literal builtin requires one String parameter, target Macro, and no body");
        builtin = node;
    }
    for (size_t u = 0; u < vm->count; ++u) for (size_t i = 0; i < vm->units[u]->itemCount; ++i) {
        RangeNode *node = vm->units[u]->items[i];
        node->literalPattern = NULL;
        if (!node->c) continue;
        for (size_t j = 0; j < node->c->itemCount; ++j) {
            RangeNode *a = node->c->items[j];
            if (!same(a->name,builtin ? builtin->name : "literal")) continue;
            if (!builtin) fail(vm,a,"literal builtin declaration is not loaded");
            for (size_t v = 0; v < vm->count; ++v) for (size_t k = 0; k < vm->units[v]->itemCount; ++k) {
                RangeNode *candidate = vm->units[v]->items[k];
                if (candidate != builtin && candidate->kind == RangeNodeMacro && same(candidate->name,builtin->name))
                    fail(vm,a,"ambiguous literal macro declaration '%s'",builtin->name);
            }
            if (node->kind != RangeNodeMacro) fail(vm,a,"literal rule must target a Macro");
            if (node->literalPattern) fail(vm,a,"duplicate literal rule");
            if (a->itemCount != 1 || (a->items[0]->name && !same(a->items[0]->name,builtin->items[0]->name)))
                fail(vm,a,"literal rule requires one pattern argument");
            const char *pattern = literalString(vm,a->items[0]->a);
            (void)literalMatch(vm,a,pattern,NULL);
            node->literalPattern = pattern;
            a->resolvedDeclaration = builtin;
        }
    }
}

#ifndef RANGE_CORE_DIR
#define RANGE_CORE_DIR "Language/Core"
#endif

static int isCoreNode(const RangeNode *node)
{
    size_t length = strlen(RANGE_CORE_DIR);
    return node->path && !strncmp(node->path,RANGE_CORE_DIR,length)
        && node->path[length] == '/';
}

static void registerLiteralDefaults(VM *vm)
{
    for (size_t u = 0; u < vm->count; ++u) for (size_t i = 0; i < vm->units[u]->itemCount; ++i) {
        RangeNode *macro = vm->units[u]->items[i];
        macro->literalDefault = NULL;
        if (macro->kind != RangeNodeMacro || !macro->literalPattern || !isCoreNode(macro)) continue;
        for (size_t v = 0; v < vm->count; ++v) for (size_t j = 0; j < vm->units[v]->itemCount; ++j) {
            RangeNode *construct = vm->units[v]->items[j];
            if (construct->kind != RangeNodeConstruct || !isCoreNode(construct) || !construct->c) continue;
            for (size_t k = 0; k < construct->c->itemCount; ++k) {
                RangeNode *attribute = construct->c->items[k];
                if (attribute->resolvedDeclaration != macro) continue;
                if (macro->literalDefault && macro->literalDefault != construct)
                    fail(vm,attribute,"literal macro '%s' has multiple Core constructs: '%s' and '%s'",
                        macro->name,macro->literalDefault->name,construct->name);
                macro->literalDefault = construct;
            }
        }
        if (!macro->literalDefault)
            fail(vm,macro,"literal macro '%s' requires one Core construct",macro->name);
    }
}

static void resolveLiteralDefaults(VM *vm, RangeNode *node)
{
    if (!node) return;
    if (node->kind == RangeNodeInteger || node->kind == RangeNodeBool) {
        const char *spelling = node->kind == RangeNodeBool ? (node->integer ? "true" : "false") : node->name;
        RangeNode *selected = NULL;
        for (size_t u = 0; u < vm->count; ++u) for (size_t i = 0; i < vm->units[u]->itemCount; ++i) {
            RangeNode *macro = vm->units[u]->items[i];
            if (!macro->literalPattern || !macro->literalDefault || !spelling
                || !literalMatch(vm,node,macro->literalPattern,spelling)) continue;
            if (selected) fail(vm,node,"ambiguous Core literal '%s'",spelling);
            selected = macro;
        }
        node->resolvedDeclaration = selected;
        node->resolvedType = selected ? selected->literalDefault : NULL;
    }
    resolveLiteralDefaults(vm,node->a); resolveLiteralDefaults(vm,node->b);
    resolveLiteralDefaults(vm,node->c); resolveLiteralDefaults(vm,node->generics);
    resolveLiteralDefaults(vm,node->annotations); resolveLiteralDefaults(vm,node->rhsReference);
    for (size_t i = 0; i < node->itemCount; ++i) resolveLiteralDefaults(vm,node->items[i]);
}

static int matchLiteralRule(RangeArena *arena, RangeNode **units, size_t count,
    const char *name, const char *input, int *matched, char *error, size_t errorSize)
{
    VM *vm = calloc(1,sizeof(*vm));
    if (!vm) { snprintf(error,errorSize,"cannot allocate literal matcher"); return 0; }
    vm->arena=arena; vm->units=units; vm->count=count; vm->error=error; vm->errorSize=errorSize;
    int ok = 0;
    if (setjmp(vm->failure) == 0) {
        registerLiteralRules(vm);
        RangeNode *macro = NULL;
        for (size_t u = 0; u < count; ++u) for (size_t i = 0; i < units[u]->itemCount; ++i) {
            RangeNode *node = units[u]->items[i];
            if (node->kind != RangeNodeMacro || !same(node->name,name)) continue;
            if (macro) fail(vm,node,"ambiguous literal macro '%s'",name);
            macro = node;
        }
        if (!macro || !macro->literalPattern) fail(vm,macro,"macro '%s' has no literal rule",name);
        *matched = literalMatch(vm,macro,macro->literalPattern,input);
        ok = 1;
    }
    free(vm);
    return ok;
}

/* Link plain top-level output references without replacing their source nodes.
 * Missing declarations and specialization remain deferred during inspection. */
static void resolveGraphOutputs(VM *vm)
{
    for (size_t u = 0; u < vm->count; ++u) {
        for (size_t i = 0; i < vm->units[u]->itemCount; ++i) {
            RangeNode *function = vm->units[u]->items[i];
            if (function->kind != RangeNodeFunction || function->generics) continue;
            RangeNode *output = function->b;
            if (!output || output->kind != RangeNodeName || output->flags || output->generics) continue;
            RangeNode *declaration = NULL;
            for (size_t v = 0; v < vm->count; ++v) {
                for (size_t j = 0; j < vm->units[v]->itemCount; ++j) {
                    RangeNode *candidate = vm->units[v]->items[j];
                    if (candidate->kind != RangeNodeConstruct || !same(candidate->name,output->name)) continue;
                    if (declaration) fail(vm,output,"ambiguous graph output '%s'",output->name);
                    declaration = candidate;
                }
            }
            output->resolvedDeclaration = declaration;
        }
    }
}

static int resolveGraphApplications(RangeArena *arena, RangeNode **units, size_t count,
                                    char *error, size_t errorSize)
{
    VM *vm = calloc(1,sizeof(*vm));
    if (!vm) { snprintf(error,errorSize,"cannot allocate graph resolver"); return 0; }
    vm->arena=arena; vm->units=units; vm->count=count; vm->error=error; vm->errorSize=errorSize;
    int ok = 0;
    if (setjmp(vm->failure) == 0) {
        for (size_t u = 0; u < count; ++u) validateGraphShape(vm,units[u],units[u]->source);
        registerLiteralRules(vm);
        for (size_t u = 0; u < count; ++u)
            for (size_t i = 0; i < units[u]->itemCount; ++i) resolveGraphTarget(vm,units[u]->items[i]);
        resolveGraphOutputs(vm);
        registerLiteralDefaults(vm);
        for (size_t u = 0; u < count; ++u) resolveLiteralDefaults(vm,units[u]);
        ok = 1;
    }
    free(vm);
    return ok;
}

/* Compiler driver: load source directories, parse their graph, and inspect or run it. */
#include "parser.h"
#include "graph.h"
#include <dirent.h>
#include <errno.h>
#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

typedef struct {
    const char **paths;
    size_t count;
    size_t capacity;
} Sources;

static int sourceError(const char *path)
{
    fprintf(stderr, "cannot load %s: %s\n", path, strerror(errno));
    return 0;
}

static int collectSources(RangeArena *arena, Sources *sources, const char *path, int nested)
{
    struct stat info;
    if (lstat(path, &info) != 0) return sourceError(path);
    int link = S_ISLNK(info.st_mode);
    if (link && stat(path, &info) != 0) return sourceError(path);
    if (S_ISDIR(info.st_mode)) {
        /* An explicitly supplied directory may be a symlink; recursive traversal
         * does not follow directory symlinks, which can lead outside Core or cycle. */
        if (nested && link) return 1;
        DIR *directory = opendir(path);
        if (!directory) return sourceError(path);
        int ok = 1;
        for (;;) {
            errno = 0;
            struct dirent *entry = readdir(directory);
            if (!entry) {
                if (errno) ok = sourceError(path);
                break;
            }
            if (!strcmp(entry->d_name, ".") || !strcmp(entry->d_name, "..")) continue;
            size_t length = strlen(path) + strlen(entry->d_name) + 2;
            char *child = malloc(length);
            if (!child) abort();
            snprintf(child, length, "%s/%s", path, entry->d_name);
            ok = collectSources(arena, sources, child, 1);
            free(child);
            if (!ok) break;
        }
        closedir(directory);
        return ok;
    }
    if (!S_ISREG(info.st_mode)) {
        if (nested) return 1;
        fprintf(stderr, "cannot load %s: expected a regular file or directory\n", path);
        return 0;
    }
    size_t length = strlen(path);
    if (nested && (length < 6 || strcmp(path + length - 6, ".range"))) return 1;
    char *resolved = realpath(path, NULL);
    if (!resolved) return sourceError(path);
    if (sources->count == sources->capacity) {
        size_t capacity = sources->capacity ? sources->capacity * 2 : 16;
        const char **paths = realloc(sources->paths, capacity * sizeof(*paths));
        if (!paths) abort();
        sources->paths = paths;
        sources->capacity = capacity;
    }
    sources->paths[sources->count++] = rangeArenaIntern(arena, resolved, strlen(resolved));
    free(resolved);
    return 1;
}

static int comparePaths(const void *left, const void *right)
{
    return strcmp(*(const char *const *)left, *(const char *const *)right);
}

static char *readFile(const char *path, size_t *size)
{
    FILE *stream = fopen(path, "rb");
    if (!stream) return NULL;
    if (fseek(stream, 0, SEEK_END) != 0) { fclose(stream); return NULL; }
    long length = ftell(stream);
    if (length < 0 || fseek(stream, 0, SEEK_SET) != 0) { fclose(stream); return NULL; }
    char *buffer = malloc((size_t)length + 1);
    if (!buffer) { fclose(stream); return NULL; }
    if (fread(buffer, 1, (size_t)length, stream) != (size_t)length) {
        fclose(stream); free(buffer); return NULL;
    }
    fclose(stream);
    buffer[length] = '\0';
    *size = (size_t)length;
    return buffer;
}


/* Flat per-source dumps; reject duplicate names before writing any files. */
static const char *sourceName(const char *path)
{
    const char *slash = strrchr(path, '/');
    return slash ? slash + 1 : path;
}

static int loadGraphTypes(RangeArena *arena, const char *directory)
{
    Sources sources = {0};
    int ok = 0;
    if (!collectSources(arena,&sources,directory,0)) goto cleanup;
    if (!sources.count) { fprintf(stderr,"no @type sources found in %s\n",directory); goto cleanup; }
    qsort(sources.paths,sources.count,sizeof(*sources.paths),comparePaths);
    arena->graphTypes = rangeNodeCreate(arena,RangeNodeUnit,directory,1,1);
    for (size_t i = 0; i < sources.count; ++i) {
        size_t size = 0;
        char *source = readFile(sources.paths[i],&size);
        if (!source) { sourceError(sources.paths[i]); goto cleanup; }
        char error[512];
        RangeNode *type = rangeParseGraphType(arena,sources.paths[i],source,size,error,sizeof(error));
        free(source);
        if (!type) { fprintf(stderr,"%s\n",error); goto cleanup; }
        if (rangeGraphType(arena,type->name)) {
            fprintf(stderr,"%s:1:1: duplicate @type '%s'\n",type->path,type->name); goto cleanup;
        }
        rangeNodeAppend(arena,arena->graphTypes,type);
    }
    ok = 1;
cleanup:
    free(sources.paths);
    return ok;
}

static int emitGraphs(RangeArena *arena, RangeNode **units, size_t count,
                      const char *directory)
{
    if (!*directory) { fprintf(stderr, "graph output directory is empty\n"); return 0; }
    for (size_t i = 0; i < count; ++i) {
        const char *name = sourceName(units[i]->path);
        const char *extension = strrchr(name, '.');
        size_t stem = extension ? (size_t)(extension - name) : strlen(name);
        for (size_t t = 0; t < arena->graphTypes->itemCount; ++t) {
            const char *type = arena->graphTypes->items[t]->name;
            if (strlen(type) == stem && !strncmp(name,type,stem)) {
                fprintf(stderr, "graph output name reserved for type definition: %s\n", name);
                return 0;
            }
        }
        for (size_t j = 0; j < i; ++j) {
            if (!strcmp(sourceName(units[i]->path), sourceName(units[j]->path))) {
                fprintf(stderr, "duplicate graph output name: %s\n", sourceName(units[i]->path));
                return 0;
            }
        }
    }
    char *folder = (char *)rangeArenaIntern(arena, directory, strlen(directory));
    for (char *p = folder + 1; ; ++p) {
        if (*p && *p != '/') continue;
        char saved = *p;
        *p = '\0';
        if (mkdir(folder, 0755) != 0 && errno != EEXIST) return sourceError(folder);
        *p = saved;
        if (!saved) break;
    }
    for (size_t i = 0; i < count + arena->graphTypes->itemCount; ++i) {
        const char *name = i < count ? sourceName(units[i]->path)
            : arena->graphTypes->items[i - count]->name;
        const char *extension = strrchr(name, '.');
        size_t stem = extension ? (size_t)(extension - name) : strlen(name);
        size_t length = strlen(directory) + stem + 6;
        char *path = rangeArenaAllocate(arena, length);
        snprintf(path, length, "%s/%.*s.txt", directory, (int)stem, name);
        FILE *output = fopen(path, "w");
        if (!output) return sourceError(path);
        if (i < count) rangeGraphWrite(output, units[i]);
        else rangeGraphWriteDefinition(output, arena->graphTypes->items[i - count]);
        int failed = ferror(output);
        if (fclose(output) != 0) failed = 1;
        if (failed) return sourceError(path);
        printf("graph=%s\n", path);
    }
    return 1;
}

#ifndef RANGE_GRAPH_TYPES_DIR
#define RANGE_GRAPH_TYPES_DIR "Language/Compiler/Types"
#endif

int main(int argc, char **argv)
{
    RangeArena arena;
    rangeArenaInit(&arena);
    int treeMode = 0;
    const char *entry = NULL;
    const char *literalMacro = NULL, *literalInput = NULL;
    const char *graphDirectory = NULL;
    const char *typesDirectory = RANGE_GRAPH_TYPES_DIR;
    int first = 1;
    if (argc > 2 && strcmp(argv[1],"--graph-types") == 0) { typesDirectory=argv[2]; first=3; }
    int option = first;
    if (argc > option + 2 && strcmp(argv[option],"--match-literal") == 0) {
        literalMacro=argv[option + 1]; literalInput=argv[option + 2]; first=option + 3;
    }
    else if (argc > option && strcmp(argv[option], "--tree") == 0) { treeMode = 1; first = option + 1; }
    else if (argc > option + 1 && strcmp(argv[option], "--run") == 0) { entry = argv[option + 1]; first = option + 2; }
    else if (argc > option + 1 && strcmp(argv[option], "--emit-graph") == 0) { graphDirectory = argv[option + 1]; first = option + 2; }
    if (first >= argc) { fprintf(stderr, "usage: compiler [--graph-types directory] [--tree | --emit-graph directory | --run function | --match-literal macro text] files-or-directories...\n"); return 64; }
    Sources sources = {0};
    RangeNode **units = NULL;
    int status = 66;
    if (!loadGraphTypes(&arena,typesDirectory)) { status=65; goto cleanup; }
    for (int index = first; index < argc; ++index) {
        if (!collectSources(&arena, &sources, argv[index], 0)) goto cleanup;
    }
    if (!sources.count) { fprintf(stderr, "no Range sources found\n"); goto cleanup; }
    qsort(sources.paths, sources.count, sizeof(*sources.paths), comparePaths);
    size_t unique = 0;
    for (size_t index = 0; index < sources.count; ++index) {
        if (!unique || strcmp(sources.paths[index], sources.paths[unique - 1]))
            sources.paths[unique++] = sources.paths[index];
    }
    sources.count = unique;
    units = calloc(sources.count, sizeof(*units));
    if (!units) { status = 70; goto cleanup; }
    size_t unitCount = 0;
    long counts[RangeNodeKindCount];
    memset(counts, 0, sizeof(counts));
    int failures = 0;
    for (size_t index = 0; index < sources.count; ++index) {
        const char *path = sources.paths[index];
        size_t size = 0;
        char *source = readFile(path, &size);
        if (!source) { fprintf(stderr, "cannot read %s\n", path); goto cleanup; }
        char error[512];
        RangeNode *unit = rangeParseUnit(&arena, path, source, size,
                                         error, sizeof(error));
        free(source);
        if (!unit) { fprintf(stderr, "%s\n", error); failures += 1; continue; }
        units[unitCount++] = unit;
        if (treeMode) { rangeGraphWriteTree(stdout, unit, 0); continue; }
        for (size_t item = 0; item < unit->itemCount; ++item) {
            counts[unit->items[item]->kind] += 1;
        }
    }
    if (graphDirectory && !failures) {
        char error[512];
        if (!resolveGraphApplications(&arena, units, unitCount, error, sizeof(error))) {
            fprintf(stderr,"%s\n",error);
            failures += 1;
        }
    }
    if (graphDirectory && !failures && !emitGraphs(&arena, units, unitCount, graphDirectory)) {
        status = 74;
        goto cleanup;
    }
    if (entry && !failures) {
        int64_t result = 0;
        char error[512];
        if (!rangeExecute(&arena, units, unitCount, entry, &result, error, sizeof(error))) {
            fprintf(stderr, "%s\n", error);
            failures += 1;
        } else printf("result=%" PRId64 "\n", result);
    }
    if (literalMacro && !failures) {
        char error[512]; int matched = 0;
        if (!matchLiteralRule(&arena,units,unitCount,literalMacro,literalInput,&matched,error,sizeof(error))) {
            fprintf(stderr,"%s\n",error); failures += 1;
        } else printf("match=%s\n",matched ? "true" : "false");
    }
    status = failures ? 65 : 0;
    if (entry || treeMode || graphDirectory || literalMacro) goto cleanup;
    printf("sources=%zu nodes=%zu construct=%ld enum=%ld function=%ld macro=%ld main=%ld failures=%d\n",
           sources.count, arena.nodeCount, counts[RangeNodeConstruct], counts[RangeNodeEnum],
           counts[RangeNodeFunction], counts[RangeNodeMacro], counts[RangeNodeMain],
           failures);
cleanup:
    free(units);
    free(sources.paths);
    rangeArenaDestroy(&arena);
    return status;
}
