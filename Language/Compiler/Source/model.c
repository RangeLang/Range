#include "model.h"

#include <stdlib.h>
#include <string.h>

#define RANGE_ARENA_BLOCK (1u << 20)

struct RangeArenaBlock {
    RangeArenaBlock *next;
    size_t used;
    size_t capacity;
    char data[];
};

void rangeArenaInit(RangeArena *arena)
{
    arena->head = NULL;
    arena->nodeCount = 0;
    arena->graphTypes = NULL;
}

void rangeArenaDestroy(RangeArena *arena)
{
    while (arena->head) {
        RangeArenaBlock *next = arena->head->next;
        free(arena->head);
        arena->head = next;
    }
    arena->nodeCount = 0;
    arena->graphTypes = NULL;
}

void *rangeArenaAllocate(RangeArena *arena, size_t size)
{
    size = (size + 15u) & ~(size_t)15u;
    if (!arena->head || arena->head->used + size > arena->head->capacity) {
        size_t capacity = size > RANGE_ARENA_BLOCK ? size : RANGE_ARENA_BLOCK;
        RangeArenaBlock *block = malloc(sizeof(RangeArenaBlock) + capacity);
        if (!block) abort();
        block->next = arena->head;
        block->used = 0;
        block->capacity = capacity;
        arena->head = block;
    }
    void *result = arena->head->data + arena->head->used;
    arena->head->used += size;
    return result;
}

const char *rangeArenaIntern(RangeArena *arena, const char *text, size_t length)
{
    char *copy = rangeArenaAllocate(arena, length + 1);
    memcpy(copy, text, length);
    copy[length] = '\0';
    return copy;
}

RangeNode *rangeNodeCreate(RangeArena *arena, RangeNodeKind kind,
                           const char *path, int line, int column)
{
    RangeNode *node = rangeArenaAllocate(arena, sizeof(RangeNode));
    memset(node, 0, sizeof(*node));
    node->kind = kind;
    node->path = path;
    node->line = line;
    node->column = column;
    arena->nodeCount += 1;
    return node;
}

void rangeNodeAppend(RangeArena *arena, RangeNode *node, RangeNode *item)
{
    if (node->itemCount == node->itemCapacity) {
        size_t capacity = node->itemCapacity ? node->itemCapacity * 2 : 4;
        RangeNode **items = rangeArenaAllocate(arena, capacity * sizeof(RangeNode *));
        if (node->itemCount) {
            memcpy(items, node->items, node->itemCount * sizeof(RangeNode *));
        }
        node->items = items;
        node->itemCapacity = capacity;
    }
    node->items[node->itemCount++] = item;
}

static const char *const RANGE_NODE_NAMES[RangeNodeKindCount] = {
    "unit", "construct", "enum", "enumCase", "function", "macro", "main",
    "member", "parameter", "attribute", "block", "local", "assign", "if",
    "while", "return", "expressionStatement", "call", "argument",
    "memberAccess", "name", "integer", "bool", "string", "stringPart",
    "case", "unary", "binary", "manyLiteral", "environment", "syntaxTemplate",
    "closure", "emission", "switch", "switchCase", "extension", "type"
};

const char *rangeNodeKindName(RangeNodeKind kind)
{
    if (kind < 0 || kind >= RangeNodeKindCount) return "<invalid>";
    return RANGE_NODE_NAMES[kind];
}

int rangeNodeHasContextReference(const RangeNode *node)
{
    if (!node) return 0;
    if (node->kind == RangeNodeEnvironment) return 1;
    if (rangeNodeHasContextReference(node->a) || rangeNodeHasContextReference(node->b)
        || rangeNodeHasContextReference(node->c) || rangeNodeHasContextReference(node->generics)) return 1;
    for (size_t i = 0; i < node->itemCount; ++i)
        if (rangeNodeHasContextReference(node->items[i])) return 1;
    return 0;
}

RangeNode *rangeGraphField(const RangeNode *type, const char *name)
{
    if (type) for (size_t i = 0; i < type->itemCount; ++i)
        if (!strcmp(type->items[i]->name,name)) return type->items[i];
    return NULL;
}

RangeNode *rangeGraphType(const RangeArena *arena, const char *name)
{
    return rangeGraphField(arena->graphTypes,name);
}

RangeNode *rangeNodeRHS(RangeNode *node)
{
    if (node->rhsReference) return node->rhsReference;
    if (node->a) return node->a;
    if (!node->typeName && node->itemCount == 1) return node->items[0]->a;
    return NULL;
}

static void appendGraphBlocks(RangeArena *arena, RangeNode *list, RangeNode *node)
{
    if (!node || node->kind == RangeNodeFunction || node->kind == RangeNodeMacro) return;
    if (node->kind == RangeNodeEmission && node->a && node->a->name
        && !strcmp(node->a->name,"graph")) {
        rangeNodeAppend(arena,list,node);
        return;
    }
    appendGraphBlocks(arena,list,node->a);
    appendGraphBlocks(arena,list,node->b);
    appendGraphBlocks(arena,list,node->c);
    for (size_t i = 0; i < node->itemCount; ++i) appendGraphBlocks(arena,list,node->items[i]);
}

/* Storage adapters expose existing relationships; @type decides which are legal. */
RangeGraphValue rangeGraphStoredField(RangeArena *arena, RangeNode *node, const char *name)
{
    RangeGraphValue none = {0};
    if (!strcmp(name,"body") && node->kind == RangeNodeMacro)
        return node->a ? (RangeGraphValue){.kind=RangeGraphNode,.node=node->a} : none;
    if (!strcmp(name,"parameters") && node->kind == RangeNodeMacro)
        return (RangeGraphValue){.kind=RangeGraphNodes,.nodes=node->items,.count=node->itemCount};
    if (!strcmp(name,"value") && node->kind == RangeNodeReturn)
        return node->a ? (RangeGraphValue){.kind=RangeGraphNode,.node=node->a} : none;
    if (node->kind == RangeNodeFunction) {
        if (!strcmp(name,"receiver")) return node->typeName
            ? (RangeGraphValue){.kind=RangeGraphText,.text=node->typeName} : none;
        if (!strcmp(name,"output")) return node->b
            ? (RangeGraphValue){.kind=RangeGraphNode,
                .node=node->b->resolvedDeclaration ? node->b->resolvedDeclaration : node->b} : none;
        if (!strcmp(name,"body")) return node->a
            ? (RangeGraphValue){.kind=RangeGraphNode,.node=node->a} : none;
        if (!strcmp(name,"parameters"))
            return (RangeGraphValue){.kind=RangeGraphNodes,.nodes=node->items,.count=node->itemCount};
    }
    if (!strcmp(name,"name")) return node->name
        ? (RangeGraphValue){.kind=RangeGraphText,.text=node->name} : none;
    if (!strcmp(name,"target") && node->kind == RangeNodeMacro)
        return node->b ? (RangeGraphValue){.kind=RangeGraphNode,
            .node=node->b->resolvedDeclaration ? node->b->resolvedDeclaration : node->b} : none;
    if (!strcmp(name,"value") && (node->kind == RangeNodeLocal || node->kind == RangeNodeMember)) {
        RangeNode *rhs = rangeNodeRHS(node);
        if (!rhs && node->source && node->rhsEnd > node->rhsStart)
            return (RangeGraphValue){.kind=RangeGraphText,
                .text=rangeArenaIntern(arena,node->source + node->rhsStart,node->rhsEnd - node->rhsStart)};
        return rhs ? (RangeGraphValue){.kind=RangeGraphNode,.node=rhs} : none;
    }
    RangeNode *list = NULL;
    if (!strcmp(name,"generics") && (node->kind == RangeNodeConstruct || node->kind == RangeNodeMacro || node->kind == RangeNodeFunction))
        list = node->generics;
    else if (!strcmp(name,"macros") && (node->kind == RangeNodeConstruct || node->kind == RangeNodeMacro
        || node->kind == RangeNodeFunction || node->kind == RangeNodeEnum))
        list = node->c;
    else if (!strcmp(name,"members") && node->kind == RangeNodeConstruct) list = node;
    else if (!strcmp(name,"cases") && node->kind == RangeNodeEnum) list = node;
    else if (!strcmp(name,"members") && node->kind == RangeNodeBlock) {
        RangeNode result = {0};
        for (size_t i = 0; i < node->itemCount; ++i)
            if (node->items[i]->kind == RangeNodeLocal) rangeNodeAppend(arena,&result,node->items[i]);
        return (RangeGraphValue){.kind=RangeGraphNodes,.nodes=result.items,.count=result.itemCount};
    } else if (!strcmp(name,"graph") && node->kind == RangeNodeBlock) {
        RangeNode result = {0};
        appendGraphBlocks(arena,&result,node);
        return (RangeGraphValue){.kind=RangeGraphNodes,.nodes=result.items,.count=result.itemCount};
    } else return none;
    return (RangeGraphValue){.kind=RangeGraphNodes,.nodes=list ? list->items : NULL,.count=list ? list->itemCount : 0};
}

/* C owns node shape and reflective field access. No source templates are loaded. */
void rangeGraphInitTypes(RangeArena *arena)
{
    static const struct { const char *type, *field; int flags; } fields[] = {
        {"Construct","name",0},
        {"Construct","macros",RangeFlagMany|RangeFlagOptional},
        {"Construct","generics",RangeFlagMany|RangeFlagOptional},
        {"Construct","members",RangeFlagMany|RangeFlagOptional},
        {"Enum","name",0},
        {"Enum","macros",RangeFlagMany|RangeFlagOptional},
        {"Enum","cases",RangeFlagMany|RangeFlagOptional},
        {"EnumCase","name",0},
        {"Function","name",0},
        {"Function","macros",RangeFlagMany|RangeFlagOptional},
        {"Function","receiver",RangeFlagOptional},
        {"Function","generics",RangeFlagMany|RangeFlagOptional},
        {"Function","parameters",RangeFlagMany|RangeFlagOptional},
        {"Function","output",RangeFlagOptional},
        {"Function","body",RangeFlagOptional},
        {"Macro","name",0},
        {"Macro","macros",RangeFlagMany|RangeFlagOptional},
        {"Macro","generics",RangeFlagMany|RangeFlagOptional},
        {"Macro","target",RangeFlagOptional},
        {"Macro","parameters",RangeFlagMany|RangeFlagOptional},
        {"Macro","body",RangeFlagOptional},
        {"Member","name",0}, {"Member","value",RangeFlagOptional},
        {"Return","value",RangeFlagOptional},
        {"Macro.body","members",RangeFlagMany|RangeFlagOptional},
        {"Macro.body","graph",RangeFlagMany|RangeFlagOptional}
    };
    arena->graphTypes = rangeNodeCreate(arena,RangeNodeUnit,"<compiler>",1,1);
    for (size_t i = 0; i < sizeof(fields)/sizeof(*fields); ++i) {
        RangeNode *type = rangeGraphType(arena,fields[i].type);
        if (!type) {
            type=rangeNodeCreate(arena,RangeNodeType,"<compiler>",1,1);
            type->name=fields[i].type;
            rangeNodeAppend(arena,arena->graphTypes,type);
        }
        RangeNode *field=rangeNodeCreate(arena,RangeNodeMember,"<compiler>",1,1);
        field->name=fields[i].field; field->flags=fields[i].flags;
        rangeNodeAppend(arena,type,field);
    }
    rangeGraphField(rangeGraphType(arena,"Macro"),"body")->a=rangeGraphType(arena,"Macro.body");
}
