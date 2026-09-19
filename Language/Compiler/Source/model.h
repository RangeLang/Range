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
    RangeNodeMember,
    RangeNodeParameter,
    RangeNodeAttribute,
    RangeNodeBlock,
    RangeNodeLocal,
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
    RangeNodeType,
    RangeNodeKindCount
} RangeNodeKind;

enum {
    RangeFlagMany     = 1 << 0,
    RangeFlagMutable  = 1 << 1,  /* state */
    RangeFlagDerived  = 1 << 2,
    RangeFlagBinding  = 1 << 3,
    RangeFlagExtern   = 1 << 4,
    RangeFlagBuiltin  = 1 << 5,
    RangeFlagOptional = 1 << 6,
    RangeFlagLiteral  = 1 << 7,  /* string part is literal text */
    RangeFlagApplication = 1 << 8 /* explicit parentheses, including () */
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
    size_t spanStart;   /* raw source span for @syntax templates */
    size_t spanEnd;
    RangeNode *a;
    RangeNode *b;
    RangeNode *c;
    /* Resolution result: declaration identity, never a name-only dispatch. */
    RangeNode *resolvedDeclaration;
    RangeNode *resolvedType; /* resolved literal representation */
    RangeMacroApplication *macroApplication; /* application-specific bindings */
    RangeNode *graphType; /* C-owned reflective shape, when applicable */
    RangeNode *grammarDefinition; /* loaded Core identity for a C-backed node */
    RangeNode *syntaxCaptures; /* template captures linked to Core fields */
    const char *literalPattern; /* validated literal rule, owned by the arena */
    RangeNode *literalDefault; /* unique Core construct for a literal macro */
    RangeNode *annotations;
    RangeNode *generics; /* declaration Let members or supplied type arguments */
    RangeNode *rhsReference; /* bare RHS identity, resolved like any name */
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
int rangeNodeHasContextReference(const RangeNode *node);
RangeNode *rangeGraphType(const RangeArena *arena, const char *name);
void rangeGraphInitTypes(RangeArena *arena);
RangeNode *rangeGraphField(const RangeNode *type, const char *name);
RangeNode *rangeNodeRHS(RangeNode *node);
RangeGraphValue rangeGraphStoredField(RangeArena *arena, RangeNode *node, const char *name);

#endif
