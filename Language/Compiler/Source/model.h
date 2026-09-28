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
    RangeNodeIf,
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
    RangeFlagChecked = 1 << 10     /* specialization: its laws have run */
};

typedef struct RangeNode RangeNode;
typedef struct RangeMacroApplication RangeMacroApplication;

typedef enum { RangeGraphNone, RangeGraphNode, RangeGraphNodes, RangeGraphText } RangeGraphValueKind;
typedef struct {
    RangeGraphValueKind kind;
    RangeNode *node;
    RangeNode **nodes;
    size_t count;
    const char *text;
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
    RangeMacroApplication *macroApplication; /* application-specific bindings */
    RangeNode *graphType; /* C-owned reflective shape, when applicable */
    RangeNode *grammarDefinition; /* loaded language identity for a C-backed node */
    const char *literalPattern; /* validated literal rule, owned by the arena */
    RangeNode *literalDefault; /* unique Core construct for a literal macro */
    RangeNode *annotations;
    RangeNode *generics; /* declaration Let members or supplied type arguments */
    RangeNode *rhsReference; /* bare RHS identity, resolved like any name */
    RangeNode *emittedBy; /* macro application whose #graph block produced this node */
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
