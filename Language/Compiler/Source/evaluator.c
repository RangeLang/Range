/* Known values: the evaluator macro bodies run in, which native code also
 * folds with. */
#define _XOPEN_SOURCE 700
#include "compiler.h"
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* ---- known values ------------------------------------------------------------
 * Macros are ordinary Range code, run here on the values they know: a macro
 * body as the type checker typed it, and every function, closure,
 * construction, and operator it reaches, each the declaration or the C
 * primitive typing chose, as native code runs it. A value keeps the type it
 * was made with, so what typing left to macro time (a value of a macro type,
 * a member kind's value) is chosen from the value it holds when it runs.
 * What only a macro has, its application's target fields, effects, #graph
 * emission, and the applications a use of a declaration needs first, is
 * reached through those nodes alone; outside an application they are not
 * known. Evaluation stops with a message, which the application reports, or
 * with none when typing reported the problem already.
 *
 * Native code runs the same evaluator on the body it compiles, folding: the
 * root frame is that body's, whose names native code holds, and a value is
 * known before run only when everything it reaches is. What is known only at
 * run, an effect, a trap, a limit, or typing that has not run leaves it
 * unknown, and native code compiles it as written. */

static int evalStatement(Eval *, EvalFrame *, RangeNode *);
static int evalInvoke(Eval *, RangeNode *, RangeNode *, RangeValue *, RangeValue *, RangeNode *, RangeValue *);
static int evalConstruct(Eval *, EvalFrame *, RangeNode *, RangeNode **, size_t, RangeNode *, RangeValue *);

static int evalFail(Eval *eval, RangeNode *at, const char *format, ...)
{
    char text[512]; va_list args; va_start(args,format);
    vsnprintf(text,sizeof(text),format,args); va_end(args);
    eval->message = rangeArenaIntern(eval->vm->arena,text,strlen(text));
    eval->at = at;
    return EvalFailed;
}

/* A problem typing reported already: evaluation stops without another report. */
static int evalStop(Eval *eval)
{
    eval->message = NULL;
    return EvalFailed;
}

/* A limit a macro reports; folding, the value is left to run. */
static int evalLimit(Eval *eval, RangeNode *at, const char *message)
{
    return eval->outside ? EvalUnknown : evalFail(eval,at,"%s",message);
}

static int evalStep(Eval *eval, RangeNode *at)
{
    return ++eval->steps > 100000 ? evalLimit(eval,at,"compile-time evaluation step limit exceeded") : EvalNormal;
}

static int evalDeeper(Eval *eval, RangeNode *at)
{
    return ++eval->depth > 64 ? evalLimit(eval,at,"compile-time call depth exceeded") : EvalNormal;
}

/* Whether a frame is the body native code compiles, or one inside it. */
static int evalRooted(const Eval *eval, const EvalFrame *frame)
{
    for (; eval->outside && frame; frame = frame->parent) if (frame == eval->root) return 1;
    return 0;
}

RangeValue *evalNamed(EvalFrame *frame, const RangeNode *declaration)
{
    for (; frame && declaration; frame = frame->parent)
        for (EvalBinding *binding = frame->bindings; binding; binding = binding->next)
            if (binding->declaration == declaration) return &binding->value;
    return NULL;
}

static void evalBind(Eval *eval, EvalFrame *frame, RangeNode *declaration, RangeValue value)
{
    for (EvalBinding *binding = frame->bindings; binding; binding = binding->next)
        if (binding->declaration == declaration) { binding->value = value; return; }
    EvalBinding *binding = rangeArenaAllocate(eval->vm->arena,sizeof(*binding));
    *binding = (EvalBinding){.declaration=declaration,.value=value,.next=frame->bindings};
    frame->bindings = binding;
}

/* The index of a member of the receiver's construct, or SIZE_MAX. */
static size_t evalMember(const RangeValue *self, RangeNode *member)
{
    if (!self || self->kind != ValueInstance || !member) return SIZE_MAX;
    size_t index = nativeMemberIndex(self->type->resolvedDeclaration,member);
    return index < self->count ? index : SIZE_MAX;
}

/* A value's members or slots change only through its own place: their array
 * is copied first, so the copies of the value made before never change. */
static void evalOwn(Eval *eval, RangeValue *value)
{
    RangeValue *values = rangeArenaAllocate(eval->vm->arena,(value->count ? value->count : 1) * sizeof(*values));
    if (value->count) memcpy(values,value->values,value->count * sizeof(*values));
    value->values = values;
}

static RangeValue *evalValues(Eval *eval, size_t count)
{
    RangeValue *values = rangeArenaAllocate(eval->vm->arena,(count ? count : 1) * sizeof(*values));
    memset(values,0,(count ? count : 1) * sizeof(*values));
    return values;
}

/* A Bool: the condition type's case whose tag is the truth. Without the
 * condition type a boolean literal stands for it. */
static RangeValue evalBool(Eval *eval, int truth)
{
    RangeNode *condition = eval->typer->boolean;
    for (size_t i = 0; condition && condition->kind == RangeNodeEnum && i < condition->itemCount; ++i)
        if (condition->items[i]->kind == RangeNodeEnumCase && condition->items[i]->integer == truth)
            return (RangeValue){.kind=ValueCase,.type=eval->typer->booleanType,.node=condition->items[i]};
    RangeNode *literal = rangeNodeCreate(eval->vm->arena,RangeNodeBool,"<compiler>",1,1);
    literal->integer = truth;
    return (RangeValue){.kind=ValueLiteral,.node=literal,.integer=truth};
}

int evalTruth(RangeValue value)
{
    return value.kind == ValueCase ? value.node->integer != 0 : value.integer != 0;
}

/* A type with a storage primitive is a scalar that many bits wide, signed
 * or not, as its specialization declares: the members layout reads. */
static int scalarShape(RangeNode *type, int *bits, int *isSigned)
{
    if (!type || type->kind != RangeNodeSpecialization) return 0;
    RangeNode *declaration = type->resolvedDeclaration, *width = NULL, *signedness = NULL;
    for (size_t i = 0; i < declaration->itemCount; ++i) {
        if (builtinMember(declaration->items[i]) && same(declaration->items[i]->name,"storage")) width = builtinValue(type,declaration->items[i]);
        if (builtinMember(declaration->items[i]) && same(declaration->items[i]->name,"signed")) signedness = builtinValue(type,declaration->items[i]);
    }
    if (!width || width->kind != RangeNodeInteger || width->integer <= 0 || width->integer > 64) return 0;
    *bits = (int)width->integer;
    *isSigned = signedness && signedness->kind == RangeNodeBool && signedness->integer;
    return 1;
}

static __int128 scalarValue(RangeValue value, int isSigned)
{
    return isSigned ? (__int128)value.integer : (__int128)(unsigned long long)value.integer;
}

static int scalarFits(__int128 value, int bits, int isSigned)
{
    __int128 low = isSigned ? -((__int128)1 << (bits - 1)) : 0;
    __int128 high = isSigned ? ((__int128)1 << (bits - 1)) - 1 : ((__int128)1 << bits) - 1;
    return value >= low && value <= high;
}

/* The type a literal has where nothing else gives it one: its family's. */
static RangeNode *literalType(Typer *typer, RangeNode *literal)
{
    return literal && literal->resolvedType ? specialize(typer,NULL,literal->resolvedType,NULL,NULL,literal) : NULL;
}

/* A value meeting a typed use: a literal takes the type, if its storage holds
 * it (the type's laws are not run), and a value where an optional of its
 * type is expected is the optional's present case holding it. */
static int evalAdopt(Eval *eval, RangeValue *value, RangeNode *type, RangeNode *at)
{
    if (!type || type->kind != RangeNodeSpecialization || value->kind == ValueNone || value->kind == ValueClosure) return EvalNormal;
    RangeNode *present = NULL, *wrapped = optionalWrapped(eval->typer,type,&present);
    if (wrapped && !(value->kind == ValueCase && value->type && value->type->resolvedDeclaration == type->resolvedDeclaration)) {
        RangeValue *payload = evalValues(eval,1);
        *payload = *value;
        int status = evalAdopt(eval,payload,wrapped,at);
        *value = (RangeValue){.kind=ValueCase,.type=type,.node=present,.values=payload,.count=1};
        return status;
    }
    if (value->kind != ValueLiteral) return EvalNormal;
    RangeNode *literal = value->node, *declaration = type->resolvedDeclaration;
    char name[160]; describeType(name,sizeof(name),type);
    int bits, isSigned;
    if (literal->kind == RangeNodeString && bytesDeclaration(declaration)) {
        *value = (RangeValue){.kind=ValueText,.type=type,.node=literal,.text=value->text,.length=value->length};
        return EvalNormal;
    }
    if (literal->kind == RangeNodeBool && declaration->kind == RangeNodeEnum) {
        RangeNode spelled = {.kind=RangeNodeBool,.integer=value->integer}, *entry = literalCase(declaration,&spelled);
        if (entry) { *value = (RangeValue){.kind=ValueCase,.type=type,.node=entry}; return EvalNormal; }
    }
    if (literal->kind == RangeNodeInteger && scalarShape(type,&bits,&isSigned)) {
        if (!scalarFits(value->integer,bits,isSigned)) return evalFail(eval,at,"%lld does not fit %s",value->integer,name);
        *value = (RangeValue){.kind=ValueScalar,.type=type,.integer=value->integer};
        return EvalNormal;
    }
    return evalFail(eval,at,"a %s literal is not a value of %s",
                    literal->kind == RangeNodeString ? "string" : literal->kind == RangeNodeBool ? "boolean" : "numeric",name);
}

/* ---- text ---- */

/* A value as a message writes it: integers in decimal, a case without a
 * payload by its name, text as its bytes, a declaration by its name. */
int evalWrite(Eval *eval, RangeValue value, RangeNode *at, const char **text, size_t *length)
{
    char piece[64];
    int bits = 64, isSigned = 1;
    switch (value.kind) {
    case ValueText: *text = value.text; *length = value.length; return EvalNormal;
    case ValueLiteral:
        if (value.node->kind == RangeNodeString) { *text = value.text; *length = value.length; return EvalNormal; }
        if (value.node->kind == RangeNodeBool) { *text = value.integer ? "true" : "false"; *length = strlen(*text); return EvalNormal; }
        snprintf(piece,sizeof(piece),"%lld",value.integer);
        break;
    case ValueScalar:
        (void)scalarShape(value.type,&bits,&isSigned);
        snprintf(piece,sizeof(piece),isSigned ? "%lld" : "%llu",value.integer);
        break;
    case ValueCase:
        if (value.count) return evalFail(eval,at,"a compile-time message cannot interpolate this value");
        *text = value.node->name; *length = strlen(*text);
        return EvalNormal;
    case ValueDeclaration:
        if (!value.node->name) return evalFail(eval,at,"a compile-time message cannot interpolate this value");
        *text = value.node->name; *length = strlen(*text);
        return EvalNormal;
    default: return evalFail(eval,at,"a compile-time message cannot interpolate this value");
    }
    *length = strlen(piece);
    *text = rangeArenaIntern(eval->vm->arena,piece,*length);
    return EvalNormal;
}

/* The text of a message or a string literal: its literal parts, and its
 * interpolated values as they are written. */
static int evalText(Eval *eval, EvalFrame *frame, RangeNode *node, const char **text, size_t *length)
{
    int status;
    if (node->kind != RangeNodeString) {
        RangeValue value;
        status = evalExpression(eval,frame,node,&value);
        return status ? status : evalWrite(eval,value,node,text,length);
    }
    size_t used = 0, capacity = 64;
    char *buffer = malloc(capacity);
    if (!buffer) abort();
    for (size_t i = 0; i < node->itemCount; ++i) {
        RangeNode *part = node->items[i];
        const char *piece = part->name;
        size_t size = (size_t)part->integer;
        if (!(part->flags & RangeFlagLiteral)) {
            RangeValue value;
            status = evalExpression(eval,frame,part->a,&value);
            if (!status) status = evalWrite(eval,value,part->a,&piece,&size);
            if (status) { free(buffer); return status; }
        }
        while (used + size + 1 > capacity) {
            capacity *= 2;
            buffer = realloc(buffer,capacity);
            if (!buffer) abort();
        }
        memcpy(buffer + used,piece,size);
        used += size;
    }
    *text = rangeArenaIntern(eval->vm->arena,buffer,used);
    *length = used;
    free(buffer);
    return EvalNormal;
}

/* ---- the macro-only inputs ---- */

/* A declaration's members and functions include what its written macros
 * emit, so a use of it at macro time first applies those that have not run:
 * `#target.cases.first()` needs the functions @collection gives Array. A failure
 * there fails the application that needed it. */
static void evalPrepare(Eval *eval, RangeNode *declaration)
{
    Resolver *vm = eval->vm;
    if (eval->outside) return; /* folding: every application has run */
    for (size_t i = 0; declaration->c && i < declaration->c->itemCount; ++i) {
        RangeNode *attribute = declaration->c->items[i];
        RangeMacroApplication *app = attribute->macroApplication;
        if (compilerAttribute(declaration,attribute) || !app || app->applied) continue;
        app->applied = 1;
        RangeNode *emitted = vm->emitted, *unit = vm->unit;
        vm->unit = app->unit ? app->unit : unit;
        for (size_t u = 0; u < vm->count; ++u)
            for (size_t j = 0; j < vm->units[u]->itemCount; ++j)
                if (vm->units[u]->items[j] == declaration) vm->unit = vm->units[u];
        mergeEmitted(vm,runMacroApplication(vm,attribute));
        vm->emitted = emitted; vm->unit = unit;
    }
}

/* In a law run, the value the checked specialization gives a declaration:
 * a generic's value there, or the literal in the member it populates; NULL
 * for any other declaration, or outside a law run. */
static RangeNode *lawValue(const RangeMacroApplication *law, RangeNode *declaration)
{
    if (!law || !law->specialization) return NULL;
    if (declaration == law->slot) return law->literal;
    RangeNode **slot = genericSlot(law->specialization,declaration);
    return slot ? *slot : NULL;
}

/* `.value` of a member kind: its initializer, known at macro time, or in a
 * law run the value the checked specialization gives it. A literal is a
 * value of no type yet, which takes its use's type; anything else is typed
 * where it is declared and run without a receiver, so a read of another
 * member is not known. */
static int evalInitializer(Eval *eval, RangeNode *declaration, RangeNode *at, RangeValue *out)
{
    RangeNode *rhs = lawValue(eval->application,declaration);
    if (!rhs) {
        RangeGraphValue raw = rangeGraphStoredField(eval->vm->arena,declaration,"value");
        rhs = raw.kind == RangeGraphNode ? raw.node : NULL;
    }
    RangeNodeKind kind; long long integer; const char *text;
    if (rhs && lawInputs(rhs,&kind,&integer,&text)) {
        *out = (RangeValue){.kind=ValueLiteral,.node=rhs->kind == RangeNodeUnary ? rhs->a : rhs,.integer=integer,
                            .text=text,.length=text ? strlen(text) : 0};
        return EvalNormal;
    }
    typeValueOnDemand(eval->typer,declaration);
    // What typing recorded beside the declaration, such as the absent case
    // `let v: T?` starts as, else what is written.
    if (declaration->lowered) rhs = declaration->lowered;
    if (!rhs) return evalFail(eval,at,"the value of '%s' is not known at macro time",declaration->name);
    EvalFrame none = {0};
    return evalExpression(eval,&none,rhs,out);
}

/* A reflection list, such as Enum.cases: Array<EnumCase>, is the collection
 * its grammar field's type names, built as Range builds one: constructed,
 * then each declaration added in order with the collection's @insertion
 * function. The collection declares @iteration too, so the list can be read. */
static int evalList(Eval *eval, RangeNode *grammar, const char *name, RangeNode *type, RangeGraphValue raw,
                    RangeNode *at, RangeValue *out)
{
    RangeNode *collection = type && type->kind == RangeNodeSpecialization ? type->resolvedDeclaration : NULL;
    if (!collection || collection->kind != RangeNodeConstruct)
        return evalFail(eval,at,"reflection field %s.%s holds declarations; its type must be a collection construct",grammar->name,name);
    // The collection's own applications run first: they may emit the
    // @insertion function, as @collection does for Array.
    evalPrepare(eval,collection);
    size_t insertions = 0, iterations = 0;
    RangeNode *append = insertionFunction(collection,&insertions);
    if (insertions != 1 || append->itemCount != 1)
        return evalFail(eval,at,"reflection field %s.%s is %s, which %s to build it with%s",grammar->name,name,collection->name,
                        insertions > 1 ? "declares more than one @insertion function"
                        : insertions ? "declares an @insertion function that does not take one element"
                        : "declares no @insertion function",
                        eval->vm->emitted ? "; a macro that defines it cannot reflect through it" : "");
    (void)iterationFunction(collection,&iterations);
    if (iterations != 1)
        return evalFail(eval,at,"reflection field %s.%s is %s, which %s; a reflection list's collection declares both @iteration and @insertion%s",
                        grammar->name,name,collection->name,
                        iterations ? "declares more than one @iteration function" : "declares no @iteration function",
                        eval->vm->emitted ? "; a macro that defines it cannot reflect through it" : "");
    // The list as it stands now: adding may merge emitted members into it.
    RangeNode **nodes = rangeArenaAllocate(eval->vm->arena,(raw.count ? raw.count : 1) * sizeof(*nodes));
    if (raw.count) memcpy(nodes,raw.nodes,raw.count * sizeof(*nodes));
    EvalFrame none = {0};
    int status = evalConstruct(eval,&none,type,NULL,0,at,out);
    for (size_t i = 0; !status && i < raw.count; ++i) {
        RangeValue element = {.kind=ValueDeclaration,.node=nodes[i]}, ignored;
        status = evalInvoke(eval,append,NULL,out,&element,at,&ignored);
    }
    return status;
}

/* `.field` of a declaration, such as `#target.members`: what C's adapter
 * holds there, as the value its grammar member's type says. An element of
 * `#target.macros`, an application, reads as the Macro it applies: its name. */
static int evalField(Eval *eval, RangeNode *owner, const char *name, RangeNode *at, RangeValue *out)
{
    RangeArena *arena = eval->vm->arena;
    if (eval->outside) return EvalUnknown; /* declarations are values of macros only */
    RangeNode *shape = owner->graphType ? owner->graphType : owner->kind == RangeNodeAttribute ? rangeGraphType(arena,"Macro") : NULL;
    if (!rangeGraphField(shape,name) || (!owner->graphType && !same(name,"name")))
        return evalFail(eval,at,"field '%s' is not declared by @type %s",name,shape ? shape->name : rangeNodeKindName(owner->kind));
    if (same(name,"value") && rangeNodeDeclaresValue(owner->kind)) return evalInitializer(eval,owner,at,out);
    RangeGraphValue raw = rangeGraphStoredField(arena,owner,name);
    const RangeMacroApplication *law = eval->application && eval->application->specialization ? eval->application : NULL;
    if (law && owner == law->target && raw.kind == RangeGraphNodes
        && (same(name,"members") || same(name,"functions") || same(name,"cases"))) {
        // A law run reads the target as it was when the run began, without
        // what its own application emitted: that is its output, not its input.
        RangeNode **seen = rangeArenaAllocate(arena,(raw.count ? raw.count : 1) * sizeof(*seen));
        size_t count = 0;
        for (size_t i = 0; i < raw.count; ++i)
            if (raw.nodes[i]->emittedBy != law->attribute && nativeMemberIndex(owner,raw.nodes[i]) < law->items) seen[count++] = raw.nodes[i];
        raw.nodes = seen;
        raw.count = count;
    }
    RangeNode *grammar = owner->graphType ? grammarDeclaration(eval->vm,owner) : shape->resolvedDeclaration;
    RangeNode *member = grammar ? findMember(grammar,name) : NULL;
    if (!member && raw.kind == RangeGraphNodes)
        return evalFail(eval,at,"reflection field '%s' has no Range type: %s declares no member '%s' in the loaded grammar",
                        name,grammar ? grammar->name : shape->name,name);
    RangeNode *type = member ? memberType(eval->typer,grammar,member,ownSpecialization(eval->typer,grammar)) : NULL;
    if (raw.kind == RangeGraphNodes) return evalList(eval,grammar,name,type,raw,at,out);
    *out = raw.kind == RangeGraphText ? (RangeValue){.kind=ValueText,.node=owner,.text=raw.text,.length=strlen(raw.text)}
        : raw.kind == RangeGraphNode ? (RangeValue){.kind=ValueDeclaration,.node=raw.node} : (RangeValue){0};
    // An optional field, such as Function.output, is a case of the optional.
    RangeNode *present = NULL;
    if (type && optionalWrapped(eval->typer,type,&present) && out->kind == ValueNone) {
        for (size_t i = 0; i < type->resolvedDeclaration->itemCount; ++i)
            if (type->resolvedDeclaration->items[i]->kind == RangeNodeEnumCase && !type->resolvedDeclaration->items[i]->itemCount)
                *out = (RangeValue){.kind=ValueCase,.type=type,.node=type->resolvedDeclaration->items[i]};
        return EvalNormal;
    }
    if (out->kind == ValueText && !deferredType(eval->typer,type)) out->type = type;
    return evalAdopt(eval,out,type,at);
}

/* `@print`, `@warning`, and `@diagnostic`: the message, written to the
 * compiler's output, reported as a warning at the application (a law run per
 * specialization repeats nothing), or ending evaluation as a failure there. */
static int evalEffect(Eval *eval, EvalFrame *frame, RangeNode *attribute)
{
    RangeNode *macro = attribute->resolvedDeclaration;
    int print = macroBuiltin(macro,"print"), warning = macroBuiltin(macro,"warning");
    if (!print && !warning && !macroBuiltin(macro,"diagnostic"))
        return evalFail(eval,attribute,"@%s is not an effect C runs at macro time",attribute->name);
    if (eval->outside) return EvalUnknown; /* folding: effects happen at run */
    if (attribute->itemCount != 1) return evalStop(eval);
    const char *text; size_t length;
    int status = evalText(eval,frame,attribute->items[0]->a,&text,&length);
    if (status) return status;
    if (warning) {
        RangeNode *at = eval->application && eval->application->attribute ? eval->application->attribute : attribute;
        if (eval->vm->report && !(eval->application && eval->application->specialization))
            sourceDiagnostic(eval->vm->report,at,1,"macro","%.*s",(int)length,text);
        return EvalNormal;
    }
    if (!print) return evalFail(eval,attribute,"%.*s",(int)length,text);
    printf("%.*s\n",(int)length,text);
    return EvalNormal;
}

/* A copy #graph emits is new code: what the compiler found about the
 * original is found about it afresh. */
static void forgetFacts(RangeNode *copy)
{
    copy->found = 0;
    copy->lowered = copy->narrowed = copy->promoted = copy->specialization = NULL;
}

/* A spliced value becomes the source a person would have written there: a
 * declaration or a name, a reference; a literal or a scalar, a literal.
 * `#target.field` is the node or the name C holds there. */
static int evalSplice(Eval *eval, EvalFrame *frame, RangeNode *at, RangeNode **out)
{
    RangeArena *arena = eval->vm->arena;
    RangeValue value;
    if (at->kind == RangeNodeMemberAccess && at->a->kind == RangeNodeEnvironment && same(at->a->name,"target")
        && !found(frame->key,at)->narrowed) {
        RangeGraphValue raw = rangeGraphStoredField(arena,eval->application->target,at->name);
        if (raw.kind == RangeGraphNodes) return evalFail(eval,at,"cannot splice a list of %zu declarations",raw.count);
        value = raw.kind == RangeGraphText ? (RangeValue){.kind=ValueText,.text=raw.text,.length=strlen(raw.text)}
            : raw.kind == RangeGraphNode ? (RangeValue){.kind=ValueDeclaration,.node=raw.node} : (RangeValue){0};
    } else {
        int status = evalExpression(eval,frame,at,&value);
        if (status) return status;
    }
    RangeNode *node = NULL;
    char spelled[32];
    int bits = 64, isSigned = 1;
    switch (value.kind) {
    case ValueNone: return evalFail(eval,at,"splice has no value");
    case ValueDeclaration: case ValueText:
        if (value.kind == ValueText && value.node && value.node->kind == RangeNodeString) break;
        node = rangeNodeCreate(arena,RangeNodeName,at->path,at->line,at->column);
        node->name = value.kind == ValueText ? rangeArenaIntern(arena,value.text,value.length) : value.node->name;
        if (!node->name) return evalFail(eval,at,"cannot splice an unnamed %s",rangeNodeKindName(value.node->kind));
        if (value.kind == ValueDeclaration) node->resolvedDeclaration = value.node;
        break;
    case ValueLiteral: case ValueScalar:
        if (value.kind == ValueLiteral && value.node->kind != RangeNodeInteger) break;
        (void)scalarShape(value.type,&bits,&isSigned);
        node = rangeNodeCreate(arena,RangeNodeInteger,at->path,at->line,at->column);
        node->integer = isSigned && value.integer < 0 ? -value.integer : value.integer;
        snprintf(spelled,sizeof(spelled),isSigned ? "%lld" : "%llu",node->integer);
        node->name = rangeArenaIntern(arena,spelled,strlen(spelled));
        if (isSigned && value.integer < 0) {
            RangeNode *negative = rangeNodeCreate(arena,RangeNodeUnary,at->path,at->line,at->column);
            negative->name = "-";
            negative->a = node;
            node = negative;
        }
        break;
    case ValueCase:
        if (value.type && value.type->resolvedDeclaration == eval->typer->boolean) {
            node = rangeNodeCreate(arena,RangeNodeBool,at->path,at->line,at->column);
            node->integer = value.node->integer;
            break;
        }
        return evalFail(eval,at,"cannot splice a compile-time enum value");
    default: return evalFail(eval,at,"cannot splice a compile-time %s value",value.kind == ValueClosure ? "closure" : "construct");
    }
    if (!node) {
        // A string or boolean literal, copied where the splice stands.
        node = rangeArenaAllocate(arena,sizeof(*node));
        *node = *value.node;
        forgetFacts(node);
        node->path = at->path; node->line = at->line; node->column = at->column;
    }
    node->emittedBy = eval->application->attribute;
    *out = node;
    return EvalNormal;
}

/* Copy one quoted declaration for this application, filling its splices.
 * Nested macro declarations keep their own splices for their own runs. */
static int evalEmitNode(Eval *eval, EvalFrame *frame, RangeNode *node, int splice, RangeNode **out)
{
    *out = NULL;
    if (!node) return EvalNormal;
    RangeNode *attribute = eval->application->attribute;
    if (splice && spliceChain(node)) return evalSplice(eval,frame,node,out);
    if (node->kind == RangeNodeMacro) splice = 0;
    size_t mask = eval->emittedCapacity - 1, slot = ((uintptr_t)node >> 4) & mask;
    if (eval->emittedCapacity)
        for (; eval->emittedFrom[slot]; slot = (slot + 1) & mask)
            if (eval->emittedFrom[slot] == node) { *out = eval->emittedTo[slot]; return EvalNormal; }
    if (2 * (eval->emittedCount + 1) > eval->emittedCapacity) {
        // Grow, keeping every pair.
        size_t capacity = eval->emittedCapacity ? eval->emittedCapacity * 2 : 256;
        RangeNode **from = rangeArenaAllocate(eval->vm->arena,capacity * sizeof(*from));
        RangeNode **to = rangeArenaAllocate(eval->vm->arena,capacity * sizeof(*to));
        memset(from,0,capacity * sizeof(*from));
        for (size_t i = 0; i < eval->emittedCapacity; ++i) {
            if (!eval->emittedFrom[i]) continue;
            size_t j = ((uintptr_t)eval->emittedFrom[i] >> 4) & (capacity - 1);
            while (from[j]) j = (j + 1) & (capacity - 1);
            from[j] = eval->emittedFrom[i]; to[j] = eval->emittedTo[i];
        }
        eval->emittedFrom = from; eval->emittedTo = to; eval->emittedCapacity = capacity;
        mask = capacity - 1;
        for (slot = ((uintptr_t)node >> 4) & mask; from[slot]; slot = (slot + 1) & mask) {}
    }
    RangeNode *copy = rangeArenaAllocate(eval->vm->arena,sizeof(*copy));
    *copy = *node;
    eval->emittedFrom[slot] = node; eval->emittedTo[slot] = copy; ++eval->emittedCount;
    copy->emittedBy = attribute;
    forgetFacts(copy);
    copy->resolvedDeclaration = NULL;
    copy->macroApplication = NULL;
    copy->items = NULL; copy->itemCount = 0; copy->itemCapacity = 0;
    int status;
    if ((status = evalEmitNode(eval,frame,node->a,splice,&copy->a))
        || (status = evalEmitNode(eval,frame,node->b,splice,&copy->b))
        || (status = evalEmitNode(eval,frame,node->c,splice,&copy->c))
        || (status = evalEmitNode(eval,frame,node->generics,splice,&copy->generics))
        || (status = evalEmitNode(eval,frame,node->annotations,splice,&copy->annotations))
        || (status = evalEmitNode(eval,frame,node->rhsReference,splice,&copy->rhsReference))) return status;
    for (size_t i = 0; i < node->itemCount; ++i) {
        RangeNode *item;
        if ((status = evalEmitNode(eval,frame,node->items[i],splice,&item))) return status;
        rangeNodeAppend(eval->vm->arena,copy,item);
    }
    if (splice) spliceDeclarationType(copy,node);
    *out = copy;
    return EvalNormal;
}

/* A #graph block's declarations, into the running application's output. */
static int evalEmit(Eval *eval, EvalFrame *frame, RangeNode *emission)
{
    for (size_t i = 0; i < emission->b->itemCount; ++i) {
        // Each emitted declaration is a fresh copy, sharing only within itself.
        if (eval->emittedCapacity) memset(eval->emittedFrom,0,eval->emittedCapacity * sizeof(*eval->emittedFrom));
        eval->emittedCount = 0;
        RangeNode *copy;
        int status = evalEmitNode(eval,frame,emission->b->items[i],1,&copy);
        if (status) return status;
        rangeNodeAppend(eval->vm->arena,eval->vm->emitted,copy);
    }
    return EvalNormal;
}

/* ---- calls ---- */

/* The element type of `member`, @many storage of `type`. */
RangeNode *manyElement(Typer *typer, RangeNode *type, RangeNode *member)
{
    SourceScope scope = {.owner=type->resolvedDeclaration};
    return resolveTypeReference(typer,&scope,member->typeName,member->generics,member->flags & ~RangeFlagMany,type,member);
}

/* The value of `type` that zeroed storage holds, as native code zero-fills
 * new slots: a scalar 0, no bytes, an enum's tag-0 case with zero fields,
 * or a construct with zero members and no slots. A field stored out of
 * line, as one holding its own enum is, holds no value then. */
static RangeValue evalZero(Eval *eval, RangeNode *type, unsigned depth)
{
    int bits, isSigned;
    if (!type || type->kind != RangeNodeSpecialization || depth > 16) return (RangeValue){0};
    RangeNode *declaration = type->resolvedDeclaration;
    if (scalarShape(type,&bits,&isSigned)) return (RangeValue){.kind=ValueScalar,.type=type};
    if (bytesDeclaration(declaration)) return (RangeValue){.kind=ValueText,.type=type,.text=""};
    int variant = declaration->kind == RangeNodeEnum;
    RangeValue zero = {.kind=variant ? ValueCase : ValueInstance,.type=type,.count=variant ? 0 : declaration->itemCount};
    for (size_t i = 0; variant && !zero.node && i < declaration->itemCount; ++i)
        if (declaration->items[i]->kind == RangeNodeEnumCase && !declaration->items[i]->integer) {
            zero.node = declaration->items[i];
            zero.count = zero.node->itemCount;
        }
    zero.values = evalValues(eval,zero.count);
    for (size_t i = 0; i < zero.count; ++i) {
        RangeNode *member = variant ? zero.node->items[i] : declaration->items[i];
        if (!variant && (!rangeNodeDeclaresValue(member->kind) || builtinMember(member))) continue;
        zero.values[i] = member->flags & RangeFlagMany ? (RangeValue){.kind=ValueSlots}
            : evalZero(eval,memberTypeIn(eval->typer,type,member),depth + 1);
    }
    return zero;
}

/* A C primitive a function declares with @builtin, on its receiver: one
 * byte of the bytes primitive, or the slot primitives on the receiver's one
 * @many member, whose new slots hold zero values. Each new slot is a step. */
static int evalBuiltin(Eval *eval, RangeNode *function, RangeValue *self, RangeValue *arguments, RangeNode *at, RangeValue *out)
{
    if (self && self->kind == ValueText && same(function->name,"byte") && function->itemCount == 1) {
        if (arguments[0].integer < 0 || (size_t)arguments[0].integer >= self->length) return evalFail(eval,at,"byte index is outside the bytes");
        *out = (RangeValue){.kind=ValueScalar,.type=function->type,.integer=(unsigned char)self->text[arguments[0].integer]};
        return EvalNormal;
    }
    if (!self || self->kind != ValueInstance || !slotPrimitive(function))
        return evalFail(eval,at,"no C primitive is implemented for builtin function '%s'",function->name);
    RangeNode *declaration = self->type->resolvedDeclaration;
    size_t many = SIZE_MAX, found = 0;
    for (size_t i = 0; i < self->count; ++i)
        if (rangeNodeDeclaresValue(declaration->items[i]->kind) && (declaration->items[i]->flags & RangeFlagMany)) { many = i; ++found; }
    if (found != 1) return evalFail(eval,at,"builtin function '%s' requires exactly one @many member in %s",function->name,declaration->name);
    evalOwn(eval,self);
    RangeValue *slots = &self->values[many];
    long long index = arguments[0].integer;
    if (same(function->name,"resize")) {
        if (index < 0) return evalFail(eval,at,"resize to a negative slot count");
        size_t kept = (size_t)index < slots->count ? (size_t)index : slots->count;
        eval->steps += (size_t)index - kept < 100000 ? (unsigned)((size_t)index - kept) : 100000;
        int status = evalStep(eval,at);
        if (status) return status;
        RangeValue *values = evalValues(eval,(size_t)index), zero = evalZero(eval,manyElement(eval->typer,self->type,declaration->items[many]),0);
        memcpy(values,slots->values,kept * sizeof(*values));
        for (size_t i = kept; i < (size_t)index; ++i) values[i] = zero;
        *slots = (RangeValue){.kind=ValueSlots,.values=values,.count=(size_t)index};
        return EvalNormal;
    }
    if (index < 0 || (size_t)index >= slots->count) return evalFail(eval,at,"slot index is outside the @many storage");
    if (same(function->name,"read")) { *out = slots->values[index]; return EvalNormal; }
    evalOwn(eval,slots);
    slots->values[index] = arguments[1];
    return EvalNormal;
}

/* Run `function`, as typed under `key`, with these arguments, one per
 * parameter in order, on `self` when it is a method: its body, or the C
 * primitive it declares. A generic function's specialization was typed as
 * it was made; without a key, the function is typed for its receiver first. */
static int evalInvoke(Eval *eval, RangeNode *function, RangeNode *key, RangeValue *self, RangeValue *arguments, RangeNode *at,
                      RangeValue *out)
{
    *out = (RangeValue){0};
    int status;
    if (!key && !eval->outside) key = typeOnDemand(eval->typer,function,self ? self->type : NULL);
    else if (!key) key = keyOf(function->owner,self ? self->type : NULL);
    if (found(key,function)->found & RangeFlagInvalid) return evalStop(eval);
    EvalFrame frame = {.self=self,.function=function,.key=key};
    for (size_t i = 0; i < function->itemCount; ++i)
        if ((status = evalAdopt(eval,&arguments[i],found(frame.key,function->items[i])->type,at))) return status;
    if (function->flags & RangeFlagBuiltin) return evalBuiltin(eval,function,self,arguments,at,out);
    if (!function->a) return evalFail(eval,at,"'%s' has no body to run at macro time",function->name);
    // Folding, typing never runs: a body not typed yet is left to run.
    if (eval->outside && !(found(key,function)->found & RangeFlagTyped)) return EvalUnknown;
    if ((status = evalDeeper(eval,at))) return status;
    frame.output = found(frame.key,function)->type;
    for (size_t i = 0; i < function->itemCount; ++i) evalBind(eval,&frame,function->items[i],arguments[i]);
    status = evalStatement(eval,&frame,function->a);
    --eval->depth;
    if (status == EvalReturn) { *out = eval->returned; return EvalNormal; }
    if (status) return status;
    if (frame.output && !unitType(eval->typer,frame.output))
        return evalFail(eval,at,"'%s' ended without returning a value",function->name);
    return EvalNormal;
}

/* `where(element)`: the closure's body with its parameters bound, in the
 * frame where it was written. It yields its one expression, or what `return`
 * gives; `return` ends the closure only. */
static int evalCallClosure(Eval *eval, RangeValue *closure, RangeValue *arguments, RangeNode *at, RangeValue *out)
{
    RangeNode *literal = closure->node, *key = closure->frame->key, *type = found(key,literal)->type;
    if (type && type->kind != RangeNodeFunctionType) type = NULL;
    int status = evalDeeper(eval,at);
    if (status) return status;
    EvalFrame frame = {.parent=closure->frame,.self=closure->frame->self,.function=closure->frame->function,
                       .output=type ? type->a : NULL,.key=key};
    for (size_t i = 0; i < literal->itemCount && !status; ++i) {
        status = evalAdopt(eval,&arguments[i],found(key,literal->items[i])->type,at);
        evalBind(eval,&frame,literal->items[i],arguments[i]);
    }
    RangeNode *value = closureResult(eval->typer,key,literal);
    if (!status && value) status = evalExpression(eval,&frame,value,out);
    else if (!status) {
        *out = (RangeValue){0};
        status = evalStatement(eval,&frame,literal->a);
        if (status == EvalReturn) { *out = eval->returned; status = EvalNormal; }
    }
    --eval->depth;
    return status ? status : evalAdopt(eval,out,frame.output,at);
}

/* A case with its payload, one argument per field in order. */
static int evalCase(Eval *eval, EvalFrame *frame, RangeNode *type, RangeNode *entry, RangeNode **arguments, size_t count, RangeValue *out)
{
    RangeValue *payload = evalValues(eval,count);
    for (size_t i = 0; i < count; ++i) {
        int status = evalExpression(eval,frame,arguments[i]->a,&payload[i]);
        if (!status && type && i < entry->itemCount) status = evalAdopt(eval,&payload[i],memberTypeIn(eval->typer,type,entry->items[i]),arguments[i]);
        if (status) return status;
    }
    *out = (RangeValue){.kind=ValueCase,.type=type,.node=entry,.values=payload,.count=count};
    return EvalNormal;
}

/* The value a construction gives a member, in both walkers: the argument
 * naming it, read under `key`; NULL when none does, and the member takes
 * its default. */
RangeNode *constructionArgument(RangeNode *key, RangeNode *member, RangeNode **arguments, size_t count)
{
    RangeNode *value = NULL;
    for (size_t j = 0; j < count; ++j) if (found(key,arguments[j])->resolvedDeclaration == member) value = arguments[j]->a;
    return value;
}

/* A scalar's or a bytes value's single input, the value itself: the
 * argument, else, *defaulted, the default of its first construction input
 * that has one, read under `own`; NULL for neither, and the value is zero. */
RangeNode *constructionSingle(RangeNode *own, RangeNode *declaration, RangeNode **arguments, size_t count, int *defaulted)
{
    *defaulted = !count;
    if (count) return arguments[0]->a;
    for (size_t i = 0; i < declaration->itemCount; ++i)
        if (constructionInput(declaration->items[i]) && declarationValue(own,declaration->items[i]))
            return declarationValue(own,declaration->items[i]);
    return NULL;
}

/* `Point(x: 1)`: each stored member is its argument or its default, which
 * sees the members before it; @many storage starts with no slots. A scalar's
 * or a bytes value's single input is the value itself, and an enum's the
 * case value given. */
static int evalConstruct(Eval *eval, EvalFrame *frame, RangeNode *type, RangeNode **arguments, size_t count, RangeNode *at,
                         RangeValue *out)
{
    if (!type || type->kind != RangeNodeSpecialization) return evalStop(eval);
    RangeNode *declaration = type->resolvedDeclaration;
    evalPrepare(eval,declaration);
    EvalFrame defaults = {.key=keyOf(declaration,type)};
    int status, bits, isSigned, defaulted;
    if (bytesDeclaration(declaration) || scalarShape(type,&bits,&isSigned)) {
        for (size_t i = 0; i < declaration->itemCount; ++i)
            if (constructionInput(declaration->items[i])) (void)memberTypeIn(eval->typer,type,declaration->items[i]); /* its default, as this specialization has it */
        RangeNode *value = constructionSingle(defaults.key,declaration,arguments,count,&defaulted);
        if (!value) { *out = evalZero(eval,type,0); return EvalNormal; }
        status = evalExpression(eval,defaulted ? &defaults : frame,value,out);
        return status ? status : evalAdopt(eval,out,type,at);
    }
    if (declaration->kind == RangeNodeEnum) {
        if (count != 1) return evalStop(eval);
        status = evalExpression(eval,frame,arguments[0]->a,out);
        return status ? status : evalAdopt(eval,out,type,at);
    }
    RangeValue instance = {.kind=ValueInstance,.type=type,.count=declaration->itemCount};
    instance.values = evalValues(eval,instance.count);
    defaults.self = &instance;
    for (size_t i = 0; i < instance.count; ++i) {
        RangeNode *member = declaration->items[i], *value = constructionArgument(frame->key,member,arguments,count);
        if (!rangeNodeDeclaresValue(member->kind) || builtinMember(member)) continue;
        if (member->flags & RangeFlagMany) { instance.values[i] = (RangeValue){.kind=ValueSlots}; continue; }
        RangeNode *memberType = memberTypeIn(eval->typer,type,member);
        if (value) status = evalExpression(eval,frame,value,&instance.values[i]);
        else if ((value = declarationValue(defaults.key,member)) == member)
            status = evalConstruct(eval,&defaults,memberType,member->items,member->itemCount,member,&instance.values[i]);
        else if (value) status = evalExpression(eval,&defaults,value,&instance.values[i]);
        else continue; /* a required input: typing reports it missing */
        if (!status) status = evalAdopt(eval,&instance.values[i],memberType,value);
        if (status) return status;
    }
    *out = instance;
    return EvalNormal;
}

/* The value a place names, to change in place: a local, a parameter, or a
 * member of the receiver, or a member of one of those; NULL for any other
 * expression. */
static RangeValue *evalPlace(Eval *eval, EvalFrame *frame, RangeNode *expr)
{
    RangeFacts *facts = found(frame->key,expr);
    if (facts->lowered || facts->narrowed) return NULL; /* it runs as something else, or reads a payload */
    if (expr->kind == RangeNodeName) {
        RangeValue *bound = evalNamed(frame,facts->resolvedDeclaration);
        if (bound) return bound;
        size_t member = evalMember(frame->self,facts->resolvedDeclaration);
        if (member == SIZE_MAX) return NULL;
        evalOwn(eval,frame->self);
        return &frame->self->values[member];
    }
    if (expr->kind != RangeNodeMemberAccess) return NULL;
    RangeValue *owner = evalPlace(eval,frame,expr->a);
    size_t member = owner ? evalMember(owner,facts->resolvedDeclaration) : SIZE_MAX;
    if (member == SIZE_MAX) return NULL;
    evalOwn(eval,owner);
    return &owner->values[member];
}

int callForm(const RangeNode *target)
{
    if (!target) return CallOther;
    if (target->kind == RangeNodeEnumCase) return CallCase;
    if (target->kind == RangeNodeConstruct || target->kind == RangeNodeEnum || target->kind == RangeNodeTypeParameter) return CallConstruct;
    if (target->kind == RangeNodeParameter || rangeNodeDeclaresValue(target->kind)) return CallClosure;
    return target->kind == RangeNodeFunction ? CallFunction : CallOther;
}

/* A call, on the receiver it is called on (in place, so a method changing it
 * changes the place) or, for a sibling, the running method's. On a value
 * known only at macro time, the function its type declares with the call's
 * name and labels. */
static int evalCall(Eval *eval, EvalFrame *frame, RangeNode *call, RangeValue *out)
{
    RangeFacts *facts = found(frame->key,call->a);
    RangeNode *callee = call->a, *target = facts->resolvedDeclaration, *type = found(frame->key,call)->type;
    int form = callForm(target);
    if (form == CallCase) return evalCase(eval,frame,type,target,call->items,call->itemCount,out);
    if (form == CallConstruct) return evalConstruct(eval,frame,type,call->items,call->itemCount,call,out);
    RangeValue receiver = {0}, *self = NULL, *arguments = evalValues(eval,call->itemCount);
    int status;
    if (callee->kind == RangeNodeMemberAccess) {
        self = evalPlace(eval,frame,callee->a);
        if (!self && (status = evalExpression(eval,frame,callee->a,&receiver))) return status;
        if (!self) self = &receiver;
    } else if (form == CallFunction && target->typeName) self = frame->self;
    // Folding, a sibling of a method native code compiles, or a closure it
    // holds, runs with values known only then.
    if (evalRooted(eval,frame) && ((form == CallFunction && target->typeName && !self) || (form == CallClosure && !evalNamed(frame,target))))
        return EvalUnknown;
    for (size_t i = 0; i < call->itemCount; ++i)
        if ((status = evalExpression(eval,frame,call->items[i]->a,&arguments[i]))) return status;
    if (form == CallClosure) {
        RangeValue *closure = evalNamed(frame,target);
        if (!closure || closure->kind != ValueClosure) return evalFail(eval,call,"no closure is bound to '%s' here",callee->name);
        return evalCallClosure(eval,closure,arguments,call,out);
    }
    if (!target && callee->kind == RangeNodeMemberAccess) {
        char type[160]; describeType(type,sizeof(type),self->type);
        target = self->type && self->type->kind == RangeNodeSpecialization
            ? findCalledFunction(self->type->resolvedDeclaration,callee->name,call) : NULL;
        if (!target) return evalFail(eval,call,"%s has no function '%s'",type,callee->name);
        if (genericTemplate(target))
            return evalFail(eval,call,"'%s' of %s is generic; calling it on a value known only at macro time is not implemented",target->name,type);
    }
    if (!target || target->kind != RangeNodeFunction) return evalStop(eval);
    return evalInvoke(eval,target,facts->specialization,self,arguments,call,out);
}

/* ---- operators ---- */

/* `=` on two values: a type with an equality function calls it; any other
 * value compares structurally, a declaration by identity. A literal takes
 * the other operand's type first. */
static int evalEquals(Eval *eval, RangeValue left, RangeValue right, RangeNode *at, int *equal)
{
    int status = EvalNormal;
    *equal = 0;
    if (left.kind == ValueLiteral && right.kind != ValueLiteral) status = evalAdopt(eval,&left,right.type,at);
    else if (right.kind == ValueLiteral && left.kind != ValueLiteral) status = evalAdopt(eval,&right,left.type,at);
    if (status || left.kind != right.kind) return status;
    RangeNode *function = left.kind == ValueCase || left.kind == ValueInstance ? equalityFunction(left.type) : NULL;
    if (function) {
        RangeValue result;
        status = evalInvoke(eval,function,NULL,&left,&right,at,&result);
        *equal = !status && evalTruth(result);
        return status;
    }
    switch (left.kind) {
    case ValueNone: *equal = 1; return EvalNormal;
    case ValueLiteral:
        *equal = left.node->kind == right.node->kind && left.integer == right.integer && left.length == right.length
            && (!left.length || !memcmp(left.text,right.text,left.length));
        return EvalNormal;
    case ValueScalar: *equal = left.integer == right.integer; return EvalNormal;
    case ValueText: *equal = left.length == right.length && (!left.length || !memcmp(left.text,right.text,left.length)); return EvalNormal;
    case ValueDeclaration: *equal = left.node == right.node; return EvalNormal;
    case ValueClosure: return evalFail(eval,at,"closures are not compared");
    case ValueCase: if (left.node != right.node) return EvalNormal; break;
    default: if (left.count != right.count) return EvalNormal; break;
    }
    *equal = 1;
    for (size_t i = 0; *equal && !status && i < left.count && i < right.count; ++i)
        status = evalEquals(eval,left.values[i],right.values[i],at,equal);
    return status;
}

int operatorForm(const RangeNode *expr, const RangeNode *function, int bytes)
{
    int binary = expr->kind == RangeNodeBinary;
    if (binary && shortCircuit(function)) return OperatorShortCircuit;
    if (binary && (same(expr->name,"=") || same(expr->name,"!="))) return OperatorEquality;
    return binary && same(expr->name,"+") && bytes ? OperatorJoin : OperatorScalar;
}

/* A builtin operator's C primitive, by its operand's layout: scalar
 * arithmetic and comparison, trapping where native code traps, Bool's `!`,
 * and the join of two bytes values. */
static int evalPrimitive(Eval *eval, RangeNode *expr, RangeValue left, RangeValue right, RangeValue *out)
{
    const char *op = expr->name;
    char name[160]; describeType(name,sizeof(name),left.type);
    int bits, isSigned;
    if (same(op,"!") && left.kind == ValueCase) { *out = evalBool(eval,!evalTruth(left)); return EvalNormal; }
    if (operatorForm(expr,NULL,left.kind == ValueText) == OperatorJoin && right.kind == ValueText) {
        char *joined = rangeArenaAllocate(eval->vm->arena,left.length + right.length + 1);
        memcpy(joined,left.text,left.length);
        memcpy(joined + left.length,right.text,right.length);
        joined[left.length + right.length] = '\0';
        *out = (RangeValue){.kind=ValueText,.type=left.type,.text=joined,.length=left.length + right.length};
        return EvalNormal;
    }
    if (left.kind != ValueScalar || !scalarShape(left.type,&bits,&isSigned))
        return evalFail(eval,expr,"no C primitive implements builtin operator '%s' on %s",op,name);
    __int128 a = scalarValue(left,isSigned), b = scalarValue(right,isSigned), result = 0;
    if (expr->kind == RangeNodeUnary) result = -a;
    else if (same(op,"<") || same(op,"<=") || same(op,">") || same(op,">=")) {
        *out = evalBool(eval,same(op,"<") ? a < b : same(op,"<=") ? a <= b : same(op,">") ? a > b : a >= b);
        return EvalNormal;
    } else if (same(op,"+")) result = a + b;
    else if (same(op,"-")) result = a - b;
    else if (same(op,"*")) { if (__builtin_mul_overflow(a,b,&result)) return evalFail(eval,expr,"result of '*' does not fit %s",name); }
    else if (same(op,"/") || same(op,"%")) {
        if (!b) return evalFail(eval,expr,"division by zero in '%s'",op);
        result = same(op,"/") ? a / b : a % b;
    } else return evalFail(eval,expr,"no C primitive implements builtin operator '%s' on %s",op,name);
    if (!scalarFits(result,bits,isSigned)) return evalFail(eval,expr,"result of '%s' does not fit %s",op,name);
    *out = (RangeValue){.kind=ValueScalar,.type=left.type,.integer=(long long)result};
    return EvalNormal;
}

/* `a op b` and `op a`: the function typing chose for the operator, or, on a
 * value known only at macro time, the one its type declares. A function with
 * a body is called; a builtin one is its C primitive. `&` and `|` evaluate
 * their right operand only when the left does not decide; `=` and `!=`
 * compare, as every type can. */
static int evalOperator(Eval *eval, EvalFrame *frame, RangeNode *expr, RangeValue *out)
{
    const char *op = expr->name;
    int binary = expr->kind == RangeNodeBinary, status;
    // `-128` is one literal.
    if (!binary && same(op,"-") && expr->a && expr->a->kind == RangeNodeInteger) {
        *out = (RangeValue){.kind=ValueLiteral,.node=expr->a,.integer=-expr->a->integer};
        return evalAdopt(eval,out,found(frame->key,expr)->type,expr);
    }
    RangeNode *function = found(frame->key,expr)->resolvedDeclaration;
    if (function && function->kind != RangeNodeFunction) function = NULL;
    int logic = binary && (same(op,"&") || same(op,"|"));
    RangeValue left, right = {0};
    if ((status = evalExpression(eval,frame,expr->a,&left))) return status;
    if (binary && !logic && (status = evalExpression(eval,frame,expr->b,&right))) return status;
    if (operatorForm(expr,function,left.kind == ValueText) == OperatorEquality) {
        int equal;
        status = evalEquals(eval,left,right,expr,&equal);
        *out = evalBool(eval,equal == same(op,"="));
        return status;
    }
    if (!function) {
        // Known only now: a literal takes the other operand's type, or its family's.
        if (left.kind == ValueLiteral)
            status = evalAdopt(eval,&left,right.kind != ValueLiteral && right.type ? right.type : literalType(eval->typer,left.node),expr);
        if (!status && right.kind == ValueLiteral) status = evalAdopt(eval,&right,left.type,expr);
        if (status) return status;
        function = left.type && left.type->kind == RangeNodeSpecialization ? operatorFunction(left.type->resolvedDeclaration,op,binary) : NULL;
        char name[160]; describeType(name,sizeof(name),left.type);
        if (!function) return evalFail(eval,expr,"'%s' is not declared on %s",op,name);
    }
    if (operatorForm(expr,function,0) == OperatorShortCircuit) {
        if (evalTruth(left) == same(op,"|")) { *out = evalBool(eval,evalTruth(left)); return EvalNormal; }
        if ((status = evalExpression(eval,frame,expr->b,&right))) return status;
        *out = evalBool(eval,evalTruth(right));
        return EvalNormal;
    }
    if (logic && (status = evalExpression(eval,frame,expr->b,&right))) return status;
    if (function->flags & RangeFlagBuiltin) return evalPrimitive(eval,expr,left,right,out);
    return evalInvoke(eval,function,NULL,&left,&right,expr,out);
}

/* ---- expressions ---- */

/* A value generic: the constant of the specialization the running body was
 * typed in, or of one it is typed within, its receiver's. */
static RangeNode *evalGeneric(EvalFrame *frame, RangeNode *declaration)
{
    if (declaration->kind != RangeNodeLet) return NULL;
    RangeNode **slot = genericSlot(frame->key,declaration);
    return slot ? *slot : NULL;
}

/* A name: a value of the frame, the receiver, a member of it, a value
 * generic, or a construct or enum, which is the declaration. */
static int evalName(Eval *eval, EvalFrame *frame, RangeNode *expr, RangeValue *out)
{
    RangeNode *declaration = found(frame->key,expr)->resolvedDeclaration;
    RangeValue *bound = evalNamed(frame,declaration);
    if (bound) { *out = *bound; return EvalNormal; }
    if (declaration && frame->self && frame->function && declaration == frame->function->receiver) { *out = *frame->self; return EvalNormal; }
    size_t member = evalMember(frame->self,declaration);
    if (member != SIZE_MAX) { *out = frame->self->values[member]; return EvalNormal; }
    RangeNode *constant = declaration ? evalGeneric(frame,declaration) : NULL;
    if (constant) {
        EvalFrame none = {0};
        int status = evalExpression(eval,&none,constant,out);
        return status ? status : evalAdopt(eval,out,found(frame->key,declaration)->type,expr);
    }
    if (declaration && (declaration->kind == RangeNodeConstruct || declaration->kind == RangeNodeEnum)) {
        *out = (RangeValue){.kind=ValueDeclaration,.node=declaration};
        return EvalNormal;
    }
    if (evalRooted(eval,frame)) return nativeKnownName(eval->outside,declaration,out); /* a name native code holds */
    return evalFail(eval,expr,"the value of '%s' is not known at macro time",expr->name);
}

/* `a.name`: a case named through its enum, a member of an instance, a reflection field of a declaration, the byte count
 * of text, or, on a value known only at macro time, whether it holds a case. */
static int evalMemberAccess(Eval *eval, EvalFrame *frame, RangeNode *expr, RangeValue *out)
{
    RangeNode *member = found(frame->key,expr)->resolvedDeclaration;
    if (member && member->kind == RangeNodeEnumCase) {
        *out = (RangeValue){.kind=ValueCase,.type=found(frame->key,expr)->type,.node=member};
        return EvalNormal;
    }
    RangeValue receiver;
    int status = evalExpression(eval,frame,expr->a,&receiver);
    if (status) return status;
    RangeNode *declaration = receiver.type && receiver.type->kind == RangeNodeSpecialization ? receiver.type->resolvedDeclaration : NULL;
    switch (receiver.kind) {
    case ValueDeclaration: return evalField(eval,receiver.node,expr->name,expr,out);
    case ValueInstance: {
        size_t index = evalMember(&receiver,member ? member : declaration ? findMember(declaration,expr->name) : NULL);
        if (index == SIZE_MAX) break;
        *out = receiver.values[index];
        return EvalNormal;
    }
    case ValueText:
        if (!declaration || !same(expr->name,"count") || !findMember(declaration,"count")) break;
        *out = (RangeValue){.kind=ValueScalar,.integer=(long long)receiver.length,
            .type=memberType(eval->typer,declaration,findMember(declaration,"count"),receiver.type)};
        return EvalNormal;
    case ValueCase:
        if (!enumCase(declaration,expr->name)) break;
        *out = evalBool(eval,receiver.node == enumCase(declaration,expr->name));
        return EvalNormal;
    default: break;
    }
    char type[160]; describeType(type,sizeof(type),receiver.type);
    return evalFail(eval,expr,"%s has no member '%s'",type,expr->name);
}

/* Whether `pattern` matches `value`; what it binds joins the frame. A name
 * bound on the right of `|` is the left side's. */
static int evalMatch(Eval *eval, EvalFrame *frame, RangeNode *pattern, RangeValue value, int *matched)
{
    int status = evalStep(eval,pattern);
    *matched = 1;
    if (status) return status;
    switch (pattern->integer) {
    case RangePatternAny: return EvalNormal;
    case RangePatternBind:
        // Folding, a name a condition binds for the code native code emits around it is bound at run.
        if (eval->outside && frame == eval->root) return EvalUnknown;
        evalBind(eval,frame,found(frame->key,pattern->a)->resolvedDeclaration ? found(frame->key,pattern->a)->resolvedDeclaration : pattern->a,value);
        return EvalNormal;
    case RangePatternCase: {
        RangeNode *declaration = value.kind == ValueCase && value.type ? value.type->resolvedDeclaration : NULL;
        RangeNode *entry = found(frame->key,pattern)->resolvedDeclaration ? found(frame->key,pattern)->resolvedDeclaration : enumCase(declaration,pattern->name);
        if (value.kind != ValueCase) return evalFail(eval,pattern,"'.%s' matches an enum case; this value is not one",pattern->name);
        if (!entry) { char type[160]; describeType(type,sizeof(type),value.type); return evalFail(eval,pattern,"%s has no case '%s'",type,pattern->name); }
        *matched = value.node == entry;
        for (size_t i = 0; *matched && !status && (pattern->flags & RangeFlagApplication) && i < pattern->itemCount && i < value.count; ++i)
            status = evalMatch(eval,frame,pattern->items[i]->a,value.values[i],matched);
        return status;
    }
    case RangePatternValue: {
        RangeValue other;
        if ((status = evalExpression(eval,frame,pattern->a,&other))) return status;
        return evalEquals(eval,value,other,pattern,matched);
    }
    default: return evalFail(eval,pattern,"this pattern form is not run at macro time");
    }
}

/* The arm a switch runs, in both walkers: its first whose rows match, a
 * row's patterns matching the subjects and its condition holding; *chosen
 * is its index, or the arm count when none does. The arm runs in `arm`, a
 * frame inside `frame` that holds what its row binds. */
int evalChoose(Eval *eval, EvalFrame *frame, RangeNode *node, EvalFrame *arm, size_t *chosen)
{
    size_t width = node->c ? node->c->itemCount : 1;
    RangeValue *subjects = evalValues(eval,width);
    RangeNode **vector = rangeArenaAllocate(eval->vm->arena,(width ? width : 1) * sizeof(*vector));
    int status;
    *arm = (EvalFrame){.parent=frame,.self=frame->self,.function=frame->function,.output=frame->output,.key=frame->key};
    for (size_t k = 0; k < width; ++k)
        if ((status = evalExpression(eval,frame,node->c ? node->c->items[k] : node->a,&subjects[k]))) return status;
    for (*chosen = 0; *chosen < node->itemCount; ++*chosen) {
        RangeNode *entry = node->items[*chosen];
        int matched = (entry->flags & RangeFlagLiteral) != 0;
        for (size_t j = 0; !matched && j < entry->itemCount; ++j) {
            RangeNode *row = entry->items[j];
            patternRow(row,vector,width);
            matched = 1;
            for (size_t k = 0; matched && k < width; ++k)
                if (vector[k] && (status = evalMatch(eval,arm,vector[k],subjects[k],&matched))) return status;
            if (matched && row->b) {
                RangeValue condition;
                if ((status = evalExpression(eval,arm,row->b,&condition))) return status;
                matched = evalTruth(condition);
            }
        }
        if (matched) break;
    }
    return EvalNormal;
}

/* A switch expression is the value its arm yields; an arm that is a block
 * runs as a statement. */
static int evalSwitch(Eval *eval, EvalFrame *frame, RangeNode *node, RangeValue *out)
{
    EvalFrame arm;
    size_t chosen;
    int status = evalChoose(eval,frame,node,&arm,&chosen);
    *out = (RangeValue){0};
    if (status || chosen == node->itemCount) return status;
    RangeNode *entry = node->items[chosen];
    if (!entry->a) return evalStatement(eval,&arm,entry->b);
    status = evalExpression(eval,&arm,entry->a,out);
    return status ? status : evalAdopt(eval,out,found(frame->key,node)->type,entry->a);
}

/* A literal: the value of the type typing gave it, or a literal of no type. */
static int evalLiteral(Eval *eval, EvalFrame *frame, RangeNode *expr, RangeValue *out)
{
    *out = (RangeValue){.kind=ValueLiteral,.node=expr,.integer=expr->integer};
    if (expr->kind == RangeNodeString) {
        int status = evalText(eval,frame,expr,&out->text,&out->length);
        if (status) return status;
        // Interpolated text is computed: no literal writes it as it is.
        if (expr->itemCount != 1 || !(expr->items[0]->flags & RangeFlagLiteral))
            *out = (RangeValue){.kind=ValueText,.type=found(frame->key,expr)->type,.text=out->text,.length=out->length};
    }
    return evalAdopt(eval,out,found(frame->key,expr)->type,expr);
}

/* An expression as written: what its own kind computes. */
int evalPlain(Eval *eval, EvalFrame *frame, RangeNode *expr, RangeValue *out)
{
    int status = evalStep(eval,expr);
    if (status) return status;
    switch (expr->kind) {
    case RangeNodeInteger: case RangeNodeBool: case RangeNodeString: return evalLiteral(eval,frame,expr,out);
    case RangeNodeName: return evalName(eval,frame,expr,out);
    case RangeNodeEnvironment:
        // A splice of a macro local, or #target: the application's target.
        if (found(frame->key,expr)->resolvedDeclaration) return evalName(eval,frame,expr,out);
        if (!eval->application) return evalFail(eval,expr,"'#%s' is read outside a macro application",expr->name);
        if (eval->outside) return EvalUnknown; /* declarations are values of macros only */
        *out = (RangeValue){.kind=ValueDeclaration,.node=eval->application->target,.type=found(frame->key,expr)->type};
        return EvalNormal;
    case RangeNodeCase:
        if (!found(frame->key,expr)->resolvedDeclaration) return evalStop(eval);
        *out = (RangeValue){.kind=ValueCase,.type=found(frame->key,expr)->type,.node=found(frame->key,expr)->resolvedDeclaration};
        return EvalNormal;
    case RangeNodeMemberAccess: return evalMemberAccess(eval,frame,expr,out);
    case RangeNodeCall: return evalCall(eval,frame,expr,out);
    case RangeNodeCaseTest: {
        RangeValue subject;
        int matched;
        if ((status = evalExpression(eval,frame,expr->a,&subject)) || (status = evalMatch(eval,frame,expr->b,subject,&matched))) return status;
        *out = evalBool(eval,matched);
        return EvalNormal;
    }
    case RangeNodeClosure:
        *out = (RangeValue){.kind=ValueClosure,.node=expr,.frame=frame};
        return EvalNormal;
    case RangeNodeSwitch: return evalSwitch(eval,frame,expr,out);
    case RangeNodeUnary: case RangeNodeBinary: return evalOperator(eval,frame,expr,out);
    case RangeNodeAttribute: return evalEffect(eval,frame,expr);
    case RangeNodeEmission:
        // A shape-only block landed before the body ran; a law run emits nothing.
        if ((eval->application && eval->application->specialization) || (expr->found & RangeFlagShape)) return EvalNormal;
        return eval->application ? evalEmit(eval,frame,expr) : EvalUnknown;
    default: return evalFail(eval,expr,"%s expressions are not run at macro time",rangeNodeKindName(expr->kind));
    }
}

/* A value where typing promoted it to the optional `type`: the present case
 * holding it, even when it is itself an optional. */
static int evalPromote(Eval *eval, RangeValue *value, RangeNode *type, RangeNode *at)
{
    RangeNode *present = NULL, *wrapped = optionalWrapped(eval->typer,type,&present);
    RangeValue *payload = evalValues(eval,1);
    *payload = *value;
    int status = evalAdopt(eval,payload,wrapped,at);
    *value = (RangeValue){.kind=ValueCase,.type=type,.node=present,.values=payload,.count=1};
    return status;
}

/* An expression's value: what typing lowered it to, if anything, runs in
 * its place; a narrowed read is the payload of the present case it goes
 * through; a promoted value is the present case holding it. */
int evalExpression(Eval *eval, EvalFrame *frame, RangeNode *expr, RangeValue *out)
{
    *out = (RangeValue){0};
    if (!expr) return EvalNormal;
    RangeFacts *facts = found(frame->key,expr);
    int status = evalPlain(eval,frame,facts->lowered ? facts->lowered : expr,out);
    if (!status && facts->narrowed && (out->kind != ValueCase || out->node != facts->narrowed || out->count != 1))
        status = evalFail(eval,expr,"this narrowed value holds no payload");
    else if (!status && facts->narrowed) *out = out->values[0];
    if (!status && facts->promoted) status = evalPromote(eval,out,facts->promoted,expr);
    if (eval->outside && frame == eval->root) nativeRemember(eval->outside,expr,status,out);
    return status;
}

/* ---- statements ---- */

/* A local's value: `let p: Point(x: 1)` constructs; `let r: step(x: 1)`
 * calls; a bare name that resolved to a value copies it. */
int evalDeclared(Eval *eval, EvalFrame *frame, RangeNode *node, RangeValue *value)
{
    RangeNode *initial = declarationValue(frame->key,node), *type = found(frame->key,node)->type;
    int status = initial == node ? evalConstruct(eval,frame,type,node->items,node->itemCount,node,value)
                                 : evalExpression(eval,frame,initial,value);
    return status ? status : evalAdopt(eval,value,type,node);
}

static int evalStatement(Eval *eval, EvalFrame *frame, RangeNode *node)
{
    if (!node) return EvalNormal;
    int status = evalStep(eval,node);
    if (status) return status;
    RangeValue value = {0};
    switch (node->kind) {
    case RangeNodeBlock:
        for (size_t i = 0; i < node->itemCount; ++i) if ((status = evalStatement(eval,frame,node->items[i]))) return status;
        return EvalNormal;
    case RangeNodeLet: case RangeNodeState:
        if (!(status = evalDeclared(eval,frame,node,&value))) evalBind(eval,frame,node,value);
        return status;
    case RangeNodeAssign: {
        RangeFacts *assigned = found(frame->key,node->a);
        RangeNode *target = assigned->type ? assigned->type
            : assigned->resolvedDeclaration ? found(frame->key,assigned->resolvedDeclaration)->type : NULL;
        if ((status = evalExpression(eval,frame,node->b,&value)) || (status = evalAdopt(eval,&value,target,node->b))) return status;
        RangeValue *place = evalPlace(eval,frame,node->a);
        if (!place) return evalStop(eval);
        *place = value;
        return EvalNormal;
    }
    case RangeNodeWhile:
        // A while without a condition ends only at break.
        for (;;) {
            if (node->a) {
                if ((status = evalExpression(eval,frame,node->a,&value))) return status;
                if (!evalTruth(value)) return EvalNormal;
            }
            status = evalStatement(eval,frame,node->b);
            if (status == EvalBreak) return EvalNormal;
            if (status && status != EvalContinue) return status;
        }
    case RangeNodeFor: return evalStatement(eval,frame,node->a); /* the loop it is written as */
    case RangeNodeBreak: return EvalBreak;
    case RangeNodeContinue: return EvalContinue;
    case RangeNodeReturn:
        if (node->a && ((status = evalExpression(eval,frame,node->a,&value)) || (status = evalAdopt(eval,&value,frame->output,node->a)))) return status;
        eval->returned = value;
        return EvalReturn;
    case RangeNodeSwitch: return evalSwitch(eval,frame,node,&value);
    case RangeNodeExpressionStatement: return evalExpression(eval,frame,node->a,&value);
    default: return evalFail(eval,node,"%s statements are not run at macro time",rangeNodeKindName(node->kind));
    }
}

/* Run an application against its target: its macro body, or with `shape`
 * only its shape-only #graph blocks. A failure is the application's (fail
 * reports it); returns 0 when the body stopped on a problem typing reported. */
int evalApplication(Resolver *vm, RangeMacroApplication *app, int shape)
{
    Eval eval = {.vm=vm,.typer=vm->typer,.application=app};
    EvalFrame frame = {0};
    RangeNode *body = app->declaration->a;
    int status = EvalNormal;
    if (shape) {
        for (size_t i = 0; !status && body && i < body->itemCount; ++i) {
            RangeNode *emission = body->items[i]->kind == RangeNodeExpressionStatement ? body->items[i]->a : NULL;
            if (emission && emission->kind == RangeNodeEmission && (emission->found & RangeFlagShape)) status = evalEmit(&eval,&frame,emission);
        }
    } else if (!typeMacroOnDemand(vm->typer,app)) return 0;
    else status = evalStatement(&eval,&frame,body);
    if (status == EvalFailed && eval.message) fail(vm,eval.at,"%s",eval.message);
    return status != EvalFailed;
}
