/* Native code generation: typed Range functions lowered to ARM64 through
 * native.c. */
#define _XOPEN_SOURCE 700
#include "compiler.h"
#include "native.h"
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* ---- native code -----------------------------------------------------------
 * Lowers typed Range to ARM64. A scalar (a type with a storage primitive) lives
 * in a 64-bit register, sign- or zero-extended by the width its storage and
 * signed primitives declare. Any other value lives in memory and expressions
 * carry its address. Calling convention, internal to Range: a method receives
 * its receiver's address in x0 and parameters after it; scalars pass by value,
 * aggregates by address (the callee copies); an aggregate result is written to
 * the address the caller passes in x8. A generic function, and a generic
 * construct's or enum's method, is compiled once per specialization it is
 * called in, reading what typing found under that specialization.
 *
 * Native code fills in every value known before run and compiles only what
 * stays unknown: each expression first asks the evaluator for its value.
 * Builtin operators are C primitives: each enforces its operand type's range
 * (the @integer law) at runtime where the compiler cannot prove it, writing a
 * located message and exiting 134. Operators with bodies are calls. Only
 * what the entry block reaches is compiled: a function, or a generic one's
 * instance, when emitted code calls it, so one whose every call was filled
 * in is not, nor an arm a known condition never takes; forms not lowered yet
 * are reported as not implemented. Compiled as written (--as-written), where
 * only leaves, literals and the like, are asked for their values, every arm
 * and every function is, reached or not, and every missing mechanism is
 * reported. */

/* A branch to patch once its target is known: its position and encoding. */
typedef struct { size_t at; uint32_t base; } NativeJump;
/* An alias slot names another binding's storage; it does not own the value.
 * A packed one is a member inside an aggregate, a scalar at its own size. A
 * known one names its value, and has no storage (offset 0). */
typedef struct { RangeNode *declaration; int32_t offset; RangeNode *type; int alias, packed; RangeValue *known; } NativeSlot;
typedef struct { size_t at; RangeNode *function, *key, *self; } NativeCall;
typedef struct { size_t at; uint32_t branch; const char *message; } NativeTrap;
typedef struct { RangeNode *function, *key, *self; size_t offset; int compiled; } NativeInstance;
typedef struct { size_t at; const char *bytes; size_t length; } NativeText;
/* A temporary that owns references until it is moved into place or its
 * statement ends. */
typedef struct { int32_t offset; RangeNode *type; int consumed; } NativeTemp;
/* A subroutine emitted once: release a value of `type` (x0 = its address),
 * release a block of `type` elements (x0 = the block, or zero), write an
 * integer in decimal (x0 = the value, x1 = the file descriptor), or compare
 * two values of `type` (x0, x1 = their addresses; x0 = 1 when equal). */
enum { NativeReleaseValue, NativeReleaseBlock, NativeWriteSigned, NativeWriteUnsigned, NativeEqual };
typedef struct { RangeNode *type; int block; size_t offset; int compiled; } NativeHelper;
typedef struct { size_t at; size_t helper; } NativeHelperCall;
/* What `break` and `continue` leave: a loop (continue branches to top), and
 * the slots and temporaries that were live when it began. */
typedef struct {
    int loop;
    size_t top, slots, temps;
    int valueDepth;  /* switch expressions around the loop */
    int32_t stack;   /* the slot holding sp at the loop, inside a switch expression; 0 outside */
    NativeJump *breaks; size_t breakCount, breakCapacity;
} NativeTarget;

/* What a body runs in: its receiver, its function, and the key it was typed
 * under. A body inlined into another, a callee's or a closure's, runs in its
 * own context. */
typedef struct NativeContext {
    RangeNode *owner, *self, *function, *key;
    int32_t selfSlot;
} NativeContext;
/* The closure a function-typed parameter holds while the call it was passed
 * to is compiled inline: the closure, the context it was written in, and the
 * slots and closures visible there. */
typedef struct {
    RangeNode *parameter, *closure;
    NativeContext *context;
    size_t slots, closures;
} NativeClosure;
/* Slots and closures a closure's body does not see: those of the calls
 * inlined since it was written. */
typedef struct { size_t slotFrom, slotTo, closureFrom, closureTo; } NativeHidden;
/* An inlined body: `return` leaves its value in result and branches to its
 * end, ending the values the body began; sp returns to stack when the return
 * is inside a switch expression's arm. */
/* What the evaluator found about an expression of the body being compiled,
 * under a key, in one compiled body (the function's, or a body inlined in
 * it, by serial): whether it is known before run, and its value. */
typedef struct { RangeNode *node, *key; size_t serial; int known; RangeValue value; } NativeFold;
typedef struct NativeRegion {
    RangeNode *function, *key, *resultType;
    int32_t result, stack;
    int resultKind, valueDepth;
    size_t slots, temps;
    NativeJump *returns; size_t returnCount, returnCapacity;
    struct NativeRegion *outer;
} NativeRegion;

typedef struct Native {
    SourceReport *report;
    Typer *typer;
    RangeMachine machine;
    int failed;
    int asWritten; /* every expression compiled as written: nothing is filled before run */
    NativeFold *folds; size_t foldCount, foldCapacity, serial, serials;
    /* The function being compiled, and the key its findings are read under. */
    RangeNode *owner, *self, *output, *function, *key;
    int32_t frame, selfSlot, resultSlot;
    NativeRegion *region;  /* the inlined body being compiled, if any */
    NativeClosure *closures; size_t closureCount, closureCapacity;
    NativeHidden *hidden; size_t hiddenCount, hiddenCapacity;
    NativeTarget *targets; size_t targetCount, targetCapacity;
    int valueDepth; /* switch expressions whose arms are being compiled */
    size_t *stackResets; size_t stackResetCount, stackResetCapacity; /* sp := frame base, patched at the end */
    NativeSlot *slots; size_t slotCount, slotCapacity;
    size_t *returns; size_t returnCount, returnCapacity;
    /* The program. */
    NativeCall *calls; size_t callCount, callCapacity;
    NativeTrap *traps; size_t trapCount, trapCapacity;
    NativeInstance *instances; size_t instanceCount, instanceCapacity;
    NativeText *texts; size_t textCount, textCapacity;
    NativeTemp *temps; size_t tempCount, tempCapacity;
    long resultTemp; /* the temporary the last expression produced, or -1 */
    NativeHelper *helpers; size_t helperCount, helperCapacity;
    NativeHelperCall *helperCalls; size_t helperCallCount, helperCallCapacity;
} Native;

#define NATIVE_PUSH(array,count,capacity,value) do { \
    if ((count) == (capacity)) { (capacity) = (capacity) ? (capacity) * 2 : 16; \
        (array) = realloc((array),(capacity) * sizeof(*(array))); if (!(array)) abort(); } \
    (array)[(count)++] = (value); } while (0)

enum { NativeNone, NativeScalar, NativeAggregate };

static void nativeMissing(Native *native, RangeNode *at, const char *format, ...)
{
    char text[512]; va_list args; va_start(args,format);
    vsnprintf(text,sizeof(text),format,args); va_end(args);
    sourceDiagnostic(native->report,at,0,"not-implemented","%s",text);
    native->failed = 1;
}

static size_t nativeEmit(Native *native, uint32_t instruction) { return rangeEmit(&native->machine,instruction); }

static void nativeConstant(Native *native, int rd, uint64_t value)
{
    nativeEmit(native,armMovz(rd,(uint16_t)value,0));
    for (int shift = 16; shift < 64; shift += 16)
        if ((uint16_t)(value >> shift)) nativeEmit(native,armMovk(rd,(uint16_t)(value >> shift),shift));
}

/* Branch to a trap stub with a located message when the branch is taken. */
static void nativeTrap(Native *native, uint32_t branch, RangeNode *at, const char *format, ...)
{
    char text[512]; va_list args; va_start(args,format);
    int prefix = snprintf(text,sizeof(text),"%s:%d:%d: ",at->path,at->line,at->column);
    vsnprintf(text + prefix,sizeof(text) - (size_t)prefix,format,args); va_end(args);
    size_t length = strlen(text);
    if (length + 2 < sizeof(text)) { text[length] = '\n'; text[length + 1] = '\0'; }
    NativeTrap trap = {.at=nativeEmit(native,branch),.branch=branch,
        .message=rangeArenaIntern(native->report->arena,text,strlen(text))};
    NATIVE_PUSH(native->traps,native->trapCount,native->trapCapacity,trap);
}

/* ---- types in the function being compiled ---- */

static int nativeKind(Native *native, RangeNode *type, RangeNode *at)
{
    char name[160];
    if (deferredType(native->typer,type)) {
        nativeMissing(native,at,"this value is known only at macro time; compiled code has no value of it");
        return NativeNone;
    }
    if (macroTimeType(native->typer,type)) {
        describeType(name,sizeof(name),type);
        nativeMissing(native,at,"values of %s exist only up to macro time; compiled code has no value of it",name);
        return NativeNone;
    }
    if (!type || type->kind != RangeNodeSpecialization) {
        describeType(name,sizeof(name),type);
        nativeMissing(native,at,"native values of %s are not implemented",name);
        return NativeNone;
    }
    if (!layoutOf(native->typer,type,at)) {
        describeType(name,sizeof(name),type);
        nativeMissing(native,at,"native values of %s are not implemented: it has no runtime layout",name);
        return NativeNone;
    }
    return type->scalarBits ? NativeScalar : NativeAggregate;
}

size_t nativeMemberIndex(RangeNode *declaration, RangeNode *member)
{
    for (size_t i = 0; i < declaration->itemCount; ++i) if (declaration->items[i] == member) return i;
    return SIZE_MAX;
}

/* ---- frame ---- */

static int32_t nativeReserve(Native *native, size_t size, size_t alignment)
{
    if (alignment < 8) alignment = 8;
    size_t frame = ((size_t)native->frame + size + alignment - 1) / alignment * alignment;
    native->frame = (int32_t)frame;
    return -(int32_t)frame;
}

/* The latest slot of a declaration that the running body sees. */
static NativeSlot *nativeSlotOf(Native *native, RangeNode *declaration)
{
    for (size_t i = native->slotCount; declaration && i-- > 0;) {
        int hidden = 0;
        for (size_t h = 0; h < native->hiddenCount && !hidden; ++h)
            hidden = i >= native->hidden[h].slotFrom && i < native->hidden[h].slotTo;
        if (!hidden && native->slots[i].declaration == declaration) return &native->slots[i];
    }
    return NULL;
}

static int32_t nativeNewSlot(Native *native, RangeNode *declaration, RangeNode *type, int kind)
{
    int32_t offset = kind == NativeAggregate ? nativeReserve(native,type->size ? type->size : 1,type->alignment) : nativeReserve(native,8,8);
    NativeSlot slot = {.declaration=declaration,.offset=offset,.type=type};
    NATIVE_PUSH(native->slots,native->slotCount,native->slotCapacity,slot);
    return offset;
}

/* rd = rn + offset (offset may exceed 12 bits). */
static void nativeAddOffset(Native *native, int rd, int rn, size_t offset)
{
    if (offset >> 24) { nativeMissing(native,NULL,"offsets beyond 16 MB are not implemented"); return; }
    if (!offset) { if (rd != rn) nativeEmit(native,armAddImm(rd,rn,0)); return; }
    if (offset >> 12) nativeEmit(native,armAddImmHigh(rd,rn,(uint32_t)(offset >> 12)));
    if (offset & 0xFFF) nativeEmit(native,armAddImm(rd,offset >> 12 ? rd : rn,(uint32_t)(offset & 0xFFF)));
}

/* rd = x29 + offset, offset negative. */
static void nativeFrameAddress(Native *native, int rd, int32_t offset)
{
    uint32_t distance = (uint32_t)-offset;
    if (distance >> 24) { nativeMissing(native,NULL,"frames beyond 16 MB are not implemented"); return; }
    if (distance >> 12) nativeEmit(native,armSubImmHigh(rd,29,distance >> 12));
    if ((distance & 0xFFF) || !(distance >> 12)) nativeEmit(native,armSubImm(rd,distance >> 12 ? rd : 29,distance & 0xFFF));
}

/* Scalar frame slots hold the full register. */
static void nativeStore(Native *native, int rt, int32_t offset)
{
    if (offset >= -256) { nativeEmit(native,armStur(rt,29,offset)); return; }
    nativeFrameAddress(native,9,offset);
    nativeEmit(native,armStr(rt,9,0));
}

static void nativeLoad(Native *native, int rt, int32_t offset)
{
    if (offset >= -256) { nativeEmit(native,armLdur(rt,29,offset)); return; }
    nativeFrameAddress(native,9,offset);
    nativeEmit(native,armLdr(rt,9,0));
}

/* A scalar inside an aggregate occupies exactly its size. */
static void nativeLoadScalar(Native *native, int rt, int rn, size_t offset, RangeNode *type)
{
    size_t size = type->size;
    if (offset % size || offset / size > 4095) { nativeAddOffset(native,10,rn,offset); rn = 10; offset = 0; }
    nativeEmit(native,armLoadSized(size,type->scalarSigned,rt,rn,(uint32_t)offset));
}

static void nativeStoreScalar(Native *native, int rt, int rn, size_t offset, RangeNode *type)
{
    size_t size = type->size;
    if (offset % size || offset / size > 4095) { nativeAddOffset(native,10,rn,offset); rn = 10; offset = 0; }
    nativeEmit(native,armStoreSized(size,rt,rn,(uint32_t)offset));
}

/* Copy `size` bytes from [source] to [destination]; clobbers x10-x12. */
static void nativeCopy(Native *native, int destination, int source, size_t size)
{
    nativeEmit(native,armAddImm(12,destination,0));
    nativeEmit(native,armAddImm(10,source,0));
    size_t offset = 0;
    for (size_t chunk = 8; chunk; chunk /= 2)
        while (size - offset >= chunk) {
            if (offset / chunk > 4095) {
                nativeAddOffset(native,12,12,offset); nativeAddOffset(native,10,10,offset);
                size -= offset; offset = 0;
            }
            nativeEmit(native,armLoadSized(chunk,0,11,10,(uint32_t)offset));
            nativeEmit(native,armStoreSized(chunk,11,12,(uint32_t)offset));
            offset += chunk;
        }
}

static void nativeZero(Native *native, int base, size_t size)
{
    nativeEmit(native,armAddImm(12,base,0));
    size_t offset = 0;
    for (size_t chunk = 8; chunk; chunk /= 2)
        while (size - offset >= chunk) {
            if (offset / chunk > 4095) { nativeAddOffset(native,12,12,offset); size -= offset; offset = 0; }
            nativeEmit(native,armStoreSized(chunk,31,12,(uint32_t)offset));
            offset += chunk;
        }
}

/* ---- what is known before run ----
 * Native code fills in every value known before run and emits machine code
 * only for what stays unknown. Each expression it reaches first asks the
 * evaluator, which runs what the expression reaches as a macro would,
 * reading the names of the body being compiled as native code holds them: a
 * known slot's value, or nothing known. A known value is emitted; anything
 * else is compiled as written, its parts asking in turn. What reads or binds
 * a name at run (a parameter, the receiver, a state, what a condition
 * binds), makes an effect, traps, exceeds the evaluator's limits, or needs
 * typing that has not run is not known. What the evaluator finds about an
 * expression at the root of the body is kept, so each is evaluated once.
 * Compiled as written, no expression asks; only leaves do (nativeLeaf). */

static size_t nativeFoldAt(const Native *native, const RangeNode *node, const RangeNode *key, size_t serial)
{
    size_t mask = native->foldCapacity - 1;
    size_t at = (((uintptr_t)node >> 4) ^ ((uintptr_t)key >> 4) ^ serial * 0x9E3779B9u) & mask;
    for (NativeFold *fold; (fold = &native->folds[at])->node; at = (at + 1) & mask)
        if (fold->node == node && fold->key == key && fold->serial == serial) break;
    return at;
}

/* What the evaluator found about an expression at the root of the body. */
void nativeRemember(Native *native, RangeNode *node, int status, const RangeValue *value)
{
    if (2 * (native->foldCount + 1) > native->foldCapacity) {
        // Grow, keeping every fold.
        NativeFold *folds = native->folds;
        size_t capacity = native->foldCapacity;
        native->foldCapacity = capacity ? capacity * 2 : 256;
        native->folds = calloc(native->foldCapacity,sizeof(*folds));
        if (!native->folds) abort();
        for (size_t i = 0; i < capacity; ++i)
            if (folds[i].node) native->folds[nativeFoldAt(native,folds[i].node,folds[i].key,folds[i].serial)] = folds[i];
        free(folds);
    }
    NativeFold *fold = &native->folds[nativeFoldAt(native,node,native->key,native->serial)];
    native->foldCount += !fold->node;
    *fold = (NativeFold){.node=node,.key=native->key,.serial=native->serial,
                         .known=status == EvalNormal && value->kind != ValueClosure,.value=*value};
}

/* The evaluator, folding the body being compiled: `root` is its frame. */
static Eval nativeEval(Native *native, EvalFrame *root)
{
    *root = (EvalFrame){.key=native->key};
    return (Eval){.vm=native->typer->vm,.typer=native->typer,.outside=native,.root=root};
}

/* Whether `expr` is known before run, and its value. */
static int nativeKnown(Native *native, RangeNode *expr, RangeValue *value)
{
    if (native->asWritten || !expr) return 0;
    NativeFold *fold = native->foldCapacity ? &native->folds[nativeFoldAt(native,expr,native->key,native->serial)] : NULL;
    if (fold && fold->node) { *value = fold->value; return fold->known; }
    EvalFrame root;
    Eval eval = nativeEval(native,&root);
    return evalExpression(&eval,&root,expr,value) == EvalNormal && value->kind != ValueClosure;
}

/* A name the evaluator reads in the body: a known slot's value. */
int nativeKnownName(Native *native, RangeNode *declaration, RangeValue *out)
{
    NativeSlot *slot = nativeSlotOf(native,declaration);
    if (!slot || !slot->known) return EvalUnknown;
    *out = *slot->known;
    return EvalNormal;
}

static size_t nativeFirstField(const RangeNode *, const RangeNode *);
static void nativeTrackTemp(Native *, int32_t, RangeNode *);

/* A known aggregate as its bytes, the image native code copies into place;
 * the bytes values in it, whose addresses in __text are patched in after;
 * and the blocks it holds, @many storage or a field stored out of line, each
 * allocated and filled from an image of its own, its address patched in.
 * Without bytes, an image notes only whether native code builds the value. */
typedef struct NativeImage {
    Typer *typer;
    unsigned char *bytes;
    size_t size;
    NativeText *texts; size_t textCount, textCapacity; /* at: the offset of the address */
    struct NativeBlock *blocks; size_t blockCount, blockCapacity;
} NativeImage;
typedef struct NativeBlock { size_t at; NativeImage image; const char *message; } NativeBlock;

static int nativeImage(NativeImage *, const RangeValue *, RangeNode *, size_t);

/* Frees what an image holds; returns how many addresses it patches in. */
static size_t nativeImageFree(NativeImage *image)
{
    size_t patches = image->textCount + image->blockCount;
    for (size_t i = 0; i < image->blockCount; ++i) patches += nativeImageFree(&image->blocks[i].image);
    free(image->texts); free(image->blocks);
    return patches;
}

/* A block of `count` values of `element` after its header, one reference
 * and the count, as native code allocates them; its address goes at `at`. */
static int nativeImageBlock(NativeImage *image, size_t at, const RangeValue *values, size_t count, RangeNode *element,
                            const char *message)
{
    NativeBlock block = {.at=at,.message=message,.image={.typer=image->typer,.size=16 + count * element->size}};
    if (image->bytes) {
        block.image.bytes = rangeArenaAllocate(image->typer->report->arena,block.image.size);
        memset(block.image.bytes,0,block.image.size);
        for (size_t i = 0; i < 8; ++i) block.image.bytes[8 + i] = (unsigned char)(count >> (8 * i));
        block.image.bytes[0] = 1;
    }
    NATIVE_PUSH(image->blocks,image->blockCount,image->blockCapacity,block);
    for (size_t i = 0; i < count; ++i)
        if (!nativeImage(&image->blocks[image->blockCount - 1].image,&values[i],element,16 + i * element->size)) return 0;
    return 1;
}

/* Lay out a known value of `type` at `offset`: a scalar as stored, a case
 * by its tag and its fields, an instance by its stored members, bytes by
 * their count and their address, @many storage by its block, or none
 * without slots. */
static int nativeImage(NativeImage *image, const RangeValue *value, RangeNode *type, size_t offset)
{
    if (!type || type->kind != RangeNodeSpecialization || value->type != type || macroTimeType(image->typer,type)
        || !layoutOf(image->typer,type,NULL)) return 0;
    RangeNode *declaration = type->resolvedDeclaration;
    uint64_t scalar = (uint64_t)(value->kind == ValueCase ? value->node->integer : value->integer);
    if (type->scalarBits && (value->kind == ValueScalar || (value->kind == ValueCase && !value->count))) {
        for (size_t i = 0; image->bytes && i < type->size; ++i) image->bytes[offset + i] = (unsigned char)(scalar >> (8 * i));
        return 1;
    }
    if (bytesType(type) && value->kind == ValueText) {
        for (size_t i = 0; image->bytes && i < 8; ++i) image->bytes[offset + 8 + i] = (unsigned char)(value->length >> (8 * i));
        NativeText text = {.at=offset,.bytes=value->text,.length=value->length};
        NATIVE_PUSH(image->texts,image->textCount,image->textCapacity,text);
        return 1;
    }
    if (type->variantTag && value->kind == ValueCase) {
        for (size_t i = 0; image->bytes && i < (size_t)type->variantTag; ++i) image->bytes[offset + i] = (unsigned char)(scalar >> (8 * i));
        for (size_t j = 0, k = nativeFirstField(declaration,value->node); j < value->count; ++j, ++k)
            if (type->memberBoxed[k] ? !nativeImageBlock(image,offset + type->memberOffsets[k],&value->values[j],1,type->memberTypes[k],
                                                         "could not allocate storage for a recursive enum field")
                : !nativeImage(image,&value->values[j],type->memberTypes[k],offset + type->memberOffsets[k])) return 0;
        return 1;
    }
    if (value->kind != ValueInstance || !type->memberOffsets || value->count != declaration->itemCount) return 0;
    for (size_t i = 0; i < value->count; ++i) {
        if (type->memberOffsets[i] == SIZE_MAX) continue;
        RangeNode *member = declaration->items[i], *element = member->flags & RangeFlagMany ? manyElement(image->typer,type,member) : NULL;
        if (element && value->values[i].count && (macroTimeType(image->typer,element) || !layoutOf(image->typer,element,NULL)
            || !nativeImageBlock(image,offset + type->memberOffsets[i],value->values[i].values,value->values[i].count,element,
                                 "could not allocate @many storage"))) return 0;
        if (!element && !nativeImage(image,&value->values[i],type->memberTypes[i],offset + type->memberOffsets[i])) return 0;
    }
    return 1;
}

/* Whether native code builds a known value of `type`: 0 when it does not,
 * 1 when the value holds no block, 2 when it holds blocks. Each address
 * patched in, of bytes or of a block, is code; a value needing more than
 * 16 is compiled as written. */
static int nativeBuilds(Native *native, const RangeValue *value, RangeNode *type, RangeNode *at)
{
    if (!type || macroTimeType(native->typer,type) || !layoutOf(native->typer,type,at)) return 0;
    NativeImage image = {.typer=native->typer};
    int builds = nativeImage(&image,value,type,0) ? 1 + !!image.blockCount : 0;
    return nativeImageFree(&image) > 16 ? 0 : builds;
}

/* The address of where an image goes: x29 + base, or, indirect, the
 * address the frame slot at base holds. */
static void nativeImageAddress(Native *native, int rd, int32_t base, int indirect)
{
    if (indirect) nativeLoad(native,rd,base);
    else nativeFrameAddress(native,rd,base);
}

/* Copy an image into place, then patch in the addresses of its bytes and
 * of its blocks, each allocated and filled in turn. */
static void nativeStoreImage(Native *native, const NativeImage *image, int32_t base, int indirect, RangeNode *at)
{
    int zero = 1;
    for (size_t i = 0; i < image->size && zero; ++i) zero = !image->bytes[i];
    nativeImageAddress(native,0,base,indirect);
    if (zero) nativeZero(native,0,image->size);
    else {
        NativeText bytes = {.at=nativeEmit(native,armAdr(1,0)),.bytes=(const char *)image->bytes,.length=image->size};
        NATIVE_PUSH(native->texts,native->textCount,native->textCapacity,bytes);
        nativeCopy(native,0,1,image->size);
    }
    for (size_t i = 0; i < image->textCount; ++i) {
        NativeText text = {.at=nativeEmit(native,armAdr(1,0)),.bytes=image->texts[i].bytes,.length=image->texts[i].length};
        NATIVE_PUSH(native->texts,native->textCount,native->textCapacity,text);
        nativeAddOffset(native,10,0,image->texts[i].at);
        nativeEmit(native,armStr(1,10,0));
    }
    for (size_t i = 0; i < image->blockCount; ++i) {
        const NativeBlock *block = &image->blocks[i];
        int32_t slot = nativeReserve(native,8,8);
        nativeConstant(native,0,block->image.size);
        rangeCallImport(&native->machine,"_malloc");
        nativeTrap(native,armCbz(0,0),at,"%s",block->message);
        nativeStore(native,0,slot);
        nativeImageAddress(native,1,base,indirect);
        nativeAddOffset(native,1,1,block->at);
        nativeEmit(native,armStr(0,1,0));
        nativeStoreImage(native,&block->image,slot,1,at);
    }
}

/* Emit a known value of `type`, which native code builds, as an expression
 * leaves it: a scalar in x0; an aggregate in a temporary, its address in x0,
 * copied from its image in __text, a temporary that owns the blocks built
 * for it. Bytes point at their text in __text, as a literal's do. */
static void nativeKnownValue(Native *native, const RangeValue *value, RangeNode *type, RangeNode *at)
{
    native->resultTemp = -1;
    if (type->scalarBits) {
        nativeConstant(native,0,(uint64_t)(value->kind == ValueCase ? value->node->integer : value->integer));
        return;
    }
    int32_t temporary = nativeReserve(native,type->size ? type->size : 1,type->alignment);
    if (value->kind == ValueText) {
        // An address and a count, and no block: the bytes are in the executable.
        NativeText text = {.at=nativeEmit(native,armAdr(1,0)),.bytes=value->text,.length=value->length};
        NATIVE_PUSH(native->texts,native->textCount,native->textCapacity,text);
        nativeConstant(native,2,text.length);
        nativeFrameAddress(native,0,temporary);
        nativeEmit(native,armStr(1,0,0));
        nativeEmit(native,armStr(2,0,8));
        nativeEmit(native,armStr(31,0,16));
        return;
    }
    NativeImage image = {.typer=native->typer,.bytes=rangeArenaAllocate(native->report->arena,type->size),.size=type->size};
    memset(image.bytes,0,type->size);
    nativeImage(&image,value,type,0);
    nativeStoreImage(native,&image,temporary,0,at);
    if (image.blockCount) nativeTrackTemp(native,temporary,type);
    nativeImageFree(&image);
    nativeFrameAddress(native,0,temporary);
}

/* A declaration whose value is known: a slot naming the value. One that
 * holds no block has no storage, and each read fills it in; returns 0,
 * adding none, for any other. */
static int nativeKnownSlot(Native *native, RangeNode *declaration, RangeNode *type, const RangeValue *value)
{
    if (nativeBuilds(native,value,type,declaration) != 1) return 0;
    RangeValue *known = rangeArenaAllocate(native->report->arena,sizeof(*known));
    *known = *value;
    NativeSlot slot = {.declaration=declaration,.type=type,.known=known};
    NATIVE_PUSH(native->slots,native->slotCount,native->slotCapacity,slot);
    return 1;
}

/* The value of the slot just made for `declaration`, built where it was
 * declared, is known too: a let holding blocks, read in place. */
static void nativeKnownStorage(Native *native, RangeNode *declaration, const RangeValue *value)
{
    NativeSlot *slot = native->slotCount ? &native->slots[native->slotCount - 1] : NULL;
    if (!slot || slot->declaration != declaration || !slot->offset || nativeBuilds(native,value,slot->type,declaration) != 2) return;
    slot->known = rangeArenaAllocate(native->report->arena,sizeof(*slot->known));
    *slot->known = *value;
}

/* ---- expressions: a scalar in x0, or an aggregate's address in x0 ---- */

static RangeNode *nativeExpression(Native *, RangeNode *);
static RangeNode *nativeAddress(Native *, RangeNode *, int *);
static void nativeCopyValue(Native *, int, int, RangeNode *, int);
static void nativeBranchHere(Native *, size_t, uint32_t);
static void nativeTrackTemp(Native *, int32_t, RangeNode *);
static int nativeTakeTemp(Native *);
static int nativeSharesSlots(const RangeNode *);

/* x0 holds a result of `type`; trap unless it fits the declared width. */
static void nativeFits(Native *native, RangeNode *type, RangeNode *at, const char *operation)
{
    if (type->scalarBits >= 64) return;
    nativeEmit(native,type->scalarSigned ? armSbfx(9,0,type->scalarBits) : armUbfx(9,0,type->scalarBits));
    nativeEmit(native,armCmp(9,0));
    char name[160]; describeType(name,sizeof(name),type);
    nativeTrap(native,armBcond(RangeNE,0),at,"result of '%s' does not fit %s",operation,name);
}

/* The condition a builtin comparison of scalars sets, by signedness; -1 when
 * the name is not a comparison. */
static int nativeRelation(const char *op, int isSigned)
{
    return same(op,"<") ? (isSigned ? RangeLT : RangeLO) : same(op,">") ? (isSigned ? RangeGT : RangeHI)
        : same(op,"<=") ? (isSigned ? RangeLE : RangeLS) : same(op,">=") ? (isSigned ? RangeGE : RangeHS) : -1;
}

static void nativeArithmetic(Native *native, RangeNode *expr, RangeNode *type)
{
    const char *op = expr->name;
    char name[160]; describeType(name,sizeof(name),type);
    int wide = type->scalarBits == 64, isSigned = type->scalarSigned;
    if (same(op,"+") || same(op,"-")) {
        int add = same(op,"+");
        if (wide) {
            nativeEmit(native,add ? armAdds(0,0,1) : armSubs(0,0,1));
            nativeTrap(native,armBcond(isSigned ? RangeVS : add ? RangeHS : RangeLO,0),expr,"result of '%s' does not fit %s",op,name);
        } else {
            nativeEmit(native,add ? armAdd(0,0,1) : armSub(0,0,1));
            nativeFits(native,type,expr,op);
        }
    } else if (same(op,"*")) {
        // The full product is checked against 64 bits, then against the width.
        nativeEmit(native,armMul(2,0,1));
        if (isSigned) {
            nativeEmit(native,armSmulh(3,0,1));
            nativeEmit(native,armCmpAsr63(3,2));
            nativeTrap(native,armBcond(RangeNE,0),expr,"result of '*' does not fit %s",name);
        } else {
            nativeEmit(native,armUmulh(3,0,1));
            nativeTrap(native,armCbnz(3,0),expr,"result of '*' does not fit %s",name);
        }
        nativeEmit(native,armMov(0,2));
        nativeFits(native,type,expr,op);
    } else if (same(op,"/") || same(op,"%")) {
        nativeTrap(native,armCbz(1,0),expr,"division by zero in '%s'",op);
        if (isSigned && wide && same(op,"/")) {
            // The minimum divided by -1 is the one quotient outside the range.
            nativeEmit(native,armCmnImm(1,1));
            nativeEmit(native,armBcond(RangeNE,3));
            nativeEmit(native,armNegs(9,0));
            nativeTrap(native,armBcond(RangeVS,0),expr,"result of '/' does not fit %s",name);
        }
        nativeEmit(native,isSigned ? armSdiv(2,0,1) : armUdiv(2,0,1));
        if (same(op,"/")) { nativeEmit(native,armMov(0,2)); nativeFits(native,type,expr,op); }
        else nativeEmit(native,armMsub(0,2,1,0));
    } else nativeMissing(native,expr,"native operator '%s' is not implemented",op);
}

/* ---- unions ----
 * A union value (an enum with payloads) is its tag at offset 0, then the
 * fields of its current case. Fields are numbered across the cases in order;
 * the specialization keeps each one's offset, type, and whether it is stored
 * out of line: then the field holds the address of a block like @many
 * storage, [references][count = 1][value], shared by copies and released
 * when its last reference ends. */

static size_t nativeFirstField(const RangeNode *declaration, const RangeNode *entry)
{
    size_t k = 0;
    for (size_t i = 0; i < declaration->itemCount && declaration->items[i] != entry; ++i)
        if (declaration->items[i]->kind == RangeNodeEnumCase) k += declaration->items[i]->itemCount;
    return k;
}

/* Whether the current case's fields need retaining or releasing. */
static int nativeCaseShares(const RangeNode *type, size_t first, size_t count)
{
    for (size_t k = first; k < first + count; ++k)
        if (type->memberBoxed[k] || nativeSharesSlots(type->memberTypes[k])) return 1;
    return 0;
}

/* Branch past this point unless the union at the address in `base` holds
 * `entry`. Uses x9 and x17. */
static size_t nativeUnlessCase(Native *native, int base, RangeNode *type, RangeNode *entry)
{
    nativeEmit(native,armLoadSized((size_t)type->variantTag,0,17,base,0));
    nativeConstant(native,9,(uint64_t)entry->integer);
    nativeEmit(native,armCmp(17,9));
    return nativeEmit(native,armBcond(RangeNE,0));
}

/* Store the value in x0, a scalar or an aggregate's address, into field k of
 * the union at frame offset `destination`: inline, or in a block of its own
 * when the field is stored out of line. A temporary moving into place is not
 * retained. */
static void nativeStoreField(Native *native, RangeNode *at, RangeNode *type, size_t k, int32_t destination, int moved)
{
    size_t offset = type->memberOffsets[k];
    RangeNode *fieldType = type->memberTypes[k];
    if (type->memberBoxed[k]) {
        nativeEmit(native,armPush(0));            /* the value */
        nativeConstant(native,0,16 + fieldType->size);
        rangeCallImport(&native->machine,"_malloc");
        nativeTrap(native,armCbz(0,0),at,"could not allocate storage for a recursive enum field");
        nativeEmit(native,armMovz(9,1,0));
        nativeEmit(native,armStr(9,0,0));         /* one reference */
        nativeEmit(native,armStr(9,0,8));         /* one slot */
        nativeEmit(native,armPop(1));
        nativeEmit(native,armPush(0));            /* the block */
        nativeEmit(native,armAddImm(0,0,16));
        if (fieldType->scalarBits) nativeStoreScalar(native,1,0,0,fieldType);
        else nativeCopyValue(native,0,1,fieldType,!moved);
        nativeEmit(native,armPop(0));
        nativeFrameAddress(native,1,destination);
        nativeAddOffset(native,1,1,offset);
        nativeEmit(native,armStr(0,1,0));
    } else {
        nativeFrameAddress(native,1,destination);
        if (fieldType->scalarBits) nativeStoreScalar(native,0,1,offset,fieldType);
        else { nativeAddOffset(native,1,1,offset); nativeCopyValue(native,1,0,fieldType,!moved); }
    }
}

/* `.value(number: 7)`: build a case of a union `type` at frame offset
 * `destination`, or in a temporary. */
static RangeNode *nativeVariant(Native *native, RangeNode *at, RangeNode *type, RangeNode *entry,
                                RangeNode **arguments, size_t count, int32_t destination)
{
    if (nativeKind(native,type,at) == NativeNone || !entry) return NULL;
    int temporary = !destination;
    if (temporary) destination = nativeReserve(native,type->size,type->alignment);
    nativeFrameAddress(native,0,destination);
    nativeZero(native,0,type->size);
    nativeConstant(native,1,(uint64_t)entry->integer);
    nativeEmit(native,armStoreSized((size_t)type->variantTag,1,0,0));
    size_t first = nativeFirstField(type->resolvedDeclaration,entry);
    for (size_t j = 0; j < entry->itemCount; ++j) {
        RangeNode *field = entry->items[j], *value = NULL;
        for (size_t i = 0; i < count; ++i) if (found(native->key,arguments[i])->resolvedDeclaration == field) value = arguments[i]->a;
        if (!value || nativeKind(native,type->memberTypes[first + j],field) == NativeNone || !nativeExpression(native,value)) continue;
        nativeStoreField(native,at,type,first + j,destination,nativeTakeTemp(native));
    }
    if (temporary) nativeTrackTemp(native,destination,type);
    else native->resultTemp = -1;
    nativeFrameAddress(native,0,destination);
    return type;
}

/* Make `context` the running one; returns the one it replaces. */
static NativeContext nativeUse(Native *native, NativeContext context)
{
    NativeContext running = {.owner=native->owner,.self=native->self,.function=native->function,.key=native->key,
                             .selfSlot=native->selfSlot};
    native->owner = context.owner; native->self = context.self; native->function = context.function;
    native->key = context.key; native->selfSlot = context.selfSlot;
    return running;
}

/* A member's default, compiled where it is declared: in the specialization
 * being constructed, under its key. */
static RangeNode *nativeDefault(Native *native, RangeNode *type, RangeNode *value)
{
    NativeContext caller = nativeUse(native,(NativeContext){.owner=type->resolvedDeclaration,.self=type,
                                                            .key=keyOf(type->resolvedDeclaration,type)});
    RangeNode *result = nativeExpression(native,value);
    nativeUse(native,caller);
    return result;
}

/* Construct `type` at frame offset `destination` (an aggregate), or into x0 (a
 * scalar). Arguments populate the members they name; the rest take their
 * defaults; @many storage starts empty. */
static RangeNode *nativeConstruct(Native *native, RangeNode *at, RangeNode *type, RangeNode **arguments,
                                  size_t count, int32_t destination)
{
    int kind = nativeKind(native,type,at);
    if (kind == NativeNone) return NULL;
    RangeNode *declaration = type->resolvedDeclaration, *key = keyOf(declaration,type);
    if (kind == NativeScalar) {
        // A scalar's single input is the value itself.
        int defaulted;
        RangeNode *value = constructionSingle(key,declaration,arguments,count,&defaulted);
        native->resultTemp = -1;
        if (!value) nativeEmit(native,armMovz(0,0,0));
        else if (defaulted) nativeDefault(native,type,value);
        else nativeExpression(native,value);
        return type;
    }
    int temporary = !destination;
    if (temporary) destination = nativeReserve(native,type->size ? type->size : 1,type->alignment);
    if (bytesType(type)) {
        // Like a scalar, a bytes construct's single input is the value itself:
        // `String("hi")` is the literal's bytes, and `String()` its default's.
        int defaulted;
        RangeNode *value = constructionSingle(key,declaration,arguments,count,&defaulted);
        nativeFrameAddress(native,0,destination);
        nativeZero(native,0,type->size);
        if (value) {
            if (!(defaulted ? nativeDefault(native,type,value) : nativeExpression(native,value))) return NULL;
            int moved = nativeTakeTemp(native);
            nativeFrameAddress(native,1,destination);
            nativeCopyValue(native,1,0,type,!moved);
        }
        if (temporary) nativeTrackTemp(native,destination,type);
        else native->resultTemp = -1;
        nativeFrameAddress(native,0,destination);
        return type;
    }
    if (declaration->kind == RangeNodeEnum) {
        // `Tree(.leaf(value: 1))` copies the case value given.
        if (count != 1 || !nativeExpression(native,arguments[0]->a)) return NULL;
        int moved = nativeTakeTemp(native);
        nativeFrameAddress(native,1,destination);
        nativeCopyValue(native,1,0,type,!moved);
        if (temporary) nativeTrackTemp(native,destination,type);
        else native->resultTemp = -1;
        nativeFrameAddress(native,0,destination);
        return type;
    }
    nativeFrameAddress(native,0,destination);
    nativeZero(native,0,type->size);
    // Members are initialized in declaration order; a default sees the ones
    // before it by name, through slots aliasing them in place.
    size_t aliases = native->slotCount, previous = SIZE_MAX;
    for (size_t i = 0; i < declaration->itemCount; ++i) {
        RangeNode *member = declaration->items[i];
        size_t offset = type->memberOffsets ? type->memberOffsets[i] : SIZE_MAX;
        if (offset == SIZE_MAX || (member->flags & RangeFlagMany)) continue;
        if (previous != SIZE_MAX) {
            // The member stored before this one is initialized now.
            NativeSlot alias = {.declaration=declaration->items[previous],.offset=destination + (int32_t)type->memberOffsets[previous],
                .type=type->memberTypes[previous],.alias=1,.packed=1};
            NATIVE_PUSH(native->slots,native->slotCount,native->slotCapacity,alias);
        }
        previous = i;
        RangeNode *memberType = type->memberTypes[i], *value = constructionArgument(native->key,member,arguments,count);
        int memberKind = nativeKind(native,memberType,member);
        if (memberKind == NativeNone) continue;
        if (value) nativeExpression(native,value);
        else if ((value = declarationValue(key,member)) == member) {
            // A default that constructs: its arguments are the declaration's.
            NativeContext caller = nativeUse(native,(NativeContext){.owner=declaration,.self=type,.key=key});
            nativeConstruct(native,member,memberType,member->items,member->itemCount,destination + (int32_t)offset);
            nativeUse(native,caller);
            if (memberKind == NativeScalar) { nativeFrameAddress(native,1,destination); nativeStoreScalar(native,0,1,offset,memberType); }
            continue;
        } else if (value) nativeDefault(native,type,value);
        else continue; /* required inputs are enforced by the type checker */
        int moved = nativeTakeTemp(native);
        nativeFrameAddress(native,1,destination);
        if (memberKind == NativeScalar) nativeStoreScalar(native,0,1,offset,memberType);
        else { nativeAddOffset(native,1,1,offset); nativeCopyValue(native,1,0,memberType,!moved); }
    }
    native->slotCount = aliases;
    if (temporary) nativeTrackTemp(native,destination,type);
    else native->resultTemp = -1;
    nativeFrameAddress(native,0,destination);
    return type;
}

/* ---- ownership ----
 * Values holding @many storage own references to their blocks. A local or
 * parameter ends at the end of its block (a return ends every value in
 * scope); a temporary ends with its statement unless it is moved into place;
 * an overwritten value ends when its place is assigned. Ending releases each
 * block through a subroutine per type; a block whose references reach zero
 * releases its elements and is freed. */

static size_t nativeHelper(Native *native, RangeNode *type, int block)
{
    for (size_t i = 0; i < native->helperCount; ++i)
        if (native->helpers[i].type == type && native->helpers[i].block == block) return i;
    NativeHelper helper = {.type=type,.block=block};
    NATIVE_PUSH(native->helpers,native->helperCount,native->helperCapacity,helper);
    return native->helperCount - 1;
}

static void nativeCallHelper(Native *native, RangeNode *type, int block)
{
    NativeHelperCall call = {.at=nativeEmit(native,armBl(0)),.helper=nativeHelper(native,type,block)};
    NATIVE_PUSH(native->helperCalls,native->helperCallCount,native->helperCallCapacity,call);
}

/* Release the value of `type` at the address in x0. Clobbers caller-saved registers. */
static void nativeRelease(Native *native, RangeNode *type)
{
    if (nativeSharesSlots(type)) nativeCallHelper(native,type,0);
}

static void nativeTrackTemp(Native *native, int32_t offset, RangeNode *type)
{
    native->resultTemp = -1;
    if (!nativeSharesSlots(type)) return;
    NativeTemp temp = {.offset=offset,.type=type};
    NATIVE_PUSH(native->temps,native->tempCount,native->tempCapacity,temp);
    native->resultTemp = (long)native->tempCount - 1;
}

/* The last expression's temporary moves into place: it no longer ends. */
static int nativeTakeTemp(Native *native)
{
    if (native->resultTemp < 0) return 0;
    native->temps[native->resultTemp].consumed = 1;
    native->resultTemp = -1;
    return 1;
}

static void nativeReleaseTemps(Native *native, size_t from)
{
    for (size_t i = native->tempCount; i-- > from;) {
        if (native->temps[i].consumed) continue;
        nativeFrameAddress(native,0,native->temps[i].offset);
        nativeRelease(native,native->temps[i].type);
    }
    native->tempCount = from;
    native->resultTemp = -1;
}

static void nativeReleaseSlots(Native *native, size_t from)
{
    for (size_t i = native->slotCount; i-- > from;) {
        RangeNode *type = native->slots[i].type;
        if (!type || native->slots[i].alias || !native->slots[i].offset || type->scalarBits || !nativeSharesSlots(type)) continue;
        nativeFrameAddress(native,0,native->slots[i].offset);
        nativeRelease(native,type);
    }
}

/* ---- @many storage ----
 * A @many member holds the address of a C heap block, or zero while empty:
 * [references: 8 bytes][slot count: 8 bytes][slots]. Storage is copy-on-write:
 * copying a value retains each block it reaches, and resize or write on a
 * shared block first give the writer its own block (cloned with libSystem
 * malloc and memcpy, retaining its elements; the old block loses a reference).
 * resize grows with realloc and zero-fills new slots; read and write check the
 * index against the count C keeps. Blocks are never released when values end,
 * and never freed. The block belongs to the construct's single @many member;
 * its element size comes from that member's declared type in this
 * specialization. */

typedef struct { size_t offset; RangeNode *element; } NativeSlots;

static int nativeSlotsOf(Native *native, RangeNode *self, RangeNode *at, NativeSlots *slots)
{
    RangeNode *declaration = self->resolvedDeclaration, *member = NULL;
    size_t index = SIZE_MAX, found = 0;
    for (size_t i = 0; i < declaration->itemCount; ++i)
        if (rangeNodeDeclaresValue(declaration->items[i]->kind) && (declaration->items[i]->flags & RangeFlagMany)) {
            member = declaration->items[i]; index = i; ++found;
        }
    if (found != 1 || !layoutOf(native->typer,self,at) || !self->memberOffsets || self->memberOffsets[index] == SIZE_MAX) {
        nativeMissing(native,at,"slot builtins need exactly one @many member with a layout");
        return 0;
    }
    RangeNode *element = manyElement(native->typer,self,member);
    if (nativeKind(native,element,member) == NativeNone) return 0;
    slots->offset = self->memberOffsets[index];
    slots->element = element;
    return 1;
}

/* A value of `type` holds @many storage, directly or in a member. */
static int nativeSharesSlots(const RangeNode *type)
{
    if (bytesType(type)) return 1; /* its owning block, when it has one */
    if (!type || type->kind != RangeNodeSpecialization || type->scalarBits || !type->memberOffsets) return 0;
    RangeNode *declaration = type->resolvedDeclaration;
    if (type->variantTag) {
        size_t fields = nativeFirstField(declaration,NULL);
        return nativeCaseShares(type,0,fields);
    }
    for (size_t i = 0; i < declaration->itemCount; ++i) {
        if (type->memberOffsets[i] == SIZE_MAX) continue;
        if ((declaration->items[i]->flags & RangeFlagMany) || nativeSharesSlots(type->memberTypes[i])) return 1;
    }
    return 0;
}

/* Retain every block the value at [base + offset] holds. Uses x9, x11, x13. */
static void nativeRetainBlock(Native *native, int base, size_t at)
{
    nativeAddOffset(native,13,base,at);
    nativeEmit(native,armLdr(9,13,0));
    nativeEmit(native,armCbz(9,4));
    nativeEmit(native,armLdr(11,9,0));
    nativeEmit(native,armAddImm(11,11,1));
    nativeEmit(native,armStr(11,9,0));
}

static void nativeRetain(Native *native, int base, size_t offset, RangeNode *type)
{
    RangeNode *declaration = type->resolvedDeclaration;
    if (bytesType(type)) { nativeRetainBlock(native,base,offset + 16); return; }
    if (type->variantTag) {
        // Only the current case's fields hold references.
        for (size_t i = 0, k = 0; i < declaration->itemCount; ++i) {
            RangeNode *entry = declaration->items[i];
            if (entry->kind != RangeNodeEnumCase) continue;
            size_t first = k;
            k += entry->itemCount;
            if (!nativeCaseShares(type,first,entry->itemCount)) continue;
            nativeAddOffset(native,13,base,offset);
            size_t skip = nativeUnlessCase(native,13,type,entry);
            for (size_t f = first; f < k; ++f) {
                if (type->memberBoxed[f]) nativeRetainBlock(native,base,offset + type->memberOffsets[f]);
                else if (nativeSharesSlots(type->memberTypes[f])) nativeRetain(native,base,offset + type->memberOffsets[f],type->memberTypes[f]);
            }
            nativeBranchHere(native,skip,armBcond(RangeNE,0));
        }
        return;
    }
    for (size_t i = 0; i < declaration->itemCount; ++i) {
        if (!type->memberOffsets || type->memberOffsets[i] == SIZE_MAX) continue;
        size_t at = offset + type->memberOffsets[i];
        if (declaration->items[i]->flags & RangeFlagMany) nativeRetainBlock(native,base,at);
        else if (nativeSharesSlots(type->memberTypes[i])) nativeRetain(native,base,at,type->memberTypes[i]);
    }
}

/* Retain the elements of the block in x6, x7 slots long. Uses x14-x16. */
static void nativeRetainElements(Native *native, RangeNode *element)
{
    if (!nativeSharesSlots(element)) return;
    nativeEmit(native,armMovz(14,0,0));
    size_t top = native->machine.size;
    nativeEmit(native,armCmp(14,7));
    size_t done = nativeEmit(native,armBcond(RangeHS,0));
    nativeConstant(native,16,element->size);
    nativeEmit(native,armMul(15,14,16));
    nativeEmit(native,armAdd(15,15,6));
    nativeEmit(native,armAddImm(15,15,16));
    nativeRetain(native,15,0,element);
    nativeEmit(native,armAddImm(14,14,1));
    nativeEmit(native,armB(-(int32_t)((native->machine.size - top) / 4)));
    rangePatch(&native->machine,done,armBcond(RangeHS,(int32_t)((native->machine.size - done) / 4)));
}

/* Copy a value; with `retain`, the copy also holds references to its blocks.
 * A temporary moving into place is not retained. */
static void nativeCopyValue(Native *native, int destination, int source, RangeNode *type, int retain)
{
    nativeCopy(native,destination,source,type->size);
    if (retain && nativeSharesSlots(type)) nativeRetain(native,destination,0,type);
}

/* x1 = the block of the receiver at [sp + depth]; x2 = its slot count. */
static void nativeLoadBlock(Native *native, NativeSlots *slots, uint32_t depth)
{
    nativeEmit(native,armLdr(1,31,depth));
    nativeAddOffset(native,1,1,slots->offset);
    nativeEmit(native,armLdr(1,1,0));
    nativeEmit(native,armMovz(2,0,0));
    nativeEmit(native,armCbz(1,2));
    nativeEmit(native,armLdr(2,1,8));
}

/* x0 = the address of slot x3 in the block in x1, after checking x3 < x2. */
static void nativeSlotAddress(Native *native, NativeSlots *slots, RangeNode *at)
{
    nativeEmit(native,armCmp(3,2));
    nativeTrap(native,armBcond(RangeHS,0),at,"slot index is outside the @many storage");
    nativeConstant(native,4,slots->element->size);
    nativeEmit(native,armMul(4,3,4));
    nativeEmit(native,armAddImm(0,1,16));
    nativeEmit(native,armAdd(0,0,4));
}

/* Give the receiver at [sp + depth] a block no other value shares. */
static void nativeUnique(Native *native, NativeSlots *slots, uint32_t depth, RangeNode *at)
{
    nativeEmit(native,armLdr(1,31,depth));
    nativeAddOffset(native,1,1,slots->offset);
    nativeEmit(native,armLdr(1,1,0));
    size_t empty = nativeEmit(native,armCbz(1,0));
    nativeEmit(native,armLdr(2,1,0));
    nativeEmit(native,armCmpImm(2,1));
    size_t owned = nativeEmit(native,armBcond(RangeLS,0));
    nativeEmit(native,armLdr(3,1,8));
    nativeConstant(native,4,slots->element->size);
    nativeEmit(native,armMul(4,3,4));
    nativeEmit(native,armAddImm(4,4,16));    /* bytes */
    nativeEmit(native,armPush(1));            /* old block */
    nativeEmit(native,armPush(4));            /* bytes */
    nativeEmit(native,armMov(0,4));
    rangeCallImport(&native->machine,"_malloc");
    nativeTrap(native,armCbz(0,0),at,"could not allocate @many storage");
    nativeEmit(native,armLdr(2,31,0));        /* bytes */
    nativeEmit(native,armLdr(1,31,16));       /* old block */
    nativeEmit(native,armPush(0));            /* new block */
    rangeCallImport(&native->machine,"_memcpy");
    nativeEmit(native,armLdr(6,31,0));
    nativeEmit(native,armMovz(9,1,0));
    nativeEmit(native,armStr(9,6,0));         /* the new block has one reference */
    nativeEmit(native,armLdr(7,6,8));
    nativeRetainElements(native,slots->element);
    nativeEmit(native,armLdr(1,31,32));       /* old block loses a reference */
    nativeEmit(native,armLdr(2,1,0));
    nativeEmit(native,armSubImm(2,2,1));
    nativeEmit(native,armStr(2,1,0));
    nativeEmit(native,armLdr(6,31,0));
    nativeEmit(native,armAddImm(31,31,48));
    nativeEmit(native,armLdr(1,31,depth));
    nativeAddOffset(native,1,1,slots->offset);
    nativeEmit(native,armStr(6,1,0));         /* the receiver holds the new block */
    nativeBranchHere(native,empty,armCbz(1,0));
    nativeBranchHere(native,owned,armBcond(RangeLS,0));
}

static RangeNode *nativeSlotCall(Native *native, RangeNode *call, RangeNode *function, RangeNode *self)
{
    NativeSlots slots;
    RangeNode *element;
    // The receiver address is pushed; arguments follow in parameter order.
    if (!nativeSlotsOf(native,self,call,&slots)) return NULL;
    element = slots.element;
    size_t size = element->size;
    if (same(function->name,"read")) {
        if (!nativeExpression(native,call->items[0]->a)) return NULL;
        nativeEmit(native,armMov(3,0));
        nativeLoadBlock(native,&slots,0);
        nativeSlotAddress(native,&slots,call);
        nativeEmit(native,armAddImm(31,31,16)); /* drop the receiver */
        if (element->scalarBits) { nativeLoadScalar(native,0,0,0,element); native->resultTemp = -1; return element; }
        // The element stays in the block, so the copy holds its own references.
        int32_t copy = nativeReserve(native,size ? size : 1,element->alignment);
        nativeFrameAddress(native,1,copy);
        nativeCopyValue(native,1,0,element,1);
        nativeTrackTemp(native,copy,element);
        nativeFrameAddress(native,0,copy);
        return element;
    }
    if (same(function->name,"write")) {
        RangeNode *at = NULL, *value = NULL;
        for (size_t i = 0; i < call->itemCount; ++i) {
            if (same(call->items[i]->name,"at")) at = call->items[i]->a;
            if (same(call->items[i]->name,"value")) value = call->items[i]->a;
        }
        // Evaluate first: a copy made while evaluating must not see the write.
        if (!at || !value || !nativeExpression(native,value)) return NULL;
        int moved = nativeTakeTemp(native);
        nativeEmit(native,armPush(0));
        if (!nativeExpression(native,at)) return NULL;
        nativeEmit(native,armPush(0));
        nativeUnique(native,&slots,32,call);   /* receiver below value and index */
        nativeEmit(native,armPop(3));           /* index */
        nativeLoadBlock(native,&slots,16);
        nativeSlotAddress(native,&slots,call);
        nativeEmit(native,armPop(1));           /* the value */
        nativeEmit(native,armAddImm(31,31,16)); /* drop the receiver */
        native->resultTemp = -1;
        if (element->scalarBits) { nativeStoreScalar(native,1,0,0,element); return NULL; }
        if (!nativeSharesSlots(element)) { nativeCopy(native,0,1,size); return NULL; }
        // Retain the new element first, then release the one it replaces.
        nativeEmit(native,armPush(0));          /* slot: [sp + 16] */
        nativeEmit(native,armPush(1));          /* value: [sp] */
        if (!moved) { nativeEmit(native,armLdr(1,31,0)); nativeRetain(native,1,0,element); }
        nativeEmit(native,armLdr(0,31,16));
        nativeRelease(native,element);
        nativeEmit(native,armPop(1));
        nativeEmit(native,armPop(0));
        nativeCopy(native,0,1,size);
        return NULL;
    }
    // resize(to: n): count checks, a block of its own, then realloc(block, 16 + n * size).
    if (!nativeExpression(native,call->items[0]->a)) return NULL;
    nativeEmit(native,armCmpImm(0,0));
    nativeTrap(native,armBcond(RangeLT,0),call,"resize to a negative slot count");
    nativeConstant(native,4,size);
    nativeEmit(native,armUmulh(5,0,4));
    nativeTrap(native,armCbnz(5,0),call,"resize exceeds addressable memory");
    nativeEmit(native,armPush(0));           /* n */
    nativeUnique(native,&slots,16,call);
    if (nativeSharesSlots(element)) {
        // Elements past the new count end: release slots n ..< old count.
        nativeEmit(native,armLdr(0,31,0));
        nativeEmit(native,armPush(0));       /* index, from n: [sp]; n: [sp + 16] */
        size_t top = native->machine.size;
        nativeEmit(native,armLdr(3,31,0));
        nativeLoadBlock(native,&slots,32);   /* receiver below index and n */
        nativeEmit(native,armCmp(3,2));
        size_t done = nativeEmit(native,armBcond(RangeHS,0));
        nativeConstant(native,4,size);
        nativeEmit(native,armMul(4,3,4));
        nativeEmit(native,armAddImm(0,1,16));
        nativeEmit(native,armAdd(0,0,4));
        nativeRelease(native,element);
        nativeEmit(native,armLdr(3,31,0));
        nativeEmit(native,armAddImm(3,3,1));
        nativeEmit(native,armStr(3,31,0));
        nativeEmit(native,armB(-(int32_t)((native->machine.size - top) / 4)));
        nativeBranchHere(native,done,armBcond(RangeHS,0));
        nativeEmit(native,armAddImm(31,31,16));
    }
    nativeEmit(native,armPop(0));
    nativeConstant(native,4,size);
    nativeEmit(native,armMul(5,0,4));        /* x5 = n * size */
    nativeEmit(native,armAddImm(5,5,16));    /* plus the header */
    nativeLoadBlock(native,&slots,0);        /* x1 = old block, x2 = old count */
    nativeEmit(native,armPush(0));           /* n */
    nativeEmit(native,armPush(2));           /* old count */
    nativeEmit(native,armMov(0,1));
    nativeEmit(native,armMov(1,5));
    rangeCallImport(&native->machine,"_realloc");
    nativeTrap(native,armCbz(0,0),call,"resize could not allocate @many storage");
    nativeEmit(native,armPop(2));            /* old count */
    nativeEmit(native,armPop(3));            /* n */
    nativeEmit(native,armMovz(9,1,0));
    nativeEmit(native,armStr(9,0,0));        /* a block of its own: one reference */
    nativeEmit(native,armStr(3,0,8));        /* the block records its count */
    nativeEmit(native,armLdr(1,31,0));       /* receiver */
    nativeAddOffset(native,1,1,slots.offset);
    nativeEmit(native,armStr(0,1,0));        /* the member holds the block */
    // Zero the slots beyond the old count: memset(block + 16 + old * size, 0, (n - old) * size).
    nativeEmit(native,armCmp(3,2));
    size_t skip = nativeEmit(native,armBcond(RangeLS,0));
    nativeConstant(native,4,size);
    nativeEmit(native,armSub(5,3,2));
    nativeEmit(native,armMul(5,5,4));        /* bytes */
    nativeEmit(native,armMul(4,2,4));
    nativeEmit(native,armAddImm(0,0,16));
    nativeEmit(native,armAdd(0,0,4));        /* first new slot */
    nativeEmit(native,armMovz(1,0,0));
    nativeEmit(native,armMov(2,5));
    rangeCallImport(&native->machine,"_memset");
    rangePatch(&native->machine,skip,armBcond(RangeLS,(int32_t)((native->machine.size - skip) / 4)));
    nativeEmit(native,armAddImm(31,31,16)); /* drop the receiver */
    native->resultTemp = -1;
    return NULL;
}

static NativeInstance *nativeInstance(Native *, RangeNode *, RangeNode *, RangeNode *);

static void nativeCallFunction(Native *native, RangeNode *function, RangeNode *key, RangeNode *self)
{
    NativeCall site = {.at=nativeEmit(native,armBl(0)),.function=function,.key=key,.self=self};
    NATIVE_PUSH(native->calls,native->callCount,native->callCapacity,site);
    nativeInstance(native,function,key,self);
}

/* x0 = 1 when the values in x0 and x1 (scalars, or aggregates' addresses) are
 * equal. A type's equality function is called as x0.=(other: x1); any other
 * type is compared structurally: scalars directly, other values through a
 * subroutine emitted once per type a program compares. Typing checked that
 * every type compared here compares. */
static void nativeEquals(Native *native, RangeNode *type)
{
    RangeNode *function = equalityFunction(type);
    if (function) {
        // The receiver is an address: a scalar is passed through the stack.
        if (type->scalarBits) { nativeEmit(native,armPush(0)); nativeEmit(native,armAddImm(0,31,0)); }
        nativeCallFunction(native,function,keyOf(function->owner,type),type);
        if (type->scalarBits) nativeEmit(native,armAddImm(31,31,16));
        native->resultTemp = -1;
    } else if (type->scalarBits) { nativeEmit(native,armCmp(0,1)); nativeEmit(native,armCset(0,RangeEQ)); }
    else nativeCallHelper(native,type,NativeEqual);
}

/* One member or payload field of a structural comparison: x0 and x1 hold the
 * two fields' addresses. A scalar compared structurally compares inline;
 * anything else goes through its own type's `=`. */
static void nativeEqualField(Native *native, RangeNode *fieldType, NativeJump **fails, size_t *failCount, size_t *failCapacity)
{
    if (fieldType->scalarBits) {
        nativeLoadScalar(native,0,0,0,fieldType);
        nativeLoadScalar(native,1,1,0,fieldType);
        if (!equalityFunction(fieldType)) {
            nativeEmit(native,armCmp(0,1));
            NativeJump jump = {.at=nativeEmit(native,armBcond(RangeNE,0)),.base=armBcond(RangeNE,0)};
            NATIVE_PUSH(*fails,*failCount,*failCapacity,jump);
            return;
        }
    }
    nativeEquals(native,fieldType);
    NativeJump jump = {.at=nativeEmit(native,armCbz(0,0)),.base=armCbz(0,0)};
    NATIVE_PUSH(*fails,*failCount,*failCapacity,jump);
}

/* x0 = 1 when the values at x0 and x1 are equal: the structural comparison a
 * builtin function '=' stands for. Bytes compare their counts, then their
 * bytes through libSystem memcmp. A union compares its tags, then the fields
 * of its case; a construct compares every stored member in order. */
static void nativeEqualBody(Native *native, RangeNode *type)
{
    nativeEmit(native,armSubImm(31,31,16));
    nativeStore(native,0,-8);
    nativeStore(native,1,-16);
    NativeJump *fails = NULL;
    size_t failCount = 0, failCapacity = 0;
    if (bytesType(type)) {
        nativeEmit(native,armLdr(2,0,8));
        nativeEmit(native,armLdr(3,1,8));
        nativeEmit(native,armCmp(2,3));
        NativeJump differ = {.at=nativeEmit(native,armBcond(RangeNE,0)),.base=armBcond(RangeNE,0)};
        NATIVE_PUSH(fails,failCount,failCapacity,differ);
        nativeEmit(native,armLdr(0,0,0));
        nativeEmit(native,armLdr(1,1,0));
        rangeCallImport(&native->machine,"_memcmp");
        nativeEmit(native,0x7100001Fu);           /* cmp w0, #0: memcmp returns an int */
        nativeEmit(native,armCset(0,RangeEQ));
        size_t end = nativeEmit(native,armB(0));
        for (size_t i = 0; i < failCount; ++i) nativeBranchHere(native,fails[i].at,fails[i].base);
        nativeEmit(native,armMovz(0,0,0));
        nativeBranchHere(native,end,armB(0));
        free(fails);
        return;
    }
    RangeNode *declaration = type->resolvedDeclaration;
    NativeJump *equal = NULL;
    size_t equalCount = 0, equalCapacity = 0;
    if (!type->variantTag) {
        for (size_t i = 0; i < declaration->itemCount; ++i) {
            if (!type->memberOffsets || type->memberOffsets[i] == SIZE_MAX) continue;
            if (declaration->items[i]->flags & RangeFlagMany) { nativeMissing(native,declaration->items[i],"'=' cannot compare @many storage"); continue; }
            for (int side = 0; side < 2; ++side) {
                nativeLoad(native,side,side ? -16 : -8);
                nativeAddOffset(native,side,side,type->memberOffsets[i]);
            }
            nativeEqualField(native,type->memberTypes[i],&fails,&failCount,&failCapacity);
        }
    } else {
        size_t tag = (size_t)type->variantTag;
        nativeEmit(native,armLoadSized(tag,0,9,0,0));
        nativeEmit(native,armLoadSized(tag,0,10,1,0));
        nativeEmit(native,armCmp(9,10));
        NativeJump differ = {.at=nativeEmit(native,armBcond(RangeNE,0)),.base=armBcond(RangeNE,0)};
        NATIVE_PUSH(fails,failCount,failCapacity,differ);
        for (size_t i = 0, k = 0; i < declaration->itemCount; ++i) {
            RangeNode *entry = declaration->items[i];
            if (entry->kind != RangeNodeEnumCase) continue;
            size_t first = k;
            k += entry->itemCount;
            if (!entry->itemCount) continue;
            nativeLoad(native,0,-8);
            size_t other = nativeUnlessCase(native,0,type,entry);
            for (size_t f = first; f < k; ++f) {
                for (int side = 0; side < 2; ++side) {
                    nativeLoad(native,side,side ? -16 : -8);
                    nativeAddOffset(native,side,side,type->memberOffsets[f]);
                    if (type->memberBoxed[f]) { nativeEmit(native,armLdr(side,side,0)); nativeEmit(native,armAddImm(side,side,16)); }
                }
                nativeEqualField(native,type->memberTypes[f],&fails,&failCount,&failCapacity);
            }
            NativeJump jump = {.at=nativeEmit(native,armB(0)),.base=armB(0)};
            NATIVE_PUSH(equal,equalCount,equalCapacity,jump);
            nativeBranchHere(native,other,armBcond(RangeNE,0));
        }
    }
    // Equal tags of a case without fields, or every field equal.
    for (size_t i = 0; i < equalCount; ++i) nativeBranchHere(native,equal[i].at,equal[i].base);
    nativeEmit(native,armMovz(0,1,0));
    size_t end = nativeEmit(native,armB(0));
    for (size_t i = 0; i < failCount; ++i) nativeBranchHere(native,fails[i].at,fails[i].base);
    nativeEmit(native,armMovz(0,0,0));
    nativeBranchHere(native,end,armB(0));
    free(fails); free(equal);
}

/* Emit one release subroutine. */
static void nativeHelperBody(Native *native, size_t index)
{
    NativeHelper helper = native->helpers[index];
    native->helpers[index].offset = native->machine.size;
    native->helpers[index].compiled = 1;
    RangeNode *type = helper.type;
    nativeEmit(native,armPushFrame());
    nativeEmit(native,armAddImm(29,31,0));
    if (helper.block == NativeEqual) nativeEqualBody(native,type);
    else if (helper.block == NativeWriteSigned || helper.block == NativeWriteUnsigned) {
        // Digits are written backwards into a 32-byte buffer on the stack.
        nativeEmit(native,armSubImm(31,31,32));
        nativeEmit(native,armMov(9,0));              /* the magnitude */
        nativeEmit(native,armMov(10,1));             /* the file descriptor */
        nativeEmit(native,armMovz(11,0,0));          /* negative */
        if (helper.block == NativeWriteSigned) {
            nativeEmit(native,armCmpImm(9,0));
            nativeEmit(native,armBcond(RangeGE,3));
            nativeEmit(native,armNeg(9,9));          /* the minimum stays as its unsigned magnitude */
            nativeEmit(native,armMovz(11,1,0));
        }
        nativeEmit(native,armAddImm(3,31,32));       /* cursor, past the buffer */
        nativeEmit(native,armMovz(13,10,0));
        size_t digit = native->machine.size;
        nativeEmit(native,armUdiv(12,9,13));
        nativeEmit(native,armMsub(14,12,13,9));
        nativeEmit(native,armAddImm(14,14,'0'));
        nativeEmit(native,armSubImm(3,3,1));
        nativeEmit(native,armStoreSized(1,14,3,0));
        nativeEmit(native,armMov(9,12));
        nativeEmit(native,armCbnz(9,-(int32_t)((native->machine.size - digit) / 4)));
        nativeEmit(native,armCbz(11,4));
        nativeEmit(native,armMovz(14,'-',0));
        nativeEmit(native,armSubImm(3,3,1));
        nativeEmit(native,armStoreSized(1,14,3,0));
        nativeEmit(native,armAddImm(2,31,32));
        nativeEmit(native,armSub(2,2,3));            /* length */
        nativeEmit(native,armMov(1,3));
        nativeEmit(native,armMov(0,10));
        rangeCallImport(&native->machine,"_write");
    } else if (!helper.block) {
        // A value: release each block it holds, directly or in members.
        nativeEmit(native,armPush(0));
        RangeNode *declaration = type->resolvedDeclaration;
        if (bytesType(type)) {
            // Bytes own a block of their own, [references][count][bytes], or none.
            nativeEmit(native,armLdr(0,0,16));
            nativeCallHelper(native,NULL,NativeReleaseBlock);
        } else if (type->variantTag) for (size_t i = 0, k = 0; i < declaration->itemCount; ++i) {
            // A union releases the fields of its current case.
            RangeNode *entry = declaration->items[i];
            if (entry->kind != RangeNodeEnumCase) continue;
            size_t first = k;
            k += entry->itemCount;
            if (!nativeCaseShares(type,first,entry->itemCount)) continue;
            nativeEmit(native,armLdr(0,31,0));
            size_t skip = nativeUnlessCase(native,0,type,entry);
            for (size_t f = first; f < k; ++f) {
                if (!type->memberBoxed[f] && !nativeSharesSlots(type->memberTypes[f])) continue;
                nativeEmit(native,armLdr(0,31,0));
                nativeAddOffset(native,0,0,type->memberOffsets[f]);
                if (type->memberBoxed[f]) { nativeEmit(native,armLdr(0,0,0)); nativeCallHelper(native,type->memberTypes[f],1); }
                else nativeCallHelper(native,type->memberTypes[f],0);
            }
            nativeBranchHere(native,skip,armBcond(RangeNE,0));
        }
        else for (size_t i = 0; i < declaration->itemCount; ++i) {
            if (!type->memberOffsets || type->memberOffsets[i] == SIZE_MAX) continue;
            RangeNode *member = declaration->items[i];
            if (member->flags & RangeFlagMany) {
                RangeNode *element = manyElement(native->typer,type,member);
                if (!element || nativeKind(native,element,member) == NativeNone) continue;
                nativeEmit(native,armLdr(0,31,0));
                nativeAddOffset(native,0,0,type->memberOffsets[i]);
                nativeEmit(native,armLdr(0,0,0));
                nativeCallHelper(native,element,1);
            } else if (nativeSharesSlots(type->memberTypes[i])) {
                nativeEmit(native,armLdr(0,31,0));
                nativeAddOffset(native,0,0,type->memberOffsets[i]);
                nativeCallHelper(native,type->memberTypes[i],0);
            }
        }
    } else {
        // A block: drop one reference; at zero release its elements and free it.
        size_t empty = nativeEmit(native,armCbz(0,0));
        nativeEmit(native,armLdr(1,0,0));
        nativeEmit(native,armSubImm(1,1,1));
        nativeEmit(native,armStr(1,0,0));
        size_t shared = nativeEmit(native,armCbnz(1,0));
        if (nativeSharesSlots(type)) {
            nativeEmit(native,armPush(0));            /* block: [sp + 32] */
            nativeEmit(native,armLdr(1,0,8));
            nativeEmit(native,armPush(1));            /* count: [sp + 16] */
            nativeEmit(native,armMovz(1,0,0));
            nativeEmit(native,armPush(1));            /* index: [sp] */
            size_t top = native->machine.size;
            nativeEmit(native,armLdr(1,31,0));
            nativeEmit(native,armLdr(2,31,16));
            nativeEmit(native,armCmp(1,2));
            size_t done = nativeEmit(native,armBcond(RangeHS,0));
            nativeEmit(native,armLdr(0,31,32));
            nativeConstant(native,3,type->size);
            nativeEmit(native,armMul(1,1,3));
            nativeEmit(native,armAdd(0,0,1));
            nativeEmit(native,armAddImm(0,0,16));
            nativeCallHelper(native,type,0);
            nativeEmit(native,armLdr(1,31,0));
            nativeEmit(native,armAddImm(1,1,1));
            nativeEmit(native,armStr(1,31,0));
            nativeEmit(native,armB(-(int32_t)((native->machine.size - top) / 4)));
            nativeBranchHere(native,done,armBcond(RangeHS,0));
            nativeEmit(native,armLdr(0,31,32));
        }
        rangeCallImport(&native->machine,"_free");
        nativeBranchHere(native,empty,armCbz(0,0));
        nativeBranchHere(native,shared,armCbnz(1,0));
    }
    nativeEmit(native,armAddImm(31,29,0));
    nativeEmit(native,armPopFrame());
    nativeEmit(native,armRet());
}

static NativeInstance *nativeInstance(Native *native, RangeNode *function, RangeNode *key, RangeNode *self)
{
    for (size_t i = 0; i < native->instanceCount; ++i)
        if (native->instances[i].function == function && native->instances[i].key == key && native->instances[i].self == self)
            return &native->instances[i];
    NativeInstance instance = {.function=function,.key=key,.self=self};
    NATIVE_PUSH(native->instances,native->instanceCount,native->instanceCapacity,instance);
    return &native->instances[native->instanceCount - 1];
}

/* ---- closures ----
 * A function with a function-typed parameter is compiled inline where it is
 * called, never on its own: its parameters are slots of the caller's frame,
 * and each function-typed one holds the closure the call passes. Calling that
 * parameter compiles the closure's body inline there, in the context the
 * closure was written in, with its parameters as slots and the slots of the
 * calls inlined since hidden, so its names mean what they mean where it was
 * written. Nothing is allocated and nothing is called indirectly; a closure
 * reads and changes its caller's values in place. A body's `return` ends its
 * own inlined body only. */

static void nativeBlock(Native *, RangeNode *);
static void nativeReleaseSlots(Native *, size_t);
static void nativeEndTemps(Native *, size_t);
static void nativeReleaseTemps(Native *, size_t);

/* Whether a function takes a closure, and so is compiled only inline. */
static int nativeInlined(const RangeNode *function)
{
    for (size_t i = 0; function && function->kind == RangeNodeFunction && i < function->itemCount; ++i)
        if (function->items[i]->flags & RangeFlagFunction) return 1;
    return 0;
}

/* The closure a function-typed parameter holds, as the running body sees it. */
static NativeClosure *nativeClosureOf(Native *native, RangeNode *parameter)
{
    for (size_t i = native->closureCount; parameter && i-- > 0;) {
        int hidden = 0;
        for (size_t h = 0; h < native->hiddenCount && !hidden; ++h)
            hidden = i >= native->hidden[h].closureFrom && i < native->hidden[h].closureTo;
        if (!hidden && native->closures[i].parameter == parameter) return &native->closures[i];
    }
    return NULL;
}

/* Evaluate an argument where the call is written and keep it at `offset`. */
static int nativeArgument(Native *native, RangeNode *value, RangeNode *type, int kind, int32_t offset)
{
    if (!nativeExpression(native,value)) return 0;
    if (kind == NativeScalar) { nativeStore(native,0,offset); return 1; }
    int moved = nativeTakeTemp(native);
    nativeFrameAddress(native,1,offset);
    nativeCopyValue(native,1,0,type,!moved);
    return 1;
}

/* Compile `body` inline, in `context`, with the slots from `slots` on as its
 * parameters; or, given `value`, the expression a closure yields. Its result
 * is left as a call's: a scalar in x0, or an aggregate temporary's address. */
static RangeNode *nativeRegion(Native *native, RangeNode *at, RangeNode *function, RangeNode *output,
                               NativeContext *context, RangeNode *body, RangeNode *value, size_t slots)
{
    int kind = output ? nativeKind(native,output,at) : NativeNone;
    if (output && kind == NativeNone) return NULL;
    NativeRegion region = {.function=function,.key=context->key,.resultType=output,.resultKind=kind,.outer=native->region,
                           .valueDepth=native->valueDepth + 1,.slots=slots,.temps=native->tempCount};
    // The result starts zeroed, for a body that ends without returning.
    if (kind == NativeAggregate) {
        region.result = nativeReserve(native,output->size ? output->size : 1,output->alignment);
        nativeFrameAddress(native,0,region.result);
        nativeZero(native,0,output->size);
    } else if (kind == NativeScalar) {
        region.result = nativeReserve(native,8,8);
        nativeStore(native,31,region.result);
    }
    region.stack = nativeReserve(native,8,8);
    nativeEmit(native,armAddImm(10,31,0)); /* mov x10, sp */
    nativeStore(native,10,region.stack);
    NativeContext saved = nativeUse(native,*context);
    size_t serial = native->serial;
    native->serial = ++native->serials; /* its own known values */
    native->region = &region;
    native->valueDepth += 1;
    if (value) {
        size_t temps = native->tempCount;
        RangeNode *type = nativeExpression(native,value);
        if (type && kind == NativeScalar) nativeStore(native,0,region.result);
        else if (type && kind == NativeAggregate) {
            int moved = nativeTakeTemp(native);
            nativeFrameAddress(native,1,region.result);
            nativeCopyValue(native,1,0,output,!moved);
        }
        nativeReleaseTemps(native,temps);
    } else nativeBlock(native,body);
    nativeReleaseSlots(native,slots);
    native->slotCount = slots;
    for (size_t i = 0; i < region.returnCount; ++i) nativeBranchHere(native,region.returns[i].at,region.returns[i].base);
    free(region.returns);
    native->valueDepth -= 1;
    native->region = region.outer;
    native->serial = serial;
    nativeUse(native,saved);
    native->resultTemp = -1;
    if (kind == NativeScalar) nativeLoad(native,0,region.result);
    else if (kind == NativeAggregate) { nativeTrackTemp(native,region.result,output); nativeFrameAddress(native,0,region.result); }
    return output;
}

/* `xs.filter(where: { m in m.unread })`: the callee's body inline, its
 * receiver's address and its parameters in slots, each closure bound to its
 * parameter. A function-typed argument that is itself a parameter passes on
 * the closure it holds. */
static RangeNode *nativeInline(Native *native, RangeNode *call, RangeNode *target, RangeNode *key)
{
    RangeNode *callee = call->a, *self = NULL;
    // Inlining ends only if no such function reaches itself: through the
    // bodies it inlines, or, more deeply, through the closures they call.
    size_t depth = 0;
    for (NativeRegion *region = native->region; region; region = region->outer) ++depth;
    for (NativeRegion *region = native->region; region && region->function; region = region->outer)
        if (region->function == target && region->key == key) depth = SIZE_MAX;
    if (depth > 64) {
        nativeMissing(native,call,"'%s' takes a closure, so it is compiled inline where it is called; it cannot reach itself",target->name);
        return NULL;
    }
    int32_t selfSlot = 0;
    if (callee->kind == RangeNodeMemberAccess) {
        int frameSlot = 0;
        self = nativeAddress(native,callee->a,&frameSlot);
        if (!self) return NULL;
        selfSlot = nativeReserve(native,8,8);
        nativeStore(native,0,selfSlot);
    } else if (target->typeName) {
        // A sibling call inside a method acts on the same receiver.
        if (!native->owner) { nativeMissing(native,call,"method '%s' called without a receiver",target->name); return NULL; }
        self = native->self;
        selfSlot = native->selfSlot;
    }
    NativeContext caller = {.owner=native->owner,.self=native->self,.function=native->function,.key=native->key,
                            .selfSlot=native->selfSlot};
    size_t slots = native->slotCount, closures = native->closureCount;
    for (size_t i = 0; i < call->itemCount && i < target->itemCount; ++i) {
        RangeNode *parameter = target->items[i], *value = call->items[i]->a;
        if (parameter->flags & RangeFlagFunction) {
            NativeClosure bound = {.parameter=parameter,.closure=value,.context=&caller,.slots=slots,.closures=closures};
            if (value->kind != RangeNodeClosure) {
                NativeClosure *passed = value->kind == RangeNodeName ? nativeClosureOf(native,found(native->key,value)->resolvedDeclaration) : NULL;
                if (!passed) { nativeMissing(native,value,"no closure is bound to '%s' here",value->name ? value->name : "this argument"); return NULL; }
                bound = *passed;
                bound.parameter = parameter;
            }
            NATIVE_PUSH(native->closures,native->closureCount,native->closureCapacity,bound);
            continue;
        }
        RangeNode *type = found(key,parameter)->type;
        int kind = nativeKind(native,type,parameter);
        if (kind == NativeNone) return NULL;
        // A known argument is known in the body inlined here.
        RangeValue known;
        int argument = nativeKnown(native,value,&known);
        if (argument && nativeKnownSlot(native,parameter,type,&known)) continue;
        int32_t offset = kind == NativeAggregate ? nativeReserve(native,type->size ? type->size : 1,type->alignment) : nativeReserve(native,8,8);
        if (!nativeArgument(native,value,type,kind,offset)) return NULL;
        NativeSlot slot = {.declaration=parameter,.offset=offset,.type=type};
        NATIVE_PUSH(native->slots,native->slotCount,native->slotCapacity,slot);
        if (argument) nativeKnownStorage(native,parameter,&known);
    }
    NativeContext context = {.owner=self ? self->resolvedDeclaration : NULL,.self=self,.function=target,.key=key,
                             .selfSlot=selfSlot};
    RangeNode *output = found(key,target)->type;
    RangeNode *result = nativeRegion(native,call,target,output,&context,target->a,NULL,slots);
    native->closureCount = closures;
    return result;
}

/* `where(element)`: the closure the parameter holds, inline, where it was
 * written. Its arguments are evaluated here first. */
static RangeNode *nativeCallClosure(Native *native, RangeNode *call, RangeNode *parameter)
{
    NativeClosure *bound = nativeClosureOf(native,parameter);
    if (!bound) { nativeMissing(native,call,"no closure is bound to '%s' here",parameter->name); return NULL; }
    NativeClosure closure = *bound;
    RangeNode *literal = closure.closure;
    size_t count = literal->itemCount;
    int32_t offsets[count ? count : 1];
    RangeNode *types[count ? count : 1];
    RangeValue known[count ? count : 1];
    for (size_t i = 0; i < count && i < call->itemCount; ++i) {
        types[i] = found(closure.context->key,literal->items[i])->type;
        int kind = nativeKind(native,types[i],literal->items[i]);
        if (kind == NativeNone) return NULL;
        // A known argument is known in the closure's body.
        offsets[i] = 0;
        if (!nativeKnown(native,call->items[i]->a,&known[i])) known[i].kind = ValueNone;
        else if (nativeBuilds(native,&known[i],types[i],literal->items[i]) == 1) continue;
        offsets[i] = kind == NativeAggregate ? nativeReserve(native,types[i]->size ? types[i]->size : 1,types[i]->alignment) : nativeReserve(native,8,8);
        if (!nativeArgument(native,call->items[i]->a,types[i],kind,offsets[i])) return NULL;
    }
    NativeHidden hidden = {.slotFrom=closure.slots,.slotTo=native->slotCount,.closureFrom=closure.closures,.closureTo=native->closureCount};
    NATIVE_PUSH(native->hidden,native->hiddenCount,native->hiddenCapacity,hidden);
    size_t slots = native->slotCount;
    for (size_t i = 0; i < count; ++i) {
        if (!offsets[i]) { nativeKnownSlot(native,literal->items[i],types[i],&known[i]); continue; }
        NativeSlot slot = {.declaration=literal->items[i],.offset=offsets[i],.type=types[i]};
        NATIVE_PUSH(native->slots,native->slotCount,native->slotCapacity,slot);
        nativeKnownStorage(native,literal->items[i],&known[i]);
    }
    RangeNode *type = found(closure.context->key,literal)->type;
    RangeNode *output = type ? type->a : NULL;
    RangeNode *result = nativeRegion(native,call,NULL,output,closure.context,literal->a,
                                     closureResult(native->typer,closure.context->key,literal),slots);
    native->hiddenCount -= 1;
    return result;
}

static void nativeWriteMessage(Native *, int, const char *, RangeNode *);

/* The builtin function print writes its message to standard output;
 * warning writes it, located at the call and marked a warning, to standard
 * error and continues; diagnostic writes it, located at the call, to
 * standard error and exits 134, as a law violation does. The message is
 * streamed as it is written, part by part. */
static void nativeEffect(Native *native, RangeNode *call, RangeNode *function)
{
    int print = builtinFunction(function,"print"), warning = builtinFunction(function,"warning");
    char location[512] = "";
    RangeNode *site = call->a ? call->a : call;
    if (!print) snprintf(location,sizeof(location),"%s:%d:%d: %s",site->path,site->line,site->column,warning ? "warning: " : "");
    nativeWriteMessage(native,print ? 1 : 2,rangeArenaIntern(native->report->arena,location,strlen(location)),call->items[0]->a);
    if (!print && !warning) {
        nativeEmit(native,armMovz(0,134,0));
        rangeCallImport(&native->machine,"_exit");
    }
}

static RangeNode *nativeCall(Native *native, RangeNode *call)
{
    RangeNode *callee = call->a;
    RangeFacts *facts = callee ? found(native->key,callee) : NULL;
    RangeNode *target = facts ? facts->resolvedDeclaration : NULL, *key = facts ? facts->specialization : NULL;
    int form = callForm(target);
    if (form == CallClosure) return nativeCallClosure(native,call,target);
    if (form == CallConstruct) return nativeConstruct(native,call,found(native->key,call)->type,call->items,call->itemCount,0);
    if (form == CallCase) return nativeVariant(native,call,found(native->key,call)->type,target,call->items,call->itemCount,0);
    if (form != CallFunction) { nativeMissing(native,call,"native call target is not implemented"); return NULL; }
    if (nativeInlined(target)) return nativeInline(native,call,target,key);
    if (call->itemCount == 1 && (builtinFunction(target,"print") || builtinFunction(target,"warning")
                                 || builtinFunction(target,"diagnostic"))) {
        nativeEffect(native,call,target);
        return NULL;
    }
    RangeNode *self = NULL;
    int hasSelf = 0;
    if (callee->kind == RangeNodeMemberAccess) {
        int frameSlot = 0;
        self = nativeAddress(native,callee->a,&frameSlot);
        if (!self) return NULL;
        nativeEmit(native,armPush(0));
        hasSelf = 1;
    } else if (target->typeName) {
        // A sibling call inside a method acts on the same receiver.
        if (!native->owner) { nativeMissing(native,call,"method '%s' called without a receiver",target->name); return NULL; }
        nativeLoad(native,0,native->selfSlot);
        nativeEmit(native,armPush(0));
        self = native->self;
        hasSelf = 1;
    }
    if ((target->flags & RangeFlagBuiltin) && hasSelf && bytesType(self) && same(target->name,"byte") && call->itemCount == 1) {
        // One byte, zero-extended; the index is checked against the count.
        if (!nativeExpression(native,call->items[0]->a)) return NULL;
        nativeEmit(native,armLdr(1,31,0));
        nativeEmit(native,armLdr(2,1,8));
        nativeEmit(native,armCmp(0,2));
        nativeTrap(native,armBcond(RangeHS,0),call,"byte index is outside the bytes");
        nativeEmit(native,armLdr(1,1,0));
        nativeEmit(native,armAdd(1,1,0));
        nativeEmit(native,armLoadSized(1,0,0,1,0));
        nativeEmit(native,armAddImm(31,31,16)); /* drop the receiver */
        native->resultTemp = -1;
        return found(key,target)->type;
    }
    if (target->flags & (RangeFlagBuiltin | RangeFlagExtern)) {
        if (!(target->flags & RangeFlagBuiltin) || !slotPrimitive(target) || !hasSelf) {
            nativeMissing(native,call,"native calls to builtin function '%s' are not implemented",target->name);
            return NULL;
        }
        return nativeSlotCall(native,call,target,self);
    }
    size_t registers = call->itemCount + (size_t)hasSelf;
    if (registers > 8) { nativeMissing(native,call,"calls with more than 8 arguments are not implemented"); return NULL; }
    for (size_t i = 0; i < call->itemCount; ++i) {
        if (!nativeExpression(native,call->items[i]->a)) return NULL;
        nativeEmit(native,armPush(0));
    }
    RangeNode *output = found(key,target)->type;
    int outputKind = output ? nativeKind(native,output,call) : NativeNone;
    int32_t result = 0;
    if (outputKind == NativeAggregate) result = nativeReserve(native,output->size ? output->size : 1,output->alignment);
    for (size_t i = registers; i-- > 0;) nativeEmit(native,armPop((int)i));
    if (result) nativeFrameAddress(native,8,result);
    nativeCallFunction(native,target,key,self);
    native->resultTemp = -1;
    if (result) { nativeTrackTemp(native,result,output); nativeFrameAddress(native,0,result); }
    return output;
}

/* The address of what an expression reads, before any narrowing, in x0, and
 * its type. A scalar local's address is its frame slot (*frameSlot = 1: it
 * holds a full register). Other values that are not places are materialized
 * into a temporary. */
static RangeNode *nativePlainAddress(Native *native, RangeNode *expr, int *frameSlot)
{
    *frameSlot = 0;
    // A form that runs as what typing lowered it to is no place: it is materialized below.
    RangeFacts *facts = found(native->key,expr);
    RangeNodeKind kind = facts->lowered ? facts->lowered->kind : expr->kind;
    if (kind == RangeNodeName) {
        RangeNode *declaration = facts->resolvedDeclaration;
        if (declaration && native->function && declaration == native->function->receiver && native->owner) {
            // The receiver, whose address the method holds.
            nativeLoad(native,0,native->selfSlot);
            return native->self;
        }
        NativeSlot *slot = nativeSlotOf(native,declaration);
        if (slot && !slot->offset) {
            // A known value, filled in where its address is needed.
            nativeKnownValue(native,slot->known,slot->type,expr);
            if (!slot->type->scalarBits) return slot->type;
            int32_t temporary = nativeReserve(native,8,8);
            nativeStore(native,0,temporary);
            nativeFrameAddress(native,0,temporary);
            *frameSlot = 1;
            return slot->type;
        }
        if (slot) {
            nativeFrameAddress(native,0,slot->offset);
            *frameSlot = slot->type && slot->type->scalarBits && !slot->packed;
            return slot->type;
        }
        size_t index = native->owner && native->owner->kind == RangeNodeConstruct ? nativeMemberIndex(native->owner,declaration) : SIZE_MAX;
        if (index != SIZE_MAX && native->self->memberOffsets && native->self->memberOffsets[index] != SIZE_MAX) {
            nativeLoad(native,0,native->selfSlot);
            nativeAddOffset(native,0,0,native->self->memberOffsets[index]);
            return native->self->memberTypes[index];
        }
        if (declaration && (declaration->flags & RangeFlagMany)) {
            nativeMissing(native,expr,"'%s' holds @many storage, not a value",expr->name);
            return NULL;
        }
        nativeMissing(native,expr,"native access to '%s' is not implemented",expr->name);
        return NULL;
    }
    RangeNode *member = facts->resolvedDeclaration;
    if (kind == RangeNodeMemberAccess && !(member && member->kind == RangeNodeEnumCase)) {
        int innerSlot = 0;
        RangeNode *receiver = nativeAddress(native,expr->a,&innerSlot);
        if (!receiver) return NULL;
        if (bytesType(receiver) && member && builtinMember(member) && same(member->name,"count")) {
            // The byte count is the bytes primitive's second word.
            nativeEmit(native,armAddImm(0,0,8));
            return facts->type;
        }
        size_t index = nativeMemberIndex(receiver->resolvedDeclaration,member);
        if (index == SIZE_MAX || !receiver->memberOffsets || receiver->memberOffsets[index] == SIZE_MAX) {
            nativeMissing(native,expr,"native access to member '%s' is not implemented",expr->name);
            return NULL;
        }
        nativeAddOffset(native,0,0,receiver->memberOffsets[index]);
        return receiver->memberTypes[index];
    }
    RangeNode *type = nativeExpression(native,expr);
    if (!type || nativeKind(native,type,expr) != NativeScalar) return type;
    int32_t temporary = nativeReserve(native,8,8);
    nativeStore(native,0,temporary);
    nativeFrameAddress(native,0,temporary);
    *frameSlot = 1;
    return type;
}

/* The address of an expression in x0, and its type: a narrowed read's is its
 * payload's, the field of the present case it goes through, read with no
 * check. */
static RangeNode *nativeAddress(Native *native, RangeNode *expr, int *frameSlot)
{
    RangeNode *optional = nativePlainAddress(native,expr,frameSlot);
    RangeNode *present = found(native->key,expr)->narrowed;
    if (!optional || !present) return optional;
    *frameSlot = 0;
    size_t field = nativeFirstField(optional->resolvedDeclaration,present);
    if (!optional->memberOffsets || optional->memberOffsets[field] == SIZE_MAX) {
        nativeMissing(native,expr,"native access to the narrowed payload is not implemented");
        return NULL;
    }
    nativeAddOffset(native,0,0,optional->memberOffsets[field]);
    if (optional->memberBoxed && optional->memberBoxed[field]) {
        // The field holds its block; the value starts after the block's header.
        nativeEmit(native,armLdr(0,0,0));
        nativeEmit(native,armAddImm(0,0,16));
    }
    return optional->memberTypes[field];
}

/* Load the value at an address produced by nativeAddress: scalars into x0. */
static RangeNode *nativeLoadPlace(Native *native, RangeNode *type, int frameSlot, RangeNode *at)
{
    int kind = nativeKind(native,type,at);
    if (kind == NativeScalar) {
        if (frameSlot) nativeEmit(native,armLdr(0,0,0));
        else nativeLoadScalar(native,0,0,0,type);
    }
    return kind == NativeNone ? NULL : type;
}

static RangeNode *nativeExpressionValue(Native *, RangeNode *);

/* The value in x0, of `type`, promoted to the optional `optional`: the
 * present case holding it, in a temporary. */
static RangeNode *nativePromote(Native *native, RangeNode *at, RangeNode *optional)
{
    RangeNode *present = NULL;
    if (!optionalWrapped(native->typer,optional,&present) || nativeKind(native,optional,at) != NativeAggregate) return NULL;
    int moved = nativeTakeTemp(native);
    nativeEmit(native,armPush(0));
    int32_t destination = nativeReserve(native,optional->size,optional->alignment);
    nativeFrameAddress(native,0,destination);
    nativeZero(native,0,optional->size);
    nativeConstant(native,1,(uint64_t)present->integer);
    nativeEmit(native,armStoreSized((size_t)optional->variantTag,1,0,0));
    nativeEmit(native,armPop(0));
    nativeStoreField(native,at,optional,nativeFirstField(optional->resolvedDeclaration,present),destination,moved);
    nativeTrackTemp(native,destination,optional);
    nativeFrameAddress(native,0,destination);
    return optional;
}

/* A value known before run is emitted as it is, unless it holds blocks
 * and a place holds it already. Otherwise what typing lowered an expression
 * to, if anything, is compiled in its place, and a promoted value becomes
 * the present case holding it. Only a call, construction, switch
 * expression, slot read, known value holding blocks, or promotion produces
 * a temporary; any other expression reports none, whatever its operands
 * left behind. */
static RangeNode *nativeExpression(Native *native, RangeNode *expr)
{
    RangeFacts *facts = expr ? found(native->key,expr) : NULL;
    RangeNode *runs = facts && facts->lowered ? facts->lowered : expr, *known = facts ? facts->promoted ? facts->promoted : facts->type : NULL;
    RangeValue value;
    int builds = nativeKnown(native,expr,&value) ? nativeBuilds(native,&value,known,expr) : 0;
    if (builds == 1 || (builds == 2 && runs->kind != RangeNodeName && runs->kind != RangeNodeMemberAccess)) {
        nativeKnownValue(native,&value,known,expr);
        return known;
    }
    RangeNode *type = nativeExpressionValue(native,runs);
    RangeNode *resolved = runs ? found(native->key,runs)->resolvedDeclaration : NULL;
    int construction = runs && (runs->kind == RangeNodeCall || runs->kind == RangeNodeSwitch);
    if (!runs || (!construction && !(resolved && resolved->kind == RangeNodeEnumCase))) native->resultTemp = -1;
    return type && facts->promoted ? nativePromote(native,expr,facts->promoted) : type;
}

/* `a + b` on bytes (x0, x1 = their addresses): a new block holding a's bytes
 * then b's, [references = 1][count][bytes], in a temporary that owns it. */
static RangeNode *nativeJoin(Native *native, RangeNode *at, RangeNode *type)
{
    nativeEmit(native,armPush(0));            /* left: [sp + 16] */
    nativeEmit(native,armPush(1));            /* right: [sp] */
    nativeEmit(native,armLdr(2,0,8));
    nativeEmit(native,armLdr(3,1,8));
    nativeEmit(native,armAdds(0,2,3));
    nativeTrap(native,armBcond(RangeHS,0),at,"joined bytes exceed addressable memory");
    nativeEmit(native,armAddImm(0,0,16));
    rangeCallImport(&native->machine,"_malloc");
    nativeTrap(native,armCbz(0,0),at,"could not allocate storage for joined bytes");
    nativeEmit(native,armPush(0));            /* block: [sp]; right: [sp + 16]; left: [sp + 32] */
    nativeEmit(native,armMovz(9,1,0));
    nativeEmit(native,armStr(9,0,0));         /* one reference */
    nativeEmit(native,armLdr(1,31,32));
    nativeEmit(native,armLdr(2,1,8));
    nativeEmit(native,armLdr(3,31,16));
    nativeEmit(native,armLdr(3,3,8));
    nativeEmit(native,armAdd(9,2,3));
    nativeEmit(native,armStr(9,0,8));         /* the count */
    nativeEmit(native,armAddImm(0,0,16));
    nativeEmit(native,armLdr(1,1,0));
    rangeCallImport(&native->machine,"_memcpy");
    nativeEmit(native,armLdr(0,31,0));
    nativeEmit(native,armAddImm(0,0,16));
    nativeEmit(native,armLdr(1,31,32));
    nativeEmit(native,armLdr(2,1,8));
    nativeEmit(native,armAdd(0,0,2));
    nativeEmit(native,armLdr(1,31,16));
    nativeEmit(native,armLdr(2,1,8));
    nativeEmit(native,armLdr(1,1,0));
    rangeCallImport(&native->machine,"_memcpy");
    nativeEmit(native,armPop(0));             /* the block */
    nativeEmit(native,armAddImm(31,31,32));
    int32_t value = nativeReserve(native,type->size,type->alignment);
    nativeFrameAddress(native,1,value);
    nativeEmit(native,armAddImm(2,0,16));
    nativeEmit(native,armStr(2,1,0));
    nativeEmit(native,armLdr(2,0,8));
    nativeEmit(native,armStr(2,1,8));
    nativeEmit(native,armStr(0,1,16));
    nativeTrackTemp(native,value,type);
    nativeFrameAddress(native,0,value);
    return type;
}

/* A leaf, compiled as written in either mode: a boolean or string literal,
 * but a string with interpolated values, which is built at run; the name of
 * a value generic, the constant of the specialization the body was typed
 * in, or of one it is typed within, its receiver's; or a case of a scalar
 * enum named without payload. Its value is what the evaluator finds. */
static int nativeLeaf(Native *native, RangeNode *expr, RangeValue *value)
{
    RangeFacts *facts = found(native->key,expr);
    RangeNode *declaration = facts->resolvedDeclaration, *type = facts->type;
    int leaf = expr->kind == RangeNodeBool
        || (expr->kind == RangeNodeString && expr->itemCount == 1 && (expr->items[0]->flags & RangeFlagLiteral))
        || (expr->kind == RangeNodeName && declaration && declaration->kind == RangeNodeLet && genericSlot(native->key,declaration))
        || (declaration && declaration->kind == RangeNodeEnumCase && expr->kind != RangeNodeCall && type
            && !macroTimeType(native->typer,type) && layoutOf(native->typer,type,expr) && type->scalarBits);
    EvalFrame root;
    Eval eval = nativeEval(native,&root);
    return leaf && evalPlain(&eval,&root,expr,value) == EvalNormal && nativeBuilds(native,value,type,expr) == 1;
}

static RangeNode *nativeSwitch(Native *, RangeNode *);
static RangeNode *nativeCaseTest(Native *, RangeNode *);

static RangeNode *nativeExpressionValue(Native *native, RangeNode *expr)
{
    if (!expr) return NULL;
    RangeFacts *facts = found(native->key,expr);
    RangeNode *type = facts->type;
    RangeValue value;
    if (nativeLeaf(native,expr,&value)) { nativeKnownValue(native,&value,type,expr); return type; }
    if (facts->resolvedDeclaration && facts->resolvedDeclaration->kind == RangeNodeEnumCase
        && (expr->kind == RangeNodeCase || expr->kind == RangeNodeMemberAccess))
        return nativeVariant(native,expr,type,facts->resolvedDeclaration,NULL,0,0);
    switch (expr->kind) {
    case RangeNodeInteger:
        // An operand's bits, as written: `-128` negates 128, which Int<bits: 8> holds only negated.
        if (nativeKind(native,type,expr) != NativeScalar) return NULL;
        nativeConstant(native,0,(uint64_t)expr->integer);
        return type;
    case RangeNodeBool:
        (void)nativeKind(native,type,expr); /* a type without native values is reported */
        return NULL;
    case RangeNodeString:
        // A literal is its UTF-8 bytes in __text, in the layout the bytes
        // primitive declares.
        if (expr->itemCount != 1 || !(expr->items[0]->flags & RangeFlagLiteral))
            nativeMissing(native,expr,"runtime string interpolation is not implemented");
        else if (nativeKind(native,type,expr) != NativeAggregate || !bytesType(type))
            nativeMissing(native,expr,"string literals need a construct with the bytes primitive");
        return NULL;
    case RangeNodeName: case RangeNodeMemberAccess: {
        if (expr->kind == RangeNodeName && facts->resolvedDeclaration && genericSlot(native->key,facts->resolvedDeclaration)) {
            nativeMissing(native,expr,"value generic '%s' needs an integer or boolean literal natively",expr->name);
            return NULL;
        }
        int frameSlot = 0;
        RangeNode *placed = nativeAddress(native,expr,&frameSlot);
        return placed ? nativeLoadPlace(native,placed,frameSlot,expr) : NULL;
    }
    case RangeNodeUnary: {
        RangeNode *operand = nativeExpression(native,expr->a);
        if (!operand) return NULL;
        if (nativeKind(native,operand,expr) != NativeScalar) {
            char name[160]; describeType(name,sizeof(name),operand);
            nativeMissing(native,expr,"no C primitive implements builtin prefix '%s' on %s",expr->name,name);
            return NULL;
        }
        // The builtin `!` of the condition type: tags 0 and 1 swap.
        if (same(expr->name,"!")) { nativeEmit(native,armCmpImm(0,0)); nativeEmit(native,armCset(0,RangeEQ)); return type; }
        if (nativeKind(native,type,expr) != NativeScalar) return NULL;
        char name[160]; describeType(name,sizeof(name),type);
        if (type->scalarBits == 64 && type->scalarSigned) {
            nativeEmit(native,armNegs(0,0));
            nativeTrap(native,armBcond(RangeVS,0),expr,"result of '-' does not fit %s",name);
        } else if (type->scalarBits == 64) {
            // Only zero negates to an unsigned value.
            nativeTrap(native,armCbnz(0,0),expr,"result of '-' does not fit %s",name);
        } else {
            nativeEmit(native,armNeg(0,0));
            nativeFits(native,type,expr,"-");
        }
        return type;
    }
    case RangeNodeBinary: {
        const char *op = expr->name;
        if (operatorForm(expr,facts->resolvedDeclaration,0) == OperatorShortCircuit) {
            nativeExpression(native,expr->a);
            uint32_t base = same(op,"&") ? armCbz(0,0) : armCbnz(0,0);
            size_t skip = nativeEmit(native,base);
            nativeExpression(native,expr->b);
            rangePatch(&native->machine,skip,base | (uint32_t)(((native->machine.size - skip) / 4) & 0x7FFFF) << 5);
            return type;
        }
        RangeNode *operand = nativeExpression(native,expr->a);
        nativeEmit(native,armPush(0));
        nativeExpression(native,expr->b);
        nativeEmit(native,armMov(1,0));
        nativeEmit(native,armPop(0));
        if (!operand) return NULL;
        if (nativeKind(native,operand,expr) == NativeNone) return NULL;
        int form = operatorForm(expr,facts->resolvedDeclaration,bytesType(operand));
        if (form == OperatorEquality) {
            nativeEquals(native,operand);
            if (same(op,"!=")) { nativeEmit(native,armCmpImm(0,0)); nativeEmit(native,armCset(0,RangeEQ)); }
            return type;
        }
        if (form == OperatorJoin) return nativeJoin(native,expr,operand);
        if (nativeKind(native,operand,expr) != NativeScalar) {
            char name[160]; describeType(name,sizeof(name),operand);
            nativeMissing(native,expr,"no C primitive implements builtin operator '%s' on %s",op,name);
            return NULL;
        }
        int cond = nativeRelation(op,operand->scalarSigned);
        if (cond >= 0) { nativeEmit(native,armCmp(0,1)); nativeEmit(native,armCset(0,cond)); }
        else nativeArithmetic(native,expr,operand);
        return type;
    }
    case RangeNodeCall:
        return nativeCall(native,expr);
    case RangeNodeSwitch:
        return nativeSwitch(native,expr);
    case RangeNodeCaseTest:
        return nativeCaseTest(native,expr);
    default:
        nativeMissing(native,expr,"native %s expressions are not implemented",rangeNodeKindName(expr->kind));
        return NULL;
    }
}

/* ---- statements ---- */

static void nativeStatement(Native *, RangeNode *);

static void nativeReleaseSlots(Native *, size_t);

/* A block's locals end with it. */
static void nativeBlock(Native *native, RangeNode *block)
{
    size_t scope = native->slotCount;
    for (size_t i = 0; block && i < block->itemCount; ++i) nativeStatement(native,block->items[i]);
    nativeReleaseSlots(native,scope);
    native->slotCount = scope;
}

static void nativeBranchHere(Native *native, size_t at, uint32_t base)
{
    int32_t words = (int32_t)((native->machine.size - at) / 4);
    uint32_t patched = (base & 0xFC000000u) == 0x14000000u ? armB(words) : base | ((uint32_t)words & 0x7FFFFu) << 5;
    rangePatch(&native->machine,at,patched);
}

/* x0 holds a value of `type`: a scalar, or an aggregate's address. Store it
 * into the place at the address in x1. */
static void nativeStorePlace(Native *native, RangeNode *type, int frameSlot, int retain)
{
    if (type->scalarBits) {
        if (frameSlot) nativeEmit(native,armStr(0,1,0));
        else nativeStoreScalar(native,0,1,0,type);
    } else nativeCopyValue(native,1,0,type,retain);
}

/* write(fd, text) for bytes placed in __text. */
static void nativeWriteText(Native *native, int fd, const char *bytes, size_t length)
{
    if (!length) return;
    nativeEmit(native,armMovz(0,(uint16_t)fd,0));
    NativeText text = {.at=nativeEmit(native,armAdr(1,0)),.bytes=bytes,.length=length};
    NATIVE_PUSH(native->texts,native->textCount,native->textCapacity,text);
    nativeConstant(native,2,length);
    rangeCallImport(&native->machine,"_write");
}

/* Write the text known so far, if any. */
static void nativeFlushText(Native *native, int fd, const char *text, size_t *length)
{
    if (*length) nativeWriteText(native,fd,rangeArenaIntern(native->report->arena,text,*length),*length);
    *length = 0;
}

/* Stream a message to fd, after `prefix` and before a newline: literal
 * parts as bytes, interpolated integers in decimal, enum values without
 * payloads (booleans among them) as their case names, strings as their
 * bytes. What is known before run, the literal parts and the values known
 * with them, is written as the evaluator writes it, each run of it at once. */
static void nativeWriteMessage(Native *native, int fd, const char *prefix, RangeNode *message)
{
    int literal = message->kind == RangeNodeString;
    size_t parts = literal ? message->itemCount : 1, length = 0, capacity = 64;
    char *known = malloc(capacity);
    if (!known) abort();
    EvalFrame root;
    Eval eval = nativeEval(native,&root);
    for (size_t i = 0; i < parts + 2; ++i) {
        // The prefix, the parts, then the newline.
        RangeNode *part = literal && i && i <= parts ? message->items[i - 1] : NULL, *value = part ? part->a : message;
        const char *piece = !i ? prefix : i > parts ? "\n" : part && (part->flags & RangeFlagLiteral) ? part->name : NULL;
        size_t size = piece ? (part ? (size_t)part->integer : strlen(piece)) : 0;
        RangeValue written;
        if (!piece && nativeKnown(native,value,&written) && evalWrite(&eval,written,value,&piece,&size) != EvalNormal) piece = NULL;
        if (piece && native->asWritten) { nativeWriteText(native,fd,piece,size); continue; }
        if (piece) {
            while (length + size > capacity) if (!(known = realloc(known,capacity *= 2))) abort();
            memcpy(known + length,piece,size);
            length += size;
            continue;
        }
        nativeFlushText(native,fd,known,&length);
        RangeNode *type = nativeExpression(native,value);
        if (!type) continue;
        if (isEnum(type) && type->scalarBits) {
            // A case without payloads is written as its name.
            RangeNode *declaration = type->resolvedDeclaration;
            nativeEmit(native,armMov(9,0));
            NativeJump *done = NULL;
            size_t doneCount = 0, doneCapacity = 0;
            for (size_t c = 0; c < declaration->itemCount; ++c) {
                RangeNode *entry = declaration->items[c];
                if (entry->kind != RangeNodeEnumCase) continue;
                nativeConstant(native,10,(uint64_t)entry->integer);
                nativeEmit(native,armCmp(9,10));
                size_t skip = nativeEmit(native,armBcond(RangeNE,0));
                nativeWriteText(native,fd,entry->name,strlen(entry->name));
                NativeJump jump = {.at=nativeEmit(native,armB(0)),.base=armB(0)};
                NATIVE_PUSH(done,doneCount,doneCapacity,jump);
                nativeBranchHere(native,skip,armBcond(RangeNE,0));
            }
            for (size_t c = 0; c < doneCount; ++c) nativeBranchHere(native,done[c].at,done[c].base);
            free(done);
        } else if (type->scalarBits) {
            nativeEmit(native,armMovz(1,(uint16_t)fd,0));
            nativeCallHelper(native,NULL,type->scalarSigned ? NativeWriteSigned : NativeWriteUnsigned);
        } else if (bytesType(type)) {
            nativeEmit(native,armLdr(2,0,8));
            nativeEmit(native,armLdr(1,0,0));
            nativeEmit(native,armMovz(0,(uint16_t)fd,0));
            rangeCallImport(&native->machine,"_write");
        } else {
            char name[160]; describeType(name,sizeof(name),type);
            nativeMissing(native,value,"writing %s is not implemented",name);
        }
    }
    nativeFlushText(native,fd,known,&length);
    free(known);
}

static void nativeStatementBody(Native *, RangeNode *);
static RangeNode *nativeSwitch(Native *, RangeNode *);

/* Temporaries a statement creates end with it, unless moved into place. */
static void nativeStatement(Native *native, RangeNode *node)
{
    size_t temps = native->tempCount;
    nativeStatementBody(native,node);
    nativeReleaseTemps(native,temps);
}

/* Enter a loop; leaving it lands its breaks here. Inside a switch
 * expression's arm the stack may hold operands; the loop keeps sp then. */
static void nativeEnter(Native *native, int loop, size_t top)
{
    NativeTarget target = {.loop=loop,.top=top,.slots=native->slotCount,.temps=native->tempCount,.valueDepth=native->valueDepth};
    if (native->valueDepth) {
        target.stack = nativeReserve(native,8,8);
        nativeEmit(native,armAddImm(10,31,0)); /* mov x10, sp */
        nativeStore(native,10,target.stack);
    }
    if (target.stack) target.top = native->machine.size;
    NATIVE_PUSH(native->targets,native->targetCount,native->targetCapacity,target);
}

/* `break` or `continue` inside a switch expression's arm leaves operands the
 * enclosing expression pushed: sp returns to its value at the loop, the
 * frame's base outside any switch expression, patched once the frame is known. */
static void nativeResetStack(Native *native, NativeTarget *target)
{
    if (target->stack) {
        nativeLoad(native,10,target->stack);
        nativeEmit(native,armAddImm(31,10,0)); /* mov sp, x10 */
        return;
    }
    size_t at = nativeEmit(native,armAddImm(31,29,0));
    nativeEmit(native,armSubImm(31,31,0));
    NATIVE_PUSH(native->stackResets,native->stackResetCount,native->stackResetCapacity,at);
}

static void nativeLeave(Native *native)
{
    NativeTarget *target = &native->targets[--native->targetCount];
    for (size_t i = 0; i < target->breakCount; ++i) nativeBranchHere(native,target->breaks[i].at,target->breaks[i].base);
    free(target->breaks);
}

/* End the live temporaries from `from` on a path that leaves their statements
 * early; the statements still end them on their ordinary paths. */
static void nativeEndTemps(Native *native, size_t from)
{
    for (size_t i = native->tempCount; i-- > from;) {
        if (native->temps[i].consumed) continue;
        nativeFrameAddress(native,0,native->temps[i].offset);
        nativeRelease(native,native->temps[i].type);
    }
}

/* A condition's temporaries end before its branch; x0 keeps the result. */
static void nativeCondition(Native *native, RangeNode *condition)
{
    size_t temps = native->tempCount;
    nativeExpression(native,condition);
    if (native->tempCount == temps) return;
    nativeEmit(native,armPush(0));
    nativeReleaseTemps(native,temps);
    nativeEmit(native,armPop(0));
}

static void nativeStatementBody(Native *native, RangeNode *node)
{
    if (!node) return;
    switch (node->kind) {
    case RangeNodeBlock: nativeBlock(native,node); break;
    case RangeNodeLet: case RangeNodeState: {
        RangeNode *type = found(native->key,node)->type;
        int kind = nativeKind(native,type,node);
        if (kind == NativeNone) break;
        // A let known before run names its value, or, holding blocks, is
        // built where it is declared and read in place. A bare name that
        // resolved to a value is a copy; to a type, a requirement.
        EvalFrame root;
        Eval eval = nativeEval(native,&root);
        RangeValue known;
        int builds = node->kind == RangeNodeLet && !native->asWritten && evalDeclared(&eval,&root,node,&known) == EvalNormal
            ? nativeBuilds(native,&known,type,node) : 0;
        if (builds == 1 && nativeKnownSlot(native,node,type,&known)) break;
        RangeNode *value = declarationValue(native->key,node);
        int construction = value == node;
        if (kind == NativeScalar) {
            if (construction) nativeConstruct(native,node,type,node->items,node->itemCount,0);
            else if (value) nativeExpression(native,value);
            else { nativeMissing(native,node,"'%s' has no initial value",node->name); break; } /* the type checker rejects it */
            nativeStore(native,0,nativeNewSlot(native,node,type,kind));
            break;
        }
        if (construction) {
            // Arguments are evaluated before the name exists, so construct in place.
            int32_t offset = nativeReserve(native,type->size ? type->size : 1,type->alignment);
            nativeConstruct(native,node,type,node->items,node->itemCount,offset);
            NativeSlot slot = {.declaration=node,.offset=offset,.type=type};
            NATIVE_PUSH(native->slots,native->slotCount,native->slotCapacity,slot);
        } else {
            int32_t offset = nativeNewSlot(native,node,type,kind);
            if (!value) nativeMissing(native,node,"'%s' has no initial value",node->name); /* the type checker rejects it */
            else if (nativeExpression(native,value)) {
                int moved = nativeTakeTemp(native);
                nativeFrameAddress(native,1,offset);
                nativeCopyValue(native,1,0,type,!moved);
            }
        }
        if (builds == 2) nativeKnownStorage(native,node,&known);
        break;
    }
    case RangeNodeAssign: {
        RangeNode *type = nativeExpression(native,node->b);
        if (!type) break;
        int moved = nativeTakeTemp(native);
        nativeEmit(native,armPush(0));
        int frameSlot = 0;
        RangeNode *placed = nativeAddress(native,node->a,&frameSlot);
        if (!placed || nativeKind(native,placed,node) == NativeNone) { nativeEmit(native,armAddImm(31,31,16)); break; }
        if (!placed->scalarBits && nativeSharesSlots(placed)) {
            // Retain the new value first, then release the one it replaces.
            nativeEmit(native,armPush(0));          /* place: [sp]; value: [sp + 16] */
            if (!moved) { nativeEmit(native,armLdr(1,31,16)); nativeRetain(native,1,0,placed); }
            nativeEmit(native,armLdr(0,31,0));
            nativeRelease(native,placed);
            nativeEmit(native,armPop(1));
            nativeEmit(native,armPop(0));
            nativeCopy(native,1,0,placed->size);
            break;
        }
        nativeEmit(native,armMov(1,0));
        nativeEmit(native,armPop(0));
        nativeStorePlace(native,placed,frameSlot,!moved);
        break;
    }
    case RangeNodeWhile: {
        // Without a condition, or with one known to hold, the loop ends only
        // at break; with one known not to, it never runs.
        RangeValue known;
        int tested = node->a && !nativeKnown(native,node->a,&known);
        if (node->a && !tested && !evalTruth(known)) break;
        size_t top = native->machine.size, exit = 0;
        nativeEnter(native,1,top);
        if (tested) {
            nativeCondition(native,node->a);
            exit = nativeEmit(native,armCbz(0,0));
        }
        nativeStatement(native,node->b);
        nativeEmit(native,armB(-(int32_t)((native->machine.size - top) / 4)));
        if (tested) nativeBranchHere(native,exit,armCbz(0,0));
        nativeLeave(native);
        break;
    }
    case RangeNodeFor:
        nativeStatement(native,node->a); /* the loop it is written as */
        break;
    case RangeNodeBreak: case RangeNodeContinue: {
        // Values that began inside the target end here, then control leaves it.
        int loop = node->kind == RangeNodeContinue;
        size_t index = native->targetCount;
        while (index > 0 && loop && !native->targets[index - 1].loop) --index;
        if (!index) { nativeMissing(native,node,"'%s' has no enclosing target",loop ? "continue" : "break"); break; }
        NativeTarget *target = &native->targets[index - 1];
        nativeEndTemps(native,target->temps);
        nativeReleaseSlots(native,target->slots);
        target = &native->targets[index - 1];
        if (native->valueDepth > target->valueDepth) nativeResetStack(native,target);
        if (loop) nativeEmit(native,armB(-(int32_t)((native->machine.size - target->top) / 4)));
        else {
            NativeJump jump = {.at=nativeEmit(native,armB(0)),.base=armB(0)};
            NATIVE_PUSH(target->breaks,target->breakCount,target->breakCapacity,jump);
        }
        break;
    }
    case RangeNodeReturn: {
        if (native->region) {
            // An inlined body's return: its value into the region's result,
            // the values the body began end, and control leaves the body.
            NativeRegion *region = native->region;
            RangeNode *type = node->a ? nativeExpression(native,node->a) : NULL;
            if (type && region->resultKind == NativeScalar) nativeStore(native,0,region->result);
            else if (type && region->resultKind == NativeAggregate) {
                int moved = nativeTakeTemp(native);
                nativeFrameAddress(native,1,region->result);
                nativeCopyValue(native,1,0,region->resultType,!moved);
            }
            nativeEndTemps(native,region->temps);
            nativeReleaseSlots(native,region->slots);
            if (native->valueDepth > region->valueDepth) {
                nativeLoad(native,10,region->stack);
                nativeEmit(native,armAddImm(31,10,0)); /* mov sp, x10 */
            }
            NativeJump jump = {.at=nativeEmit(native,armB(0)),.base=armB(0)};
            NATIVE_PUSH(region->returns,region->returnCount,region->returnCapacity,jump);
            break;
        }
        // The result moves or is retained into place; then every value in scope ends.
        if (node->a) {
            RangeNode *type = nativeExpression(native,node->a);
            if (type && !type->scalarBits && native->resultSlot) {
                int moved = nativeTakeTemp(native);
                nativeLoad(native,1,native->resultSlot);
                nativeCopyValue(native,1,0,type,!moved);
            }
        }
        // Ending the temporaries leaves them listed: other paths through the
        // enclosing statement, such as a switch expression's other arms, still end them.
        nativeEmit(native,armPush(0));
        nativeEndTemps(native,0);
        nativeReleaseSlots(native,0);
        nativeEmit(native,armPop(0));
        size_t at = nativeEmit(native,armB(0));
        NATIVE_PUSH(native->returns,native->returnCount,native->returnCapacity,at);
        break;
    }
    case RangeNodeExpressionStatement: {
        // A value known before run has no effect: nothing runs.
        RangeValue known;
        if (!nativeKnown(native,node->a,&known)) nativeExpression(native,node->a);
        break;
    }
    case RangeNodeSwitch:
        (void)nativeSwitch(native,node);
        break;
    case RangeNodeFunction: case RangeNodeConstruct:
        nativeMissing(native,node,"nested %s declarations are not implemented natively",rangeNodeKindName(node->kind));
        break;
    default:
        nativeMissing(native,node,"native %s statements are not implemented",rangeNodeKindName(node->kind));
        break;
    }
}

/* ---- switch ----
 * Each subject is evaluated once and kept in a frame slot: a scalar's value,
 * or an aggregate's address. An arm tries its rows in order. A row tests
 * tags and values first, subject by subject, then copies its bindings into
 * the arm's slots (a copy holds its own references), then runs the row's
 * condition; a failed condition ends the bindings. The first match runs its
 * arm, and arms do not fall through. */

typedef struct { int32_t slot; size_t offset; int value; } NativePlace; /* value: the slot holds the scalar itself */
typedef struct { RangeNode *binding; NativePlace place; RangeNode *type; } NativeBind;
typedef struct {
    NativeJump *fails; size_t failCount, failCapacity;
    NativeBind *binds; size_t bindCount, bindCapacity;
} NativeMatch;

/* x0 = the scalar at a place, or the aggregate's address. */
static void nativePlaceLoad(Native *native, NativePlace place, RangeNode *type)
{
    nativeLoad(native,0,place.slot);
    if (place.value) return;
    nativeAddOffset(native,0,0,place.offset);
    if (type->scalarBits) nativeLoadScalar(native,0,0,0,type);
}

static void nativeFail(NativeMatch *match, size_t at, uint32_t base)
{
    NativeJump jump = {.at=at,.base=base};
    NATIVE_PUSH(match->fails,match->failCount,match->failCapacity,jump);
}

static void nativeMatch(Native *native, NativeMatch *match, RangeNode *pattern, NativePlace place, RangeNode *type)
{
    if (!pattern || !type) return;
    switch (pattern->integer) {
    case RangePatternAny: return;
    case RangePatternBind: {
        NativeBind bind = {.binding=pattern->a,.place=place,.type=type};
        NATIVE_PUSH(match->binds,match->bindCount,match->bindCapacity,bind);
        return;
    }
    case RangePatternCase: {
        RangeNode *entry = found(native->key,pattern)->resolvedDeclaration;
        nativePlaceLoad(native,place,type);
        if (type->scalarBits) {
            nativeConstant(native,1,(uint64_t)entry->integer);
            nativeEmit(native,armCmp(0,1));
            nativeFail(match,nativeEmit(native,armBcond(RangeNE,0)),armBcond(RangeNE,0));
            return;
        }
        nativeFail(match,nativeUnlessCase(native,0,type,entry),armBcond(RangeNE,0));
        if (!(pattern->flags & RangeFlagApplication)) return;
        size_t first = nativeFirstField(type->resolvedDeclaration,entry);
        for (size_t j = 0; j < entry->itemCount && j < pattern->itemCount; ++j) {
            RangeNode *inner = pattern->items[j]->a;
            size_t k = first + j;
            if (!inner || inner->integer == RangePatternAny) continue;
            NativePlace field = {.slot=place.slot,.offset=place.offset + type->memberOffsets[k]};
            if (type->memberBoxed[k]) {
                // The field's value is the slot of its block.
                field = (NativePlace){.slot=nativeReserve(native,8,8)};
                nativePlaceLoad(native,place,type);
                nativeAddOffset(native,0,0,type->memberOffsets[k]);
                nativeEmit(native,armLdr(0,0,0));
                nativeEmit(native,armAddImm(0,0,16));
                nativeStore(native,0,field.slot);
            }
            nativeMatch(native,match,inner,field,type->memberTypes[k]);
        }
        return;
    }
    case RangePatternValue: {
        // A value the field must equal, by its type's `=`.
        nativePlaceLoad(native,place,type);
        nativeEmit(native,armPush(0));
        nativeExpression(native,pattern->a);
        nativeEmit(native,armMov(1,0));
        nativeEmit(native,armPop(0));
        nativeEquals(native,type);
        nativeFail(match,nativeEmit(native,armCbz(0,0)),armCbz(0,0));
        return;
    }
    default:
        nativeMissing(native,pattern,"this pattern form is not implemented natively");
    }
}

/* Copies a match's bindings into the slots of the names they bind. A slot
 * that a case test fills may hold an earlier value of the arm (zero when
 * none): that value ends first. */
static void nativeBindMatch(Native *native, NativeMatch *match, int replace)
{
    for (size_t b = 0; b < match->bindCount; ++b) {
        NativeBind *bind = &match->binds[b];
        RangeNode *shared = found(native->key,bind->binding)->resolvedDeclaration, *target = shared ? shared : bind->binding;
        NativeSlot *slot = nativeSlotOf(native,target);
        if (!slot) continue;
        int32_t offset = slot->offset;
        if (replace && !bind->type->scalarBits && nativeSharesSlots(bind->type)) {
            nativeFrameAddress(native,0,offset);
            nativeRelease(native,bind->type);
        }
        nativePlaceLoad(native,bind->place,bind->type);
        if (bind->type->scalarBits) nativeStore(native,0,offset);
        else { nativeFrameAddress(native,1,offset); nativeCopyValue(native,1,0,bind->type,1); }
        if (target != bind->binding) {
            NativeSlot alias = {.declaration=bind->binding,.offset=offset,.type=bind->type,.alias=1};
            NATIVE_PUSH(native->slots,native->slotCount,native->slotCapacity,alias);
        }
    }
}

/* `phase.failed(let reason)`: x0 = 1 when the subject holds the case and
 * its payload matches, its bindings copied into their slots; else 0. The
 * subject's temporaries end here. */
static RangeNode *nativeCaseTest(Native *native, RangeNode *test)
{
    size_t temps = native->tempCount;
    RangeNode *type = nativeExpression(native,test->a);
    if (!type) return NULL;
    int kind = nativeKind(native,type,test->a);
    if (kind == NativeNone) return NULL;
    NativePlace place = {.slot=nativeReserve(native,8,8),.value=kind == NativeScalar};
    nativeStore(native,0,place.slot);
    NativeMatch match = {0};
    nativeMatch(native,&match,test->b,place,type);
    nativeBindMatch(native,&match,1);
    nativeConstant(native,0,1);
    size_t done = nativeEmit(native,armB(0));
    for (size_t f = 0; f < match.failCount; ++f) nativeBranchHere(native,match.fails[f].at,match.fails[f].base);
    nativeConstant(native,0,0);
    nativeBranchHere(native,done,armB(0));
    free(match.fails); free(match.binds);
    if (native->tempCount != temps) {
        nativeEmit(native,armPush(0));
        nativeReleaseTemps(native,temps);
        nativeEmit(native,armPop(0));
    }
    native->resultTemp = -1;
    return found(native->key,test)->type;
}

/* The arm a switch runs when the choice is known before run, its bindings
 * known with it; the arm count when no arm runs; SIZE_MAX when the choice
 * is left to run. */
static size_t nativeKnownArm(Native *native, RangeNode *node, EvalFrame *arm)
{
    EvalFrame root;
    Eval eval = nativeEval(native,&root);
    size_t chosen;
    if (native->asWritten || evalChoose(&eval,&root,node,arm,&chosen) != EvalNormal) return SIZE_MAX;
    if (chosen == node->itemCount) return (node->flags & RangeFlagValue) ? SIZE_MAX : chosen;
    RangeNode *entry = node->items[chosen];
    for (size_t j = 0; entry->c && j < entry->c->itemCount; ++j) {
        RangeNode *binding = entry->c->items[j], *type = found(native->key,binding)->type;
        RangeValue *value = evalNamed(arm,binding);
        if (!value || nativeBuilds(native,value,type,binding) != 1) return SIZE_MAX;
    }
    return chosen;
}

/* A switch statement, or a switch expression (RangeFlagValue): each arm that
 * yields leaves the value in one frame slot, a scalar or the aggregate itself
 * holding its own references, which the expression then is, as a temporary.
 * Only the chosen arm is evaluated; when the choice is known before run,
 * only that arm is compiled, with nothing tested. Returns the expression's
 * type. */
static RangeNode *nativeSwitch(Native *native, RangeNode *node)
{
    int value = (node->flags & RangeFlagValue) != 0;
    RangeNode *valueType = value ? found(native->key,node)->type : NULL;
    int valueKind = value ? nativeKind(native,valueType,node) : NativeNone;
    if (value && valueKind == NativeNone) return NULL;
    EvalFrame arm;
    size_t known = nativeKnownArm(native,node,&arm);
    // Each subject is evaluated once, in order, into its own slot.
    size_t width = node->c ? node->c->itemCount : 1;
    // A switch over conditions has no subjects; the arrays keep one entry.
    NativePlace places[width ? width : 1];
    RangeNode *types[width ? width : 1];
    for (size_t k = 0; known == SIZE_MAX && k < width; ++k) {
        RangeNode *subject = node->c ? node->c->items[k] : node->a;
        types[k] = nativeExpression(native,subject);
        if (!types[k]) return NULL;
        int kind = nativeKind(native,types[k],subject);
        if (kind == NativeNone) return NULL;
        places[k] = (NativePlace){.slot=nativeReserve(native,8,8),.value=kind == NativeScalar};
        nativeStore(native,0,places[k].slot);
    }
    int32_t result = valueKind == NativeAggregate ? nativeReserve(native,valueType->size ? valueType->size : 1,valueType->alignment)
                   : valueKind == NativeScalar ? nativeReserve(native,8,8) : 0;
    native->valueDepth += value;
    NativeJump *ends = NULL;
    size_t endCount = 0, endCapacity = 0;
    for (size_t i = 0; i < node->itemCount; ++i) {
        RangeNode *entry = node->items[i];
        size_t scope = native->slotCount;
        if (known != SIZE_MAX && i != known) continue;
        for (size_t j = 0; entry->c && j < entry->c->itemCount; ++j) {
            RangeNode *binding = entry->c->items[j], *bindingType = found(native->key,binding)->type;
            int bindingKind = nativeKind(native,bindingType,binding);
            if (bindingKind == NativeNone) continue;
            if (known != SIZE_MAX) { nativeKnownSlot(native,binding,bindingType,evalNamed(&arm,binding)); continue; }
            int32_t offset = nativeNewSlot(native,binding,bindingType,bindingKind);
            // A condition's case tests fill the slot, and a failed one leaves
            // it empty: it starts empty, so ending it is always safe.
            if (bindingKind == NativeAggregate && nativeSharesSlots(bindingType)) {
                nativeFrameAddress(native,0,offset);
                nativeZero(native,0,bindingType->size);
            }
        }
        size_t bound = native->slotCount;
        NativeJump *bodies = NULL;
        size_t bodyCount = 0, bodyCapacity = 0;
        int fallible = known == SIZE_MAX && !(entry->flags & RangeFlagLiteral);
        for (size_t j = 0; fallible && j < entry->itemCount; ++j) {
            RangeNode *pattern = entry->items[j], *patterns[width ? width : 1];
            NativeMatch match = {0};
            patternRow(pattern,patterns,width);
            for (size_t k = 0; k < width; ++k) nativeMatch(native,&match,patterns[k],places[k],types[k]);
            nativeBindMatch(native,&match,0);
            if (pattern->b) {
                nativeCondition(native,pattern->b);
                NativeJump body = {.at=nativeEmit(native,armCbnz(0,0)),.base=armCbnz(0,0)};
                NATIVE_PUSH(bodies,bodyCount,bodyCapacity,body);
                nativeReleaseSlots(native,scope); /* the condition failed: its bindings end */
                nativeFail(&match,nativeEmit(native,armB(0)),armB(0));
            } else {
                NativeJump body = {.at=nativeEmit(native,armB(0)),.base=armB(0)};
                NATIVE_PUSH(bodies,bodyCount,bodyCapacity,body);
            }
            native->slotCount = bound;
            for (size_t f = 0; f < match.failCount; ++f) nativeBranchHere(native,match.fails[f].at,match.fails[f].base);
            free(match.fails); free(match.binds);
        }
        size_t next = fallible ? nativeEmit(native,armB(0)) : 0;
        for (size_t b = 0; b < bodyCount; ++b) nativeBranchHere(native,bodies[b].at,bodies[b].base);
        free(bodies);
        if (entry->a) {
            // The arm's value moves, or is retained, into the result; the
            // arm's temporaries end before it joins the others.
            size_t temps = native->tempCount;
            if (nativeExpression(native,entry->a)) {
                if (valueKind == NativeScalar) nativeStore(native,0,result);
                else {
                    int moved = nativeTakeTemp(native);
                    nativeFrameAddress(native,1,result);
                    nativeCopyValue(native,1,0,valueType,!moved);
                }
            }
            nativeReleaseTemps(native,temps);
        } else nativeBlock(native,entry->b);
        nativeReleaseSlots(native,scope);
        native->slotCount = scope;
        if (known != SIZE_MAX) break;
        NativeJump end = {.at=nativeEmit(native,armB(0)),.base=armB(0)};
        NATIVE_PUSH(ends,endCount,endCapacity,end);
        if (fallible) nativeBranchHere(native,next,armB(0));
    }
    for (size_t i = 0; i < endCount; ++i) nativeBranchHere(native,ends[i].at,ends[i].base);
    free(ends);
    native->valueDepth -= value;
    if (valueKind == NativeScalar) {
        nativeLoad(native,0,result);
        native->resultTemp = -1;
    } else if (valueKind == NativeAggregate) {
        nativeTrackTemp(native,result,valueType);
        nativeFrameAddress(native,0,result);
    }
    return valueType;
}

/* One function instance or the entry block: frame, receiver, parameters,
 * body, epilogue. A body that ends without returning returns zero. */
static void nativeFunction(Native *native, NativeInstance *instance)
{
    RangeNode *function = instance->function;
    instance->offset = native->machine.size;
    instance->compiled = 1;
    native->function = function;
    native->key = instance->key;
    native->targetCount = 0;
    native->self = instance->self;
    native->owner = instance->self ? instance->self->resolvedDeclaration : NULL;
    native->slotCount = 0; native->returnCount = 0; native->frame = 0;
    native->valueDepth = 0; native->stackResetCount = 0;
    native->tempCount = 0; native->resultTemp = -1;
    native->selfSlot = 0; native->resultSlot = 0;
    native->region = NULL; native->closureCount = 0; native->hiddenCount = 0;
    native->serial = ++native->serials; native->foldCount = 0; /* what is known is found afresh */
    if (native->folds) memset(native->folds,0,native->foldCapacity * sizeof(*native->folds));
    nativeEmit(native,armPushFrame());
    nativeEmit(native,armAddImm(29,31,0)); /* mov x29, sp */
    size_t frameHigh = nativeEmit(native,armSubImmHigh(31,31,0));
    size_t frameLow = nativeEmit(native,armSubImm(31,31,0));
    RangeNode *body = function->kind == RangeNodeMain ? function->a : function->a;
    native->output = found(native->key,function)->type;
    int outputKind = native->output ? nativeKind(native,native->output,function) : NativeScalar;
    if (outputKind == NativeAggregate) { native->resultSlot = nativeReserve(native,8,8); nativeStore(native,8,native->resultSlot); }
    int base = 0;
    if (native->owner) { native->selfSlot = nativeReserve(native,8,8); nativeStore(native,0,native->selfSlot); base = 1; }
    if (function->kind == RangeNodeFunction) {
        if (function->itemCount + (size_t)base > 8) nativeMissing(native,function,"functions with more than 8 parameters are not implemented");
        for (size_t i = 0; i < function->itemCount && i + (size_t)base < 8; ++i) {
            RangeNode *parameter = function->items[i], *type = found(native->key,parameter)->type;
            int kind = nativeKind(native,type,parameter);
            if (kind == NativeNone) continue;
            int reg = (int)i + base;
            int32_t offset = nativeNewSlot(native,parameter,type,kind);
            // x0-x7 still hold the later parameters: copy through x14 and x15.
            if (kind == NativeScalar) nativeStore(native,reg,offset);
            else { nativeEmit(native,armAddImm(14,reg,0)); nativeFrameAddress(native,15,offset); nativeCopyValue(native,15,14,type,1); }
        }
    }
    nativeBlock(native,body);
    nativeReleaseSlots(native,0); /* parameters */
    nativeEmit(native,armMovz(0,0,0));
    for (size_t i = 0; i < native->returnCount; ++i) nativeBranchHere(native,native->returns[i],armB(0));
    nativeEmit(native,armAddImm(31,29,0)); /* mov sp, x29 */
    nativeEmit(native,armPopFrame());
    nativeEmit(native,armRet());
    size_t bytes = ((size_t)native->frame + 15) / 16 * 16;
    if (bytes >> 24) nativeMissing(native,function,"frames beyond 16 MB are not implemented");
    rangePatch(&native->machine,frameHigh,bytes >> 12 ? armSubImmHigh(31,31,(uint32_t)(bytes >> 12)) : armAddImm(31,31,0));
    rangePatch(&native->machine,frameLow,armSubImm(31,31,(uint32_t)(bytes & 0xFFF)));
    for (size_t i = 0; i < native->stackResetCount; ++i) {
        size_t at = native->stackResets[i];
        rangePatch(&native->machine,at,bytes >> 12 ? armSubImmHigh(31,29,(uint32_t)(bytes >> 12)) : armAddImm(31,29,0));
        rangePatch(&native->machine,at + 4,armSubImm(31,31,(uint32_t)(bytes & 0xFFF)));
    }
}

/* Trap stubs: write the message to stderr, then exit with status 134, as an
 * abort would, without the delay of a crash report. Text and known values
 * follow; a branch or adr reaches them within 1 MB. */
static void nativeTraps(Native *native)
{
    size_t *messages = calloc(native->trapCount ? native->trapCount : 1,sizeof(*messages)), far = 0;
    if (!messages) abort();
    for (size_t i = 0; i < native->trapCount; ++i) {
        NativeTrap *trap = &native->traps[i];
        int32_t words = (int32_t)((native->machine.size - trap->at) / 4);
        if (native->machine.size - trap->at > far) far = native->machine.size - trap->at;
        rangePatch(&native->machine,trap->at,trap->branch | ((uint32_t)words & 0x7FFFFu) << 5);
        messages[i] = nativeEmit(native,armAdr(1,0));
        nativeEmit(native,armMovz(0,2,0));
        nativeConstant(native,2,strlen(trap->message));
        rangeCallImport(&native->machine,"_write");
        nativeEmit(native,armMovz(0,134,0));
        rangeCallImport(&native->machine,"_exit");
    }
    for (size_t i = 0; i < native->trapCount; ++i) {
        size_t text = rangeEmitBytes(&native->machine,native->traps[i].message,strlen(native->traps[i].message));
        rangePatch(&native->machine,messages[i],armAdr(1,(int32_t)(text - messages[i])));
    }
    for (size_t i = 0; i < native->textCount; ++i) {
        size_t text = rangeEmitBytes(&native->machine,native->texts[i].bytes,native->texts[i].length);
        rangePatch(&native->machine,native->texts[i].at,armAdr(1,(int32_t)(text - native->texts[i].at)));
        if (text - native->texts[i].at > far) far = text - native->texts[i].at;
    }
    if (far >= (size_t)1 << 20) nativeMissing(native,NULL,"executables whose code reaches a trap or its data more than 1 MB away are not implemented");
    free(messages);
}

/* A specialization over graph constructs or macro types (Array<Macro> and
 * Array<@member> in the grammar) holds compile-time graph values that C
 * provides; it has no runtime instance. */
static int nativeGraphValues(Native *native, const RangeNode *type)
{
    return macroTimeType(native->typer,type);
}

/* A construct's methods are compiled for its own specialization, as they
 * were typed there. A generic construct's, as a generic function's, are
 * compiled per specialization when called, under its key, so Array<Point>'s
 * `=`, and Point's `=` with it, exist only if such arrays are compared. */
static void nativeMethods(Native *native, RangeNode *construct)
{
    RangeNode *self = ownSpecialization(native->typer,construct);
    if (!self || nativeGraphValues(native,self)) return;
    for (size_t j = 0; j < construct->itemCount; ++j) {
        RangeNode *function = construct->items[j];
        // A type's function '=' is compiled only when the type is compared.
        if (function->kind == RangeNodeFunction && !(function->flags & (RangeFlagBuiltin | RangeFlagExtern))
            && !same(function->name,"=") && !genericTemplate(function) && !nativeInlined(function))
            nativeInstance(native,function,NULL,self);
    }
}

/* Compile the entry block and every function and specialization instance its
 * emitted code calls; write the executable when nothing is missing. With
 * `asWritten`, or without an entry block, every function and every method of
 * every concrete specialization is compiled, reached or not; with
 * `asWritten`, every expression is compiled as written: nothing is filled in
 * before run. Returns 1 when an executable was written. */
int emitNative(SourceReport *report, Typer *typer, const char *path, int asWritten)
{
    Native native = {.report=report,.typer=typer,.asWritten=asWritten};
    RangeNode *entry = NULL;
    size_t entries = 0;
    for (size_t u = 0; u < report->count; ++u) for (size_t i = 0; i < report->units[u]->itemCount; ++i)
        if (report->units[u]->items[i]->kind == RangeNodeMain) { entry = report->units[u]->items[i]; ++entries; }
    if (entries > 1) { sourceDiagnostic(report,entry,0,"entry","the program has %zu entry blocks; it needs one",entries); return 0; }
    if (entry) nativeInstance(&native,entry,NULL,NULL);
    // Compiled as written, or without an entry block, every function is
    // compiled, reached or not; otherwise only what the entry block reaches.
    if (asWritten || !entry) {
        for (size_t u = 0; u < report->count; ++u) for (size_t i = 0; i < report->units[u]->itemCount; ++i) {
            RangeNode *item = report->units[u]->items[i];
            if (item->kind == RangeNodeFunction && !(item->flags & (RangeFlagBuiltin | RangeFlagExtern)) && !genericTemplate(item)
                && !nativeInlined(item))
                nativeInstance(&native,item,NULL,NULL);
        }
        // Generic functions: one compiled function per specialization. A
        // generic method's is compiled for its receiver's specialization; one a
        // macro calls with its graph values runs only at macro time.
        for (size_t i = 0; i < typer->instances->itemCount; ++i) {
            RangeNode *key = typer->instances->items[i], *context = key->outer;
            if (nativeGraphValues(&native,key) || (context && nativeGraphValues(&native,context))
                || nativeInlined(key->resolvedDeclaration)) continue;
            nativeInstance(&native,key->resolvedDeclaration,key,context);
        }
        for (size_t u = 0; u < report->count; ++u) for (size_t i = 0; i < report->units[u]->itemCount; ++i)
            if (report->units[u]->items[i]->kind == RangeNodeConstruct || report->units[u]->items[i]->kind == RangeNodeEnum)
                nativeMethods(&native,report->units[u]->items[i]);
    }
    // Compiling may reach new instances and subroutines, each where emitted
    // code calls it, and a subroutine may reach further ones of both; the
    // entry block stays first.
    for (int progress = 1; progress;) {
        progress = 0;
        for (size_t i = 0; i < native.instanceCount; ++i)
            if (!native.instances[i].compiled) { nativeFunction(&native,&native.instances[i]); progress = 1; }
        for (size_t i = 0; i < native.helperCount; ++i)
            if (!native.helpers[i].compiled) { nativeHelperBody(&native,i); progress = 1; }
    }
    for (size_t i = 0; i < native.helperCallCount; ++i) {
        NativeHelper *helper = &native.helpers[native.helperCalls[i].helper];
        rangePatch(&native.machine,native.helperCalls[i].at,armBl((int32_t)(((int64_t)helper->offset - (int64_t)native.helperCalls[i].at) / 4)));
    }
    for (size_t i = 0; i < native.callCount; ++i) {
        NativeInstance *instance = nativeInstance(&native,native.calls[i].function,native.calls[i].key,native.calls[i].self);
        if (!instance->compiled) continue; /* reported where it was compiled */
        rangePatch(&native.machine,native.calls[i].at,armBl((int32_t)(((int64_t)instance->offset - (int64_t)native.calls[i].at) / 4)));
    }
    nativeTraps(&native);
    drainLaws(typer); /* the specializations and instances code generation met */
    int written = 0;
    if (!native.failed && entry) {
        char error[512];
        if (rangeWriteExecutable(&native.machine,0,path,error,sizeof(error))) written = 1;
        else sourceDiagnostic(report,NULL,0,"output","%s",error);
    }
    rangeMachineFree(&native.machine);
    free(native.slots); free(native.returns); free(native.calls); free(native.traps); free(native.instances); free(native.texts);
    free(native.temps); free(native.helpers); free(native.helperCalls); free(native.targets); free(native.stackResets);
    free(native.closures); free(native.hidden); free(native.folds);
    return written;
}
