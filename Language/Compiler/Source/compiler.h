/* What the compiler's layers share: the contexts each one runs in, and the
 * functions one layer calls in another. Everything else is static in its
 * layer: resolution.c, macros.c, typing.c, evaluator.c, codegen.c, and the
 * driver in compiler.c. */
#ifndef RANGE_COMPILER_COMPILER_H
#define RANGE_COMPILER_COMPILER_H

#include "model.h"
#include <setjmp.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>

typedef struct Typer Typer;

/* Resolution context, in which macro applications also run. */
typedef struct {
    RangeArena *arena;
    RangeNode **units;
    size_t count;
    char *error;
    size_t errorSize;
    jmp_buf failure;
    RangeNode *emitted; /* declarations emitted by the running application */
    RangeNode *unit;    /* unit holding the running application's target */
    struct SourceReport *report; /* where warning(message:) reports, when compiling */
    Typer *typer; /* alive from before the first application to the end of type checking */
    size_t checked; /* applications run */
} Resolver;

/* Compilation reports independent source gaps before attempting dependent work.
 * These references come from the parsed graph, never a required-type name list. */
typedef struct SourceDiagnostic {
    RangeNode *at;
    const char *category;
    const char *message;
    size_t uses;
    int warning;
    struct SourceDiagnostic *next;
} SourceDiagnostic;

typedef struct SourceReport {
    RangeArena *arena;
    RangeNode **units;
    size_t count;
    SourceDiagnostic *first, *last;
    size_t errors, warnings;
} SourceReport;

typedef struct SourceScope {
    RangeNode *owner;
    struct SourceScope *parent;
    int meta; /* inside a macro body: code that runs at macro time */
} SourceScope;

/* A law run on a literal depends only on the specialization and the
 * literal's value, so its outcome is kept under exactly those inputs. */
typedef struct {
    RangeNode *type;
    RangeNodeKind kind;
    long long integer;
    const char *text;
    const char **failures;
    size_t failureCount;
} LawResult;

struct Typer {
    SourceReport *report;
    Resolver *vm;                /* applies macros, and runs laws per specialization */
    RangeNode *specializations;  /* interned specializations of constructs, enums, and macro types */
    RangeNode *integer, *boolean; /* constructs the integer and boolean literal rules select */
    RangeNode *booleanType;
    LawResult *laws; size_t lawCount, lawCapacity;
    int loops; /* enclosing loops in this function: the targets of break and continue */
    RangeNode *function; /* the function being typed */
    RangeNode *output;   /* what its `return` gives: the function's result, or the entry block's status */
    RangeNode *key;      /* whose findings typing writes: the specialization being typed, or NULL */
    /* Values compared with `=`, and the key they were typed under: checked once every type is known. */
    struct { RangeNode *type, *at, *key; } *equalities; size_t equalityCount, equalityCapacity;
    RangeNode *instances; /* interned specializations of generic functions, in the order typing met them */
    RangeNode *typing[64]; size_t typingCount; /* declarations whose type is being derived from their value */
    RangeNode *functionTypes;   /* interned RangeNodeFunctionType nodes */
    RangeNode *closureSite;     /* the argument being typed for a function-typed parameter */
    int inferring; RangeNode *inferred; /* a closure whose result its returns decide */
    int closures; /* closure bodies being typed in the function being typed */
    /* Values narrowed to their optional's payload where they are read now;
     * the function being typed sees those from narrowedFloor on. */
    struct { RangeNode *path, *entry, *type; } *narrowed;
    size_t narrowedCount, narrowedCapacity, narrowedFloor;
    RangeNode *deferred; /* the type of a value known only at macro time */
    RangeNode *macro;    /* the macro whose body is being typed */
    int arguments;       /* typing an application's arguments: macro-time code outside any macro body */
    /* Laws to run: typing never runs Range code, so a specialization or a
     * literal it meets waits here until typing returns to the top level. */
    struct { RangeNode *type, *value, *at; } *queued; size_t queuedCount, queuedCapacity;
    /* Written code as it was read: each leaf declaration and its hash. */
    struct { RangeNode *node; uint64_t hash; } *written; size_t writtenCount, writtenCapacity;
};

typedef enum {
    ValueNone, ValueLiteral, ValueScalar, ValueText, ValueCase, ValueInstance, ValueSlots,
    ValueDeclaration, ValueClosure
} RangeValueKind;

struct EvalFrame;

/* A known value. A literal has no type yet: a member kind's `.value` is the
 * literal its declaration writes, and it takes the type of its use, node
 * being the literal. A scalar is a value of a type with a storage primitive,
 * integer its bits. Text is a value of a type with the bytes primitive, or a
 * name C holds; node is the string literal it was written as, or the
 * declaration whose name it is, which a splice writes as a reference to it.
 * A case is a value of an enum: node the case, values its payload; Bool's
 * values are the condition type's cases. An instance has one value per item
 * of its construct, set for the stored members; slots are a @many member's
 * elements. A declaration is a graph node, a value of its grammar kind or of
 * a macro type. A closure is its literal and the frame it was written in. */
typedef struct RangeValue {
    RangeValueKind kind;
    RangeNode *type;
    RangeNode *node;
    long long integer;
    const char *text; size_t length;
    struct RangeValue *values; size_t count;
    struct EvalFrame *frame;
} RangeValue;

/* The values a running body names, found by the declaration typing resolved
 * each name to: its parameters, locals, and bindings. A body reads what
 * typing found under the key it was typed in. A closure's frame continues in
 * the one it was written in, which is alive while it runs: a closure runs
 * only while the call it is passed to runs. */
typedef struct EvalBinding { RangeNode *declaration; RangeValue value; struct EvalBinding *next; } EvalBinding;
typedef struct EvalFrame {
    struct EvalFrame *parent;
    EvalBinding *bindings;
    RangeValue *self;    /* the receiver of the running method, changed in place */
    RangeNode *function; /* the running function: its receiver and its value generics */
    RangeNode *output;   /* what its `return` gives */
    RangeNode *key;      /* the specialization its body was typed in, or NULL */
} EvalFrame;

/* How evaluation goes on: normally, or leaving through return (the value in
 * returned), break, continue, or a failure (the message at, or none); or,
 * folding, on a value that is not known before run. */
enum { EvalNormal, EvalReturn, EvalBreak, EvalContinue, EvalFailed, EvalUnknown };

struct Native;

typedef struct {
    Resolver *vm;
    Typer *typer;
    RangeMacroApplication *application; /* the running application: its target and output */
    unsigned steps, depth;
    RangeValue returned;
    const char *message; RangeNode *at;
    /* Emitted copies by original, so a node quoted code reaches twice (a
     * for-in's binding is in its pattern and its scope) stays one node. */
    RangeNode **emittedFrom, **emittedTo; size_t emittedCapacity, emittedCount;
    /* Folding: native code asks what a body it compiles knows before run.
     * Root is that body's frame, whose names native code holds. */
    struct Native *outside;
    EvalFrame *root;
} Eval;

/* What a call runs, in both walkers, by the declaration typing resolved its
 * callee to: a case with its payload, a construction, the closure a
 * parameter holds, or a function. */
enum { CallCase, CallConstruct, CallClosure, CallFunction, CallOther };

/* How an operator runs, in both walkers, by the function typing chose and
 * whether its left operand is bytes: `&` and `|` decide on their left
 * operand when they can, `=` and `!=` compare by the operands' type's `=`,
 * `+` on bytes joins them, and any other is the operand's scalar primitive,
 * or Bool's `!`, or a call. */
enum { OperatorShortCircuit, OperatorEquality, OperatorJoin, OperatorScalar };

/* resolution.c */
int same(const char *a, const char *b);
_Noreturn void fail(Resolver *vm, RangeNode *at, const char *format, ...);
RangeNode *grammarDeclaration(Resolver *vm, RangeNode *node);
void resolveApplication(Resolver *vm, RangeNode *target, RangeNode *attribute);
void resolveGraphTarget(Resolver *vm, RangeNode *target);
void singleApplication(Resolver *vm, RangeNode *declaration, RangeNode *attribute);
void validateGraphShape(Resolver *vm, RangeNode *node, const char *source);
int literalMatch(Resolver *vm, RangeNode *at, const char *pattern, const char *input);
int macroBuiltin(RangeNode *node, const char *name);
int builtinFunction(const RangeNode *node, const char *name);
int roleMacro(RangeNode *node);
int appliesMacro(const RangeNode *declaration, const RangeNode *macro);
void linkGrammarNodes(Resolver *vm, RangeNode *node);
void resolveLiteralDefaults(Resolver *vm, RangeNode *node);
int matchLiteralRule(RangeArena *arena, RangeNode **units, size_t count, const char *name, const char *input, int *matched, char *error, size_t errorSize);
int enclosing(RangeNode *within, RangeNode *node, RangeNode **chain, size_t *count, size_t capacity);
void resolveSignatureTypes(Resolver *vm, RangeNode *node, RangeNode *owner);
int resolveGraphApplications(RangeArena *arena, RangeNode **units, size_t count, char *error, size_t errorSize);
int spliceChain(const RangeNode *node);
void spliceDeclarationType(RangeNode *copy, const RangeNode *original);
int argumentFits(const RangeNode *argument, const RangeNode *function, size_t index);
RangeNode *insertionFunction(const RangeNode *declaration, size_t *count);
void sourceDiagnostic(SourceReport *report, RangeNode *at, int warning, const char *category, const char *format, ...);
RangeNode *methodReceiver(SourceReport *report, RangeNode *function);
RangeNode *sourceLookup(SourceReport *report, SourceScope *scope, const char *name, int kind);
RangeNode *nameLookup(SourceReport *report, SourceScope *scope, const RangeNode *name);
RangeNode *nestedDeclaration(RangeNode *owner, const char *name, size_t length);
RangeNode *dottedLookup(SourceReport *report, SourceScope *scope, const char *name, int kind);
RangeNode *typePath(SourceReport *report, SourceScope *scope, RangeNode *expr);
const char *typePathText(SourceReport *report, RangeNode *expr);
int requiredPath(SourceReport *report, SourceScope *scope, RangeNode *node);
RangeNode *bindingNamed(const RangeNode *bindings, const char *name);
void diagnoseSourceNode(SourceReport *report, SourceScope *scope, RangeNode *node, int metadata);
void writeSourceDiagnostics(SourceReport *report, FILE *output);
int slotPrimitive(const RangeNode *function);
int appliesBuiltin(const RangeNode *node, const char *name);
void diagnoseBuiltinFunctions(SourceReport *report, RangeNode *owner);
void diagnoseDuplicates(SourceReport *report);

/* macros.c */
int compilerAttribute(RangeNode *target, RangeNode *attribute);
RangeNode *runMacroApplication(Resolver *vm, RangeNode *attribute);
void mergeEmitted(Resolver *vm, RangeNode *emitted);
Typer *diagnoseMacroApplications(SourceReport *report);
void queueLaws(Typer *typer, RangeNode *specialization, RangeNode *value, RangeNode *at);
void drainLaws(Typer *typer);

/* typing.c */
RangeFacts *found(RangeNode *key, RangeNode *node);
void patternRow(RangeNode *row, RangeNode **vector, size_t width);
void describeType(char *out, size_t size, const RangeNode *type);
int bareSpecialization(const RangeNode *specialization);
int uninhabited(const RangeNode *type);
int lawInputs(const RangeNode *value, RangeNodeKind *kind, long long *integer, const char **text);
RangeNode **genericSlot(RangeNode *specialization, RangeNode *generic);
RangeNode *specialize(Typer *typer, SourceScope *scope, RangeNode *declaration, RangeNode *arguments, RangeNode *context, RangeNode *at);
RangeNode *ownSpecialization(Typer *typer, RangeNode *declaration);
int unitType(Typer *typer, const RangeNode *type);
int deferredType(const Typer *typer, const RangeNode *type);
int macroTimeType(Typer *typer, const RangeNode *type);
RangeNode *resolveTypeReference(Typer *typer, SourceScope *scope, const char *name, RangeNode *generics, int flags, RangeNode *context, RangeNode *at);
RangeNode *keyOf(const RangeNode *declaration, RangeNode *type);
RangeNode *memberTypeIn(Typer *typer, RangeNode *type, RangeNode *member);
RangeNode *findMember(RangeNode *declaration, const char *name);
RangeNode *findCalledFunction(RangeNode *owner, const char *name, const RangeNode *call);
RangeNode *memberType(Typer *typer, RangeNode *declaration, RangeNode *member, RangeNode *receiver);
int isEnum(const RangeNode *type);
RangeNode *enumCase(const RangeNode *declaration, const char *name);
RangeNode *literalCase(const RangeNode *declaration, const RangeNode *literal);
int bytesDeclaration(const RangeNode *declaration);
int bytesType(const RangeNode *type);
RangeNode *operatorFunction(const RangeNode *declaration, const char *symbol, size_t arity);
int operatorName(const char *name);
int shortCircuit(const RangeNode *function);
RangeNode *optionalWrapped(Typer *typer, RangeNode *type, RangeNode **present);
int constructionInput(const RangeNode *member);
RangeNode *declarationValue(RangeNode *key, RangeNode *node);
int genericTemplate(const RangeNode *function);
RangeNode *closureResult(Typer *typer, RangeNode *key, RangeNode *closure);
RangeNode *iterationFunction(const RangeNode *declaration, size_t *count);
int builtinMember(const RangeNode *member);
RangeNode *builtinValue(RangeNode *specialization, RangeNode *member);
int layoutOf(Typer *typer, RangeNode *specialization, RangeNode *at);
RangeNode *equalityFunction(const RangeNode *type);
void noteWritten(Typer *typer, RangeNode *node);
void diagnoseWritten(Typer *typer);
Typer *newTyper(SourceReport *report, Resolver *vm);
void typerLanguage(Typer *typer);
RangeNode *typeOnDemand(Typer *typer, RangeNode *function, RangeNode *receiver);
void typeValueOnDemand(Typer *typer, RangeNode *member);
int typeMacroOnDemand(Typer *typer, RangeMacroApplication *app);
int typeApplicationOnDemand(Typer *typer, RangeMacroApplication *app);
void typeCheck(Typer *typer);

/* evaluator.c */
RangeValue *evalNamed(EvalFrame *frame, const RangeNode *declaration);
int evalTruth(RangeValue value);
int evalWrite(Eval *eval, RangeValue value, RangeNode *at, const char **text, size_t *length);
RangeNode *manyElement(Typer *typer, RangeNode *type, RangeNode *member);
RangeNode *constructionArgument(RangeNode *key, RangeNode *member, RangeNode **arguments, size_t count);
RangeNode *constructionSingle(RangeNode *own, RangeNode *declaration, RangeNode **arguments, size_t count, int *defaulted);
int callForm(const RangeNode *target);
int operatorForm(const RangeNode *expr, const RangeNode *function, int bytes);
int evalChoose(Eval *eval, EvalFrame *frame, RangeNode *node, EvalFrame *arm, size_t *chosen);
int evalPlain(Eval *eval, EvalFrame *frame, RangeNode *expr, RangeValue *out);
int evalExpression(Eval *eval, EvalFrame *frame, RangeNode *expr, RangeValue *out);
int evalDeclared(Eval *eval, EvalFrame *frame, RangeNode *node, RangeValue *value);
int evalApplication(Resolver *vm, RangeMacroApplication *app, int shape);

/* codegen.c */
size_t nativeMemberIndex(RangeNode *declaration, RangeNode *member);
void nativeRemember(struct Native *native, RangeNode *node, int status, const RangeValue *value);
int nativeKnownName(struct Native *native, RangeNode *declaration, RangeValue *out);
int emitNative(SourceReport *report, Typer *typer, const char *path, int asWritten);

#endif
