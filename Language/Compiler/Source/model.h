/* Shared graph model for the Range compiler.
 *
 * One node shape with named structural slots. Every node carries its source
 * location so unsupported forms can fail loudly with a real position. */
#ifndef RANGE_COMPILER_MODEL_H
#define RANGE_COMPILER_MODEL_H

#include <stddef.h>

typedef enum {
    RangeNodeUnit,
    RangeNodeConstruct,
    RangeNodeEnum,
    RangeNodeEnumCase,
    RangeNodeFunction,
    RangeNodeMacro,
    RangeNodeMain,
    /* One node kind per grammar member kind, in constructs and in blocks. */
    RangeNodeLet,
    RangeNodeState,
    RangeNodeDerived,
    RangeNodeBinding,
    RangeNodeTypeParameter, /* <Element>: a generic that names a type */
    RangeNodeParameter,
    RangeNodeAttribute,
    RangeNodeBlock,
    RangeNodeAssign,
    RangeNodeWhile,
    RangeNodeReturn,
    RangeNodeExpressionStatement,
    RangeNodeCall,
    RangeNodeArgument,
    RangeNodeMemberAccess,
    RangeNodeName,
    RangeNodeInteger,
    RangeNodeBool,
    RangeNodeString,
    RangeNodeStringPart,
    RangeNodeCase,
    RangeNodeUnary,
    RangeNodeBinary,
    RangeNodeManyLiteral,
    RangeNodeEnvironment,
    RangeNodeSyntaxTemplate,
    RangeNodeClosure,
    RangeNodeEmission,
    RangeNodeSwitch,
    RangeNodeSwitchCase,
    RangeNodeExtension,
    RangeNodeSpecialization, /* a construct plus one value per generic */
    RangeNodeType,
    RangeNodePattern,        /* a switch arm's pattern; integer is its RangePattern form */
    RangeNodeFor,            /* for-in: a is the loop it lowers to, calling the @iteration function */
    RangeNodeBreak,
    RangeNodeContinue,
    RangeNodeFunctionType,   /* (A, B) -> R: items are the parameter types, a the result */
    RangeNodeCaseTest,       /* phase.failed(let reason): a Bool, whether the value a holds the case
                              * its pattern b names; b's `let` arguments bind the payload fields */
    RangeNodeKindCount
} RangeNodeKind;

enum {
    RangeFlagMany     = 1 << 0,
    RangeFlagBinding  = 1 << 3,  /* binding input parameter */
    RangeFlagExtern   = 1 << 4,
    RangeFlagBuiltin  = 1 << 5,
    RangeFlagOptional = 1 << 6,
    RangeFlagLiteral  = 1 << 7,  /* string part is literal text */
    RangeFlagApplication = 1 << 8, /* explicit parentheses, including () */
    RangeFlagMacroType = 1 << 9,   /* @name type: declarations that applied the macro */
    RangeFlagChecked = 1 << 10,    /* specialization: its laws have run */
    RangeFlagMutating = 1 << 11,   /* function: changes its receiver's state */
    RangeFlagMutationKnown = 1 << 12,
    RangeFlagValue = 1 << 13,      /* switch: an expression; an arm yields its a, or its block diverges */
    RangeFlagFunction = 1 << 14,   /* written type: a function type, (A, B) -> R; its generics hold the
                                    * parameter types as arguments and the result as a */
    RangeFlagImplicit = 1 << 15,   /* attribute: applied by its grammar declaration's @defaults, not written;
                                    * switch arm: a default the compiler wrote for a lowering;
                                    * binding: one a lowering wrote, not a pattern's `let`;
                                    * name: the receiver a bare case name tests */
    RangeFlagEarlier = 1 << 16     /* name: read to the left of the case test that binds the same name
                                    * in its condition, so it names what it names outside the condition */
};

/* Pattern forms: a case test's pattern and its arguments, and the rows of
 * a switch's arms. A case pattern's items are arguments (label,
 * sub-pattern). An arm's row is its pattern: in a switch over conditions a
 * row with no items, in the switch a for loop lowers to the pattern of its
 * one subject. A row's b is its condition, if it has one, and c the block
 * of its bindings. */
enum {
    RangePatternAny,      /* _ */
    RangePatternBind,     /* let name: a is the Let it declares */
    RangePatternCase,     /* .name(…): a case, with one sub-pattern per payload field */
    RangePatternValue,    /* a value compared for equality, by its type's `=`: a */
    RangePatternPresent,  /* for-in lowering: the payload of the @optional declaration's payload case */
    RangePatternRow       /* a row of a switch over conditions: no items, b its condition */
};

typedef struct RangeNode RangeNode;
typedef struct RangeMacroApplication RangeMacroApplication;

/* A compile-time value. Graph nodes, node lists, and text are what C's
 * reflection adapters hold. A case is a value of an enum: node is the case,
 * declaration the enum, values its payload, one per field. An instance is a
 * value of a construct: declaration is the construct, values one per item of
 * the declaration (only stored members are set). Slots are the elements of a
 * @many member: values, count of them. A closure is node, the closure
 * literal, with what it captured; it lives only while the call it was passed
 * to runs. */
typedef enum { RangeGraphNone, RangeGraphNode, RangeGraphNodes, RangeGraphText,
               RangeGraphCase, RangeGraphInstance, RangeGraphSlots, RangeGraphClosure } RangeGraphValueKind;
typedef struct RangeGraphValue {
    RangeGraphValueKind kind;
    RangeNode *node;
    RangeNode **nodes;
    size_t count;
    const char *text;
    RangeNode *declaration;
    struct RangeGraphValue *values;
    void *closure; /* a closure: what it captured where it was written, for the evaluator */
} RangeGraphValue;

typedef struct {
    RangeNode *definition;
    RangeGraphValue value;
    int state; /* 0 deferred, 1 resolving, 2 resolved */
} RangeGraphBinding;

struct RangeMacroApplication {
    RangeNode *declaration;
    RangeNode *target;
    RangeNode *unit;
    RangeNode *attribute; /* the application site on the target */
    int applied;          /* each application runs once */
    RangeGraphBinding *bindings;
    size_t count;
};

struct RangeNode {
    RangeNodeKind kind;
    const char *path;
    const char *source;    /* unit owns the text; inspected children borrow it */
    int line;
    int column;
    const char *name;      /* interned, NUL terminated */
    const char *typeName;  /* interned, NUL terminated */
    int flags;
    long long integer;
    size_t spanStart;   /* raw source span for retained code */
    size_t spanEnd;
    RangeNode *a;
    RangeNode *b;
    RangeNode *c;
    /* Resolution result: declaration identity, never a name-only dispatch. */
    RangeNode *resolvedDeclaration;
    RangeNode *resolvedType; /* resolved literal representation */
    RangeNode *type; /* the specialization an expression or declaration has */
    size_t size, alignment; /* specialization layout in bytes; layout 0 unknown, 1 computing, 2 done */
    int layout;
    int scalarBits, scalarSigned; /* from the builtin storage and signed members; 0 bits if not a scalar */
    int variantTag; /* union specialization: bytes of its leading tag; 0 for other layouts */
    unsigned char *memberBoxed; /* union specialization: per payload field, stored out of line */
    size_t *memberOffsets;   /* specialization: byte offset per declaration item, SIZE_MAX if not stored */
    struct RangeNode **memberTypes; /* specialization: type per declaration item; NULL for @many storage */
    RangeMacroApplication *macroApplication; /* application-specific bindings */
    RangeNode *graphType; /* C-owned reflective shape, when applicable */
    RangeNode *grammarDefinition; /* loaded language identity for a C-backed node */
    const char *literalPattern; /* validated literal rule, owned by the arena */
    RangeNode *literalDefault; /* unique Core construct for a literal macro */
    RangeNode *annotations;
    RangeNode *generics; /* declaration Let members or supplied type arguments */
    RangeNode *rhsReference; /* bare RHS identity, resolved like any name */
    RangeNode *emittedBy; /* macro application whose #graph block produced this node */
    RangeNode *receiver; /* method: its implicit receiver declaration, made on first use */
    RangeNode *owner;    /* method: the construct or enum that declares it */
    /* Complete declaration RHS source range, independent of legacy type slots. */
    size_t rhsStart;
    size_t rhsEnd;
    RangeNode **items;
    size_t itemCount;
    size_t itemCapacity;
};

/* Arena owning every node and interned string for the process lifetime. */
typedef struct RangeArenaBlock RangeArenaBlock;
typedef struct {
    RangeArenaBlock *head;
    size_t nodeCount;
    RangeNode *graphTypes;
} RangeArena;

void rangeArenaInit(RangeArena *arena);
void rangeArenaDestroy(RangeArena *arena);
void *rangeArenaAllocate(RangeArena *arena, size_t size);
const char *rangeArenaIntern(RangeArena *arena, const char *text, size_t length);
RangeNode *rangeNodeCreate(RangeArena *arena, RangeNodeKind kind,
                           const char *path, int line, int column);
void rangeNodeAppend(RangeArena *arena, RangeNode *node, RangeNode *item);
const char *rangeNodeKindName(RangeNodeKind kind);
int rangeNodeDeclaresValue(RangeNodeKind kind);
int rangeNodeHasContextReference(const RangeNode *node);
RangeNode *rangeGraphType(const RangeArena *arena, const char *name);
void rangeGraphInitTypes(RangeArena *arena);
RangeNode *rangeGraphField(const RangeNode *type, const char *name);
RangeNode *rangeNodeRHS(RangeNode *node);
RangeGraphValue rangeGraphStoredField(RangeArena *arena, RangeNode *node, const char *name);

#endif
