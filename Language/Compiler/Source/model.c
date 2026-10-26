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
    "let", "state", "derived", "binding", "typeParameter", "parameter", "attribute", "block", "assign",
    "while", "return", "expressionStatement", "call", "argument",
    "memberAccess", "name", "integer", "bool", "string", "stringPart",
    "case", "unary", "binary", "manyLiteral", "environment", "syntaxTemplate",
    "closure", "emission", "switch", "switchCase", "extension", "specialization", "type", "pattern",
    "for", "break", "continue", "functionType", "caseTest"
};

/* let, state, derived, and binding: each names a value in its scope. */
int rangeNodeDeclaresValue(RangeNodeKind kind)
{
    return kind == RangeNodeLet || kind == RangeNodeState
        || kind == RangeNodeDerived || kind == RangeNodeBinding;
}

const char *rangeNodeKindName(RangeNodeKind kind)
{
    if (kind < 0 || kind >= RangeNodeKindCount) return "<invalid>";
    return RANGE_NODE_NAMES[kind];
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
        // receiver, output, and a parameter's type are declarations: the
        // construct or enum that owns the method, or that the written type
        // names. They are absent when the type names a type parameter or
        // nothing declared.
        if (!strcmp(name,"receiver")) return node->owner
            ? (RangeGraphValue){.kind=RangeGraphNode,.node=node->owner} : none;
        if (!strcmp(name,"output")) return node->b && node->b->resolvedDeclaration
            ? (RangeGraphValue){.kind=RangeGraphNode,.node=node->b->resolvedDeclaration} : none;
        if (!strcmp(name,"body")) return node->a
            ? (RangeGraphValue){.kind=RangeGraphNode,.node=node->a} : none;
        if (!strcmp(name,"parameters"))
            return (RangeGraphValue){.kind=RangeGraphNodes,.nodes=node->items,.count=node->itemCount};
    }
    if (!strcmp(name,"type") && node->kind == RangeNodeParameter)
        return node->b && node->b->resolvedDeclaration
            ? (RangeGraphValue){.kind=RangeGraphNode,.node=node->b->resolvedDeclaration} : none;
    if (!strcmp(name,"name")) return node->name
        ? (RangeGraphValue){.kind=RangeGraphText,.text=node->name} : none;
    if (!strcmp(name,"target") && node->kind == RangeNodeMacro)
        return node->b ? (RangeGraphValue){.kind=RangeGraphNode,
            .node=node->b->resolvedDeclaration ? node->b->resolvedDeclaration : node->b} : none;
    if (!strcmp(name,"value") && rangeNodeDeclaresValue(node->kind)) {
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
        || node->kind == RangeNodeFunction || node->kind == RangeNodeEnum)) {
        // The applications a declaration writes, copied: a merge may add more.
        RangeNode result = {0};
        for (size_t i = 0; node->c && i < node->c->itemCount; ++i) rangeNodeAppend(arena,&result,node->c->items[i]);
        return (RangeGraphValue){.kind=RangeGraphNodes,.nodes=result.items,.count=result.itemCount};
    } else if (!strcmp(name,"functions") && (node->kind == RangeNodeConstruct || node->kind == RangeNodeEnum)) {
        RangeNode result = {0};
        for (size_t i = 0; i < node->itemCount; ++i)
            if (node->items[i]->kind == RangeNodeFunction) rangeNodeAppend(arena,&result,node->items[i]);
        return (RangeGraphValue){.kind=RangeGraphNodes,.nodes=result.items,.count=result.itemCount};
    }
    else if (!strcmp(name,"members") && node->kind == RangeNodeConstruct) list = node;
    else if (!strcmp(name,"cases") && node->kind == RangeNodeEnum) list = node;
    else if (!strcmp(name,"members") && node->kind == RangeNodeBlock) {
        RangeNode result = {0};
        for (size_t i = 0; i < node->itemCount; ++i)
            if (rangeNodeDeclaresValue(node->items[i]->kind)) rangeNodeAppend(arena,&result,node->items[i]);
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
        {"Construct","functions",RangeFlagMany|RangeFlagOptional},
        {"Enum","name",0},
        {"Enum","macros",RangeFlagMany|RangeFlagOptional},
        {"Enum","cases",RangeFlagMany|RangeFlagOptional},
        {"Enum","functions",RangeFlagMany|RangeFlagOptional},
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
        {"Let","name",0}, {"Let","value",RangeFlagOptional},
        {"State","name",0}, {"State","value",RangeFlagOptional},
        {"Derived","name",0}, {"Derived","value",RangeFlagOptional},
        {"Binding","name",0}, {"Binding","value",RangeFlagOptional},
        {"TypeParameter","name",0},
        {"Parameter","name",0},
        {"Parameter","type",RangeFlagOptional},
        {"Return","value",RangeFlagOptional},
        {"Block","members",RangeFlagMany|RangeFlagOptional},
        {"Block","graph",RangeFlagMany|RangeFlagOptional}
    };
    arena->graphTypes = rangeNodeCreate(arena,RangeNodeUnit,"<compiler>",1,1);
    for (size_t i = 0; i < sizeof(fields)/sizeof(*fields); ++i) {
        RangeNode *type = rangeGraphType(arena,fields[i].type);
        if (!type) {
            type=rangeNodeCreate(arena,RangeNodeType,"<compiler>",1,1);
            type->name=fields[i].type;
            rangeNodeAppend(arena,arena->graphTypes,type);
        }
        RangeNode *field=rangeNodeCreate(arena,RangeNodeLet,"<compiler>",1,1);
        field->name=fields[i].field; field->flags=fields[i].flags;
        rangeNodeAppend(arena,type,field);
    }
    // A macro's or function's body is a block, with its own reflective shape.
    rangeGraphField(rangeGraphType(arena,"Macro"),"body")->a=rangeGraphType(arena,"Block");
    rangeGraphField(rangeGraphType(arena,"Function"),"body")->a=rangeGraphType(arena,"Block");
}

/* FNV-1a over what a node's author wrote: its kind, written flags, values,
 * names, location, and written children, each child's presence marked.
 * Facts the compiler finds beside the code are not part of it. */
static uint64_t writtenBytes(uint64_t hash, const void *bytes, size_t size)
{
    for (size_t i = 0; i < size; ++i) hash = (hash ^ ((const unsigned char *)bytes)[i]) * 1099511628211ull;
    return hash;
}

static uint64_t writtenText(uint64_t hash, const char *text)
{
    unsigned char present = text != NULL;
    hash = writtenBytes(hash,&present,1);
    return text ? writtenBytes(hash,text,strlen(text) + 1) : hash;
}

static uint64_t writtenNode(uint64_t hash, const RangeNode *node)
{
    unsigned char present = node != NULL;
    hash = writtenBytes(hash,&present,1);
    if (!node) return hash;
    int flags = node->flags & ~RangeFlagFacts;
    hash = writtenBytes(hash,&node->kind,sizeof(node->kind));
    hash = writtenBytes(hash,&flags,sizeof(flags));
    hash = writtenBytes(hash,&node->integer,sizeof(node->integer));
    hash = writtenText(hash,node->name);
    hash = writtenText(hash,node->typeName);
    hash = writtenText(hash,node->path);
    hash = writtenBytes(hash,&node->line,sizeof(node->line));
    hash = writtenBytes(hash,&node->column,sizeof(node->column));
    hash = writtenBytes(hash,&node->spanStart,sizeof(node->spanStart));
    hash = writtenBytes(hash,&node->spanEnd,sizeof(node->spanEnd));
    hash = writtenBytes(hash,&node->rhsStart,sizeof(node->rhsStart));
    hash = writtenBytes(hash,&node->rhsEnd,sizeof(node->rhsEnd));
    hash = writtenNode(hash,node->a);
    hash = writtenNode(hash,node->b);
    hash = writtenNode(hash,node->c);
    hash = writtenNode(hash,node->generics);
    hash = writtenNode(hash,node->annotations);
    hash = writtenNode(hash,node->rhsReference);
    hash = writtenBytes(hash,&node->itemCount,sizeof(node->itemCount));
    for (size_t i = 0; i < node->itemCount; ++i) hash = writtenNode(hash,node->items[i]);
    return hash;
}

uint64_t rangeWrittenHash(const RangeNode *node)
{
    return writtenNode(1469598103934665603ull,node);
}
