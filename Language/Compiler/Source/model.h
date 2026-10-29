/* Shared graph model for the Range compiler.
 *
 * One node shape with named structural slots. Every node carries its source
 * location so unsupported forms can fail loudly with a real position. Written
 * code is read once and never changed: what the compiler finds lives beside
 * it, in the node's own record of facts, or in the table of the
 * specialization it was typed for. */
#ifndef RANGE_COMPILER_MODEL_H
#define RANGE_COMPILER_MODEL_H

#include <stddef.h>
#include <stdint.h>

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
    RangeNodeSpecialization, /* a construct, enum, or function plus one value per generic */
    RangeNodeType,
    RangeNodePattern,        /* a switch arm's pattern; integer is its RangePattern form */
    RangeNodeFor,            /* for-in: a is the loop it lowers to, calling the @iteration function */
    RangeNodeBreak,
    RangeNodeContinue,
    RangeNodeFunctionType,   /* (A, B) -> R: items are the parameter types, a the result */
    RangeNodeCaseTest,       /* what typing lowers phase.failed(let reason) to, beside it: a Bool, whether
                              * the value a holds the case its pattern b names; b's `let` arguments bind
                              * the payload fields */
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
    RangeFlagValue = 1 << 13,      /* switch: an expression; an arm yields its a, or its block diverges */
    RangeFlagFunction = 1 << 14,   /* written type: a function type, (A, B) -> R; its generics hold the
                                    * parameter types as arguments and the result as a */
    RangeFlagImplicit = 1 << 15,   /* switch arm: a default the compiler wrote for a lowering;
                                    * binding: one a lowering wrote, not a pattern's `let`;
                                    * name: the receiver a bare case name tests */
    RangeFlagEarlier = 1 << 16     /* name: read to the left of the case test that binds the same name
                                    * in its condition, so it names what it names outside the condition */
};

/* What the compiler finds about a node, the bits of its `found`. */
enum {
    RangeFlagChecked = 1 << 10,    /* specialization: its laws have run */
    RangeFlagMutating = 1 << 11,   /* function: changes its receiver's state */
    RangeFlagMutationKnown = 1 << 12,
    RangeFlagTyped = 1 << 18,      /* function, macro, entry block, member: typed already, so typing on
                                    * demand at macro time and typing in order meet once; local: its
                                    * declaration was typed, so later statements may read it */
    RangeFlagShape = 1 << 19,      /* #graph: a shape-only block, emitted before any macro body runs */
    RangeFlagInvalid = 1 << 20,    /* function, macro: typing it reported errors, so it does not run at macro time */
    RangeFlagRequired = 1 << 21    /* let, state: its type path names a type it requires, not a value */
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
    RangePatternCase,     /* .name(…): a case, with one sub-pattern per payload field; unnamed, the
                           * payload case `for … in` unwraps */
    RangePatternValue,    /* a value compared for equality, by its type's `=`: a */
    RangePatternRow       /* a row of a switch over conditions: no items, b its condition */
};

typedef struct RangeNode RangeNode;
typedef struct RangeMacroApplication RangeMacroApplication;

/* What C's reflection adapter holds in a field of a graph node: a node, a
 * list of nodes, or text, such as a declaration's name. */
typedef enum { RangeGraphNone, RangeGraphNode, RangeGraphNodes, RangeGraphText } RangeGraphValueKind;
typedef struct RangeGraphValue {
    RangeGraphValueKind kind;
    RangeNode *node;
    RangeNode **nodes;
    size_t count;
    const char *text;
} RangeGraphValue;

/* What the compiler finds about one node: the declaration a name or call
 * resolves to, the specialization it has (after narrowing, before
 * promotion), what runs in place of the written form (a case test, or a
 * call: an operator with a body, the @interval construction, a function-call
 * initializer; on a declaration, its value as typing wrote it), the @optional
 * present case a read goes through, whose one field is the payload, the
 * optional a value is wrapped into where it is used, for a call of a generic
 * function or of a generic declaration's method the specialization it runs
 * in, and the found bits.
 * Lowered nodes are compiler-written, point at written children, and are
 * never linked into the tree. */
typedef struct RangeFacts {
    RangeNode *resolvedDeclaration, *type, *lowered, *narrowed, *promoted, *specialization;
    int found;
} RangeFacts;

struct RangeMacroApplication {
    RangeNode *declaration;
    RangeNode *target;
    RangeNode *unit;
    RangeNode *attribute; /* the application site on the target */
    int applied;          /* each application runs once */
    int shaped;           /* its shape-only #graph blocks have landed */
    /* A law run checks the target as one specialization sees it, and emits
     * nothing: that specialization, the member a supplied literal populates
     * and the literal, and how many items the target had as the run began. */
    RangeNode *specialization, *slot, *literal;
    size_t items;
    /* Its arguments: typed once, where the application is written (argued
     * 1, or -1 when they did not type), and their values, computed once at
     * macro time; every run binds them to the macro's parameters. */
    int argued;
    struct RangeValue *arguments;
};

struct RangeNode {
    /* What was written: read once, then never changed. The parser, a parser
     * desugaring, or a #graph block writes these; the guard in the type
     * checker proves nothing changes them after they are read. */
    RangeNodeKind kind;
    const char *path;
    int line;
    int column;
    const char *name;      /* interned, NUL terminated */
    const char *typeName;  /* interned, NUL terminated */
    int flags;             /* written flags */
    long long integer;
    size_t spanStart;   /* raw source span for retained code */
    size_t spanEnd;
    RangeNode *a;
    RangeNode *b;
    RangeNode *c;
    RangeNode *annotations;
    RangeNode *generics; /* declaration Let members or supplied type arguments */
    RangeNode *rhsReference; /* bare RHS identity, resolved like any name */
    /* Complete declaration RHS source range, independent of legacy type slots. */
    size_t rhsStart;
    size_t rhsEnd;
    RangeNode **items;
    size_t itemCount;
    size_t itemCapacity;
    RangeNode *emittedBy; /* macro application whose #graph block produced this node */

    /* What the compiler found: beside the written code, never in it. */
    const char *source;    /* unit owns the text; inspected children borrow it */
    RangeNode *resolvedType; /* resolved literal representation */
    union {
        RangeFacts facts;  /* the node's own findings */
        struct { RangeNode *resolvedDeclaration, *type, *lowered, *narrowed, *promoted, *specialization; int found; };
    };
    size_t size, alignment; /* specialization layout in bytes; layout 0 unknown, 1 computing, 2 done */
    int layout;
    int scalarBits, scalarSigned; /* from the builtin storage and signed members; 0 bits if not a scalar */
    int variantTag; /* union specialization: bytes of its leading tag; 0 for other layouts */
    unsigned char *memberBoxed; /* union specialization: per payload field, stored out of line */
    size_t *memberOffsets;   /* specialization: byte offset per declaration item, SIZE_MAX if not stored */
    struct RangeNode **memberTypes; /* specialization: type per declaration item; NULL for @many storage */
    struct RangeFactTable *keyed; /* specialization: what typing found under it, by node */
    RangeNode **values;  /* specialization: per generic of its declaration, the type or value it holds */
    RangeNode *outer;    /* specialization of a generic method: its receiver's specialization */
    RangeMacroApplication *macroApplication; /* the application this attribute writes */
    RangeNode *graphType; /* C-owned reflective shape, when applicable */
    RangeNode *grammarDefinition; /* loaded language identity for a C-backed node */
    const char *literalPattern; /* validated literal rule, owned by the arena */
    RangeNode *literalDefault; /* unique Core construct for a literal macro */
    RangeNode *receiver; /* method: its implicit receiver declaration, made on first use */
    RangeNode *owner;    /* method: the construct or enum that declares it */
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
RangeNode *rangeGraphType(const RangeArena *arena, const char *name);
void rangeGraphInitTypes(RangeArena *arena);
RangeNode *rangeGraphField(const RangeNode *type, const char *name);
RangeNode *rangeNodeRHS(RangeNode *node);
RangeGraphValue rangeGraphStoredField(RangeArena *arena, RangeNode *node, const char *name);
uint64_t rangeWrittenHash(const RangeNode *node);

#endif
