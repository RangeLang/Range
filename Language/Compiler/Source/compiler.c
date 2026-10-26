#define _XOPEN_SOURCE 700
#include "model.h"
#include "native.h"
#include <ctype.h>
#include <limits.h>
#include <regex.h>
#include <setjmp.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

struct SourceReport;
static void sourceDiagnostic(struct SourceReport *, RangeNode *, int, const char *, const char *, ...);
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
    int skipEmission;   /* law runs per specialization check; emission stays on the declaration */
    struct SourceReport *report; /* where @warning reports, when compiling */
    Typer *typer; /* alive from before the first application to the end of type checking */
    size_t checked; /* applications run */
} Resolver;

static int same(const char *a, const char *b) { return a && b && !strcmp(a,b); }

_Noreturn static void fail(Resolver *vm, RangeNode *at, const char *format, ...)
{
    char detail[384]; va_list args; va_start(args,format);
    vsnprintf(detail,sizeof(detail),format,args); va_end(args);
    snprintf(vm->error,vm->errorSize,"%s:%d:%d: %s",
        at ? at->path : "<compiler>",at ? at->line : 1,at ? at->column : 1,detail);
    longjmp(vm->failure,1);
}

static RangeNode *graphTypeIdentity(RangeNode *node)
{
    return node->grammarDefinition ? node->grammarDefinition : node->graphType;
}

static int appliesMacro(const RangeNode *, const RangeNode *);

/* Names select candidates; the declared target identity selects an application. */
static RangeNode *resolveMacroDeclaration(Resolver *vm, RangeNode *attribute,
                                          RangeNode *target, RangeNode **owner)
{
    RangeNode *macro = NULL;
    RangeNode *type = graphTypeIdentity(target);
    int named = 0;
    for (size_t u = 0; u < vm->count; ++u) for (size_t m = 0; m < vm->units[u]->itemCount; ++m) {
        RangeNode *candidate = vm->units[u]->items[m];
        if (candidate->kind != RangeNodeMacro || !same(candidate->name,attribute->name)) continue;
        named = 1;
        if (!candidate->b || !type) continue;
        RangeNode *wanted = candidate->b->resolvedDeclaration;
        if (wanted != type && !((candidate->b->flags & RangeFlagMacroType) && appliesMacro(type,wanted))) continue;
        if (macro) fail(vm,attribute,"ambiguous graph macro '%s' for target %s",attribute->name,type->name);
        macro = candidate;
        if (owner) *owner = vm->units[u];
    }
    if (!macro) {
        if (named) fail(vm,attribute,"no macro '%s' targets %s",attribute->name,
            type ? type->name : rangeNodeKindName(target->kind));
        fail(vm,attribute,"unresolved graph macro '%s'",attribute->name);
    }
    attribute->resolvedDeclaration = macro;
    return macro;
}

static int macroBuiltin(RangeNode *, const char *);

/* The grammar declaration of a node's kind: the language's, or, in sources
 * without the language grammar, a top-level construct named like the kind. */
static RangeNode *grammarDeclaration(Resolver *vm, RangeNode *node)
{
    if (node->grammarDefinition) return node->grammarDefinition;
    if (!node->graphType) return NULL;
    RangeNode *found = NULL;
    for (size_t u = 0; u < vm->count; ++u) for (size_t i = 0; i < vm->units[u]->itemCount; ++i) {
        RangeNode *candidate = vm->units[u]->items[i];
        if (candidate->kind != RangeNodeConstruct || !same(candidate->name,node->graphType->name)) continue;
        if (found) return NULL;
        found = candidate;
    }
    return found;
}

/* One application site on a target: its macro declaration, selected by name
 * and the target's type. */
static void resolveApplication(Resolver *vm, RangeNode *target, RangeNode *attribute)
{
    RangeNode *unit = NULL;
    attribute->macroApplication = NULL;
    if (same(attribute->name,"builtin")
        || (target->kind == RangeNodeFunction && same(attribute->name,"extern"))) return;
    RangeNode *macro = resolveMacroDeclaration(vm,attribute,target,&unit);
    if (macroBuiltin(macro,"literal")) return; /* a registered compiler primitive */
    if (attribute->itemCount || macro->itemCount)
        fail(vm,attribute,"parameterized macro graph resolution is not implemented");
    RangeMacroApplication *app = rangeArenaAllocate(vm->arena,sizeof(*app));
    *app = (RangeMacroApplication){.declaration=macro,.target=target,.unit=unit,.attribute=attribute};
    attribute->resolvedDeclaration = macro;
    attribute->macroApplication = app;
}

static void resolveGraphTarget(Resolver *vm, RangeNode *target)
{
    if (!target->graphType) return;
    RangeNode *attributes = target->c;
    if (attributes) for (size_t a = 0; a < attributes->itemCount; ++a)
        resolveApplication(vm,target,attributes->items[a]);
    if (target->kind == RangeNodeConstruct || target->kind == RangeNodeEnum)
        for (size_t i = 0; i < target->itemCount; ++i) resolveGraphTarget(vm,target->items[i]);
}

static size_t graphValueCount(RangeGraphValue value)
{
    return value.kind == RangeGraphNone ? 0 : value.kind == RangeGraphNodes ? value.count : 1;
}

static void validateGraphShape(Resolver *vm, RangeNode *node, const char *source)
{
    if (!node) return;
    if (node->kind == RangeNodeUnit) source = node->source;
    else node->source = source;
    const char *type = node->kind == RangeNodeMacro ? "Macro"
        : node->kind == RangeNodeConstruct ? "Construct"
        : node->kind == RangeNodeEnum ? "Enum"
        : node->kind == RangeNodeEnumCase ? "EnumCase"
        : node->kind == RangeNodeFunction ? "Function"
        : node->kind == RangeNodeReturn ? "Return"
        : node->kind == RangeNodeLet ? "Let" : node->kind == RangeNodeState ? "State"
        : node->kind == RangeNodeDerived ? "Derived" : node->kind == RangeNodeBinding ? "Binding"
        : node->kind == RangeNodeTypeParameter ? "TypeParameter"
        : node->kind == RangeNodeParameter ? "Parameter" : NULL;
    if (type) {
        node->graphType = rangeGraphType(vm->arena,type);
        if (!node->graphType) fail(vm,node,"missing @type %s",type);
    }
    if (node->graphType) {
        type = node->graphType->name;
        /* These are physical storage adapters, not a list of permitted fields. */
        static const char *const storage[] = {"name","target","members","graph","macros","generics","value",
            "receiver","parameters","output","body","cases","functions","type"};
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
static const char *literalString(Resolver *vm, RangeNode *node)
{
    if (!node || node->kind != RangeNodeString || node->itemCount != 1
        || !(node->items[0]->flags & RangeFlagLiteral))
        fail(vm,node,"literal pattern requires a non-interpolated string");
    return node->items[0]->name;
}

/* Each literal pattern is compiled once per process; every literal in the
 * program is matched against the compiled form. */
static regex_t *literalRegex(Resolver *vm, RangeNode *at, const char *pattern)
{
    static struct { char *pattern; regex_t regex; } cache[32];
    static size_t cached;
    for (size_t i = 0; i < cached; ++i) if (!strcmp(cache[i].pattern,pattern)) return &cache[i].regex;
    regex_t regex;
    int code = regcomp(&regex,pattern,REG_EXTENDED);
    if (code) {
        char detail[256];
        regerror(code,&regex,detail,sizeof(detail));
        fail(vm,at,"invalid literal regex: %s",detail);
    }
    if (cached == sizeof(cache)/sizeof(*cache)) { regfree(&cache[0].regex); free(cache[0].pattern); cache[0] = cache[--cached]; }
    char *copy = strdup(pattern);
    if (!copy) abort();
    cache[cached].pattern = copy;
    cache[cached].regex = regex;
    return &cache[cached++].regex;
}

static int literalMatch(Resolver *vm, RangeNode *at, const char *pattern, const char *input)
{
    regex_t *regex = literalRegex(vm,at,pattern);
    regmatch_t match;
    int code = input ? regexec(regex,input,1,&match,0) : REG_NOMATCH;
    if (code && code != REG_NOMATCH) {
        char detail[256];
        regerror(code,regex,detail,sizeof(detail));
        fail(vm,at,"literal regex matching failed: %s",detail);
    }
    return !code && match.rm_so == 0 && match.rm_eo >= 0 && (size_t)match.rm_eo == strlen(input);
}

/* A builtin macro is `@builtin macro name`; its name selects the C primitive. */
static int macroBuiltin(RangeNode *node, const char *name)
{
    if (!node || node->kind != RangeNodeMacro || !node->c || !same(node->name,name)) return 0;
    for (size_t i = 0; i < node->c->itemCount; ++i)
        if (same(node->c->items[i]->name,"builtin")) return 1;
    return 0;
}

/* A role marks the function C calls for a construct: @iteration for `for … in`
 * and @insertion for building reflection lists. Applying one has no
 * compile-time effect. */
static int roleMacro(RangeNode *node)
{
    return macroBuiltin(node,"iteration") || macroBuiltin(node,"insertion");
}

static void registerLiteralRules(Resolver *vm)
{
    RangeNode *builtin = NULL;
    for (size_t u = 0; u < vm->count; ++u) for (size_t i = 0; i < vm->units[u]->itemCount; ++i) {
        RangeNode *node = vm->units[u]->items[i];
        if (!macroBuiltin(node,"literal")) continue;
        if (builtin) fail(vm,node,"ambiguous literal builtin");
        if (!node->b || !same(node->b->name,"Macro") || node->itemCount != 1
            || !node->items[0]->b || node->a)
            fail(vm,node,"literal builtin requires one pattern parameter, target Macro, and no body");
        builtin = node;
    }
    for (size_t u = 0; u < vm->count; ++u) for (size_t i = 0; i < vm->units[u]->itemCount; ++i) {
        RangeNode *node = vm->units[u]->items[i];
        node->literalPattern = NULL;
        if (!node->c) continue;
        for (size_t j = 0; j < node->c->itemCount; ++j) {
            RangeNode *a = node->c->items[j];
            if (!builtin || !same(a->name,builtin->name)) continue;
            if (resolveMacroDeclaration(vm,a,node,NULL) != builtin) continue;
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

#ifndef RANGE_LANGUAGE_DIR
#define RANGE_LANGUAGE_DIR "Language"
#endif

static int isLanguageNode(const RangeNode *node)
{
    static const char *const directories[] = {
        RANGE_LANGUAGE_DIR "/Grammar", RANGE_LANGUAGE_DIR "/Macros", RANGE_LANGUAGE_DIR "/Types"
    };
    if (!node->path) return 0;
    for (size_t i = 0; i < sizeof(directories)/sizeof(*directories); ++i) {
        size_t length = strlen(directories[i]);
        if (!strncmp(node->path,directories[i],length) && node->path[length] == '/') return 1;
    }
    return 0;
}

/* A macro type @name admits declarations that applied that macro. */
static int appliesMacro(const RangeNode *declaration, const RangeNode *macro)
{
    if (!declaration || !declaration->c || !macro) return 0;
    for (size_t i = 0; i < declaration->c->itemCount; ++i) {
        const RangeNode *attribute = declaration->c->items[i];
        if (same(attribute->name,macro->name)
            && (!attribute->resolvedDeclaration || attribute->resolvedDeclaration == macro)) return 1;
    }
    return 0;
}

static RangeNode *macroType(Resolver *vm, RangeNode *at, const char *name)
{
    RangeNode *found = NULL;
    for (size_t u = 0; u < vm->count; ++u) for (size_t i = 0; i < vm->units[u]->itemCount; ++i) {
        RangeNode *candidate = vm->units[u]->items[i];
        if (candidate->kind != RangeNodeMacro || !same(candidate->name,name)) continue;
        if (found) fail(vm,at,"ambiguous macro type '@%s'",name);
        found = candidate;
    }
    if (!found) fail(vm,at,"unknown macro type '@%s'",name);
    return found;
}

/* #field must exist on the target type, or on every kind a macro type admits. */
static void validateTargetReferences(Resolver *vm, RangeNode *node, RangeNode *type, RangeNode *nominal)
{
    if (!node || node->kind == RangeNodeEmission) return; /* deferred code */
    if (node->kind == RangeNodeEnvironment && nominal) {
        size_t kinds = 0;
        RangeNode *shapes = vm->arena->graphTypes;
        for (size_t i = 0; i < shapes->itemCount; ++i) {
            RangeNode *shape = shapes->items[i];
            if (!appliesMacro(shape->resolvedDeclaration,nominal)) continue;
            ++kinds;
            if (!rangeGraphField(shape,node->name))
                fail(vm,node,"field '%s' is not declared by %s, which applies @%s",node->name,shape->name,nominal->name);
        }
        if (!kinds) fail(vm,node,"no declaration kind applies @%s",nominal->name);
    } else if (node->kind == RangeNodeEnvironment) {
        if (!type) fail(vm,node,"#%s requires a declared macro target",node->name);
        if (!rangeGraphField(type,node->name))
            fail(vm,node,"field '%s' is not declared by @type %s",node->name,type->name);
    }
    validateTargetReferences(vm,node->a,type,nominal); validateTargetReferences(vm,node->b,type,nominal);
    validateTargetReferences(vm,node->c,type,nominal); validateTargetReferences(vm,node->generics,type,nominal);
    for (size_t i = 0; i < node->itemCount; ++i) validateTargetReferences(vm,node->items[i],type,nominal);
}

static int spliceChain(const RangeNode *);

/* Whether quoted code splices only bare target fields, each a single node
 * of the target's shape that no parameter or top-level local of the macro
 * shadows. A nested macro's splices are its own. */
static int shapeSplices(const RangeNode *macro, const RangeNode *shape, const RangeNode *node)
{
    if (!node || node->kind == RangeNodeMacro) return 1;
    if (spliceChain(node)) {
        const RangeNode *field = node->kind == RangeNodeEnvironment ? rangeGraphField(shape,node->name) : NULL;
        if (!field || (field->flags & (RangeFlagMany | RangeFlagOptional))) return 0;
        for (size_t i = 0; i < macro->itemCount; ++i) if (same(macro->items[i]->name,node->name)) return 0;
        for (size_t i = 0; i < macro->a->itemCount; ++i)
            if (rangeNodeDeclaresValue(macro->a->items[i]->kind) && same(macro->a->items[i]->name,node->name)) return 0;
        return 1;
    }
    if (!shapeSplices(macro,shape,node->a) || !shapeSplices(macro,shape,node->b) || !shapeSplices(macro,shape,node->c)
        || !shapeSplices(macro,shape,node->generics) || !shapeSplices(macro,shape,node->annotations)
        || !shapeSplices(macro,shape,node->rhsReference)) return 0;
    for (size_t i = 0; i < node->itemCount; ++i) if (!shapeSplices(macro,shape,node->items[i])) return 0;
    return 1;
}

/* A #graph block written as a statement of the macro's body, outside any
 * switch, loop, or closure, whose splices read only the target's shape:
 * what it emits depends on nothing the body computes, so it is emitted
 * before any macro body runs. */
static void markShapeBlocks(RangeNode *macro, const RangeNode *shape)
{
    for (size_t i = 0; shape && macro->a && i < macro->a->itemCount; ++i) {
        RangeNode *statement = macro->a->items[i];
        RangeNode *emission = statement->kind == RangeNodeExpressionStatement ? statement->a : NULL;
        if (emission && emission->kind == RangeNodeEmission && shapeSplices(macro,shape,emission->b))
            emission->flags |= RangeFlagShape;
    }
}

static void linkGrammarNodes(Resolver *vm, RangeNode *node)
{
    if (!node) return;
    node->grammarDefinition = node->graphType ? node->graphType->resolvedDeclaration : NULL;
    if (node->kind == RangeNodeMacro) {
        RangeNode *shape = NULL, *nominal = NULL;
        if (node->b) {
            if ((node->b->flags & ~RangeFlagMacroType) || node->b->generics)
                fail(vm,node->b,"macro target requires one declaration type");
            if (node->b->flags & RangeFlagMacroType) {
                nominal = macroType(vm,node->b,node->b->name);
                node->b->resolvedDeclaration = nominal;
            } else {
                shape = rangeGraphType(vm->arena,node->b->name);
                if (!shape) fail(vm,node->b,"unknown macro target type '%s'",node->b->name);
                node->b->resolvedDeclaration = shape->resolvedDeclaration ? shape->resolvedDeclaration : shape;
            }
        }
        validateTargetReferences(vm,node->a,shape,nominal);
        markShapeBlocks(node,shape);
    }
    linkGrammarNodes(vm,node->a); linkGrammarNodes(vm,node->b); linkGrammarNodes(vm,node->c);
    linkGrammarNodes(vm,node->generics); linkGrammarNodes(vm,node->annotations);
    for (size_t i = 0; i < node->itemCount; ++i) linkGrammarNodes(vm,node->items[i]);
}

/* C parses structure; ordinary language declarations supply node identities. */
static void registerGrammarDefinitions(Resolver *vm)
{
    for (size_t i = 0; i < vm->arena->graphTypes->itemCount; ++i)
        vm->arena->graphTypes->items[i]->resolvedDeclaration = NULL;
    for (size_t u = 0; u < vm->count; ++u) for (size_t i = 0; i < vm->units[u]->itemCount; ++i) {
        RangeNode *definition = vm->units[u]->items[i];
        if (definition->kind != RangeNodeConstruct || !isLanguageNode(definition)) continue;
        RangeNode *shape = rangeGraphType(vm->arena,definition->name);
        if (!shape) continue;
        if (shape->resolvedDeclaration)
            fail(vm,definition,"ambiguous language grammar construct '%s'",definition->name);
        for (size_t j = 0; j < definition->itemCount; ++j) {
            RangeNode *field = definition->items[j];
            if (!rangeNodeDeclaresValue(field->kind) || !rangeGraphField(shape,field->name))
                fail(vm,field,"no C field adapter for %s.%s",definition->name,field->name ? field->name : "<unnamed>");
            for (size_t k = 0; k < j; ++k)
                if (same(definition->items[k]->name,field->name))
                    fail(vm,field,"duplicate language grammar field '%s'",field->name);
        }
        shape->resolvedDeclaration = definition;
    }
    for (size_t u = 0; u < vm->count; ++u) linkGrammarNodes(vm,vm->units[u]);
}

static void registerLiteralDefaults(Resolver *vm)
{
    for (size_t u = 0; u < vm->count; ++u) for (size_t i = 0; i < vm->units[u]->itemCount; ++i) {
        RangeNode *macro = vm->units[u]->items[i];
        macro->literalDefault = NULL;
        if (macro->kind != RangeNodeMacro || !macro->literalPattern || !isLanguageNode(macro)) continue;
        for (size_t v = 0; v < vm->count; ++v) for (size_t j = 0; j < vm->units[v]->itemCount; ++j) {
            RangeNode *construct = vm->units[v]->items[j];
            if ((construct->kind != RangeNodeConstruct && construct->kind != RangeNodeEnum)
                || !isLanguageNode(construct) || !construct->c) continue;
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

/* A string literal's spelling is its quoted source text, interpolation included. */
static const char *stringSpelling(Resolver *vm, const RangeNode *node)
{
    if (!node->source || node->spanEnd <= node->spanStart) return NULL;
    return rangeArenaIntern(vm->arena,node->source + node->spanStart,node->spanEnd - node->spanStart);
}

static void resolveLiteralDefaults(Resolver *vm, RangeNode *node)
{
    if (!node) return;
    if (node->kind == RangeNodeInteger || node->kind == RangeNodeBool || node->kind == RangeNodeString) {
        const char *spelling = node->kind == RangeNodeBool ? (node->integer ? "true" : "false")
            : node->kind == RangeNodeString ? stringSpelling(vm,node) : node->name;
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

static int resolveGraphApplications(RangeArena *, RangeNode **, size_t, char *, size_t);

static int matchLiteralRule(RangeArena *arena, RangeNode **units, size_t count,
    const char *name, const char *input, int *matched, char *error, size_t errorSize)
{
    if (!resolveGraphApplications(arena,units,count,error,errorSize)) return 0;
    Resolver *vm = calloc(1,sizeof(*vm));
    if (!vm) { snprintf(error,errorSize,"cannot allocate literal matcher"); return 0; }
    vm->arena=arena; vm->units=units; vm->count=count; vm->error=error; vm->errorSize=errorSize;
    int ok = 0;
    if (setjmp(vm->failure) == 0) {
        RangeNode *macro = NULL;
        for (size_t u = 0; u < count; ++u) for (size_t i = 0; i < units[u]->itemCount; ++i) {
            RangeNode *node = units[u]->items[i];
            if (node->kind != RangeNodeMacro || !same(node->name,name) || !node->literalPattern) continue;
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

static RangeNode *nestedDeclaration(RangeNode *, const char *, size_t);
static int appliesBuiltin(const RangeNode *, const char *);

/* The constructs and enums enclosing `node`, innermost first. */
static int enclosing(RangeNode *within, RangeNode *node, RangeNode **chain, size_t *count, size_t capacity)
{
    for (size_t i = 0; i < within->itemCount; ++i) {
        RangeNode *item = within->items[i];
        if (item == node) return 1;
        if (item->kind != RangeNodeConstruct && item->kind != RangeNodeEnum) continue;
        if (enclosing(item,node,chain,count,capacity)) {
            if (*count < capacity) chain[(*count)++] = item;
            return 1;
        }
    }
    return 0;
}

/* The construct or enum a written type names, seen from `from`: a scope's own
 * name, its type parameters, and its nested types, from the innermost scope
 * out, then the program's top-level declarations. A type parameter names no
 * declaration; `T?` names the declaration applying @optional. */
static RangeNode *namedDeclaration(Resolver *vm, RangeNode *from, const char *name, int flags,
                                   RangeNode *at, const char *what)
{
    if (!name || !*name || (flags & (RangeFlagMacroType | RangeFlagMany))) return NULL;
    RangeNode *found = NULL;
    if (flags & RangeFlagOptional) {
        for (size_t u = 0; u < vm->count; ++u) for (size_t i = 0; i < vm->units[u]->itemCount; ++i) {
            RangeNode *candidate = vm->units[u]->items[i];
            if ((candidate->kind != RangeNodeConstruct && candidate->kind != RangeNodeEnum)
                || !appliesBuiltin(candidate,"optional")) continue;
            if (found) return NULL; /* reported where the type is checked */
            found = candidate;
        }
        return found;
    }
    const char *dot = strchr(name,'.');
    size_t length = dot ? (size_t)(dot - name) : strlen(name);
    RangeNode *chain[32];
    size_t count = 0;
    if (from) {
        chain[count++] = from;
        for (size_t u = 0; u < vm->count; ++u) if (enclosing(vm->units[u],from,chain,&count,32)) break;
    }
    for (size_t i = 0; i < count && !found; ++i) {
        RangeNode *scope = chain[i];
        if ((scope->kind == RangeNodeConstruct || scope->kind == RangeNodeEnum) && scope->name
            && !strncmp(scope->name,name,length) && !scope->name[length]) { found = scope; break; }
        for (size_t j = 0; scope->generics && j < scope->generics->itemCount; ++j) {
            RangeNode *generic = scope->generics->items[j];
            if (generic->kind == RangeNodeTypeParameter && generic->name
                && !strncmp(generic->name,name,length) && !generic->name[length]) return NULL;
        }
        found = nestedDeclaration(scope,name,length);
    }
    for (size_t u = 0; u < vm->count && !found; ++u) for (size_t i = 0; i < vm->units[u]->itemCount; ++i) {
        RangeNode *candidate = vm->units[u]->items[i];
        if ((candidate->kind != RangeNodeConstruct && candidate->kind != RangeNodeEnum) || !candidate->name
            || strncmp(candidate->name,name,length) || candidate->name[length]) continue;
        for (size_t v = u, k = i + 1; v < vm->count; ++v, k = 0) for (; k < vm->units[v]->itemCount; ++k) {
            RangeNode *other = vm->units[v]->items[k];
            if ((other->kind == RangeNodeConstruct || other->kind == RangeNodeEnum) && other->name
                && !strncmp(other->name,name,length) && !other->name[length])
                fail(vm,at,"ambiguous %s '%s'",what,name);
        }
        found = candidate;
        break;
    }
    while (found && dot) {
        const char *next = strchr(dot + 1,'.');
        found = nestedDeclaration(found,dot + 1,next ? (size_t)(next - dot - 1) : strlen(dot + 1));
        dot = next;
    }
    return found;
}

/* A function's output and parameter types link to the constructs and enums
 * they name, and a method to its owner, without replacing source nodes; the
 * graph exposes them as Function.output, Parameter.type, and
 * Function.receiver. Missing declarations stay unlinked here and are
 * reported where they are checked. */
static void resolveSignatureTypes(Resolver *vm, RangeNode *node, RangeNode *owner)
{
    if (!node) return;
    if (node->kind == RangeNodeFunction) {
        if (owner) node->owner = owner;
        RangeNode *output = node->b;
        if (output && output->kind == RangeNodeName)
            output->resolvedDeclaration = namedDeclaration(vm,node,output->name,output->flags,output,"graph output");
        for (size_t i = 0; i < node->itemCount; ++i) {
            RangeNode *parameter = node->items[i];
            if (parameter->kind == RangeNodeParameter && parameter->b && parameter->b->kind == RangeNodeName)
                parameter->b->resolvedDeclaration = namedDeclaration(vm,node,parameter->b->name,parameter->flags,parameter->b,"parameter type");
        }
        return;
    }
    if (node->kind != RangeNodeUnit && node->kind != RangeNodeConstruct && node->kind != RangeNodeEnum) return;
    for (size_t i = 0; i < node->itemCount; ++i)
        resolveSignatureTypes(vm,node->items[i],node->kind == RangeNodeUnit ? NULL : node);
}

/* An application of a macro without a target (an effect such as @print) is a
 * statement of its own, even when it precedes a declaration it would
 * otherwise appear to annotate. */
static int effectMacro(Resolver *vm, const char *name)
{
    for (size_t u = 0; u < vm->count; ++u) for (size_t i = 0; i < vm->units[u]->itemCount; ++i) {
        RangeNode *node = vm->units[u]->items[i];
        if (node->kind == RangeNodeMacro && !node->b && same(node->name,name)) return 1;
    }
    return 0;
}

static void separateEffects(Resolver *vm, RangeNode *node)
{
    if (!node) return;
    if (node->kind == RangeNodeBlock) {
        for (size_t i = 0; i < node->itemCount; ++i) {
            RangeNode *statement = node->items[i], *annotations = statement->annotations;
            if (!annotations) continue;
            size_t kept = 0, moved = 0;
            for (size_t j = 0; j < annotations->itemCount; ++j) {
                RangeNode *attribute = annotations->items[j];
                if (!effectMacro(vm,attribute->name)) { annotations->items[kept++] = attribute; continue; }
                RangeNode *effect = rangeNodeCreate(vm->arena,RangeNodeExpressionStatement,attribute->path,attribute->line,attribute->column);
                effect->a = attribute;
                // Insert before the statement, keeping source order.
                rangeNodeAppend(vm->arena,node,effect);
                memmove(node->items + i + moved + 1,node->items + i + moved,(node->itemCount - 1 - i - moved) * sizeof(*node->items));
                node->items[i + moved] = effect;
                ++moved;
            }
            annotations->itemCount = kept;
            if (!kept) statement->annotations = NULL;
            i += moved;
        }
    }
    separateEffects(vm,node->a); separateEffects(vm,node->b); separateEffects(vm,node->c);
    for (size_t i = 0; i < node->itemCount; ++i) separateEffects(vm,node->items[i]);
}

static int resolveGraphApplications(RangeArena *arena, RangeNode **units, size_t count,
                                    char *error, size_t errorSize)
{
    Resolver *vm = calloc(1,sizeof(*vm));
    if (!vm) { snprintf(error,errorSize,"cannot allocate graph resolver"); return 0; }
    vm->arena=arena; vm->units=units; vm->count=count; vm->error=error; vm->errorSize=errorSize;
    int ok = 0;
    if (setjmp(vm->failure) == 0) {
        for (size_t u = 0; u < count; ++u) separateEffects(vm,units[u]);
        for (size_t u = 0; u < count; ++u) validateGraphShape(vm,units[u],units[u]->source);
        registerGrammarDefinitions(vm);
        registerLiteralRules(vm);
        // Signature types link before macro bindings read them, and again once
        // applications are resolved, which `T?` (the @optional enum) needs.
        for (size_t u = 0; u < count; ++u) resolveSignatureTypes(vm,units[u],NULL);
        for (size_t u = 0; u < count; ++u)
            for (size_t i = 0; i < units[u]->itemCount; ++i) resolveGraphTarget(vm,units[u]->items[i]);
        for (size_t u = 0; u < count; ++u) resolveSignatureTypes(vm,units[u],NULL);
        registerLiteralDefaults(vm);
        for (size_t u = 0; u < count; ++u) resolveLiteralDefaults(vm,units[u]);
        ok = 1;
    }
    free(vm);
    return ok;
}

/* A splice is a #name chain such as #element or #element.name; the whole
 * chain runs at macro time. `#name(…)` calls the spliced name where the code
 * lands: only the name is spliced. */
static int spliceChain(const RangeNode *node)
{
    while (node && (node->kind == RangeNodeMemberAccess || node->kind == RangeNodeCall)) {
        if (node->kind == RangeNodeCall && node->a && node->a->kind == RangeNodeEnvironment) return 0;
        node = node->a;
    }
    return node && node->kind == RangeNodeEnvironment;
}

/* `let x: #element` becomes `let x: Element`: a spliced name in a
 * declaration RHS takes the type position, as the parser would place it. */
static void spliceDeclarationType(RangeNode *copy, const RangeNode *original)
{
    if (!rangeNodeDeclaresValue(copy->kind) || copy->typeName
        || copy->itemCount != 1 || copy->items[0]->kind != RangeNodeArgument
        || !spliceChain(original->items[0]->a) || copy->items[0]->a->kind != RangeNodeName) return;
    RangeNode *reference = copy->items[0]->a;
    copy->typeName = reference->name;
    copy->itemCount = 0;
    if (!copy->flags) copy->rhsReference = reference;
}

/* The parameter a trailing closure fills: the function's last function-typed
 * parameter, SIZE_MAX when it has none. */
static size_t trailingParameter(const RangeNode *function)
{
    for (size_t i = function->itemCount; i-- > 0;)
        if (function->items[i]->flags & RangeFlagFunction) return i;
    return SIZE_MAX;
}

/* An argument fits a parameter by its label, or, written as a trailing
 * closure, `xs.filter { m in … }`, by being the last function-typed one. */
static int argumentFits(const RangeNode *argument, const RangeNode *function, size_t index)
{
    if (same(argument->name,function->items[index]->name)) return 1;
    return !argument->name && (argument->flags & RangeFlagImplicit) && trailingParameter(function) == index;
}

/* The function a construct or enum declares with @insertion, which C calls to
 * build a reflection list; *count is how many it declares. The role, not a
 * name, selects it. */
static RangeNode *insertionFunction(const RangeNode *declaration, size_t *count)
{
    RangeNode *found = NULL;
    *count = 0;
    if (declaration && (declaration->kind == RangeNodeConstruct || declaration->kind == RangeNodeEnum))
        for (size_t i = 0; i < declaration->itemCount; ++i)
            if (declaration->items[i]->kind == RangeNodeFunction && appliesBuiltin(declaration->items[i],"insertion")) {
                found = declaration->items[i];
                ++*count;
            }
    return found;
}

/* ---- case tests ----
 * `phase.loading` and `phase.failed(let reason)` read a case off a value: a
 * Bool, true when the value holds that case. Inside the parentheses each
 * argument is a pattern for its payload field: `let x` binds it, `_` ignores
 * it, `.case(…)` tests it in turn, and any other expression is a value the
 * field must equal, by its type's `=`. Inside an enum's own functions a bare
 * case name tests the receiver. Once the subject is known to hold an enum
 * with that case, typing records beside the member access or call the
 * RangeNodeCaseTest that runs in its place: a the subject, b the case
 * pattern. */

static RangeNode *casePattern(RangeArena *arena, RangeNode *at, const char *name, RangeNode *call);

/* An argument of a case test, as the pattern it is. */
static RangeNode *argumentPattern(RangeArena *arena, RangeNode *value)
{
    if (value->kind == RangeNodePattern) return value;
    if (value->kind == RangeNodeCase) return casePattern(arena,value,value->name,NULL);
    if (value->kind == RangeNodeCall && value->a && value->a->kind == RangeNodeCase)
        return casePattern(arena,value,value->a->name,value);
    RangeNode *pattern = rangeNodeCreate(arena,RangeNodePattern,value->path,value->line,value->column);
    pattern->integer = RangePatternValue;
    pattern->a = value;
    return pattern;
}

static RangeNode *casePattern(RangeArena *arena, RangeNode *at, const char *name, RangeNode *call)
{
    RangeNode *pattern = rangeNodeCreate(arena,RangeNodePattern,at->path,at->line,at->column);
    pattern->integer = RangePatternCase;
    pattern->name = name;
    if (!call) return pattern;
    pattern->flags |= RangeFlagApplication;
    for (size_t i = 0; i < call->itemCount; ++i) {
        RangeNode *argument = rangeNodeCreate(arena,RangeNodeArgument,call->items[i]->path,call->items[i]->line,call->items[i]->column);
        argument->name = call->items[i]->name;
        argument->a = argumentPattern(arena,call->items[i]->a);
        rangeNodeAppend(arena,pattern,argument);
    }
    return pattern;
}

/* The case test the member access `subject.name`, the call
 * `subject.name(…)`, or the bare `name` or `name(…)` (subject flagged
 * implicit: the receiver) is, written beside it. */
static RangeNode *caseTest(RangeArena *arena, RangeNode *at, RangeNode *subject, const char *name, RangeNode *call)
{
    RangeNode *test = rangeNodeCreate(arena,RangeNodeCaseTest,at->path,at->line,at->column);
    test->a = subject;
    test->b = casePattern(arena,at,name,call);
    test->name = name;
    return test;
}

/* The receiver a bare case name tests, inside an enum's own functions. */
static RangeNode *receiverSubject(RangeArena *arena, RangeNode *at)
{
    RangeNode *subject = rangeNodeCreate(arena,RangeNodeName,at->path,at->line,at->column);
    subject->flags |= RangeFlagImplicit;
    return subject;
}

/* A label row as a coverage vector of `width` columns, one per subject: a
 * row pattern's items, or the one pattern; NULL, the default, is wild. */
static void patternRow(RangeNode *row, RangeNode **vector, size_t width)
{
    for (size_t k = 0; k < width; ++k) vector[k] = NULL;
    if (!row) return;
    if (row->integer != RangePatternRow) { vector[0] = row; return; }
    for (size_t k = 0; k < width && k < row->itemCount; ++k) vector[k] = row->items[k];
}

static int useful(Typer *, RangeNode ***, size_t, RangeNode **, RangeNode **, size_t);

/* The combinations of the subjects' cases that no row covers, written as
 * '.on & .off' into missing; a subject that is not an enum is `_` there.
 * cases[k] declares subject k's cases, or is NULL. Returns how many. */
static size_t patternMissing(RangeArena *arena, Typer *typer, RangeNode ***rows, size_t count,
                             RangeNode **types, RangeNode **cases, size_t width, const char **names, char *missing, size_t size)
{
    size_t *index = rangeArenaAllocate(arena,width * sizeof(*index)), found = 0, length = strlen(missing);
    RangeNode **q = rangeArenaAllocate(arena,width * sizeof(*q));
    for (size_t k = 0; k < width; ++k) index[k] = 0;
    for (size_t tried = 0; tried < 4096; ++tried) {
        int valid = 1;
        for (size_t k = 0; k < width; ++k) {
            q[k] = NULL;
            if (!cases[k]) continue;
            size_t seen = 0;
            for (size_t i = 0; i < cases[k]->itemCount && !q[k]; ++i)
                if (cases[k]->items[i]->kind == RangeNodeEnumCase && seen++ == index[k]) {
                    q[k] = rangeNodeCreate(arena,RangeNodePattern,cases[k]->path,cases[k]->line,cases[k]->column);
                    q[k]->integer = RangePatternCase;
                    q[k]->name = cases[k]->items[i]->name;
                    q[k]->resolvedDeclaration = cases[k]->items[i];
                }
            if (!q[k]) valid = 0;
        }
        if (valid && useful(typer,rows,count,q,types,width)) {
            char text[256]; size_t used = 0;
            // Named subjects read as the condition that tests them: 'value.present & bits.absent'.
            for (size_t k = 0, written = 0; k < width; ++k) {
                if (names && !q[k]) continue;
                const char *subject = names ? names[k] : "";
                used += (size_t)snprintf(text + used,sizeof(text) > used ? sizeof(text) - used : 0,"%s%s%s%s",
                                         written++ ? " & " : "",subject,q[k] && (!names || *subject) ? "." : q[k] ? "" : "_",
                                         q[k] ? q[k]->name : "");
            }
            if (length + strlen(text) + 8 < size)
                length += (size_t)snprintf(missing + length,size - length,"%s'%s'",found ? ", " : "",text);
            ++found;
        }
        // The next combination: the last subject's case advances first.
        size_t k = width;
        for (;;) {
            if (k == 0) return found;
            --k;
            size_t total = 0;
            for (size_t i = 0; cases[k] && i < cases[k]->itemCount; ++i) total += cases[k]->items[i]->kind == RangeNodeEnumCase;
            if (++index[k] < total) break;
            index[k] = 0;
        }
    }
    return found;
}

/* ---- the static structure of a switch's conditions ----
 * A switch arm's condition is a Bool, but its case tests on stable subjects
 * are a pattern table: a local, a parameter, a member path of one, a
 * #reflection value, or the receiver, never a call or a name the arm binds.
 * The condition, read as `|` of `&`s, gives one row per alternative, with
 * one column per subject: the case test of that subject, or wild. A row
 * that also needs anything else, a guard, covers nothing for the arms after
 * it. The rows then decide, as a switch over those subjects would, which
 * arms are reached and whether the arms cover every combination. */

static RangeNode *bindingNamed(const RangeNode *, const char *);

static int stablePath(const RangeNode *path, const RangeNode *bindings)
{
    if (!path || path->generics) return 0;
    if (path->kind == RangeNodeName)
        return (path->flags & (RangeFlagImplicit | RangeFlagEarlier)) || !bindings || !bindingNamed(bindings,path->name);
    if (path->kind == RangeNodeEnvironment) return 1;
    return path->kind == RangeNodeMemberAccess && stablePath(path->a,bindings);
}

/* Two subjects read the same path; a narrowing is one more step of it. */
static int samePath(const RangeNode *a, const RangeNode *b)
{
    if (!a || !b || a->kind != b->kind || a->narrowed != b->narrowed) return 0;
    if ((a->flags & RangeFlagImplicit) || (b->flags & RangeFlagImplicit)) return (a->flags & RangeFlagImplicit) && (b->flags & RangeFlagImplicit);
    if (!same(a->name,b->name)) return 0;
    return a->kind != RangeNodeMemberAccess || samePath(a->a,b->a);
}

/* A subject as written, with the case of each narrowing it reads through:
 * `value.present.bits`. */
static const char *pathText(RangeArena *arena, const RangeNode *path)
{
    if (path->flags & RangeFlagImplicit) return "";
    const char *owner = path->kind == RangeNodeMemberAccess ? pathText(arena,path->a) : path->kind == RangeNodeEnvironment ? "#" : "";
    const char *narrowed = path->narrowed ? path->narrowed->name : "";
    size_t length = strlen(owner) + strlen(path->name) + strlen(narrowed) + 3;
    char *text = rangeArenaAllocate(arena,length);
    snprintf(text,length,"%s%s%s%s%s",owner,path->kind == RangeNodeMemberAccess ? "." : "",path->name,*narrowed ? "." : "",narrowed);
    return text;
}

typedef struct { RangeNode **terms; size_t count; int guarded; } ShapeRow;
typedef struct { ShapeRow *rows; size_t count; } ShapeRows;

#define RANGE_SHAPE_ROWS 256

/* The condition as alternatives of case tests; *overflow when there are too many to check. */
static ShapeRows shapeRows(RangeArena *arena, RangeNode *node, RangeNode *bindings, int *overflow)
{
    ShapeRows out = {0};
    if (*overflow) return out;
    if (node && node->kind == RangeNodeBinary && (same(node->name,"&") || same(node->name,"|"))) {
        ShapeRows left = shapeRows(arena,node->a,bindings,overflow);
        ShapeRows right = shapeRows(arena,node->b,bindings,overflow);
        size_t count = same(node->name,"|") ? left.count + right.count : left.count * right.count;
        if (*overflow || count > RANGE_SHAPE_ROWS) { *overflow = 1; return out; }
        out.rows = rangeArenaAllocate(arena,(count ? count : 1) * sizeof(*out.rows));
        if (same(node->name,"|")) {
            memcpy(out.rows,left.rows,left.count * sizeof(*out.rows));
            memcpy(out.rows + left.count,right.rows,right.count * sizeof(*out.rows));
            out.count = count;
            return out;
        }
        for (size_t i = 0; i < left.count; ++i)
            for (size_t j = 0; j < right.count; ++j) {
                ShapeRow *row = &out.rows[out.count++];
                row->count = left.rows[i].count + right.rows[j].count;
                row->terms = rangeArenaAllocate(arena,(row->count ? row->count : 1) * sizeof(*row->terms));
                memcpy(row->terms,left.rows[i].terms,left.rows[i].count * sizeof(*row->terms));
                memcpy(row->terms + left.rows[i].count,right.rows[j].terms,right.rows[j].count * sizeof(*row->terms));
                row->guarded = left.rows[i].guarded || right.rows[j].guarded;
            }
        return out;
    }
    out.rows = rangeArenaAllocate(arena,sizeof(*out.rows));
    out.rows[0] = (ShapeRow){0};
    out.count = 1;
    RangeNode *test = node && node->lowered ? node->lowered : node;
    RangeNode *found = test && test->kind == RangeNodeCaseTest && stablePath(test->a,bindings) ? test : NULL;
    if (found) {
        out.rows[0].terms = rangeArenaAllocate(arena,sizeof(*out.rows[0].terms));
        out.rows[0].terms[0] = found;
        out.rows[0].count = 1;
    } else out.rows[0].guarded = 1;
    return out;
}

/* The pattern table of a switch over conditions: its subjects, and one row
 * per alternative of each arm in order (the default a wild row), each with
 * its arm and whether a guard narrows it. `overflow` marks an arm with too
 * many alternatives to check, which counts as guarded. */
typedef struct {
    RangeNode **subjects; const char **names; size_t width;
    RangeNode ***rows; RangeNode **arms; int *guarded; size_t count;
} ConditionShape;

static void conditionShape(RangeArena *arena, RangeNode *node, ConditionShape *shape)
{
    size_t arms = node->itemCount;
    ShapeRows *each = rangeArenaAllocate(arena,(arms ? arms : 1) * sizeof(*each));
    size_t subjectCapacity = 1, total = 0;
    for (size_t i = 0; i < arms; ++i) {
        RangeNode *entry = node->items[i];
        int overflow = 0;
        if (entry->flags & RangeFlagLiteral || !entry->itemCount) each[i] = (ShapeRows){0};
        else each[i] = shapeRows(arena,entry->items[0]->b,entry->items[0]->c,&overflow);
        if (overflow) {
            each[i].rows = rangeArenaAllocate(arena,sizeof(*each[i].rows));
            each[i].rows[0] = (ShapeRow){.guarded=1};
            each[i].count = 1;
        }
        if (!each[i].count) {
            each[i].rows = rangeArenaAllocate(arena,sizeof(*each[i].rows));
            each[i].rows[0] = (ShapeRow){0};
            each[i].count = 1;
        }
        total += each[i].count;
        for (size_t r = 0; r < each[i].count; ++r) subjectCapacity += each[i].rows[r].count;
    }
    *shape = (ConditionShape){0};
    shape->subjects = rangeArenaAllocate(arena,subjectCapacity * sizeof(*shape->subjects));
    shape->names = rangeArenaAllocate(arena,subjectCapacity * sizeof(*shape->names));
    for (size_t i = 0; i < arms; ++i)
        for (size_t r = 0; r < each[i].count; ++r)
            for (size_t t = 0; t < each[i].rows[r].count; ++t) {
                RangeNode *subject = each[i].rows[r].terms[t]->a;
                size_t k = 0;
                while (k < shape->width && !samePath(shape->subjects[k],subject)) ++k;
                if (k < shape->width) continue;
                shape->subjects[shape->width] = subject;
                shape->names[shape->width++] = pathText(arena,subject);
            }
    shape->rows = rangeArenaAllocate(arena,(total ? total : 1) * sizeof(*shape->rows));
    shape->arms = rangeArenaAllocate(arena,(total ? total : 1) * sizeof(*shape->arms));
    shape->guarded = rangeArenaAllocate(arena,(total ? total : 1) * sizeof(*shape->guarded));
    for (size_t i = 0; i < arms; ++i)
        for (size_t r = 0; r < each[i].count; ++r) {
            ShapeRow *row = &each[i].rows[r];
            RangeNode **vector = rangeArenaAllocate(arena,(shape->width ? shape->width : 1) * sizeof(*vector));
            for (size_t k = 0; k < shape->width; ++k) vector[k] = NULL;
            int guarded = row->guarded;
            for (size_t t = 0; t < row->count; ++t) {
                size_t k = 0;
                while (!samePath(shape->subjects[k],row->terms[t]->a)) ++k;
                // A second test of one subject narrows the row as a guard does.
                if (vector[k]) guarded = 1;
                else vector[k] = row->terms[t]->b;
            }
            shape->rows[shape->count] = vector;
            shape->arms[shape->count] = node->items[i];
            shape->guarded[shape->count++] = guarded;
        }
}

/* Which rows nothing before them leaves anything for (reached[i] = 0), and
 * the combinations no row covers, written into missing; returns whether the
 * arms cover every combination. cases[k] declares subject k's cases. */
static int conditionCoverage(RangeArena *arena, Typer *typer, ConditionShape *shape,
                             RangeNode **types, RangeNode **cases, int *reached, char *missing, size_t size)
{
    RangeNode ***rows = rangeArenaAllocate(arena,(shape->count ? shape->count : 1) * sizeof(*rows));
    size_t count = 0;
    for (size_t i = 0; i < shape->count; ++i) {
        reached[i] = useful(typer,rows,count,shape->rows[i],types,shape->width);
        if (!shape->guarded[i]) rows[count++] = shape->rows[i];
    }
    RangeNode **wild = rangeArenaAllocate(arena,(shape->width ? shape->width : 1) * sizeof(*wild));
    for (size_t k = 0; k < shape->width; ++k) wild[k] = NULL;
    if (!useful(typer,rows,count,wild,types,shape->width)) return 1;
    *missing = '\0';
    if (shape->width) patternMissing(arena,typer,rows,count,types,cases,shape->width,shape->names,missing,size);
    return 0;
}

static int compilerAttribute(RangeNode *target, RangeNode *attribute)
{
    return same(attribute->name,"builtin")
        || (target->kind == RangeNodeFunction && same(attribute->name,"extern"))
        || macroBuiltin(attribute->resolvedDeclaration,"literal");
}

static int evalApplication(Resolver *, RangeMacroApplication *, int);
static void mergeEmitted(Resolver *, RangeNode *);

/* An application's shape-only #graph blocks, emitted and merged once. Shape
 * rounds run them for every application before any macro body runs; an
 * application that joins later runs them just before its body. They land
 * even when the body then fails. */
static void shapeApplication(Resolver *vm, RangeNode *attribute)
{
    RangeMacroApplication *app = attribute->macroApplication;
    if (!app || app->shaped) return;
    app->shaped = 1;
    RangeNode *outer = vm->emitted;
    RangeNode *emitted = rangeNodeCreate(vm->arena,RangeNodeBlock,attribute->path,attribute->line,attribute->column);
    vm->emitted = emitted;
    (void)evalApplication(vm,app,1);
    vm->emitted = outer;
    mergeEmitted(vm,emitted);
}

/* Run one application. Its #graph output is collected and returned only when
 * the whole body succeeds, so a failed application emits nothing beyond its
 * shape-only blocks. */
static RangeNode *runMacroApplication(Resolver *vm, RangeNode *attribute)
{
    RangeMacroApplication *app = attribute->macroApplication;
    if (!app) fail(vm,attribute,"macro application was not resolved");
    shapeApplication(vm,attribute);
    RangeNode *emitted = rangeNodeCreate(vm->arena,RangeNodeBlock,attribute->path,attribute->line,attribute->column);
    // @many marks layout, @optional the `?` sugar's enum, @interval the `..<`
    // sugar's construct, @iteration the function `for … in` calls, and
    // @insertion the function C builds reflection lists with; applying any of
    // them has no compile-time effect.
    if (macroBuiltin(app->declaration,"many") || macroBuiltin(app->declaration,"optional")
        || macroBuiltin(app->declaration,"interval") || roleMacro(app->declaration)) return emitted;
    if (app->declaration->c) for (size_t j = 0; j < app->declaration->c->itemCount; ++j)
        if (same(app->declaration->c->items[j]->name,"builtin")) {
            if (!macroBuiltin(app->declaration,"literal") && !macroBuiltin(app->declaration,"diagnostic"))
                fail(vm,attribute,"no C primitive is implemented for builtin macro '%s'",app->declaration->name);
            fail(vm,attribute,"builtin macro '%s' is an effect C runs where it is written; it applies to no target",app->declaration->name);
        }
    // A body that stopped on a problem typing reported emits nothing.
    vm->emitted = emitted;
    if (!evalApplication(vm,app,0)) emitted->itemCount = 0;
    vm->emitted = NULL;
    return emitted;
}

static void noteWritten(Typer *, RangeNode *);

/* Emitted and written declarations join the graph through the same path as
 * parsed source: kept as written, then shape, grammar identity, macro
 * targets, and literal defaults. */
static void resolveMergedNode(Resolver *vm, RangeNode *node)
{
    if (vm->typer) noteWritten(vm->typer,node);
    validateGraphShape(vm,node,node->source);
    linkGrammarNodes(vm,node);
    resolveSignatureTypes(vm,node,node->kind == RangeNodeFunction ? node->owner : NULL);
    resolveGraphTarget(vm,node);
    resolveLiteralDefaults(vm,node);
}

/* Two applications with the same written arguments, compared as syntax. */
static int sameSyntax(const RangeNode *a, const RangeNode *b)
{
    if (!a || !b) return a == b;
    if (a->kind != b->kind || a->integer != b->integer || a->itemCount != b->itemCount
        || (a->flags & ~RangeFlagImplicit) != (b->flags & ~RangeFlagImplicit)) return 0;
    if ((a->name || b->name) && !same(a->name,b->name)) return 0;
    if ((a->typeName || b->typeName) && !same(a->typeName,b->typeName)) return 0;
    if (!sameSyntax(a->a,b->a) || !sameSyntax(a->b,b->b) || !sameSyntax(a->c,b->c)
        || !sameSyntax(a->generics,b->generics)) return 0;
    for (size_t i = 0; i < a->itemCount; ++i) if (!sameSyntax(a->items[i],b->items[i])) return 0;
    return 1;
}

/* A macro application written on an extension applies to the extended
 * declaration as if written there: it is listed in #macros. The same macro
 * applied twice to one declaration is one application; different arguments
 * are an error. */
static void attachApplication(Resolver *vm, RangeNode *declaration, RangeNode *attribute)
{
    if (!declaration->c)
        declaration->c = rangeNodeCreate(vm->arena,RangeNodeAttribute,declaration->path,declaration->line,declaration->column);
    RangeNode *list = declaration->c;
    for (size_t i = 0; i < list->itemCount; ++i) {
        RangeNode *existing = list->items[i];
        if (!same(existing->name,attribute->name)) continue;
        if (!sameSyntax(existing,attribute))
            fail(vm,attribute,"@%s is applied to '%s' twice with different arguments, at %s:%d:%d and at %s:%d:%d",
                 attribute->name,declaration->name,existing->path,existing->line,existing->column,
                 attribute->path,attribute->line,attribute->column);
        if (vm->report)
            sourceDiagnostic(vm->report,attribute,2,"macro",
                "@%s is already applied to '%s' at %s:%d:%d; this is the same application",
                attribute->name,declaration->name,existing->path,existing->line,existing->column);
        return;
    }
    rangeNodeAppend(vm->arena,list,attribute);
    resolveApplication(vm,declaration,attribute);
}

/* An extension names its declaration; its members move there and resolve in
 * that declaration's scope, so an emitted `Element` finds Array<Element>. */
static void mergeExtension(Resolver *vm, RangeNode *extension)
{
    RangeNode *subject = extension->a, *declaration = NULL;
    if (!subject || subject->kind != RangeNodeName)
        fail(vm,extension,"#name splices are only valid inside #graph");
    // `extension #name` emitted by an application extends that application's
    // target, nested or not.
    RangeMacroApplication *emitter = extension->emittedBy ? extension->emittedBy->macroApplication : NULL;
    if (emitter && emitter->target && same(emitter->target->name,subject->name)
        && (emitter->target->kind == RangeNodeConstruct || emitter->target->kind == RangeNodeEnum))
        declaration = emitter->target;
    for (size_t u = 0; u < vm->count && !declaration; ++u) for (size_t i = 0; i < vm->units[u]->itemCount; ++i) {
        RangeNode *candidate = vm->units[u]->items[i];
        if (!same(candidate->name,subject->name)) continue;
        if (candidate->kind != RangeNodeConstruct && candidate->kind != RangeNodeEnum) continue;
        if (declaration) fail(vm,subject,"ambiguous extension of '%s'",subject->name);
        declaration = candidate;
    }
    if (!declaration) fail(vm,subject,"extension of undeclared '%s'",subject->name);
    // An enum's values are its cases: an extension adds functions and nested types.
    if (declaration->kind == RangeNodeEnum)
        for (size_t i = 0; i < extension->itemCount; ++i)
            if (rangeNodeDeclaresValue(extension->items[i]->kind))
                fail(vm,extension->items[i],"an extension of enum '%s' cannot add stored member '%s'",declaration->name,extension->items[i]->name);
    for (size_t i = 0; i < extension->itemCount; ++i) {
        RangeNode *item = extension->items[i];
        if (item->kind == RangeNodeFunction) { item->typeName = declaration->name; item->owner = declaration; }
        rangeNodeAppend(vm->arena,declaration,item);
        resolveMergedNode(vm,item);
    }
    extension->itemCount = 0;
    extension->resolvedDeclaration = declaration;
    // Applications join only after the members: an application never runs
    // while its extension is half merged, so it sees every member written
    // beside it.
    RangeNode *attributes = extension->c;
    extension->c = NULL;
    for (size_t i = 0; attributes && i < attributes->itemCount; ++i)
        attachApplication(vm,declaration,attributes->items[i]);
}

static void mergeEmitted(Resolver *vm, RangeNode *emitted)
{
    for (size_t i = 0; i < emitted->itemCount; ++i) {
        RangeNode *node = emitted->items[i];
        if (node->kind == RangeNodeExtension) { mergeExtension(vm,node); continue; }
        rangeNodeAppend(vm->arena,vm->unit,node);
        resolveMergedNode(vm,node);
    }
}

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

static void sourceDiagnostic(SourceReport *report, RangeNode *at, int warning,
                             const char *category, const char *format, ...)
{
    char text[768]; va_list args; va_start(args,format);
    vsnprintf(text,sizeof(text),format,args); va_end(args);
    /* Keep every distinct issue and its first location in each source file. */
    for (SourceDiagnostic *d = report->first; d; d = d->next)
        if (d->warning == warning && same(d->category,category) && same(d->message,text)
            && ((!at && !d->at) || (at && d->at && same(at->path,d->at->path)))) {
            ++d->uses;
            return;
        }
    SourceDiagnostic *d = rangeArenaAllocate(report->arena,sizeof(*d));
    *d = (SourceDiagnostic){.at=at,.category=category,.warning=warning,.uses=1,
        .message=rangeArenaIntern(report->arena,text,strlen(text))};
    if (report->last) report->last->next = d;
    else report->first = d;
    report->last = d;
    if (warning == 1) ++report->warnings;
    else if (!warning) ++report->errors;
}

static int sourceDeclaration(RangeNode *node)
{
    return node->kind == RangeNodeConstruct || node->kind == RangeNodeEnum
        || node->kind == RangeNodeFunction || node->kind == RangeNodeMacro
        || rangeNodeDeclaresValue(node->kind) || node->kind == RangeNodeParameter;
}

static int sourceMatches(RangeNode *node, const char *name, int kind)
{
    if (!sourceDeclaration(node) || !same(node->name,name)) return 0;
    if (kind == 1) return node->kind == RangeNodeMacro;
    if (kind == 2) return node->kind == RangeNodeConstruct || node->kind == RangeNodeEnum;
    return node->kind != RangeNodeMacro;
}

/* A method's receiver: an implicit let of the method, made on first use and
 * never found by name. Range has no `self`: members are reached by their bare
 * names, and inside an enum's own functions a bare case name tests the
 * current value. The type checker gives it the method's receiver
 * specialization. */
static RangeNode *methodReceiver(SourceReport *report, RangeNode *function)
{
    if (!function->receiver) {
        function->receiver = rangeNodeCreate(report->arena,RangeNodeLet,function->path,function->line,function->column);
        function->receiver->name = function->typeName;
    }
    return function->receiver;
}

static RangeNode *sourceLookup(SourceReport *report, SourceScope *scope,
                               const char *name, int kind)
{
    for (; scope; scope = scope->parent) {
        RangeNode *owner = scope->owner;
        if (!owner) continue;
        // A nested declaration names itself inside its own body.
        if (kind != 1 && (owner->kind == RangeNodeConstruct || owner->kind == RangeNodeEnum) && same(owner->name,name)) return owner;
        if (kind != 1 && owner->generics && same(owner->generics->name,"genericMembers"))
            for (size_t i = 0; i < owner->generics->itemCount; ++i)
                if (same(owner->generics->items[i]->name,name)) return owner->generics->items[i];
        for (size_t i = 0; i < owner->itemCount; ++i) {
            RangeNode *node = owner->items[i];
            if (sourceMatches(node,name,kind)) return node;
        }
    }
    for (size_t u = 0; u < report->count; ++u) for (size_t i = 0; i < report->units[u]->itemCount; ++i) {
        RangeNode *node = report->units[u]->items[i];
        if (sourceMatches(node,name,kind)) return node;
    }
    return NULL;
}

/* A name read to the left of the case test that binds it: what it names
 * outside that condition's bindings. */
static RangeNode *nameLookup(SourceReport *report, SourceScope *scope, const RangeNode *name)
{
    if (name->flags & RangeFlagEarlier)
        for (SourceScope *outer = scope; outer; outer = outer->parent)
            if (outer->owner && outer->owner->kind == RangeNodeBlock && same(outer->owner->name,"bindings")
                && bindingNamed(outer->owner,name->name))
                return sourceLookup(report,outer->parent,name->name,0);
    return sourceLookup(report,scope,name->name,0);
}

/* A declaration nested in a construct or an enum. */
static RangeNode *nestedDeclaration(RangeNode *owner, const char *name, size_t length)
{
    for (size_t i = 0; owner && i < owner->itemCount; ++i) {
        RangeNode *item = owner->items[i];
        if ((item->kind == RangeNodeConstruct || item->kind == RangeNodeEnum) && item->name
            && !strncmp(item->name,name,length) && !item->name[length]) return item;
    }
    return NULL;
}

/* `Outer.Inner` names Inner through its owner; the first name resolves in scope. */
static RangeNode *dottedLookup(SourceReport *report, SourceScope *scope, const char *name, int kind)
{
    const char *dot = strchr(name,'.');
    if (!dot) return sourceLookup(report,scope,name,kind);
    RangeNode *owner = sourceLookup(report,scope,rangeArenaIntern(report->arena,name,(size_t)(dot - name)),2);
    while (owner && dot) {
        const char *next = strchr(dot + 1,'.');
        owner = nestedDeclaration(owner,dot + 1,next ? (size_t)(next - dot - 1) : strlen(dot + 1));
        dot = next;
    }
    return owner;
}

/* A type path in an expression: Light, Outer.Inner. A value of the same name
 * shadows the type, as it does for a bare name. */
static RangeNode *typePath(SourceReport *report, SourceScope *scope, RangeNode *expr)
{
    if (!expr) return NULL;
    if (expr->kind == RangeNodeName) {
        RangeNode *declaration = sourceLookup(report,scope,expr->name,0);
        return declaration && (declaration->kind == RangeNodeConstruct || declaration->kind == RangeNodeEnum) ? declaration : NULL;
    }
    if (expr->kind != RangeNodeMemberAccess || expr->generics) return NULL;
    RangeNode *owner = typePath(report,scope,expr->a);
    return owner ? nestedDeclaration(owner,expr->name,strlen(expr->name)) : NULL;
}

static const char *typePathText(SourceReport *report, RangeNode *expr)
{
    if (expr->kind == RangeNodeName) return expr->name;
    const char *owner = typePathText(report,expr->a);
    size_t length = strlen(owner) + strlen(expr->name) + 2;
    char *text = rangeArenaAllocate(report->arena,length);
    snprintf(text,length,"%s.%s",owner,expr->name);
    return text;
}

/* `let inner: Outer.Inner` parses as an expression; a path that names a
 * nested type is that type in the type position: a requirement, not a value. */
static int requiredPath(SourceReport *report, SourceScope *scope, RangeNode *node)
{
    return rangeNodeDeclaresValue(node->kind) && !node->typeName && node->itemCount == 1 && node->items[0]->a
        && node->items[0]->a->kind == RangeNodeMemberAccess && typePath(report,scope,node->items[0]->a);
}

static RangeNode *sourceReference(SourceReport *report, SourceScope *scope,
                                  RangeNode *at, const char *name, int kind)
{
    if (!name || !*name) return NULL;
    if (kind != 1 && strchr(name,'.')) {
        RangeNode *nested = dottedLookup(report,scope,name,kind);
        if (!nested) sourceDiagnostic(report,at,0,"undeclared","no declaration for '%s' in the loaded sources",name);
        return nested;
    }
    RangeNode *declaration = sourceLookup(report,scope,name,kind);
    if (!declaration) {
        if (kind != 1 && rangeGraphType(report->arena,name))
            sourceDiagnostic(report,at,0,"undeclared","'%s' has a C graph shape but no Range declaration",name);
        else sourceDiagnostic(report,at,0,"undeclared","no declaration for %s'%s' in the loaded sources",kind == 1 ? "macro " : "",name);
    }
    return declaration;
}

static void diagnoseSourceNode(SourceReport *, SourceScope *, RangeNode *, int);

/* Whether `name` is a list field of some reflection shape, such as cases. */
static int reflectionList(RangeArena *arena, const char *name)
{
    for (size_t i = 0; name && i < arena->graphTypes->itemCount; ++i) {
        RangeNode *field = rangeGraphField(arena->graphTypes->items[i],name);
        if (field && (field->flags & RangeFlagMany)) return 1;
    }
    return 0;
}

static void diagnoseType(SourceReport *report, SourceScope *scope, RangeNode *node)
{
    if (!node) return;
    if ((node->flags & RangeFlagFunction) && node->generics) {
        // (A, B) -> R names its parts; the function type itself is C's.
        sourceDiagnostic(report,node,1,"C-implementation","function types are C's: a parameter typed (A) -> R takes a closure, "
                         "which C compiles inline where the call it is passed to is made; it is never a value");
        for (size_t i = 0; i < node->generics->itemCount; ++i) diagnoseType(report,scope,node->generics->items[i]->a);
        diagnoseType(report,scope,node->generics->a);
        return;
    }
    (void)sourceReference(report,scope,node,node->name,node->flags & RangeFlagMacroType ? 1 : 2);
    diagnoseSourceNode(report,scope,node->generics,0);
    diagnoseType(report,scope,node->a); /* an explicit macro result type */
}

static RangeNode *bindingNamed(const RangeNode *bindings, const char *name)
{
    for (size_t i = 0; bindings && i < bindings->itemCount; ++i)
        if (same(bindings->items[i]->name,name)) return bindings->items[i];
    return NULL;
}

/* Whether a name is read anywhere in the tree, quoted #graph code and
 * interpolations included. A read of a nested binding that shadows the name
 * counts too, so the check never warns about a name that is used. */
static int nameRead(const RangeNode *node, const char *name)
{
    if (!node) return 0;
    if (node->kind == RangeNodeName && same(node->name,name) && !(node->flags & RangeFlagEarlier)) return 1;
    // `let copy: xs` keeps a bare right-hand name in the type position.
    if (rangeNodeDeclaresValue(node->kind) && same(node->typeName,name)) return 1;
    if (nameRead(node->a,name) || nameRead(node->b,name) || nameRead(node->c,name)
        || nameRead(node->generics,name) || nameRead(node->annotations,name)) return 1;
    for (size_t i = 0; i < node->itemCount; ++i) if (nameRead(node->items[i],name)) return 1;
    return 0;
}

/* A name a pattern binds is read by some row's condition or by the arm's
 * body; every row of an arm binds the same names, so a read in any of them
 * uses the name. Native code and macros alike. */
static void diagnoseUnusedBindings(SourceReport *report, RangeNode *arm)
{
    for (size_t i = 0; i < arm->itemCount; ++i) {
        RangeNode *bindings = arm->items[i]->c;
        for (size_t k = 0; bindings && k < bindings->itemCount; ++k) {
            if (bindings->items[k]->flags & RangeFlagImplicit) continue;
            const char *name = bindings->items[k]->name;
            int seen = 0, used = nameRead(arm->a,name) || nameRead(arm->b,name);
            for (size_t j = 0; j < i && !seen; ++j) seen = bindingNamed(arm->items[j]->c,name) != NULL;
            for (size_t j = 0; j < arm->itemCount && !used; ++j) used = nameRead(arm->items[j]->b,name);
            if (!seen && !used)
                sourceDiagnostic(report,bindings->items[k],1,"unused",
                    "'%s' is bound but never used; write the pattern without 'let %s'",name,name);
        }
    }
}

/* Inside an enum's own functions, a bare name that is one of its cases and
 * declares nothing nearer: a case test of the receiver. */
static int receiverCaseName(SourceScope *scope, const char *name)
{
    int function = 0;
    for (; scope; scope = scope->parent) {
        RangeNode *owner = scope->owner;
        if (!owner) continue;
        for (size_t i = 0; owner->kind != RangeNodeEnum && i < owner->itemCount; ++i)
            if (sourceMatches(owner->items[i],name,0)) return 0;
        if (owner->kind == RangeNodeFunction) function = 1;
        if (owner->kind == RangeNodeConstruct) return 0;
        if (owner->kind == RangeNodeEnum) {
            if (!function) return 0;
            for (size_t i = 0; i < owner->itemCount; ++i)
                if (owner->items[i]->kind == RangeNodeEnumCase && same(owner->items[i]->name,name)) return 1;
            return 0;
        }
    }
    return 0;
}

static void diagnoseDuplicate(SourceReport *, RangeNode *, RangeNode *, const char *);

static void diagnoseSourceNode(SourceReport *report, SourceScope *scope, RangeNode *node, int metadata)
{
    if (!node) return;
    switch (node->kind) {
    case RangeNodeUnit: case RangeNodeBlock: {
        SourceScope block = {.owner=node,.parent=scope,.meta=scope && scope->meta};
        for (size_t i = 0; i < node->itemCount; ++i) {
            RangeNode *item = node->items[i];
            // A block declares a name once, as a construct does.
            for (size_t j = 0; node->kind == RangeNodeBlock && rangeNodeDeclaresValue(item->kind) && j < i; ++j)
                if (rangeNodeDeclaresValue(node->items[j]->kind) && same(node->items[j]->name,item->name)) {
                    diagnoseDuplicate(report,node->items[j],item,"this block");
                    break;
                }
            diagnoseSourceNode(report,&block,item,metadata);
        }
        return;
    }
    case RangeNodeConstruct: case RangeNodeEnum: case RangeNodeFunction: case RangeNodeMacro: {
        if (node->kind == RangeNodeMacro && (node->flags & RangeFlagTyped)) return; /* diagnosed as it was typed, when first applied */
        SourceScope declaration = {.owner=node,.parent=scope,.meta=(scope && scope->meta) || node->kind == RangeNodeMacro};
        if (node->kind == RangeNodeFunction)
            (void)sourceReference(report,scope,node,node->typeName,2);
        if (node->kind == RangeNodeFunction || node->kind == RangeNodeMacro) diagnoseType(report,&declaration,node->b);
        if (macroBuiltin(node,"many"))
            sourceDiagnostic(report,node,1,"C-implementation","@many storage is a C heap block of copy-on-write slots, allocated through libSystem and freed when its last reference ends");
        else if (macroBuiltin(node,"optional")) {
            sourceDiagnostic(report,node,1,"C-implementation","'?' sugar resolves to the enum applying @optional, and 'for … in' unwraps its payload case, in C");
            sourceDiagnostic(report,node,1,"C-implementation","a value of T where T? is expected becomes the payload case holding it, in C");
        }
        else if (macroBuiltin(node,"print"))
            sourceDiagnostic(report,node,1,"C-implementation","@print writes through libSystem write in C, formatting integers in C");
        else if (macroBuiltin(node,"iteration")) {
            sourceDiagnostic(report,node,1,"C-implementation","'for … in' calls the function applying @iteration at positions 0, 1, 2, … until it returns absence; C writes the loop");
            sourceDiagnostic(report,node,1,"C-implementation","the @iteration law (one per type, one Int parameter, an optional result) is checked in C");
        }
        else if (macroBuiltin(node,"insertion")) {
            sourceDiagnostic(report,node,1,"C-implementation","C builds each reflection list by calling the function applying @insertion on its collection once per declaration");
            sourceDiagnostic(report,node,1,"C-implementation","the @insertion law (at most one per type, one parameter of the element its @iteration function yields) is checked in C");
        }
        else if (macroBuiltin(node,"interval"))
            sourceDiagnostic(report,node,1,"C-implementation","'a..<b' resolves to the construct applying @interval, constructed with lower: a, upper: b, in C");
        else if (macroBuiltin(node,"warning"))
            sourceDiagnostic(report,node,1,"C-implementation","@warning reports a compile-time warning through C's diagnostics");
        else if (node->kind == RangeNodeMacro && node->c && !macroBuiltin(node,"literal") && !macroBuiltin(node,"diagnostic")
                 && !macroBuiltin(node,"print"))
            for (size_t i = 0; i < node->c->itemCount; ++i)
                if (same(node->c->items[i]->name,"builtin"))
                    sourceDiagnostic(report,node,0,"not-implemented","no C primitive is implemented for builtin macro '%s'",node->name);
        diagnoseSourceNode(report,&declaration,node->generics,0);
        diagnoseSourceNode(report,scope,node->c,0);
        for (size_t i = 0; i < node->itemCount; ++i) diagnoseSourceNode(report,&declaration,node->items[i],0);
        diagnoseSourceNode(report,&declaration,node->a,0);
        return;
    }
    case RangeNodeParameter:
        diagnoseType(report,scope,node->b);
        break;
    case RangeNodeLet: case RangeNodeState: case RangeNodeDerived: case RangeNodeBinding: {
        // `let xs: filled<size: 3>(value: 1)` calls a generic function; `let
        // xs: Array<Int>` names a type.
        (void)sourceReference(report,scope,node,node->typeName,
            node->flags & RangeFlagMacroType ? 1
            : (node->flags & RangeFlagApplication) && !(node->flags & RangeFlagOptional) ? 0
            : node->generics || (node->flags & RangeFlagOptional) ? 2 : 0);
        // A type path is a requirement, recorded beside the declaration; it is not read as a value.
        if (requiredPath(report,scope,node)) {
            node->flags |= RangeFlagRequired;
            return;
        }
        break;
    }
    case RangeNodeName:
        if (!(node->flags & RangeFlagMacroType) && receiverCaseName(scope,node->name)) break; /* tests the receiver */
        if (node->flags & RangeFlagEarlier) {
            if (!nameLookup(report,scope,node))
                sourceDiagnostic(report,node,0,"undeclared","no declaration for '%s' here; the case test that binds it is to its right",node->name);
            break;
        }
        (void)sourceReference(report,scope,node,node->name,node->flags & RangeFlagMacroType ? 1 : 0);
        break;
    case RangeNodeMemberAccess:
        /* Runtime member access is typed later. */
        if (scope && scope->meta && reflectionList(report->arena,node->name))
            sourceDiagnostic(report,node,1,"C-implementation","'.%s' is a reflection list: C builds the collection its grammar field declares by calling that collection's @insertion function for each declaration",node->name);
        break;
    case RangeNodeEnvironment:
        if (reflectionList(report->arena,node->name))
            sourceDiagnostic(report,node,1,"C-implementation","'#%s' is a reflection list: C builds the collection its grammar field declares by calling that collection's @insertion function for each declaration",node->name);
        break;
    case RangeNodeAttribute: {
        if (same(node->name,"builtin") || same(node->name,"extern")) {
            metadata = 1; /* compiler metadata still contains source expressions */
            break;
        }
        if (node->name) {
            RangeNode *macro = sourceReference(report,scope,node,node->name,1);
            if (node->resolvedDeclaration) macro = node->resolvedDeclaration;
            metadata = macroBuiltin(macro,"literal") || macroBuiltin(macro,"diagnostic") || macroBuiltin(macro,"warning");
        }
        break;
    }
    case RangeNodeInteger:
        if (!metadata) sourceDiagnostic(report,node,1,"C-implementation",
            "numeric literal values use C signed 64-bit storage; Range literal materialization is not implemented");
        break;
    case RangeNodeBool:
        if (!metadata) sourceDiagnostic(report,node,1,"C-implementation",
            "boolean literals are recognized by the C parser and name the enum case spelled like them; Range literal materialization is not implemented");
        break;
    case RangeNodeString:
        if (!metadata) sourceDiagnostic(report,node,1,"C-implementation",
            "string literal values are supplied by C; Range literal materialization is not implemented");
        break;
    case RangeNodeUnary: case RangeNodeBinary:
        if (node->kind == RangeNodeBinary && same(node->name,"..<")) break; /* the @interval sugar */
        // An operator calls the function its operand's type declares, at run
        // time and at macro time alike; only the grammar of operators is C's.
        if (node->kind == RangeNodeBinary)
            sourceDiagnostic(report,node,1,"C-implementation",
                "operator precedence and associativity are fixed in the C parser: prefix '!' and '-', arithmetic, comparisons, '&', then '|'; Range does not declare them yet");
        break;
    case RangeNodeEmission: case RangeNodeExtension:
        return; /* quoted and extension code is checked where it lands */
    case RangeNodeSwitchCase: {
        // A row's condition sees that row's bindings; the arm's body sees the
        // first row's, which every row binds.
        for (size_t i = 0; i < node->itemCount; ++i) {
            RangeNode *row = node->items[i];
            diagnoseSourceNode(report,scope,row,metadata);
            SourceScope own = {.owner=row->c ? row->c : node,.parent=scope,.meta=scope && scope->meta};
            diagnoseSourceNode(report,&own,row->b,metadata);
        }
        SourceScope bound = {.owner=node->c ? node->c : node,.parent=scope,.meta=scope && scope->meta};
        diagnoseSourceNode(report,&bound,node->a,metadata);
        diagnoseSourceNode(report,&bound,node->b,metadata);
        diagnoseUnusedBindings(report,node);
        return;
    }
    case RangeNodePattern:
        diagnoseSourceNode(report,scope,node->a,metadata);
        for (size_t i = 0; i < node->itemCount; ++i) diagnoseSourceNode(report,scope,node->items[i],metadata);
        return;
    case RangeNodeClosure: {
        // Its parameters name values in its body; it sees the names where it
        // is written. The body's switch read as an expression, its b, has the
        // same names, so the statements alone are checked.
        SourceScope own = {.owner=node,.parent=scope,.meta=scope && scope->meta};
        if (!(scope && scope->meta))
            sourceDiagnostic(report,node,1,"C-implementation","a closure is compiled by C inline, where the call it is passed to "
                             "is made, and runs only during that call");
        else sourceDiagnostic(report,node,1,"C-implementation","a compile-time closure is run by C's evaluator while the call it is passed to runs");
        diagnoseSourceNode(report,&own,node->a,metadata);
        return;
    }
    case RangeNodeSyntaxTemplate:
        sourceDiagnostic(report,node,0,"not-implemented","execution of '%s' is not implemented",rangeNodeKindName(node->kind));
        break;
    default: break;
    }
    diagnoseSourceNode(report,scope,node->a,metadata);
    if (node->kind != RangeNodeParameter) diagnoseSourceNode(report,scope,node->b,metadata);
    diagnoseSourceNode(report,scope,node->c,metadata);
    diagnoseSourceNode(report,scope,node->generics,0);
    diagnoseSourceNode(report,scope,node->annotations,0);
    for (size_t i = 0; i < node->itemCount; ++i) diagnoseSourceNode(report,scope,node->items[i],metadata);
    /* rhsReference aliases the already checked member/local type-position name. */
}

static void writeSourceDiagnostics(SourceReport *report, FILE *output)
{
    for (SourceDiagnostic *d = report->first; d; d = d->next) {
        if (d->at) fprintf(output,"%s:%d:%d: ",d->at->path,d->at->line,d->at->column);
        else fputs("compiler: ",output);
        fprintf(output,"%s[%s]: %s",d->warning == 2 ? "note" : d->warning ? "warning" : "error",d->category,d->message);
        if (d->uses > 1) fprintf(output," (%zu uses in this source)",d->uses);
        fputc('\n',output);
    }
}

/* Macro application: written extensions merge first; then shape rounds emit
 * every application's shape-only #graph blocks, so declarations have the
 * members those give them before any macro body runs; then every application
 * runs once and its #graph output merges before the next round. Applications
 * introduced by emitted code run in a later round. This discovery order is a
 * bootstrap stand-in: the accepted design is a Datalog scheduler that orders
 * applications by what they read and write, reruns only reads a write changes,
 * and rejects cycles through absence or whole-list reads. */
enum { RangeMacroRounds = 16 };

/* Each failure is recorded and the remaining applications still run. */
static void guarded(Resolver *vm, SourceReport *report, const char *category,
                    void (*step)(Resolver *, RangeNode *), RangeNode *node)
{
    jmp_buf outer;
    memcpy(outer,vm->failure,sizeof(outer));
    if (setjmp(vm->failure) == 0) step(vm,node);
    else sourceDiagnostic(report,NULL,0,category,"%s",vm->error);
    memcpy(vm->failure,outer,sizeof(outer));
}

static void applyAndMerge(Resolver *vm, RangeNode *attribute)
{
    mergeEmitted(vm,runMacroApplication(vm,attribute));
}

static void drainLaws(Typer *);

/* One round over a target and its members: in a shape round, the shape
 * parts not run yet; otherwise the applications not run yet. */
static int applyTarget(Resolver *vm, SourceReport *report, RangeNode *unit, RangeNode *target, int shape)
{
    if (!target->graphType) return 0;
    int ran = 0;
    if (target->c) for (size_t i = 0; i < target->c->itemCount; ++i) {
        RangeNode *attribute = target->c->items[i];
        if (compilerAttribute(target,attribute)) continue;
        // An unresolved application here comes from a merge that already failed.
        RangeMacroApplication *app = attribute->macroApplication;
        if (!app || app->applied || (shape && app->shaped)) continue;
        ran = 1;
        vm->unit = unit;
        if (shape) { guarded(vm,report,"macro-validation",shapeApplication,attribute); continue; }
        app->applied = 1;
        ++vm->checked;
        guarded(vm,report,"macro-validation",applyAndMerge,attribute);
    }
    // Members merged during this round wait for the next one.
    if (target->kind == RangeNodeConstruct || target->kind == RangeNodeEnum)
        for (size_t i = 0, n = target->itemCount; i < n; ++i)
            ran |= applyTarget(vm,report,unit,target->items[i],shape);
    return ran;
}

/* Rounds until one runs nothing; whether they settled. */
static int applyRounds(Resolver *vm, SourceReport *report, int shape)
{
    for (int round = 0; round < RangeMacroRounds; ++round) {
        int ran = 0;
        for (size_t u = 0; u < vm->count; ++u)
            for (size_t i = 0, n = vm->units[u]->itemCount; i < n; ++i)
                ran |= applyTarget(vm,report,vm->units[u],vm->units[u]->items[i],shape);
        drainLaws(vm->typer);
        if (!ran) return 1;
    }
    sourceDiagnostic(report,NULL,0,"macro-validation","macro emission did not settle after %d rounds",RangeMacroRounds);
    return 0;
}

static void applyMacros(Resolver *vm, SourceReport *report)
{
    for (size_t u = 0; u < vm->count; ++u)
        for (size_t i = 0; i < vm->units[u]->itemCount; ++i)
            if (vm->units[u]->items[i]->kind == RangeNodeExtension)
                guarded(vm,report,"resolution",mergeExtension,vm->units[u]->items[i]);
    if (applyRounds(vm,report,1)) (void)applyRounds(vm,report,0);
}

static Typer *newTyper(SourceReport *, Resolver *);
static void typerLanguage(Typer *);

/* Apply every macro. The type checker exists from the start, so macro time
 * can type what it runs; the typer returned finishes in typeCheck. */
static Typer *diagnoseMacroApplications(SourceReport *report)
{
    Resolver *vm = rangeArenaAllocate(report->arena,sizeof(*vm));
    *vm = (Resolver){.arena=report->arena,.units=report->units,.count=report->count,
        .error=rangeArenaAllocate(report->arena,512),.errorSize=512,.report=report};
    vm->typer = newTyper(report,vm);
    for (size_t u = 0; u < report->count; ++u) noteWritten(vm->typer,report->units[u]);
    if (setjmp(vm->failure) == 0) {
        typerLanguage(vm->typer);
        applyMacros(vm,report);
    } else sourceDiagnostic(report,NULL,0,"macro-validation","%s",vm->error);
    return vm->typer;
}

/* The ordinary rule: one declaration per name in a scope, however it arrived.
 * Functions and macros are exempt because they overload. */
static void diagnoseDuplicate(SourceReport *report, RangeNode *first, RangeNode *second, const char *scope)
{
    // Emitted declarations are reported at the application that produced them.
    char origin[512];
    RangeNode *source = first->emittedBy;
    if (source) snprintf(origin,sizeof(origin),"first emitted by @%s at %s:%d",source->name,source->path,source->line);
    else snprintf(origin,sizeof(origin),"first declared at %s:%d",first->path,first->line);
    source = second->emittedBy;
    if (source) sourceDiagnostic(report,source,0,"duplicate",
        "@%s emits '%s', which is declared more than once in %s; %s",
        source->name,second->name,scope,origin);
    else sourceDiagnostic(report,second,0,"duplicate",
        "'%s' is declared more than once in %s; %s",second->name,scope,origin);
}

static int scopeDeclaration(const RangeNode *node)
{
    return rangeNodeDeclaresValue(node->kind) || node->kind == RangeNodeConstruct || node->kind == RangeNodeEnum
        || node->kind == RangeNodeEnumCase;
}

static void diagnoseDuplicateMembers(SourceReport *report, RangeNode *construct)
{
    // `phase.loading` reads a case off a value, so no member of the enum
    // (a function, or a nested type, reported below) has a case's name.
    for (size_t i = 0; construct->kind == RangeNodeEnum && i < construct->itemCount; ++i) {
        RangeNode *item = construct->items[i];
        if (item->kind != RangeNodeFunction || !item->name) continue;
        for (size_t j = 0; j < construct->itemCount; ++j)
            if (construct->items[j]->kind == RangeNodeEnumCase && same(construct->items[j]->name,item->name)) {
                sourceDiagnostic(report,item->emittedBy ? item->emittedBy : item,0,"duplicate",
                    "'%s' is a case of %s, so %s declares no function of that name",item->name,construct->name,construct->name);
                break;
            }
    }
    for (size_t i = 0; i < construct->itemCount; ++i) {
        RangeNode *item = construct->items[i];
        if (!scopeDeclaration(item) || !item->name) continue;
        for (size_t j = 0; j < i; ++j)
            if (scopeDeclaration(construct->items[j]) && same(construct->items[j]->name,item->name)) {
                diagnoseDuplicate(report,construct->items[j],item,construct->name);
                break;
            }
        if (item->kind == RangeNodeConstruct || item->kind == RangeNodeEnum || item->kind == RangeNodeEnumCase)
            diagnoseDuplicateMembers(report,item);
    }
}

static int builtinMember(const RangeNode *);

/* Builtin functions are C primitives selected by name. resize, read, and write
 * act on their construct's @many member, so that construct needs exactly one. */
static int slotPrimitive(const RangeNode *function)
{
    return same(function->name,"resize") || same(function->name,"read") || same(function->name,"write");
}

static int appliesBuiltin(const RangeNode *node, const char *name)
{
    if (node->c) for (size_t i = 0; i < node->c->itemCount; ++i)
        if (macroBuiltin(node->c->items[i]->resolvedDeclaration,name)) return 1;
    return 0;
}

static int bytesDeclaration(const RangeNode *);
static int operatorName(const char *);

/* Builtin operators are C primitives selected by the operator and by the
 * owner's layout: integer arithmetic and comparison on a storage primitive,
 * joining on the bytes primitive, and on an enum without payloads (the
 * condition type, which the type checker confirms) negation and the
 * short-circuit `&` and `|`. */
static void diagnoseBuiltinOperator(SourceReport *report, RangeNode *owner, RangeNode *item, int bytes)
{
    const char *op = item->name;
    int storage = 0, payloads = 0;
    for (size_t i = 0; i < owner->itemCount; ++i) {
        if (builtinMember(owner->items[i]) && same(owner->items[i]->name,"storage")) storage = 1;
        if (owner->items[i]->kind == RangeNodeEnumCase && owner->items[i]->itemCount) payloads = 1;
    }
    int binary = item->itemCount == 1, prefix = item->itemCount == 0;
    int arithmetic = same(op,"+") || same(op,"-") || same(op,"*") || same(op,"/") || same(op,"%");
    int comparison = same(op,"<") || same(op,">") || same(op,"<=") || same(op,">=");
    int tag = owner->kind == RangeNodeEnum && !payloads;
    if (storage && binary && arithmetic)
        sourceDiagnostic(report,item,1,"C-implementation","builtin function '%s' is integer arithmetic on the storage primitive in C, trapping when the result does not fit%s",
            op,same(op,"/") || same(op,"%") ? " and on division by zero" : "");
    else if (storage && binary && comparison)
        sourceDiagnostic(report,item,1,"C-implementation","builtin function '%s' compares the storage primitive in C, signed or not as the specialization declares",op);
    else if (storage && prefix && same(op,"-"))
        sourceDiagnostic(report,item,1,"C-implementation","builtin prefix '-' negates the storage primitive in C, trapping when the result does not fit");
    else if (bytes && binary && same(op,"+"))
        sourceDiagnostic(report,item,1,"C-implementation","builtin function '+' joins two values' bytes into a new block in C");
    else if (tag && prefix && same(op,"!"))
        sourceDiagnostic(report,item,1,"C-implementation","builtin prefix '!' swaps the condition type's tags 0 and 1 in C");
    else if (tag && binary && (same(op,"&") || same(op,"|")))
        sourceDiagnostic(report,item,1,"C-implementation","builtin function '%s' is C control flow: the right operand is evaluated only when the left one does not decide the result",op);
    else sourceDiagnostic(report,item,0,"not-implemented","no C primitive is implemented for builtin function '%s' of %s",op,owner->name);
}

/* A builtin member of a grammar declaration that C reads through its field
 * adapter for that kind of node, such as Let's value. */
static int reflectionBuiltin(SourceReport *report, const RangeNode *owner, const RangeNode *member)
{
    RangeNode *shapes = report->arena->graphTypes;
    for (size_t i = 0; shapes && i < shapes->itemCount; ++i)
        if (shapes->items[i]->resolvedDeclaration == owner) return rangeGraphField(shapes->items[i],member->name) != NULL;
    return 0;
}

static void diagnoseBuiltinFunctions(SourceReport *report, RangeNode *owner)
{
    size_t slots = 0;
    int bytes = owner->kind == RangeNodeConstruct && bytesDeclaration(owner);
    if (owner->kind == RangeNodeConstruct)
        for (size_t i = 0; i < owner->itemCount; ++i)
            if (rangeNodeDeclaresValue(owner->items[i]->kind) && appliesBuiltin(owner->items[i],"many")) ++slots;
    for (size_t i = 0; i < owner->itemCount; ++i) {
        RangeNode *item = owner->items[i];
        if (item->kind == RangeNodeConstruct || item->kind == RangeNodeEnum) diagnoseBuiltinFunctions(report,item);
        if (builtinMember(item) && reflectionBuiltin(report,owner,item))
            sourceDiagnostic(report,item,1,"C-implementation","builtin member '%s' of %s is C's reflection of the declaration: "
                             "a macro reading it gets what C provides, whose type is known only at macro time",item->name,owner->name);
        else if (builtinMember(item) && bytes && same(item->name,"count"))
            sourceDiagnostic(report,item,1,"C-implementation","builtin member 'count' is the byte count the bytes primitive holds, read in C");
        else if (builtinMember(item) && ((!same(item->name,"storage") && !same(item->name,"signed") && !same(item->name,"bytes"))
            || owner->kind != RangeNodeConstruct))
            sourceDiagnostic(report,item,0,"not-implemented","no C primitive is implemented for builtin member '%s'",item->name);
        else if (builtinMember(item))
            sourceDiagnostic(report,item,1,"C-implementation","builtin member '%s' is a C layout primitive",item->name);
        if (item->kind != RangeNodeFunction || !(item->flags & RangeFlagBuiltin)) continue;
        if (same(item->name,"="))
            sourceDiagnostic(report,item,1,"C-implementation","builtin function '=' is C's structural comparison: every stored member, or the tag then the payload; it is emitted only for the types a program compares");
        else if (bytes && same(item->name,"byte"))
            sourceDiagnostic(report,item,1,"C-implementation","builtin function 'byte' reads one byte of the bytes primitive in C, checking the index");
        else if (operatorName(item->name)) diagnoseBuiltinOperator(report,owner,item,bytes);
        else if (!slotPrimitive(item) || owner->kind != RangeNodeConstruct)
            sourceDiagnostic(report,item,0,"not-implemented","no C primitive is implemented for builtin function '%s'",item->name);
        else if (slots != 1)
            sourceDiagnostic(report,item,0,"builtin","builtin function '%s' requires exactly one @many member in %s; found %zu",
                item->name,owner->name,slots);
        else sourceDiagnostic(report,item,1,"C-implementation","builtin function '%s' is implemented in C on @many storage",item->name);
    }
}

static void diagnoseDuplicates(SourceReport *report)
{
    for (size_t u = 0; u < report->count; ++u) for (size_t i = 0; i < report->units[u]->itemCount; ++i) {
        RangeNode *item = report->units[u]->items[i];
        if (item->kind == RangeNodeConstruct || item->kind == RangeNodeEnum) diagnoseDuplicateMembers(report,item);
        if (item->kind != RangeNodeConstruct && item->kind != RangeNodeEnum) continue;
        int found = 0;
        for (size_t v = 0; v <= u && !found; ++v)
            for (size_t j = 0; j < (v == u ? i : report->units[v]->itemCount) && !found; ++j) {
                RangeNode *earlier = report->units[v]->items[j];
                if ((earlier->kind == RangeNodeConstruct || earlier->kind == RangeNodeEnum) && same(earlier->name,item->name)) {
                    diagnoseDuplicate(report,earlier,item,"the program");
                    found = 1;
                }
            }
    }
}

/* ---- types -------------------------------------------------------------
 * A type is a specialization: a construct plus one value per generic. Equal
 * specializations are interned to one node, so type equality is identity.
 * Inside a construct's own bodies its type parameters stand for themselves.
 * Literals take the type their context requires; a construct's laws (its
 * macro applications) run once per distinct specialization and once per
 * supplied literal. Emission stays on the declaration, so those runs only
 * check. An operator calls the function its operand's type declares; the
 * literal families select the integer default and the condition type. */

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
    RangeNode *specializations;  /* interned RangeNodeSpecialization nodes */
    RangeNode *integer, *boolean; /* constructs the integer and boolean literal rules select */
    RangeNode *booleanType;
    LawResult *laws; size_t lawCount, lawCapacity;
    int loops; /* enclosing loops in this function: the targets of break and continue */
    RangeNode *function; /* the function being typed */
    RangeNode *output;   /* what its `return` gives: the function's result, or the entry block's status */
    /* Values compared with `=`: checked once every type is known. */
    struct { RangeNode *type, *at; const char *in; } *equalities; size_t equalityCount, equalityCapacity;
    /* Generic functions, specialized per instantiation: each instance is a
     * copy of the declaration whose type parameters name the inferred types. */
    struct { RangeNode *declaration, *instance, **types, **values, *context; const char *name; } *instances;
    size_t instanceCount, instanceCapacity;
    const char *instance; /* the instantiation being typed, as written in errors */
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
    /* Laws to run: typing never runs Range code, so a specialization or a
     * literal it meets waits here until typing returns to the top level. */
    struct { RangeNode *type, *value, *at; } *queued; size_t queuedCount, queuedCapacity;
    /* Written code as it was read: each leaf declaration and its hash. */
    struct { RangeNode *node; uint64_t hash; } *written; size_t writtenCount, writtenCapacity;
};

/* What the typer is in the middle of. Typing one declaration from inside
 * another saves it first and restores it after, so the outer one goes on as
 * it was. */
typedef struct {
    RangeNode *function, *output, *macro, *inferred, *closureSite;
    int loops, inferring, closures;
    size_t narrowedFloor, narrowedCount, typingCount;
    const char *instance;
} TyperContext;

static TyperContext typerSave(const Typer *typer)
{
    return (TyperContext){.function=typer->function,.output=typer->output,.macro=typer->macro,
        .inferred=typer->inferred,.closureSite=typer->closureSite,.loops=typer->loops,
        .inferring=typer->inferring,.closures=typer->closures,.narrowedFloor=typer->narrowedFloor,
        .narrowedCount=typer->narrowedCount,.typingCount=typer->typingCount,.instance=typer->instance};
}

static void typerRestore(Typer *typer, TyperContext saved)
{
    typer->function = saved.function; typer->output = saved.output; typer->macro = saved.macro;
    typer->inferred = saved.inferred; typer->closureSite = saved.closureSite; typer->loops = saved.loops;
    typer->inferring = saved.inferring; typer->closures = saved.closures;
    typer->narrowedFloor = saved.narrowedFloor; typer->narrowedCount = saved.narrowedCount;
    typer->typingCount = saved.typingCount; typer->instance = saved.instance;
}

/* Typing on demand starts from the top level, as typing in order does; the
 * caller restores the context returned once it is done. */
static TyperContext typerTop(Typer *typer)
{
    TyperContext saved = typerSave(typer);
    typer->function = NULL; typer->output = NULL; typer->macro = NULL; typer->inferred = NULL; typer->closureSite = NULL;
    typer->loops = 0; typer->inferring = 0; typer->closures = 0;
    typer->narrowedFloor = typer->narrowedCount; typer->typingCount = 0; typer->instance = NULL;
    return saved;
}

static void diagnoseWritten(Typer *);

/* Macro application as compiling runs it, for tests: the number of
 * applications run, or the first error, located. */
int validateMacroApplications(RangeArena *arena, RangeNode **units, size_t count,
    size_t *checked, char *error, size_t errorSize)
{
    SourceReport report = {.arena=arena,.units=units,.count=count};
    Typer *typer = diagnoseMacroApplications(&report);
    diagnoseWritten(typer);
    *checked = typer->vm->checked;
    for (SourceDiagnostic *d = report.first; d; d = d->next) {
        if (d->warning) continue;
        if (d->at) snprintf(error,errorSize,"%s:%d:%d: %s",d->at->path,d->at->line,d->at->column,d->message);
        else snprintf(error,errorSize,"%s",d->message);
        *checked = 0;
        return 0;
    }
    return 1;
}

static RangeNode *typeOf(Typer *, SourceScope *, RangeNode *, RangeNode *, RangeNode *);
static RangeNode *declaredType(Typer *, SourceScope *, RangeNode *, RangeNode *);
static RangeNode *resolveTypeReference(Typer *, SourceScope *, const char *, RangeNode *, int, RangeNode *, RangeNode *);
static void expectType(Typer *, RangeNode *, RangeNode *, RangeNode *, const char *);
static void coerce(Typer *, RangeNode *, RangeNode *, RangeNode *, const char *);

static void typeError(Typer *typer, RangeNode *at, const char *format, ...)
{
    char text[768]; va_list args; va_start(args,format);
    vsnprintf(text,sizeof(text),format,args); va_end(args);
    // Code a macro emitted is located in the macro; name the application too.
    RangeNode *emitter = typer->function ? typer->function->emittedBy : NULL;
    RangeMacroApplication *app = emitter ? emitter->macroApplication : NULL;
    size_t length = strlen(text);
    if (app && app->target && length < sizeof(text))
        snprintf(text + length,sizeof(text) - length,"; in the code @%s emits for %s at %s:%d",
                 emitter->name,app->target->name,app->target->path,app->target->line);
    length = strlen(text);
    if (typer->instance && length < sizeof(text)) snprintf(text + length,sizeof(text) - length,"; in %s",typer->instance);
    sourceDiagnostic(typer->report,at,0,"type","%s",text);
}

static void describeType(char *out, size_t size, const RangeNode *type)
{
    if (!type) { snprintf(out,size,"<unknown>"); return; }
    if (type->kind == RangeNodeTypeParameter) { snprintf(out,size,"%s",type->name); return; }
    if (type->kind == RangeNodeFunctionType) {
        size_t n = (size_t)snprintf(out,size,"(");
        for (size_t i = 0; i < type->itemCount && n < size; ++i) {
            char part[160]; describeType(part,sizeof(part),type->items[i]);
            n += (size_t)snprintf(out + n,size - n,"%s%s",i ? ", " : "",part);
        }
        char result[160] = "?";
        if (type->a) describeType(result,sizeof(result),type->a);
        if (n < size) snprintf(out + n,size - n,") -> %s",result);
        return;
    }
    size_t n = (size_t)snprintf(out,size,"%s",type->name);
    RangeNode *generics = type->generics;
    if (!generics || !generics->itemCount || n >= size) return;
    n += (size_t)snprintf(out + n,size - n,"<");
    for (size_t i = 0; i < generics->itemCount && n < size; ++i) {
        RangeNode *generic = generics->items[i];
        char inner[128];
        if (generic->kind == RangeNodeTypeParameter) describeType(inner,sizeof(inner),generic->resolvedType);
        else {
            RangeNode *value = rangeNodeRHS(generic);
            if (!value) snprintf(inner,sizeof(inner),"?");
            else if (value->kind == RangeNodeInteger) snprintf(inner,sizeof(inner),"%lld",value->integer);
            else if (value->kind == RangeNodeBool) snprintf(inner,sizeof(inner),"%s",value->integer ? "true" : "false");
            else if (value->kind == RangeNodeString && value->itemCount == 1 && (value->items[0]->flags & RangeFlagLiteral))
                snprintf(inner,sizeof(inner),"\"%s\"",value->items[0]->name);
            else snprintf(inner,sizeof(inner),"%s",value->name ? value->name : "?");
        }
        n += (size_t)snprintf(out + n,size - n,"%s%s: %s",i ? ", " : "",generic->name,inner);
    }
    if (n < size) snprintf(out + n,size - n,">");
}

static int sameGenericValue(RangeNode *x, RangeNode *y)
{
    if (x->kind == RangeNodeTypeParameter) return y->kind == RangeNodeTypeParameter && x->resolvedType == y->resolvedType;
    if (y->kind == RangeNodeTypeParameter) return 0;
    RangeNode *a = rangeNodeRHS(x), *b = rangeNodeRHS(y);
    if (!a || !b) return a == b;
    if (a == b) return 1;
    if (a->kind != b->kind) return 0;
    if (a->kind == RangeNodeInteger || a->kind == RangeNodeBool) return a->integer == b->integer;
    if (a->kind == RangeNodeString)
        return a->itemCount == 1 && b->itemCount == 1 && (a->items[0]->flags & RangeFlagLiteral)
            && (b->items[0]->flags & RangeFlagLiteral) && same(a->items[0]->name,b->items[0]->name);
    return 0;
}

static RangeNode *internSpecialization(Typer *typer, RangeNode *declaration, RangeNode *generics, int *created)
{
    *created = 0;
    for (size_t i = 0; i < typer->specializations->itemCount; ++i) {
        RangeNode *candidate = typer->specializations->items[i];
        if (candidate->resolvedDeclaration != declaration) continue;
        size_t count = generics ? generics->itemCount : 0;
        if ((candidate->generics ? candidate->generics->itemCount : 0) != count) continue;
        size_t matched = 0;
        for (size_t j = 0; j < count; ++j)
            if (sameGenericValue(candidate->generics->items[j],generics->items[j])) ++matched;
        if (matched == count) return candidate;
    }
    RangeArena *arena = typer->report->arena;
    RangeNode *specialization = rangeNodeCreate(arena,RangeNodeSpecialization,declaration->path,declaration->line,declaration->column);
    specialization->name = declaration->name;
    specialization->resolvedDeclaration = declaration;
    specialization->generics = generics;
    rangeNodeAppend(arena,typer->specializations,specialization);
    *created = 1;
    return specialization;
}

/* A copy of a node is new code: what the compiler found about the original
 * is found about it afresh. */
static void forgetFacts(RangeNode *copy)
{
    copy->flags &= ~RangeFlagFacts;
    copy->lowered = copy->narrowed = copy->promoted = NULL;
}

static RangeNode *copyGeneric(RangeArena *arena, RangeNode *generic)
{
    RangeNode *copy = rangeArenaAllocate(arena,sizeof(*copy));
    *copy = *generic;
    copy->items = NULL; copy->itemCount = 0; copy->itemCapacity = 0;
    copy->rhsReference = NULL; copy->typeName = NULL; copy->type = NULL;
    copy->a = generic->kind == RangeNodeTypeParameter ? NULL : rangeNodeRHS(generic);
    return copy;
}

/* The literal populates the one member whose default the same literal rule
 * matched; C never names that member. */
static RangeNode *literalHolder(RangeNode *declaration, RangeNode *value, size_t *holders)
{
    RangeNode *holder = NULL;
    *holders = 0;
    for (size_t i = 0; i < declaration->itemCount; ++i) {
        RangeNode *member = declaration->items[i];
        if (!rangeNodeDeclaresValue(member->kind)) continue;
        RangeNode *rhs = rangeNodeRHS(member);
        if (!rhs || !rhs->resolvedDeclaration || rhs->resolvedDeclaration != value->resolvedDeclaration) continue;
        holder = member;
        ++*holders;
    }
    return holder;
}

/* The inputs a literal gives a law: its kind and value, `-n` as one value. */
static int lawInputs(const RangeNode *value, RangeNodeKind *kind, long long *integer, const char **text)
{
    *integer = 0; *text = NULL;
    if (value->kind == RangeNodeUnary && same(value->name,"-") && value->a && value->a->kind == RangeNodeInteger) {
        *kind = RangeNodeInteger;
        *integer = -value->a->integer;
        return value->a->integer != LLONG_MIN;
    }
    *kind = value->kind;
    if (value->kind == RangeNodeInteger || value->kind == RangeNodeBool) { *integer = value->integer; return 1; }
    if (value->kind == RangeNodeString && value->itemCount == 1 && (value->items[0]->flags & RangeFlagLiteral)) {
        *text = value->items[0]->name;
        return 1;
    }
    return 0;
}

static LawResult *lawResult(Typer *typer, RangeNode *type, RangeNode *value)
{
    RangeNodeKind kind; long long integer; const char *text;
    if (!lawInputs(value,&kind,&integer,&text)) return NULL;
    for (size_t i = 0; i < typer->lawCount; ++i) {
        LawResult *result = &typer->laws[i];
        if (result->type == type && result->kind == kind && result->integer == integer
            && (result->text == text || (result->text && text && !strcmp(result->text,text)))) return result;
    }
    if (typer->lawCount == typer->lawCapacity) {
        typer->lawCapacity = typer->lawCapacity ? typer->lawCapacity * 2 : 64;
        LawResult *grown = rangeArenaAllocate(typer->report->arena,typer->lawCapacity * sizeof(*grown));
        if (typer->lawCount) memcpy(grown,typer->laws,typer->lawCount * sizeof(*grown));
        typer->laws = grown;
    }
    typer->laws[typer->lawCount] = (LawResult){.type=type,.kind=kind,.integer=integer,.text=text,.failureCount=SIZE_MAX};
    return &typer->laws[typer->lawCount++];
}

/* Run the construct's macro applications against this specialization, with
 * the supplied literal in place of the member it populates. A literal's
 * outcome is reused for every equal literal of the same type. */
static void checkLaws(Typer *typer, RangeNode *specialization, RangeNode *value, RangeNode *at)
{
    RangeNode *declaration = specialization->resolvedDeclaration;
    if (!declaration->c || !declaration->c->itemCount) return;
    if (!value) {
        if (specialization->flags & RangeFlagChecked) return;
        specialization->flags |= RangeFlagChecked;
    }
    LawResult *known = value ? lawResult(typer,specialization,value) : NULL;
    if (known && known->failureCount != SIZE_MAX) {
        for (size_t i = 0; i < known->failureCount; ++i) sourceDiagnostic(typer->report,at,0,"law","%s",known->failures[i]);
        return;
    }
    const char *failures[8];
    size_t failureCount = 0;
    RangeArena *arena = typer->report->arena;
    Resolver *vm = typer->vm;
    RangeNode *copy = rangeArenaAllocate(arena,sizeof(*copy));
    *copy = *declaration;
    copy->generics = specialization->generics;
    RangeNodeKind kind; long long integer; const char *text;
    if (value && lawInputs(value,&kind,&integer,&text)) {
        // The law sees the literal's value alone, as a literal of its own: the
        // written one carries what typing found where it is used.
        RangeNode *literal = rangeNodeCreate(arena,kind,value->path,value->line,value->column);
        literal->integer = integer;
        literal->resolvedDeclaration = (value->kind == RangeNodeUnary ? value->a : value)->resolvedDeclaration;
        if (text) {
            RangeNode *part = rangeNodeCreate(arena,RangeNodeStringPart,value->path,value->line,value->column);
            part->flags = RangeFlagLiteral;
            part->name = text;
            part->integer = (long long)strlen(text);
            rangeNodeAppend(arena,literal,part);
        }
        value = literal;
    }
    if (value) {
        size_t holders = 0;
        RangeNode *holder = literalHolder(declaration,value,&holders);
        if (holders != 1) {
            sourceDiagnostic(typer->report,at,0,"not-implemented",
                "literal materialization for '%s' is not implemented: %zu members hold a %s literal",
                declaration->name,holders,value->resolvedDeclaration->name);
            return;
        }
        copy->items = rangeArenaAllocate(arena,declaration->itemCount * sizeof(*copy->items));
        copy->itemCapacity = declaration->itemCount;
        memcpy(copy->items,declaration->items,declaration->itemCount * sizeof(*copy->items));
        RangeNode *member = rangeArenaAllocate(arena,sizeof(*member));
        *member = *holder;
        member->rhsReference = NULL; member->typeName = NULL; member->a = NULL;
        member->items = NULL; member->itemCount = 0; member->itemCapacity = 0;
        forgetFacts(member);
        RangeNode *argument = rangeNodeCreate(arena,RangeNodeArgument,value->path,value->line,value->column);
        argument->a = value;
        rangeNodeAppend(arena,member,argument);
        for (size_t i = 0; i < copy->itemCount; ++i) if (copy->items[i] == holder) copy->items[i] = member;
    }
    for (size_t i = 0; i < declaration->c->itemCount; ++i) {
        RangeNode *attribute = declaration->c->items[i];
        RangeMacroApplication *declared = attribute->macroApplication;
        if (!declared || compilerAttribute(declaration,attribute) || !declared->declaration->a) continue;
        if (macroBuiltin(declared->declaration,"many")) continue;
        // The application checks the declaration it saw: its own emitted
        // members are its output, not its input.
        RangeNode *target = copy;
        for (size_t k = 0; k < copy->itemCount; ++k) {
            if (copy->items[k]->emittedBy != attribute) continue;
            target = rangeArenaAllocate(arena,sizeof(*target));
            *target = *copy;
            target->items = rangeArenaAllocate(arena,copy->itemCount * sizeof(*target->items));
            target->itemCount = 0;
            target->itemCapacity = copy->itemCount;
            for (size_t m = 0; m < copy->itemCount; ++m)
                if (copy->items[m]->emittedBy != attribute) target->items[target->itemCount++] = copy->items[m];
            break;
        }
        RangeMacroApplication *app = rangeArenaAllocate(arena,sizeof(*app));
        *app = (RangeMacroApplication){.declaration=declared->declaration,.target=target,.unit=declared->unit,.attribute=attribute};
        jmp_buf outer;
        memcpy(outer,vm->failure,sizeof(outer));
        vm->skipEmission = 1;
        if (setjmp(vm->failure) == 0) (void)evalApplication(vm,app,0);
        else {
            char type[160], text[768];
            describeType(type,sizeof(type),specialization);
            snprintf(text,sizeof(text),"%s does not satisfy @%s: %s",type,app->declaration->name,vm->error);
            sourceDiagnostic(typer->report,at,0,"law","%s",text);
            if (failureCount < sizeof(failures)/sizeof(*failures))
                failures[failureCount++] = rangeArenaIntern(arena,text,strlen(text));
        }
        vm->skipEmission = 0;
        memcpy(vm->failure,outer,sizeof(outer));
    }
    if (known) {
        known->failures = rangeArenaAllocate(arena,(failureCount ? failureCount : 1) * sizeof(*known->failures));
        memcpy(known->failures,failures,failureCount * sizeof(*failures));
        known->failureCount = failureCount;
    }
}

/* A law to run once typing is back at the top level. */
static void queueLaws(Typer *typer, RangeNode *specialization, RangeNode *value, RangeNode *at)
{
    if (typer->queuedCount == typer->queuedCapacity) {
        typer->queuedCapacity = typer->queuedCapacity ? typer->queuedCapacity * 2 : 64;
        void *grown = rangeArenaAllocate(typer->report->arena,typer->queuedCapacity * sizeof(*typer->queued));
        if (typer->queuedCount) memcpy(grown,typer->queued,typer->queuedCount * sizeof(*typer->queued));
        typer->queued = grown;
    }
    typer->queued[typer->queuedCount].type = specialization;
    typer->queued[typer->queuedCount].value = value;
    typer->queued[typer->queuedCount++].at = at;
}

/* Run every queued law, in the order typing met them, including any queued
 * while they run. */
static void drainLaws(Typer *typer)
{
    for (size_t i = 0; i < typer->queuedCount; ++i)
        checkLaws(typer,typer->queued[i].type,typer->queued[i].value,typer->queued[i].at);
    typer->queuedCount = 0;
}

/* Build the specialization named by generic arguments, in the context whose
 * type parameters the arguments may mention. */
static RangeNode *specialize(Typer *typer, SourceScope *scope, RangeNode *declaration,
                             RangeNode *arguments, RangeNode *context, RangeNode *at)
{
    RangeArena *arena = typer->report->arena;
    RangeNode *declared = declaration->generics, *generics = NULL;
    int isDefault = 1;
    size_t positional = 0;
    if (declared) {
        generics = rangeNodeCreate(arena,RangeNodeBlock,declaration->path,declaration->line,declaration->column);
        generics->name = "genericMembers";
        for (size_t i = 0; i < declared->itemCount; ++i) {
            RangeNode *generic = declared->items[i], *argument = NULL;
            size_t unnamed = 0;
            if (arguments) for (size_t j = 0; j < arguments->itemCount; ++j) {
                RangeNode *candidate = arguments->items[j];
                if (candidate->name ? same(candidate->name,generic->name)
                    : generic->kind == RangeNodeTypeParameter && unnamed++ == positional) { argument = candidate; break; }
            }
            RangeNode *copy = copyGeneric(arena,generic);
            if (generic->kind == RangeNodeTypeParameter) {
                ++positional;
                if (!argument) { typeError(typer,at,"'%s' requires generic %s",declaration->name,generic->name); return NULL; }
                RangeNode *reference = argument->a;
                if (!reference || reference->kind != RangeNodeName) { typeError(typer,argument,"generic %s requires a type",generic->name); return NULL; }
                RangeNode *type = resolveTypeReference(typer,scope,reference->name,reference->generics,reference->flags,context,reference);
                if (!type) return NULL;
                copy->resolvedType = type;
                isDefault = 0;
            } else if (argument) {
                SourceScope declarationScope = {.owner=declaration};
                RangeNode *expected = declaredType(typer,&declarationScope,generic,NULL);
                RangeNode *actual = typeOf(typer,scope,argument->a,expected,context);
                if (expected && actual && expected != actual) {
                    char want[160], got[160];
                    describeType(want,sizeof(want),expected); describeType(got,sizeof(got),actual);
                    typeError(typer,argument->a,"generic %s requires %s; found %s",generic->name,want,got);
                    return NULL;
                }
                copy->a = argument->a;
                if (!sameGenericValue(copy,generic)) isDefault = 0;
            } else if (generic->typeName) {
                // `<let width: Int>` has no default: each use supplies it.
                typeError(typer,at,"'%s' requires generic %s",declaration->name,generic->name);
                return NULL;
            }
            rangeNodeAppend(arena,generics,copy);
        }
        size_t unnamed = 0;
        if (arguments) for (size_t j = 0; j < arguments->itemCount; ++j) {
            RangeNode *candidate = arguments->items[j];
            int known = 0;
            if (!candidate->name) known = unnamed++ < positional;
            else for (size_t i = 0; i < declared->itemCount; ++i)
                if (same(candidate->name,declared->items[i]->name)) known = 1;
            if (!known && candidate->name) { typeError(typer,candidate,"'%s' has no generic named '%s'",declaration->name,candidate->name); return NULL; }
            if (!known) { typeError(typer,candidate,"'%s' takes %zu type arguments; %zu supplied",declaration->name,positional,unnamed); return NULL; }
        }
    } else if (arguments && arguments->itemCount) {
        typeError(typer,at,"'%s' takes no generic arguments",declaration->name);
        return NULL;
    }
    int created = 0;
    RangeNode *specialization = internSpecialization(typer,declaration,generics,&created);
    if (created) {
        // The declaration's own application already covered its defaults.
        if (isDefault) specialization->flags |= RangeFlagChecked;
        else queueLaws(typer,specialization,NULL,at);
    }
    return specialization;
}

/* Inside its own bodies, a construct is specialized by its own parameters. */
static RangeNode *selfSpecialization(Typer *typer, RangeNode *declaration)
{
    RangeArena *arena = typer->report->arena;
    RangeNode *generics = NULL;
    if (declaration->generics) {
        generics = rangeNodeCreate(arena,RangeNodeBlock,declaration->path,declaration->line,declaration->column);
        generics->name = "genericMembers";
        for (size_t i = 0; i < declaration->generics->itemCount; ++i) {
            RangeNode *generic = declaration->generics->items[i], *copy = copyGeneric(arena,generic);
            if (generic->kind == RangeNodeTypeParameter) copy->resolvedType = generic;
            else if (generic->typeName) copy->a = NULL; /* a required value: none in the bodies' own view */
            rangeNodeAppend(arena,generics,copy);
        }
    }
    int created = 0;
    RangeNode *specialization = internSpecialization(typer,declaration,generics,&created);
    specialization->flags |= RangeFlagChecked;
    return specialization;
}

static int parametric(const RangeNode *);
static int graphConstruct(Typer *, const RangeNode *);

/* ---- function types ----
 * `(A, B) -> R` is a parameter's type: the parameter takes a closure, which
 * runs only while the call it is passed to runs. Function types are interned,
 * so equal ones are one node; one whose result is still being inferred, for a
 * generic call, is not interned and has no result. */
static int isFunctionType(const RangeNode *type)
{
    return type && type->kind == RangeNodeFunctionType;
}

static RangeNode *functionType(Typer *typer, RangeNode **parameters, size_t count, RangeNode *result, RangeNode *at)
{
    for (size_t i = 0; result && i < typer->functionTypes->itemCount; ++i) {
        RangeNode *candidate = typer->functionTypes->items[i];
        if (candidate->a != result || candidate->itemCount != count) continue;
        size_t matched = 0;
        while (matched < count && candidate->items[matched] == parameters[matched]) ++matched;
        if (matched == count) return candidate;
    }
    RangeArena *arena = typer->report->arena;
    RangeNode *type = rangeNodeCreate(arena,RangeNodeFunctionType,at->path,at->line,at->column);
    type->name = "->";
    for (size_t i = 0; i < count; ++i) rangeNodeAppend(arena,type,parameters[i]);
    type->a = result;
    if (result) rangeNodeAppend(arena,typer->functionTypes,type);
    return type;
}

/* A construct with no stored members, such as Void: it has one value and
 * holds nothing, so a closure that returns it yields no value, and `return`
 * needs none. The rule is structural; C names no such type. */
static int unitType(Typer *typer, const RangeNode *type)
{
    if (!type || type->kind != RangeNodeSpecialization) return 0;
    RangeNode *declaration = type->resolvedDeclaration;
    if (declaration->kind != RangeNodeConstruct || graphConstruct(typer,declaration)) return 0;
    for (size_t i = 0; i < declaration->itemCount; ++i)
        if (rangeNodeDeclaresValue(declaration->items[i]->kind)) return 0;
    return 1;
}

/* ---- macro time ----
 * A macro type, @member, names a declaration of any kind that applies the
 * macro, as a grammar kind such as Let names a declaration of that kind. Its
 * values are declarations, which exist only up to macro time, and so do
 * values of grammar kinds and of types holding them, such as Array<@member>:
 * they have no runtime layout, and the evaluator compares them. A macro
 * type's specialization has the macro as its declaration.
 *
 * Some values' types depend on which declaration a reflection value holds:
 * a member kind's C-backed value, a field only some kinds of a macro type
 * declare, and what an operator or a function makes of a macro type's value.
 * Their type is known at macro time: it is accepted wherever a type is
 * expected, what is computed from it is known at macro time too, and the
 * evaluator checks it when the macro runs. */

static int isMacroType(const RangeNode *type)
{
    return type && type->kind == RangeNodeSpecialization && type->resolvedDeclaration
        && type->resolvedDeclaration->kind == RangeNodeMacro;
}

static int deferredType(const Typer *typer, const RangeNode *type)
{
    return type && type == typer->deferred;
}

/* A value whose operations are chosen only at macro time: one known then, or
 * a declaration of some kind a macro type admits. */
static int macroOperand(const Typer *typer, const RangeNode *type)
{
    return deferredType(typer,type) || isMacroType(type);
}

/* Whether values of `type` exist only up to macro time. */
static int macroTimeType(Typer *typer, const RangeNode *type)
{
    if (deferredType(typer,type)) return 1;
    if (!type || type->kind != RangeNodeSpecialization) return 0;
    if (isMacroType(type) || graphConstruct(typer,type->resolvedDeclaration)) return 1;
    for (size_t i = 0; type->generics && i < type->generics->itemCount; ++i) {
        RangeNode *generic = type->generics->items[i];
        if (generic->kind == RangeNodeTypeParameter && macroTimeType(typer,generic->resolvedType)) return 1;
    }
    return 0;
}

/* `@member` as a type: the one macro of that name. */
static RangeNode *macroTypeNamed(Typer *typer, const char *name, RangeNode *at)
{
    RangeNode *macro = NULL;
    size_t found = 0;
    for (size_t u = 0; u < typer->report->count; ++u) for (size_t i = 0; i < typer->report->units[u]->itemCount; ++i) {
        RangeNode *candidate = typer->report->units[u]->items[i];
        if (candidate->kind == RangeNodeMacro && same(candidate->name,name)) { macro = candidate; ++found; }
    }
    if (!found) return NULL; /* undeclared is reported already */
    if (found > 1) { typeError(typer,at,"'@%s' names %zu macros; a macro type names one",name,found); return NULL; }
    int created = 0;
    RangeNode *type = internSpecialization(typer,macro,NULL,&created);
    if (created) {
        char spelled[160];
        snprintf(spelled,sizeof(spelled),"@%s",name);
        type->name = rangeArenaIntern(typer->report->arena,spelled,strlen(spelled));
        type->flags |= RangeFlagChecked; /* the kinds it admits ran their own laws */
    }
    return type;
}

/* A value of a kind is a value of a macro type that kind applies: an Enum is
 * a @nominal. */
static int converts(const RangeNode *expected, const RangeNode *actual)
{
    return isMacroType(expected) && actual && actual->kind == RangeNodeSpecialization
        && appliesMacro(actual->resolvedDeclaration,expected->resolvedDeclaration);
}

static RangeNode *resolveTypeReference(Typer *typer, SourceScope *scope, const char *name,
                                       RangeNode *generics, int flags, RangeNode *context, RangeNode *at)
{
    if (!name || !*name) return NULL;
    if (flags & RangeFlagFunction) {
        // Each part resolves where the written type stands. A result that
        // does not resolve yet, an unbound type parameter, is inferred.
        if (!generics) return NULL;
        RangeNode **parts = rangeArenaAllocate(typer->report->arena,(generics->itemCount ? generics->itemCount : 1) * sizeof(*parts));
        for (size_t i = 0; i < generics->itemCount; ++i) {
            RangeNode *written = generics->items[i]->a;
            parts[i] = resolveTypeReference(typer,scope,written->name,written->generics,written->flags,context,written);
            if (!parts[i]) return NULL;
        }
        RangeNode *written = generics->a;
        RangeNode *result = written ? resolveTypeReference(typer,scope,written->name,written->generics,written->flags,context,written) : NULL;
        return functionType(typer,parts,generics->itemCount,result,at);
    }
    if (flags & RangeFlagOptional) {
        // `T?` is the construct applying @optional, specialized with T.
        RangeNode *optional = NULL;
        size_t found = 0;
        for (size_t u = 0; u < typer->report->count; ++u) for (size_t i = 0; i < typer->report->units[u]->itemCount; ++i) {
            RangeNode *candidate = typer->report->units[u]->items[i];
            if ((candidate->kind == RangeNodeConstruct || candidate->kind == RangeNodeEnum)
                && appliesBuiltin(candidate,"optional")) { optional = candidate; ++found; }
        }
        if (found != 1) {
            sourceDiagnostic(typer->report,at,0,"undeclared","'%s?' needs exactly one construct applying @optional; found %zu",name,found);
            return NULL;
        }
        RangeArena *arena = typer->report->arena;
        RangeNode *wrapped = rangeNodeCreate(arena,RangeNodeName,at->path,at->line,at->column);
        wrapped->name = name; wrapped->generics = generics; wrapped->flags = flags & ~RangeFlagOptional;
        RangeNode *arguments = rangeNodeCreate(arena,RangeNodeBlock,at->path,at->line,at->column);
        arguments->name = "genericArguments";
        RangeNode *argument = rangeNodeCreate(arena,RangeNodeArgument,at->path,at->line,at->column);
        argument->a = wrapped;
        rangeNodeAppend(arena,arguments,argument);
        return specialize(typer,scope,optional,arguments,context,at);
    }
    if (flags & RangeFlagMacroType) return macroTypeNamed(typer,name,at);
    if (context && context->generics)
        for (size_t i = 0; i < context->generics->itemCount; ++i) {
            RangeNode *generic = context->generics->items[i];
            if (generic->kind == RangeNodeTypeParameter && same(generic->name,name)) return generic->resolvedType;
        }
    RangeNode *declaration = dottedLookup(typer->report,scope,name,2);
    // A generic function's type parameter, in an instance, names the inferred type.
    if (declaration && declaration->kind == RangeNodeTypeParameter && declaration->resolvedType && !generics)
        return declaration->resolvedType;
    if (!declaration || (declaration->kind != RangeNodeConstruct && declaration->kind != RangeNodeEnum))
        return NULL; /* undeclared is reported already */
    // As in Swift, a generic declaration's bare name inside its own bodies is
    // the specialization being typed: `Optional` in Optional<Wrapped>'s methods.
    // Value generics too: `#name` in Int's operators is Int<bits: 8> there.
    if (!generics && context && context->kind == RangeNodeSpecialization
        && context->resolvedDeclaration == declaration && declaration->generics) return context;
    return specialize(typer,scope,declaration,generics,context,at);
}

static RangeNode *optionalWrapped(Typer *, RangeNode *, RangeNode **);
static int optionalWithoutValue(const RangeNode *);

/* The optional's case without a payload, a value written beside `at`: what
 * `let v: T?` starts as. */
static RangeNode *absentValue(Typer *typer, RangeNode *at, RangeNode *type)
{
    if (!optionalWrapped(typer,type,NULL)) return NULL;
    RangeNode *declaration = type->resolvedDeclaration;
    for (size_t i = 0; i < declaration->itemCount; ++i) {
        RangeNode *entry = declaration->items[i];
        if (entry->kind != RangeNodeEnumCase || entry->itemCount) continue;
        RangeNode *value = rangeNodeCreate(typer->report->arena,RangeNodeCase,at->path,at->line,at->column);
        value->name = entry->name;
        value->resolvedDeclaration = entry;
        value->type = type;
        return value;
    }
    return NULL;
}

static RangeNode *declaredType(Typer *typer, SourceScope *scope, RangeNode *node, RangeNode *context)
{
    if (node->kind == RangeNodeParameter)
        return node->b ? resolveTypeReference(typer,scope,node->b->name,node->b->generics,node->flags,context,node->b) : NULL;
    if (node->flags & RangeFlagMany) return NULL; /* @many storage is not a standalone value */
    if (node->lowered && node->lowered->kind == RangeNodeCall) return node->lowered->type; /* `let r: step(x: 1)` */
    if (node->typeName && (node->flags & RangeFlagApplication) && node->type) {
        // Construction. A generic construct's member, such as Box<T>'s
        // `state items: Array<T>()`, has its type in the specialization asked about.
        RangeNode *owner = context && context->kind == RangeNodeSpecialization ? context->resolvedDeclaration : NULL;
        int member = 0;
        for (size_t i = 0; owner && parametric(owner) && i < owner->itemCount; ++i) member |= owner->items[i] == node;
        if (!member) return node->type;
        SourceScope ownerScope = {.owner=owner};
        return resolveTypeReference(typer,&ownerScope,node->typeName,node->generics,node->flags & ~RangeFlagApplication,context,node);
    }
    // A bare name's resolved declaration decides its meaning: a value is
    // copied, a construct is a requirement.
    if (node->typeName && node->rhsReference && !node->generics) {
        RangeNode *value = sourceLookup(typer->report,scope,node->typeName,0);
        if (value && (rangeNodeDeclaresValue(value->kind) || value->kind == RangeNodeParameter) && value != node) {
            node->rhsReference->resolvedDeclaration = value;
            return typeOf(typer,scope,node->rhsReference,NULL,context);
        }
    }
    if (node->typeName) {
        RangeNode *type = resolveTypeReference(typer,scope,node->typeName,node->generics,node->flags,context,node);
        // An enum's lets are its cases' payload fields: types, not bindings.
        if (optionalWithoutValue(node) && !(scope && scope->owner && scope->owner->kind == RangeNodeEnum))
            node->lowered = absentValue(typer,node,type);
        return type;
    }
    // `let inner: Outer.Inner` requires the nested type its path names.
    if ((node->flags & RangeFlagRequired) || requiredPath(typer->report,scope,node)) {
        node->flags |= RangeFlagRequired;
        return resolveTypeReference(typer,scope,typePathText(typer->report,node->items[0]->a),NULL,node->flags,context,node);
    }
    // A literal member of the construct its literal selects (Int's `value: 0`)
    // has that construct's own specialization.
    RangeNode *rhs = rangeNodeRHS(node);
    return rhs ? typeOf(typer,scope,rhs,context,context) : NULL;
}

static RangeNode *findMember(RangeNode *declaration, const char *name)
{
    for (size_t i = 0; i < declaration->itemCount; ++i)
        if (rangeNodeDeclaresValue(declaration->items[i]->kind) && same(declaration->items[i]->name,name))
            return declaration->items[i];
    return NULL;
}

static RangeNode *findFunction(RangeNode *owner, const char *name)
{
    for (size_t i = 0; i < owner->itemCount; ++i)
        if (owner->items[i]->kind == RangeNodeFunction && same(owner->items[i]->name,name)) return owner->items[i];
    return NULL;
}

/* Overloads differ in their labels: a call selects the function whose
 * labels it writes, or else the first of that name, which reports why the
 * call does not fit it. */
static RangeNode *findCalledFunction(RangeNode *owner, const char *name, const RangeNode *call)
{
    for (size_t i = 0; call && i < owner->itemCount; ++i) {
        RangeNode *function = owner->items[i];
        if (function->kind != RangeNodeFunction || !same(function->name,name) || function->itemCount != call->itemCount) continue;
        int labels = 1;
        for (size_t j = 0; j < call->itemCount && labels; ++j) labels = argumentFits(call->items[j],function,j);
        if (labels) return function;
    }
    return findFunction(owner,name);
}

/* A member's type in a specialization of its declaration. A grammar kind's
 * builtin member without a type, such as Let's value, is C's reflection of
 * the declaration, known at macro time. */
static RangeNode *memberType(Typer *typer, RangeNode *declaration, RangeNode *member, RangeNode *receiver)
{
    if (builtinMember(member) && !member->typeName && graphConstruct(typer,declaration)) return typer->deferred;
    SourceScope scope = {.owner=declaration};
    return declaredType(typer,&scope,member,receiver);
}

/* The kinds a macro type admits: the constructs and enums applying its macro. */
static size_t macroKinds(Typer *typer, const RangeNode *type, RangeNode **kinds, size_t capacity)
{
    size_t count = 0;
    for (size_t u = 0; u < typer->report->count; ++u) for (size_t i = 0; i < typer->report->units[u]->itemCount; ++i) {
        RangeNode *kind = typer->report->units[u]->items[i];
        if ((kind->kind == RangeNodeConstruct || kind->kind == RangeNodeEnum)
            && appliesMacro(kind,type->resolvedDeclaration) && count < capacity) kinds[count++] = kind;
    }
    return count;
}

/* `member.name` on a value of a macro type: the type every kind admitted
 * gives the field, when all declare it with one type. A field only some
 * kinds declare, or declare with different types, is known at macro time,
 * from the declaration the value holds. */
static RangeNode *macroTypeMember(Typer *typer, RangeNode *type, const char *name, RangeNode *at)
{
    RangeNode *kinds[32], *found = NULL;
    size_t count = macroKinds(typer,type,kinds,32), declaring = 0;
    int agree = 1, function = 0;
    for (size_t i = 0; i < count; ++i) {
        RangeNode *member = findMember(kinds[i],name);
        if (!member) { function |= findFunction(kinds[i],name) != NULL; continue; }
        if (member->flags & RangeFlagMany) { typeError(typer,at,"'%s' holds @many storage and is not a value",name); return NULL; }
        RangeNode *field = memberType(typer,kinds[i],member,selfSpecialization(typer,kinds[i]));
        if (!declaring++) found = field;
        else if (field != found) agree = 0;
    }
    if (!count) return NULL; /* no kind applies the macro: nothing says what its values hold */
    if (!declaring) {
        char t[160]; describeType(t,sizeof(t),type);
        if (function) typeError(typer,at,"'%s.%s' is a function; call it",t,name);
        else typeError(typer,at,"%s has no member '%s'",t,name);
        return NULL;
    }
    return declaring == count && agree && found ? found : typer->deferred;
}

static RangeNode *lookupFunction(SourceReport *report, SourceScope *scope, const char *name)
{
    for (; scope; scope = scope->parent) {
        RangeNode *function = findFunction(scope->owner,name);
        if (function) return function;
    }
    for (size_t u = 0; u < report->count; ++u) {
        RangeNode *function = findFunction(report->units[u],name);
        if (function) return function;
    }
    return NULL;
}

/* ---- enums ----
 * An enum is a closed union: a value is one of its cases, and a case may carry
 * payload fields. A case's fields are Let nodes named by label, or by position
 * when unlabeled. The case's ordinal is its tag. */

static int isEnum(const RangeNode *type)
{
    return type && type->kind == RangeNodeSpecialization && type->resolvedDeclaration
        && type->resolvedDeclaration->kind == RangeNodeEnum;
}

static RangeNode *enumCase(const RangeNode *declaration, const char *name)
{
    for (size_t i = 0; declaration && name && i < declaration->itemCount; ++i)
        if (declaration->items[i]->kind == RangeNodeEnumCase && same(declaration->items[i]->name,name))
            return declaration->items[i];
    return NULL;
}

static int enumPayloads(const RangeNode *declaration)
{
    for (size_t i = 0; i < declaration->itemCount; ++i)
        if (declaration->items[i]->kind == RangeNodeEnumCase && declaration->items[i]->itemCount) return 1;
    return 0;
}

static int labeledField(const RangeNode *field)
{
    return field->name && !(field->name[0] >= '0' && field->name[0] <= '9');
}

static int parametric(const RangeNode *declaration)
{
    for (size_t i = 0; declaration->generics && i < declaration->generics->itemCount; ++i)
        if (declaration->generics->items[i]->kind == RangeNodeTypeParameter) return 1;
    return 0;
}

/* A payload field's type in this specialization of its enum. */
static RangeNode *caseFieldType(Typer *typer, RangeNode *type, RangeNode *field)
{
    RangeNode *declaration = type->resolvedDeclaration;
    if (!parametric(declaration)) return field->type;
    SourceScope scope = {.owner=declaration};
    return declaredType(typer,&scope,field,type);
}

/* A literal of an enum names the case spelled like it: `true` is case true. */
static const char *literalSpelling(const RangeNode *literal)
{
    if (literal->kind == RangeNodeBool) return literal->integer ? "true" : "false";
    if (literal->kind == RangeNodeInteger) return literal->name;
    return NULL;
}

static RangeNode *literalCase(const RangeNode *declaration, const RangeNode *literal)
{
    return enumCase(declaration,literalSpelling(literal));
}

/* The enum a `.case` names: the one its context expects. */
static RangeNode *contextualEnum(Typer *typer, RangeNode *at, RangeNode *expected)
{
    if (isEnum(expected)) return expected;
    if (expected) {
        char want[160]; describeType(want,sizeof(want),expected);
        typeError(typer,at,"'.%s' names an enum case, but the context expects %s",at->name,want);
    } else typeError(typer,at,"'.%s' needs a context that names its enum",at->name);
    return NULL;
}

/* `Light.red`: the enum written in the path, specialized by its context when
 * the path supplies no generic arguments. */
static RangeNode *pathEnum(Typer *typer, SourceScope *scope, RangeNode *declaration, RangeNode *path,
                           RangeNode *expected, RangeNode *context, RangeNode *at)
{
    if (path->generics) return specialize(typer,scope,declaration,path->generics,context,at);
    if (expected && expected->kind == RangeNodeSpecialization && expected->resolvedDeclaration == declaration) return expected;
    if (context && context->resolvedDeclaration == declaration) return context;
    if (!parametric(declaration)) return specialize(typer,scope,declaration,NULL,context,at);
    typeError(typer,at,"'%s' needs its generic arguments here; the context does not supply them",declaration->name);
    return NULL;
}

/* `Int?` written before `.case`, as in `Int?.absent`: the optional of the
 * type, the enum applying @optional specialized with it. */
static RangeNode *optionalPath(Typer *typer, SourceScope *scope, RangeNode *path, RangeNode *context)
{
    if (!path || path->kind != RangeNodeName || !(path->flags & RangeFlagOptional)) return NULL;
    RangeNode *type = resolveTypeReference(typer,scope,path->name,path->generics,RangeFlagOptional,context,path);
    return isEnum(type) ? type : NULL;
}

static RangeNode *namedCase(Typer *typer, RangeNode *type, const char *name, RangeNode *at)
{
    RangeNode *found = enumCase(type->resolvedDeclaration,name);
    if (!found) { char t[160]; describeType(t,sizeof(t),type); typeError(typer,at,"%s has no case '%s'",t,name); }
    return found;
}

/* `.value(number: 7)`: one argument per payload field, in order, labeled as
 * the field is. */
static void typePayload(Typer *typer, SourceScope *scope, RangeNode *at, RangeNode *type, RangeNode *entry,
                        RangeNode **arguments, size_t count, RangeNode *context)
{
    char t[160]; describeType(t,sizeof(t),type);
    if (count != entry->itemCount)
        typeError(typer,at,"case '%s' of %s takes %zu payload fields; %zu supplied",entry->name,t,entry->itemCount,count);
    for (size_t i = 0; i < count && i < entry->itemCount; ++i) {
        RangeNode *argument = arguments[i], *field = entry->items[i];
        if (labeledField(field) && !same(argument->name,field->name))
            typeError(typer,argument,"payload field %zu of '%s' requires label '%s'",i + 1,entry->name,field->name);
        else if (!labeledField(field) && argument->name)
            typeError(typer,argument,"payload field %zu of '%s' takes no label",i + 1,entry->name);
        argument->resolvedDeclaration = field;
        RangeNode *expected = caseFieldType(typer,type,field);
        char what[200]; snprintf(what,sizeof(what),"payload field %zu of '%s'",i + 1,entry->name);
        coerce(typer,argument->a,expected,typeOf(typer,scope,argument->a,expected,context),what);
    }
}

static int isLiteral(const RangeNode *node)
{
    return node->kind == RangeNodeInteger || node->kind == RangeNodeBool || node->kind == RangeNodeString;
}

/* Operands typed from the other side: literals and `.case` forms. */
static int contextual(const RangeNode *node)
{
    return node && (isLiteral(node) || node->kind == RangeNodeCase
        || (node->kind == RangeNodeCall && node->a && node->a->kind == RangeNodeCase));
}

/* A construct whose layout is the bytes primitive: UTF-8 bytes C holds. */
static int bytesDeclaration(const RangeNode *declaration)
{
    for (size_t i = 0; declaration && i < declaration->itemCount; ++i)
        if (builtinMember(declaration->items[i]) && same(declaration->items[i]->name,"bytes")) return 1;
    return 0;
}

static int bytesType(const RangeNode *type)
{
    return type && type->kind == RangeNodeSpecialization && bytesDeclaration(type->resolvedDeclaration);
}

typedef struct { RangeNode *seen[64]; size_t count; } Comparing;

/* `a + b` calls the function named by the operator, `+`, that a's type
 * declares, with b as its one argument; `-a` calls the `-` that takes none.
 * The symbol and the arity are the key; overloads with the same signature are
 * rejected, so a type has at most one such function. */
static RangeNode *operatorFunction(const RangeNode *declaration, const char *symbol, size_t arity)
{
    if (declaration && (declaration->kind == RangeNodeConstruct || declaration->kind == RangeNodeEnum))
        for (size_t i = 0; i < declaration->itemCount; ++i)
            if (declaration->items[i]->kind == RangeNodeFunction && same(declaration->items[i]->name,symbol)
                && declaration->items[i]->itemCount == arity) return declaration->items[i];
    return NULL;
}

/* A function named by an operator symbol rather than a name. */
static int operatorName(const char *name)
{
    return name && *name && !isalpha((unsigned char)*name) && *name != '_';
}

/* `&` and `|` evaluate their right operand only when the left does not
 * decide the result: their builtin functions are C control flow. */
static int shortCircuit(const RangeNode *function)
{
    return function && (function->flags & RangeFlagBuiltin) && (same(function->name,"&") || same(function->name,"|"));
}

/* `=` on values of `type` is checked once every type is known: layouts and
 * member types are complete then. */
static int nativeConcrete(const RangeNode *);

static void noteEquality(Typer *typer, RangeNode *type, RangeNode *at)
{
    if (!nativeConcrete(type)) return; /* it mentions a type parameter: checked per specialization */
    if (macroTimeType(typer,type)) {
        // Values that exist only up to macro time hold declarations.
        sourceDiagnostic(typer->report,at,1,"C-implementation","'=' here compares values that exist only up to macro time, in C: declarations by their identity");
        return;
    }
    if (typer->equalityCount == typer->equalityCapacity) {
        typer->equalityCapacity = typer->equalityCapacity ? typer->equalityCapacity * 2 : 64;
        void *grown = rangeArenaAllocate(typer->report->arena,typer->equalityCapacity * sizeof(*typer->equalities));
        if (typer->equalityCount) memcpy(grown,typer->equalities,typer->equalityCount * sizeof(*typer->equalities));
        typer->equalities = grown;
    }
    typer->equalities[typer->equalityCount].type = type;
    typer->equalities[typer->equalityCount].in = typer->instance;
    typer->equalities[typer->equalityCount++].at = at;
}

static void expectType(Typer *typer, RangeNode *at, RangeNode *expected, RangeNode *actual, const char *what)
{
    if (!expected || !actual || expected == actual || deferredType(typer,expected) || deferredType(typer,actual)
        || converts(expected,actual)) return;
    char want[160], got[160];
    describeType(want,sizeof(want),expected); describeType(got,sizeof(got),actual);
    typeError(typer,at,"%s requires %s; found %s",what,want,got);
}

/* `T?` is the enum applying @optional: its single payload case and, in this
 * specialization, the type that case wraps. */
static RangeNode *optionalWrapped(Typer *typer, RangeNode *type, RangeNode **present)
{
    if (!isEnum(type) || !appliesBuiltin(type->resolvedDeclaration,"optional")) return NULL;
    RangeNode *declaration = type->resolvedDeclaration, *payload = NULL;
    size_t payloads = 0;
    for (size_t i = 0; i < declaration->itemCount; ++i) {
        RangeNode *entry = declaration->items[i];
        if (entry->kind != RangeNodeEnumCase || !entry->itemCount) continue;
        payloads += entry->itemCount == 1 ? 1 : 2;
        payload = entry;
    }
    if (payloads != 1) return NULL;
    if (present) *present = payload;
    return caseFieldType(typer,type,payload->items[0]);
}

/* Optional promotion, as in Swift: where `T?` is expected, a value of T is the
 * present case holding it. The optional is recorded beside the expression,
 * whose type stays T. */
static void coerce(Typer *typer, RangeNode *expr, RangeNode *expected, RangeNode *actual, const char *what)
{
    RangeNode *wrapped = NULL;
    if (expr) expr->promoted = NULL; /* typing records it afresh */
    if (deferredType(typer,expected) || deferredType(typer,actual) || converts(expected,actual)) return;
    if (expr && expected && actual && expected != actual && (wrapped = optionalWrapped(typer,expected,NULL))
        && (wrapped == actual || converts(wrapped,actual))) {
        expr->promoted = expected;
        return;
    }
    expectType(typer,expr,expected,actual,what);
}

/* `.north` where `Direction?` is expected names Direction's case, unless the
 * optional has a case of that name. */
static RangeNode *caseContext(Typer *typer, RangeNode *enumeration, const char *name)
{
    if (!enumeration || enumCase(enumeration->resolvedDeclaration,name)) return enumeration;
    RangeNode *wrapped = optionalWrapped(typer,enumeration,NULL);
    return isEnum(wrapped) && enumCase(wrapped->resolvedDeclaration,name) ? wrapped : enumeration;
}

/* The law checks `value`: the literal itself, or `-literal` as one value. */
static RangeNode *typeLiteral(Typer *typer, RangeNode *literal, RangeNode *value, RangeNode *expected)
{
    RangeNode *rule = literal->resolvedDeclaration;
    if (!rule || !rule->literalDefault) return NULL;
    RangeNode *declaration = rule->literalDefault, *type;
    RangeNode *wrapped = optionalWrapped(typer,expected,NULL);
    if (wrapped && expected->resolvedDeclaration != declaration) expected = wrapped; /* promoted where it is used */
    if (expected && expected->kind == RangeNodeSpecialization && expected->resolvedDeclaration == declaration) type = expected;
    else type = specialize(typer,NULL,declaration,NULL,NULL,literal);
    if (type && declaration->kind == RangeNodeEnum) {
        // The literal is one of the enum's cases; the enum's laws ran on the declaration.
        if (value != literal || !literalCase(declaration,literal))
            typeError(typer,value,"this literal names no case of %s",declaration->name);
    } else if (type) queueLaws(typer,type,value,value);
    literal->type = type;
    return type;
}

/* Construction inputs: let and state members that are neither builtin nor
 * @many storage, which starts empty. A member with a default is optional;
 * one without is required. */
static int constructionInput(const RangeNode *member)
{
    return (member->kind == RangeNodeLet || member->kind == RangeNodeState)
        && !builtinMember(member) && !(member->flags & RangeFlagMany);
}

/* `let v: T?` written without a value: it starts as the optional's case
 * without a payload, which typing records beside it. */
static int optionalWithoutValue(const RangeNode *node)
{
    return (node->kind == RangeNodeLet || node->kind == RangeNodeState) && node->typeName
        && (node->flags & RangeFlagOptional) && !(node->flags & (RangeFlagApplication | RangeFlagMacroType))
        && !node->rhsReference && !node->a && !node->itemCount;
}

/* A local's value, or a member's default: what typing recorded beside the
 * declaration; else an inferred RHS; the declaration itself for a
 * construction; or a copied name. A bare type reference or a type path is a
 * requirement and supplies nothing. */
static RangeNode *declarationValue(RangeNode *node)
{
    if (node->lowered) return node->lowered;
    if (node->flags & RangeFlagRequired) return NULL;
    if (!node->typeName) return rangeNodeRHS(node);
    if (node->flags & RangeFlagApplication) return node;
    RangeNode *copied = node->rhsReference ? node->rhsReference->resolvedDeclaration : NULL;
    return copied && (rangeNodeDeclaresValue(copied->kind) || copied->kind == RangeNodeParameter) ? node->rhsReference : NULL;
}

/* `Point(x: 1, y: 2)`: each argument names the member it populates, and is
 * typed with that member's type in this specialization. */
static RangeNode *typeConstructionOf(Typer *typer, SourceScope *scope, RangeNode *at, RangeNode *type,
                                     RangeNode **arguments, size_t count, RangeNode *context)
{
    if (!type) return NULL;
    if (type->kind == RangeNodeTypeParameter) { typeError(typer,at,"type parameter %s cannot be constructed",type->name); return NULL; }
    RangeNode *declaration = type->resolvedDeclaration;
    if (declaration->kind == RangeNodeEnum) {
        // `Int?(maybe)` copies the enum value given, promoted if it is a Wrapped.
        // A case has one spelling, Light.red or .red in context, so
        // `Light(.red)` is not one.
        RangeNode *given = count == 1 ? arguments[0]->a : NULL;
        if (given && (given->kind == RangeNodeCase || (given->kind == RangeNodeCall && given->a && given->a->kind == RangeNodeCase))) {
            const char *name = given->kind == RangeNodeCase ? given->name : given->a->name;
            const char *written = at->typeName ? at->typeName : at->kind == RangeNodeCall && at->a && at->a->name ? at->a->name : declaration->name;
            const char *optional = (at->flags & RangeFlagOptional) || (at->kind == RangeNodeCall && at->a && (at->a->flags & RangeFlagOptional)) ? "?" : "";
            typeError(typer,at,"an enum value is written %s%s.%s, or .%s where the context names its type; %s%s(.%s) is not Range",
                      written,optional,name,name,written,optional,name);
            return type;
        }
        // An enum value is always a case. `Int?(5)` was a second spelling of
        // `Int?.present(5)`, and `Int?(maybe)` of letting the type be inferred.
        char t[160];
        {
            const char *written = at->typeName ? at->typeName : at->kind == RangeNodeCall && at->a && at->a->name ? at->a->name : declaration->name;
            const char *optional = (at->flags & RangeFlagOptional) || (at->kind == RangeNodeCall && at->a && (at->a->flags & RangeFlagOptional)) ? "?" : "";
            snprintf(t,sizeof(t),"%s%s",written,optional);
        }
        RangeNode *present = NULL;
        if (optionalWrapped(typer,type,&present))
            typeError(typer,at,"an enum is not constructed: write %s.%s(value), or bind the value directly to infer %s",
                      t,present->name,t);
        else
            typeError(typer,at,"an enum is not constructed: write %s.%s, or bind a value of %s directly",t,
                      declaration->itemCount ? declaration->items[0]->name : "case",t);
        return type;
    }
    size_t inputs = 0;
    RangeNode *only = NULL;
    for (size_t i = 0; i < declaration->itemCount; ++i)
        if (constructionInput(declaration->items[i])) { ++inputs; only = declaration->items[i]; }
    SourceScope declarationScope = {.owner=declaration};
    char typeName[160]; describeType(typeName,sizeof(typeName),type);
    for (size_t i = 0; i < count; ++i) {
        RangeNode *argument = arguments[i], *member = NULL;
        if (!argument->name) {
            if (inputs != 1 || count != 1) { typeError(typer,argument,"%s requires labeled arguments",typeName); continue; }
            member = only;
        } else for (size_t j = 0; j < declaration->itemCount; ++j)
            if (constructionInput(declaration->items[j]) && same(declaration->items[j]->name,argument->name)) member = declaration->items[j];
        if (!member) { typeError(typer,argument,"%s has no input '%s'",typeName,argument->name); continue; }
        for (size_t j = 0; j < i; ++j)
            if (arguments[j]->resolvedDeclaration == member) typeError(typer,argument,"'%s' is supplied twice",member->name);
        argument->resolvedDeclaration = member;
        RangeNode *expected = declaredType(typer,&declarationScope,member,type);
        RangeNode *actual = typeOf(typer,scope,argument->a,expected,context);
        char what[200]; snprintf(what,sizeof(what),"input '%s' of %s",member->name,typeName);
        coerce(typer,argument->a,expected,actual,what);
    }
    for (size_t i = 0; i < declaration->itemCount; ++i) {
        RangeNode *member = declaration->items[i];
        if (!constructionInput(member) || declarationValue(member) || optionalWithoutValue(member)) continue;
        int supplied = 0;
        for (size_t j = 0; j < count; ++j) if (arguments[j]->resolvedDeclaration == member) supplied = 1;
        if (!supplied) typeError(typer,at,"%s requires input '%s'",typeName,member->name);
    }
    return type;
}

static RangeNode *typeConstruction(Typer *typer, SourceScope *scope, RangeNode *at, const char *name, RangeNode *generics,
                                   int flags, RangeNode **arguments, size_t count, RangeNode *context)
{
    RangeNode *type = resolveTypeReference(typer,scope,name,generics,flags & ~RangeFlagApplication,context,at);
    return typeConstructionOf(typer,scope,at,type,arguments,count,context);
}

/* ---- generic functions ----
 * `function first<Element>(let xs: Array<Element>): Element?` is specialized
 * per instantiation, as a construct is: each distinct set of type arguments
 * gets its own copy of the declaration, typed and compiled with the type
 * parameters naming those types, and the types it mentions run their laws as
 * any specialization does. Arguments are inferred from the call's arguments,
 * then from the type the context expects; `first<Int>(xs: a)` writes them.
 * There are no constraints: a body that uses an operation its types lack
 * fails while that instance is typed, and the error names the instance. */

static void typeFunction(Typer *, SourceScope *, RangeNode *, RangeNode *);
static void checkMutations(Typer *, RangeNode *);

/* A generic function not yet specialized: a type parameter names no type. */
static int genericTemplate(const RangeNode *function)
{
    if (!function || function->kind != RangeNodeFunction || !function->generics) return 0;
    // A type parameter names no type yet, or a value generic has no value yet.
    for (size_t i = 0; i < function->generics->itemCount; ++i)
        if (!function->generics->items[i]->resolvedType) return 1;
    return 0;
}

/* `function scaled<let factor: 2>(…)`: value generics, constants per
 * instantiation as a construct's are per specialization. */
static size_t valueGenericCount(const RangeNode *function)
{
    size_t count = 0;
    for (size_t i = 0; function->generics && i < function->generics->itemCount; ++i)
        count += function->generics->items[i]->kind != RangeNodeTypeParameter;
    return count;
}

static RangeNode *valueGeneric(const RangeNode *function, size_t index)
{
    for (size_t i = 0, k = 0; function->generics && i < function->generics->itemCount; ++i)
        if (function->generics->items[i]->kind != RangeNodeTypeParameter && k++ == index) return function->generics->items[i];
    return NULL;
}

static size_t valueGenericIndex(const RangeNode *function, const char *name)
{
    for (size_t i = 0, k = 0; function->generics && i < function->generics->itemCount; ++i) {
        if (function->generics->items[i]->kind == RangeNodeTypeParameter) continue;
        if (same(function->generics->items[i]->name,name)) return k;
        ++k;
    }
    return SIZE_MAX;
}

static int sameLiteral(const RangeNode *a, const RangeNode *b)
{
    RangeNodeKind ka, kb; long long ia, ib; const char *ta, *tb;
    if (!lawInputs(a,&ka,&ia,&ta) || !lawInputs(b,&kb,&ib,&tb)) return a == b;
    return ka == kb && ia == ib && (ta == tb || (ta && tb && !strcmp(ta,tb)));
}

static size_t typeParameterIndex(const RangeNode *function, const char *name)
{
    for (size_t i = 0, k = 0; function->generics && i < function->generics->itemCount; ++i) {
        if (function->generics->items[i]->kind != RangeNodeTypeParameter) continue;
        if (same(function->generics->items[i]->name,name)) return k;
        ++k;
    }
    return SIZE_MAX;
}

static size_t typeParameterCount(const RangeNode *function)
{
    size_t count = 0;
    for (size_t i = 0; function->generics && i < function->generics->itemCount; ++i)
        count += function->generics->items[i]->kind == RangeNodeTypeParameter;
    return count;
}

static const char *typeParameterName(const RangeNode *function, size_t index)
{
    for (size_t i = 0, k = 0; function->generics && i < function->generics->itemCount; ++i)
        if (function->generics->items[i]->kind == RangeNodeTypeParameter && k++ == index) return function->generics->items[i]->name;
    return "?";
}

/* Whether a written type, such as Array<Element>?, mentions a type parameter. */
static int mentionsParameter(const RangeNode *function, const char *name, const RangeNode *generics)
{
    if (typeParameterIndex(function,name) != SIZE_MAX) return 1;
    for (size_t i = 0; generics && i < generics->itemCount; ++i) {
        const RangeNode *argument = generics->items[i]->a;
        if (!generics->items[i]->name && argument && argument->kind == RangeNodeName
            && mentionsParameter(function,argument->name,argument->generics)) return 1;
    }
    // A function type's result, as in (Element) -> Result.
    const RangeNode *result = generics && same(generics->name,"functionType") ? generics->a : NULL;
    return result && mentionsParameter(function,result->name,result->generics);
}

/* Bind the type parameters a written type mentions by matching it against a
 * type: `Array<Element>` against Array<Int> binds Element to Int, and
 * `Element?` binds it to the wrapped type, or to a plain value promoted there.
 * Returns 0 when a parameter is already bound to another type. */
static int unifyType(Typer *typer, RangeNode *function, const char *name, RangeNode *generics, int flags,
                     RangeNode *actual, RangeNode **bound, size_t *conflict)
{
    // A function type binds through its parameter types and its result:
    // `(Element) -> Result` against (Int) -> Bool binds Result to Bool.
    if ((flags & RangeFlagFunction) && generics) {
        if (!isFunctionType(actual)) return 1; /* coercion reports it */
        for (size_t i = 0; i < generics->itemCount && i < actual->itemCount; ++i) {
            RangeNode *part = generics->items[i]->a;
            if (!unifyType(typer,function,part->name,part->generics,part->flags,actual->items[i],bound,conflict)) return 0;
        }
        RangeNode *result = generics->a;
        return !result || unifyType(typer,function,result->name,result->generics,result->flags,actual->a,bound,conflict);
    }
    // A type parameter binds to any type, including an enclosing construct's
    // own type parameter: `first(xs: items)` inside Box<T> binds Element to T.
    if (!actual || (actual->kind != RangeNodeSpecialization && actual->kind != RangeNodeTypeParameter)) return 1;
    if ((flags & RangeFlagOptional) && actual->kind == RangeNodeSpecialization) {
        RangeNode *wrapped = optionalWrapped(typer,actual,NULL);
        if (wrapped) actual = wrapped;
    }
    size_t index = typeParameterIndex(function,name);
    if (index != SIZE_MAX && !generics) {
        if (!bound[index]) { bound[index] = actual; return 1; }
        if (bound[index] == actual) return 1;
        *conflict = index;
        return 0;
    }
    if (!generics || actual->kind != RangeNodeSpecialization) return 1;
    SourceScope scope = {.owner=function};
    RangeNode *declaration = dottedLookup(typer->report,&scope,name,2);
    if (!declaration || actual->resolvedDeclaration != declaration || !actual->generics) return 1; /* coercion reports it */
    size_t position = 0;
    for (size_t i = 0; i < generics->itemCount; ++i) {
        RangeNode *argument = generics->items[i];
        if (argument->name || !argument->a || argument->a->kind != RangeNodeName) continue;
        for (size_t j = 0, k = 0; j < actual->generics->itemCount; ++j) {
            RangeNode *slot = actual->generics->items[j];
            if (slot->kind != RangeNodeTypeParameter || k++ != position) continue;
            if (!unifyType(typer,function,argument->a->name,argument->a->generics,argument->a->flags,slot->resolvedType,bound,conflict))
                return 0;
        }
        ++position;
    }
    return 1;
}

/* A written type of the declaration, with the type parameters bound so far
 * standing for their types; NULL while one it mentions is unbound, which
 * resolves to no type. */
static RangeNode *boundType(Typer *typer, RangeNode *function, const char *name, RangeNode *generics, int flags,
                            RangeNode **bound, RangeNode *at, RangeNode *receiver)
{
    RangeArena *arena = typer->report->arena;
    RangeNode *owner = rangeNodeCreate(arena,RangeNodeFunction,function->path,function->line,function->column);
    owner->generics = rangeNodeCreate(arena,RangeNodeBlock,function->path,function->line,function->column);
    owner->generics->name = "genericMembers";
    for (size_t i = 0, k = 0; function->generics && i < function->generics->itemCount; ++i) {
        RangeNode *generic = function->generics->items[i];
        if (generic->kind != RangeNodeTypeParameter) continue;
        RangeNode *copy = rangeArenaAllocate(arena,sizeof(*copy));
        *copy = *generic;
        copy->resolvedType = bound[k++];
        rangeNodeAppend(arena,owner->generics,copy);
    }
    // A method's types also name its receiver's type parameters.
    SourceScope ownerScope = {.owner=receiver ? receiver->resolvedDeclaration : NULL};
    SourceScope scope = {.owner=owner,.parent=receiver ? &ownerScope : NULL};
    return resolveTypeReference(typer,&scope,name,generics,flags,receiver,at);
}

static void cloneRemap(RangeNode **from, RangeNode **to, size_t count, RangeNode **slot)
{
    if (!*slot) return;
    size_t mask = count - 1, at = ((uintptr_t)*slot >> 4) & mask;
    while (from[at]) { if (from[at] == *slot) { *slot = to[at]; return; } at = (at + 1) & mask; }
}

typedef struct { RangeNode **from, **to; size_t capacity, count; RangeArena *arena; } CloneMap;

static RangeNode *cloneNode(CloneMap *map, RangeNode *node)
{
    if (!node) return NULL;
    size_t mask = map->capacity - 1, at = ((uintptr_t)node >> 4) & mask;
    while (map->from[at]) { if (map->from[at] == node) return map->to[at]; at = (at + 1) & mask; }
    if (2 * (map->count + 1) > map->capacity) {
        // Grow, keeping every pair.
        CloneMap grown = {.capacity=map->capacity * 2,.count=map->count,.arena=map->arena};
        grown.from = rangeArenaAllocate(map->arena,grown.capacity * sizeof(*grown.from));
        grown.to = rangeArenaAllocate(map->arena,grown.capacity * sizeof(*grown.to));
        memset(grown.from,0,grown.capacity * sizeof(*grown.from));
        for (size_t i = 0; i < map->capacity; ++i) {
            if (!map->from[i]) continue;
            size_t j = ((uintptr_t)map->from[i] >> 4) & (grown.capacity - 1);
            while (grown.from[j]) j = (j + 1) & (grown.capacity - 1);
            grown.from[j] = map->from[i]; grown.to[j] = map->to[i];
        }
        *map = grown;
        return cloneNode(map,node);
    }
    RangeNode *copy = rangeArenaAllocate(map->arena,sizeof(*copy));
    *copy = *node;
    forgetFacts(copy);
    map->from[at] = node; map->to[at] = copy; ++map->count;
    if (node->itemCount) {
        copy->items = rangeArenaAllocate(map->arena,node->itemCount * sizeof(*copy->items));
        copy->itemCapacity = node->itemCount;
        for (size_t i = 0; i < node->itemCount; ++i) copy->items[i] = cloneNode(map,node->items[i]);
    } else { copy->items = NULL; copy->itemCapacity = 0; }
    copy->a = cloneNode(map,node->a); copy->b = cloneNode(map,node->b); copy->c = cloneNode(map,node->c);
    copy->generics = cloneNode(map,node->generics); copy->annotations = cloneNode(map,node->annotations);
    copy->rhsReference = cloneNode(map,node->rhsReference);
    return copy;
}

/* A declaration's identity inside the copy points at the copy's own nodes. */
static void cloneLinks(CloneMap *map)
{
    for (size_t i = 0; i < map->capacity; ++i) {
        if (!map->from[i]) continue;
        RangeNode *copy = map->to[i];
        cloneRemap(map->from,map->to,map->capacity,&copy->resolvedDeclaration);
        cloneRemap(map->from,map->to,map->capacity,&copy->receiver);
    }
}

/* The instance of a generic function for these types, typed on first use. */
static RangeNode *instantiate(Typer *typer, RangeNode *function, RangeNode **bound, RangeNode **values, RangeNode *at,
                             RangeNode *receiver)
{
    size_t count = typeParameterCount(function), valueCount = valueGenericCount(function);
    for (size_t i = 0; i < typer->instanceCount; ++i) {
        if (typer->instances[i].declaration != function || typer->instances[i].context != receiver) continue;
        size_t matched = 0, same = 0;
        while (matched < count && typer->instances[i].types[matched] == bound[matched]) ++matched;
        while (same < valueCount && sameLiteral(typer->instances[i].values[same],values[same])) ++same;
        if (matched == count && same == valueCount) return typer->instances[i].instance;
    }
    RangeArena *arena = typer->report->arena;
    CloneMap map = {.capacity=256,.arena=arena};
    map.from = rangeArenaAllocate(arena,map.capacity * sizeof(*map.from));
    map.to = rangeArenaAllocate(arena,map.capacity * sizeof(*map.to));
    memset(map.from,0,map.capacity * sizeof(*map.from));
    RangeNode *instance = cloneNode(&map,function);
    cloneLinks(&map);
    instance->receiver = NULL; /* a method instance has its own receiver, typed with its context */
    for (size_t i = 0, k = 0, v = 0; instance->generics && i < instance->generics->itemCount; ++i) {
        RangeNode *generic = instance->generics->items[i];
        if (generic->kind == RangeNodeTypeParameter) { generic->resolvedType = bound[k++]; continue; }
        // A value generic is the constant this instance was made for.
        generic->type = generic->resolvedType = values[v]->type;
        generic->a = values[v++];
        generic->typeName = NULL; generic->rhsReference = NULL; generic->generics = NULL; generic->itemCount = 0;
    }
    char name[512];
    size_t length = (size_t)snprintf(name,sizeof(name),"%s<",function->name);
    for (size_t k = 0; k < count && length < sizeof(name); ++k) {
        char type[160]; describeType(type,sizeof(type),bound[k]);
        length += (size_t)snprintf(name + length,sizeof(name) - length,"%s%s: %s",k ? ", " : "",typeParameterName(function,k),type);
    }
    for (size_t v = 0; v < valueCount && length < sizeof(name); ++v) {
        RangeNodeKind kind; long long integer; const char *text;
        char value[160] = "?";
        if (lawInputs(values[v],&kind,&integer,&text)) {
            if (kind == RangeNodeInteger) snprintf(value,sizeof(value),"%lld",integer);
            else if (kind == RangeNodeBool) snprintf(value,sizeof(value),"%s",integer ? "true" : "false");
            else if (text) snprintf(value,sizeof(value),"\"%s\"",text);
        }
        length += (size_t)snprintf(name + length,sizeof(name) - length,"%s%s: %s",count || v ? ", " : "",valueGeneric(function,v)->name,value);
    }
    if (length < sizeof(name)) length += (size_t)snprintf(name + length,sizeof(name) - length,">, specialized at %s:%d:%d",at->path,at->line,at->column);
    if (typer->instanceCount == typer->instanceCapacity) {
        typer->instanceCapacity = typer->instanceCapacity ? typer->instanceCapacity * 2 : 16;
        void *grown = rangeArenaAllocate(arena,typer->instanceCapacity * sizeof(*typer->instances));
        if (typer->instanceCount) memcpy(grown,typer->instances,typer->instanceCount * sizeof(*typer->instances));
        typer->instances = grown;
    }
    RangeNode **types = rangeArenaAllocate(arena,(count ? count : 1) * sizeof(*types));
    memcpy(types,bound,count * sizeof(*types));
    RangeNode **kept = rangeArenaAllocate(arena,(valueCount ? valueCount : 1) * sizeof(*kept));
    if (valueCount) memcpy(kept,values,valueCount * sizeof(*kept));
    typer->instances[typer->instanceCount].values = kept;
    typer->instances[typer->instanceCount].declaration = function;
    typer->instances[typer->instanceCount].instance = instance;
    typer->instances[typer->instanceCount].types = types;
    typer->instances[typer->instanceCount].context = receiver;
    typer->instances[typer->instanceCount++].name = rangeArenaIntern(arena,name,strlen(name));
    // Registered before its body is typed, so a recursive call finds it. A
    // method's instance is typed in its receiver's specialization.
    const char *outer = typer->instance;
    typer->instance = typer->instances[typer->instanceCount - 1].name;
    SourceScope ownerScope = {.owner=receiver ? receiver->resolvedDeclaration : NULL};
    typeFunction(typer,receiver ? &ownerScope : NULL,instance,receiver);
    typer->instance = outer;
    return instance;
}

/* A call of a generic function: infer its type arguments, then call the
 * instance for them. Arguments are typed once each: those whose parameter
 * names no type parameter first, with that parameter's type; then the others
 * that need no context; then the expected result; then the rest, such as
 * literals, with whatever the earlier ones bound. */
static RangeNode *typeGenericCall(Typer *typer, SourceScope *scope, RangeNode *call, RangeNode *function,
                                  RangeNode *expected, RangeNode *context, RangeNode *receiver)
{
    RangeNode *callee = call->a;
    size_t count = typeParameterCount(function), conflict = SIZE_MAX;
    RangeNode **bound = rangeArenaAllocate(typer->report->arena,(count ? count : 1) * sizeof(*bound));
    memset(bound,0,(count ? count : 1) * sizeof(*bound));
    if (call->itemCount != function->itemCount)
        typeError(typer,call,"'%s' takes %zu arguments; %zu supplied",function->name,function->itemCount,call->itemCount);
    size_t n = call->itemCount < function->itemCount ? call->itemCount : function->itemCount;
    for (size_t i = 0; i < n; ++i)
        if (callee->name && !argumentFits(call->items[i],function,i))
            typeError(typer,call->items[i],"argument %zu of '%s' requires label '%s'",i + 1,function->name,function->items[i]->name);
    // Value generics: written by label, or their defaults.
    size_t valueCount = valueGenericCount(function);
    RangeNode **values = rangeArenaAllocate(typer->report->arena,(valueCount ? valueCount : 1) * sizeof(*values));
    memset(values,0,(valueCount ? valueCount : 1) * sizeof(*values));
    // Written type arguments: positional, or labeled by parameter name.
    size_t positional = 0;
    for (size_t i = 0; callee->generics && i < callee->generics->itemCount; ++i) {
        RangeNode *argument = callee->generics->items[i], *reference = argument->a;
        size_t value = argument->name ? valueGenericIndex(function,argument->name) : SIZE_MAX;
        if (value != SIZE_MAX) { values[value] = argument->a; continue; }
        size_t index = argument->name ? typeParameterIndex(function,argument->name) : positional++;
        if (index >= count) {
            if (argument->name) typeError(typer,argument,"'%s' has no generic '%s'",function->name,argument->name);
            else typeError(typer,argument,"'%s' takes %zu type argument%s",function->name,count,count == 1 ? "" : "s");
            return NULL;
        }
        if (!reference || reference->kind != RangeNodeName) { typeError(typer,argument,"type argument %s requires a type",typeParameterName(function,index)); return NULL; }
        bound[index] = resolveTypeReference(typer,scope,reference->name,reference->generics,reference->flags,context,reference);
        if (!bound[index]) return NULL;
    }
    // A method's signature also names its receiver's type parameters and types.
    SourceScope ownerScope = {.owner=receiver ? receiver->resolvedDeclaration : NULL};
    SourceScope declarationScope = {.owner=function,.parent=receiver ? &ownerScope : NULL};
    RangeNode **actual = rangeArenaAllocate(typer->report->arena,(n ? n : 1) * sizeof(*actual));
    int *done = rangeArenaAllocate(typer->report->arena,(n ? n : 1) * sizeof(*done));
    memset(done,0,(n ? n : 1) * sizeof(*done));
    // A closure for a generic function type is typed last, once the other
    // arguments have bound what its parameters need; its result binds the rest.
    for (int pass = 0; pass < 4; ++pass) {
        if (pass == 2 && expected && function->b)
            (void)unifyType(typer,function,function->b->name,function->b->generics,function->b->flags,expected,bound,&(size_t){0});
        for (size_t i = 0; i < n; ++i) {
            RangeNode *parameter = function->items[i], *value = call->items[i]->a;
            int generic = parameter->b && mentionsParameter(function,parameter->b->name,parameter->b->generics);
            int closure = (parameter->flags & RangeFlagFunction) != 0;
            if (done[i] || (pass == 0 && generic) || (pass == 1 && (!generic || contextual(value) || closure))
                || (pass == 2 && closure)) continue;
            RangeNode *want = !generic ? declaredType(typer,&declarationScope,parameter,receiver)
                : boundType(typer,function,parameter->b->name,parameter->b->generics,parameter->flags,bound,parameter->b,receiver);
            if (closure && !want) {
                typeError(typer,value,"the parameter types of this closure for '%s' are not known: write the generic arguments, as in %s<…>(…)",
                          function->name,function->name);
                return NULL;
            }
            RangeNode *site = typer->closureSite;
            typer->closureSite = isFunctionType(want) ? value : NULL;
            actual[i] = typeOf(typer,scope,value,want,context);
            typer->closureSite = site;
            done[i] = 1;
            if (generic && !unifyType(typer,function,parameter->b->name,parameter->b->generics,parameter->flags,actual[i],bound,&conflict)) {
                char first[160], second[160];
                describeType(first,sizeof(first),bound[conflict]); describeType(second,sizeof(second),actual[i]);
                typeError(typer,value,"type parameter %s of '%s' is %s from an earlier argument, but argument '%s' is %s",
                          typeParameterName(function,conflict),function->name,first,parameter->name,second);
                return NULL;
            }
        }
    }
    for (size_t k = 0; k < count; ++k)
        if (!bound[k]) {
            typeError(typer,call,"cannot infer type parameter %s of '%s'; write it, as in %s<…>(…)",
                      typeParameterName(function,k),function->name,function->name);
            return NULL;
        }
    // A value generic is a literal of its declared type, checked by that type's laws.
    for (size_t v = 0; v < valueCount; ++v) {
        RangeNode *generic = valueGeneric(function,v);
        RangeNode *want = declaredType(typer,&declarationScope,generic,receiver);
        if (!values[v] && generic->typeName) {
            typeError(typer,call,"'%s' requires generic %s; write it, as in %s<%s: …>(…)",function->name,generic->name,function->name,generic->name);
            return NULL;
        }
        if (!values[v]) values[v] = rangeNodeRHS(generic);
        RangeNodeKind kind; long long integer; const char *text;
        if (!values[v] || !lawInputs(values[v],&kind,&integer,&text)) {
            typeError(typer,values[v] ? values[v] : call,"generic %s of '%s' requires a literal value",generic->name,function->name);
            return NULL;
        }
        char what[160]; snprintf(what,sizeof(what),"generic %s of '%s'",generic->name,function->name);
        RangeNode *actual = typeOf(typer,scope,values[v],want,context);
        expectType(typer,values[v],want,actual,what);
        if (!actual || (want && actual != want)) return NULL;
    }
    // A type that mentions an enclosing construct's type parameter, as in
    // Box<T>'s methods, gives an instance typed with that parameter; code is
    // generated per concrete specialization, which substitutes it.
    RangeNode *instance = instantiate(typer,function,bound,values,call,receiver);
    callee->resolvedDeclaration = instance;
    for (size_t i = 0; i < n; ++i) {
        char what[160];
        snprintf(what,sizeof(what),"argument '%s' of '%s'",function->items[i]->name,function->name);
        coerce(typer,call->items[i]->a,instance->items[i]->type,actual[i],what);
    }
    return instance->type;
}

/* ---- closures ----
 * `{ x in body }` is an argument for a function-typed parameter, typed with
 * that parameter's type: its parameters take the type's parameter types, and
 * its body returns the type's result. A body that is one expression yields
 * it; otherwise `return` does, and returns from the closure only. A closure
 * whose result is a unit type such as Void yields no value. It sees the
 * names where it is written, and may change a `state` there: it runs while
 * the call it is passed to runs, never after. So a closure, and a parameter
 * holding one, is only called or passed on to a function-typed parameter. */

static void typeBlock(Typer *, SourceScope *, RangeNode *, RangeNode *, RangeNode *);
static int exits(const RangeNode *, int);

/* The expression a closure body is: its switch read as an expression, or its
 * one expression statement. */
static RangeNode *closureValue(RangeNode *closure)
{
    if (closure->b) return closure->b;
    RangeNode *body = closure->a;
    if (!body || body->itemCount != 1 || body->items[0]->kind != RangeNodeExpressionStatement) return NULL;
    RangeNode *value = body->items[0]->a;
    return value && value->kind != RangeNodeAttribute ? value : NULL;
}

/* What a typed closure yields: its one expression, unless its result is a
 * unit type; otherwise its body runs and `return` gives the value. */
static RangeNode *closureResult(Typer *typer, RangeNode *closure)
{
    RangeNode *value = closureValue(closure);
    return value && !(isFunctionType(closure->type) && unitType(typer,closure->type->a)) ? value : NULL;
}

static RangeNode *typeClosure(Typer *typer, SourceScope *scope, RangeNode *closure, RangeNode *expected, RangeNode *context)
{
    char t[320]; describeType(t,sizeof(t),expected);
    if (closure->itemCount != expected->itemCount) {
        typeError(typer,closure,"this closure takes %zu parameter%s; %s takes %zu",closure->itemCount,
                  closure->itemCount == 1 ? "" : "s",t,expected->itemCount);
        return NULL;
    }
    for (size_t i = 0; i < closure->itemCount; ++i) {
        for (size_t j = 0; j < i; ++j)
            if (same(closure->items[j]->name,closure->items[i]->name))
                typeError(typer,closure->items[i],"'%s' names two parameters of this closure",closure->items[i]->name);
        closure->items[i]->type = expected->items[i];
    }
    SourceScope own = {.owner=closure,.parent=scope};
    RangeNode *result = expected->a, *value = closureValue(closure);
    int unit = unitType(typer,result);
    // `break` and `continue` do not leave the closure; `return` returns from it.
    int loops = typer->loops, inferring = typer->inferring;
    RangeNode *output = typer->output, *inferred = typer->inferred, *site = typer->closureSite;
    typer->loops = 0;
    typer->closures += 1;
    typer->closureSite = NULL;
    typer->output = result;
    typer->inferring = !result;
    typer->inferred = NULL;
    if (value && !unit) {
        RangeNode *actual = typeOf(typer,&own,value,result,context);
        if (result) coerce(typer,value,result,actual,"the result of this closure");
        else result = actual;
    } else {
        typeBlock(typer,&own,closure->a,context,result);
        if (!result) result = typer->inferred;
        if (!result) typeError(typer,closure,"the result of this closure is not known: return a value, or make its body one expression");
        else if (!unit && !exits(closure->a,0))
            typeError(typer,closure,"this closure returns %s: return a value on every path, or make its body one expression",
                      (describeType(t,sizeof(t),result),t));
    }
    typer->loops = loops; typer->inferring = inferring; typer->closures -= 1;
    typer->output = output; typer->inferred = inferred; typer->closureSite = site;
    if (!result) return NULL;
    RangeNode **parameters = rangeArenaAllocate(typer->report->arena,(expected->itemCount ? expected->itemCount : 1) * sizeof(*parameters));
    for (size_t i = 0; i < expected->itemCount; ++i) parameters[i] = expected->items[i];
    return functionType(typer,parameters,expected->itemCount,result,closure);
}

/* `where(element)`: a call of the closure a parameter holds, with one
 * unlabeled argument per parameter of its type. */
static RangeNode *typeClosureCall(Typer *typer, SourceScope *scope, RangeNode *call, RangeNode *value, RangeNode *context)
{
    RangeNode *callee = call->a, *type = value->type;
    callee->resolvedDeclaration = value;
    callee->type = type;
    char t[320]; describeType(t,sizeof(t),type);
    if (callee->generics) typeError(typer,callee,"'%s' is a closure, %s; it takes no type arguments",callee->name,t);
    if (call->itemCount != type->itemCount)
        typeError(typer,call,"'%s' is %s: it takes %zu argument%s; %zu supplied",callee->name,t,type->itemCount,
                  type->itemCount == 1 ? "" : "s",call->itemCount);
    for (size_t i = 0; i < call->itemCount; ++i) {
        RangeNode *argument = call->items[i];
        if (argument->name)
            typeError(typer,argument,"a closure's arguments take no labels: write %s(…) with argument %zu unlabeled",callee->name,i + 1);
        RangeNode *expected = i < type->itemCount ? type->items[i] : NULL;
        RangeNode *actual = typeOf(typer,scope,argument->a,expected,context);
        char what[160]; snprintf(what,sizeof(what),"argument %zu of '%s'",i + 1,callee->name);
        coerce(typer,argument->a,expected,actual,what);
    }
    return type->a;
}

static void typePattern(Typer *, SourceScope *, RangeNode *, RangeNode *, RangeNode *);

/* Inside an enum's own functions, a bare name that is one of its cases
 * tests the receiver; the enum declares no member of that name. */
static int receiverCase(Typer *typer, RangeNode *context, const char *name)
{
    return typer->function && typer->function->typeName && isEnum(context) && enumCase(context->resolvedDeclaration,name);
}

/* A name bound on the right of `|` stands for the left side's: same type. */
static void typeSharedBindings(Typer *typer, RangeNode *pattern)
{
    if (!pattern) return;
    if (pattern->integer == RangePatternBind && pattern->a->resolvedDeclaration) {
        RangeNode *first = pattern->a->resolvedDeclaration;
        if (first->type && pattern->a->type && first->type != pattern->a->type) {
            char f[160], o[160]; describeType(f,sizeof(f),first->type); describeType(o,sizeof(o),pattern->a->type);
            typeError(typer,pattern->a,"both sides of '|' bind '%s' with one type; the left side binds %s, this side %s",
                      pattern->a->name,f,o);
        }
        return;
    }
    for (size_t i = 0; i < pattern->itemCount; ++i) typeSharedBindings(typer,pattern->items[i]->a);
}

/* ---- narrowing ----
 * A test of a stable optional value for its present case, with no pattern,
 * as in `manager.present`, narrows the value: to the right of the test in
 * the same `&` chain, and in the arm's body or the loop's, the value is the
 * payload of the present case, read with no check. A stable value is a let,
 * a parameter, a #reflection value, or a member path of one; a state can
 * change and a call is computed again, so neither narrows. A test under `!`
 * or on one side of `|` narrows nothing beyond it, unless both sides of the
 * `|` narrow the same value. The optional is the enum applying @optional.
 * A value known only at macro time is not narrowed: typing does not know
 * that it holds an optional. */

static int narrowablePath(const RangeNode *path)
{
    if (!path || path->generics) return 0;
    if (path->kind == RangeNodeEnvironment) return 1;
    if (path->kind == RangeNodeMemberAccess) {
        const RangeNode *member = path->resolvedDeclaration;
        return member && rangeNodeDeclaresValue(member->kind) && narrowablePath(path->a);
    }
    if (path->kind != RangeNodeName || (path->flags & RangeFlagImplicit) || !path->resolvedDeclaration) return 0;
    const RangeNode *declaration = path->resolvedDeclaration;
    return declaration->kind == RangeNodeLet || (declaration->kind == RangeNodeParameter && !(declaration->flags & RangeFlagBinding));
}

/* Two narrowable paths read the same value: each step reads the same
 * declaration, narrowed alike. */
static int sameNarrowedPath(const RangeNode *a, const RangeNode *b)
{
    if (!a || !b || a->kind != b->kind || a->narrowed != b->narrowed) return 0;
    if (a->kind == RangeNodeName) return a->resolvedDeclaration && a->resolvedDeclaration == b->resolvedDeclaration;
    if (a->kind == RangeNodeEnvironment) return same(a->name,b->name);
    return a->kind == RangeNodeMemberAccess && a->resolvedDeclaration == b->resolvedDeclaration && sameNarrowedPath(a->a,b->a);
}

static void pushNarrowed(Typer *typer, RangeNode *path, RangeNode *entry, RangeNode *type)
{
    if (typer->narrowedCount == typer->narrowedCapacity) {
        typer->narrowedCapacity = typer->narrowedCapacity ? typer->narrowedCapacity * 2 : 16;
        void *grown = rangeArenaAllocate(typer->report->arena,typer->narrowedCapacity * sizeof(*typer->narrowed));
        if (typer->narrowedCount) memcpy(grown,typer->narrowed,typer->narrowedCount * sizeof(*typer->narrowed));
        typer->narrowed = grown;
    }
    typer->narrowed[typer->narrowedCount].path = path;
    typer->narrowed[typer->narrowedCount].entry = entry;
    typer->narrowed[typer->narrowedCount++].type = type;
}

/* A read of a narrowed value reads its payload: the present case it goes
 * through is recorded beside it, and its type is the payload's. */
static RangeNode *narrowedRead(Typer *typer, RangeNode *expr, RangeNode *type)
{
    if (!type || expr->lowered
        || (expr->kind != RangeNodeName && expr->kind != RangeNodeMemberAccess && expr->kind != RangeNodeEnvironment)) return type;
    for (size_t i = typer->narrowedCount; i-- > typer->narrowedFloor;) {
        if (!sameNarrowedPath(typer->narrowed[i].path,expr)) continue;
        expr->narrowed = typer->narrowed[i].entry;
        return expr->type = typer->narrowed[i].type;
    }
    return type;
}

static RangeNode *typeOperator(Typer *, SourceScope *, RangeNode *, RangeNode *, RangeNode *, RangeNode *);

/* `a | b` narrows what both sides narrow; each side's narrowing holds
 * only within it. */
static RangeNode *typeEither(Typer *typer, SourceScope *scope, RangeNode *expr, RangeNode *context)
{
    size_t mark = typer->narrowedCount;
    RangeNode *left = typeOf(typer,scope,expr->a,NULL,context);
    size_t leftCount = typer->narrowedCount - mark;
    RangeNode **paths = rangeArenaAllocate(typer->report->arena,(leftCount ? leftCount : 1) * sizeof(*paths));
    for (size_t i = 0; i < leftCount; ++i) paths[i] = typer->narrowed[mark + i].path;
    typer->narrowedCount = mark;
    RangeNode *type = left ? typeOperator(typer,scope,expr,left,NULL,context) : (typeOf(typer,scope,expr->b,NULL,context), NULL);
    size_t end = typer->narrowedCount, kept = mark;
    for (size_t i = mark; i < end; ++i) {
        int both = 0;
        for (size_t k = 0; k < leftCount && !both; ++k) both = sameNarrowedPath(paths[k],typer->narrowed[i].path);
        if (both) typer->narrowed[kept++] = typer->narrowed[i];
    }
    typer->narrowedCount = kept;
    return type;
}

static RangeNode *typeCaseTest(Typer *typer, SourceScope *scope, RangeNode *test, RangeNode *context)
{
    RangeNode *subject = test->a, *type;
    size_t mark = typer->narrowedCount;
    if (subject->flags & RangeFlagImplicit) {
        subject->resolvedDeclaration = methodReceiver(typer->report,typer->function);
        subject->type = type = context;
    } else type = typeOf(typer,scope,subject,NULL,context);
    if (!type) return NULL;
    typePattern(typer,scope,test->b,type,context);
    typeSharedBindings(typer,test->b);
    typer->narrowedCount = mark;
    RangeNode *present = NULL, *payload = optionalWrapped(typer,type,&present), *pattern = test->b;
    if (payload && pattern->resolvedDeclaration == present && narrowablePath(subject)) {
        RangeNode *bound = pattern->itemCount == 1 ? pattern->items[0]->a : NULL;
        if (!(pattern->flags & RangeFlagApplication)) pushNarrowed(typer,subject,present,payload);
        else if (subject->kind == RangeNodeName && bound && bound->integer == RangePatternBind && same(bound->a->name,subject->name))
            typeError(typer,bound->a,"'%s' is already narrowed to the payload here; related: a test of an optional "
                      "value for its present case narrows that value",subject->name);
    }
    return test->type = typer->booleanType;
}

static RangeNode *typeCall(Typer *typer, SourceScope *scope, RangeNode *call, RangeNode *expected, RangeNode *context)
{
    RangeNode *callee = call->a, *function = NULL, *receiver = NULL;
    if (!callee) return NULL;
    if (callee->kind == RangeNodeCase) {
        // `.value(number: 7)`: a case with its payload, of the enum the context expects.
        RangeNode *type = caseContext(typer,contextualEnum(typer,callee,expected),callee->name);
        RangeNode *entry = type ? namedCase(typer,type,callee->name,callee) : NULL;
        if (!entry) return NULL;
        if (!entry->itemCount) { typeError(typer,call,"case '%s' has no payload; write .%s",entry->name,entry->name); return NULL; }
        callee->resolvedDeclaration = entry;
        typePayload(typer,scope,call,type,entry,call->items,call->itemCount,context);
        return type;
    }
    if (callee->kind == RangeNodeMemberAccess && callee->name) {
        RangeNode *optional = optionalPath(typer,scope,callee->a,context);
        RangeNode *owner = optional ? optional->resolvedDeclaration : typePath(typer->report,scope,callee->a);
        if (owner) {
            // `Outer.Inner(…)` constructs a nested type; `Tree.leaf(value: 1)` a case.
            RangeNode *nested = nestedDeclaration(owner,callee->name,strlen(callee->name));
            if (nested) {
                callee->resolvedDeclaration = nested;
                return typeConstructionOf(typer,scope,call,specialize(typer,scope,nested,callee->generics,context,call),
                                          call->items,call->itemCount,context);
            }
            if (owner->kind != RangeNodeEnum) {
                typeError(typer,callee,"'%s' has no case or nested type '%s'",owner->name,callee->name);
                return NULL;
            }
            RangeNode *type = optional ? optional : pathEnum(typer,scope,owner,callee->a,expected,context,callee);
            RangeNode *entry = type ? namedCase(typer,type,callee->name,callee) : NULL;
            if (!entry) return NULL;
            if (!entry->itemCount) { typeError(typer,call,"case '%s' has no payload; write %s.%s",entry->name,owner->name,entry->name); return NULL; }
            callee->resolvedDeclaration = entry;
            typePayload(typer,scope,call,type,entry,call->items,call->itemCount,context);
            return type;
        }
    }
    if (callee->kind == RangeNodeName) {
        // `where(element)` calls the closure a function-typed parameter holds.
        RangeNode *value = sourceLookup(typer->report,scope,callee->name,0);
        if (!value && receiverCase(typer,context,callee->name)) {
            call->lowered = caseTest(typer->report->arena,call,receiverSubject(typer->report->arena,callee),callee->name,call);
            return typeCaseTest(typer,scope,call->lowered,context);
        }
        if (value && (value->kind == RangeNodeParameter || rangeNodeDeclaresValue(value->kind)) && isFunctionType(value->type))
            return typeClosureCall(typer,scope,call,value,context);
        function = lookupFunction(typer->report,scope,callee->name);
        if (function && function->owner) function = findCalledFunction(function->owner,callee->name,call);
        if (!function) {
            RangeNode *declaration = sourceLookup(typer->report,scope,callee->name,0);
            if (!declaration) declaration = sourceLookup(typer->report,scope,callee->name,2);
            if (declaration && (declaration->kind == RangeNodeConstruct || declaration->kind == RangeNodeEnum
                                || declaration->kind == RangeNodeTypeParameter)) {
                callee->resolvedDeclaration = declaration;
                return typeConstruction(typer,scope,call,callee->name,callee->generics,callee->flags,call->items,call->itemCount,context);
            }
            if (declaration) typeError(typer,call,"'%s' is not a function",callee->name);
            return NULL; /* undeclared names are reported already */
        }
        if (genericTemplate(function)) return typeGenericCall(typer,scope,call,function,expected,context,function->typeName ? context : NULL);
        if (callee->generics) { typeError(typer,callee,"'%s' takes no type arguments",function->name); return NULL; }
        receiver = function->typeName ? context : NULL;
    } else if (callee->kind == RangeNodeMemberAccess) {
        receiver = typeOf(typer,scope,callee->a,NULL,context);
        if (!receiver) return NULL;
        if (receiver->kind == RangeNodeTypeParameter) { typeError(typer,callee,"type parameter %s has no functions",receiver->name); return NULL; }
        if (macroOperand(typer,receiver)) {
            // Which function this calls depends on the declaration the value
            // holds: its result is known at macro time.
            RangeNode *kinds[32];
            size_t count = isMacroType(receiver) ? macroKinds(typer,receiver,kinds,32) : 0, declaring = 0;
            for (size_t i = 0; i < count; ++i) declaring += findFunction(kinds[i],callee->name) != NULL;
            if (count && !declaring) {
                char type[160]; describeType(type,sizeof(type),receiver);
                typeError(typer,callee,"%s has no function '%s'",type,callee->name);
                return NULL;
            }
            for (size_t i = 0; i < call->itemCount; ++i) {
                RangeNode *argument = call->items[i]->a;
                if (argument && argument->kind == RangeNodeClosure)
                    typeError(typer,argument,"this closure's parameter types are not known: '%s' is called on a value known only at macro time",
                              callee->name);
                else if (argument) (void)typeOf(typer,scope,argument,NULL,context);
            }
            return typer->deferred;
        }
        if (isEnum(receiver) && callee->name && enumCase(receiver->resolvedDeclaration,callee->name)) {
            // `phase.failed(let reason)`: whether phase holds the case, with its payload's patterns.
            call->lowered = caseTest(typer->report->arena,call,callee->a,callee->name,call);
            return typeCaseTest(typer,scope,call->lowered,context);
        }
        // A member with no name is one `for … in` resolved by its @iteration role.
        function = callee->name ? findCalledFunction(receiver->resolvedDeclaration,callee->name,call) : callee->resolvedDeclaration;
        if (!function) {
            char type[160]; describeType(type,sizeof(type),receiver);
            typeError(typer,callee,"%s has no function '%s'",type,callee->name);
            return NULL;
        }
        if (genericTemplate(function)) return typeGenericCall(typer,scope,call,function,expected,context,receiver);
    } else {
        typeError(typer,call,"call target is not a function");
        return NULL;
    }
    callee->resolvedDeclaration = function;
    // A method's signature names types in its owner, such as a nested enum.
    SourceScope ownerScope = {.owner=receiver && receiver->kind == RangeNodeSpecialization ? receiver->resolvedDeclaration : NULL};
    SourceScope functionScope = {.owner=function,.parent=ownerScope.owner ? &ownerScope : NULL};
    if (call->itemCount != function->itemCount)
        typeError(typer,call,"'%s' takes %zu arguments; %zu supplied",function->name,function->itemCount,call->itemCount);
    // A function chosen by its role, as `for … in` chooses its @iteration
    // function, takes its arguments in order, unlabeled.
    for (size_t i = 0; i < call->itemCount && i < function->itemCount; ++i) {
        RangeNode *argument = call->items[i], *parameter = function->items[i];
        if (callee->name && !argumentFits(argument,function,i))
            typeError(typer,argument,"argument %zu of '%s' requires label '%s'",i + 1,function->name,parameter->name);
        RangeNode *expected = declaredType(typer,&functionScope,parameter,receiver);
        RangeNode *site = typer->closureSite;
        typer->closureSite = isFunctionType(expected) ? argument->a : NULL;
        RangeNode *actual = typeOf(typer,scope,argument->a,expected,context);
        typer->closureSite = site;
        char what[160];
        snprintf(what,sizeof(what),"argument '%s' of '%s'",parameter->name,function->name);
        coerce(typer,argument->a,expected,actual,what);
    }
    RangeNode *output = function->b;
    return output ? resolveTypeReference(typer,&functionScope,output->name,output->generics,output->flags,receiver,output) : NULL;
}

/* `a..<b` is sugar for the construct applying @interval, constructed with
 * lower: a and upper: b: that construction, typed, is what runs in its place. */
static RangeNode *typeInterval(Typer *typer, SourceScope *scope, RangeNode *expr, RangeNode *context)
{
    RangeNode *interval = NULL;
    size_t found = 0;
    for (size_t u = 0; u < typer->report->count; ++u) for (size_t i = 0; i < typer->report->units[u]->itemCount; ++i) {
        RangeNode *candidate = typer->report->units[u]->items[i];
        if (candidate->kind == RangeNodeConstruct && appliesBuiltin(candidate,"interval")) { interval = candidate; ++found; }
    }
    if (found != 1) {
        sourceDiagnostic(typer->report,expr,0,"undeclared","'..<' needs exactly one construct applying @interval; found %zu",found);
        return NULL;
    }
    RangeArena *arena = typer->report->arena;
    RangeNode *callee = rangeNodeCreate(arena,RangeNodeName,expr->path,expr->line,expr->column);
    callee->name = interval->name;
    callee->resolvedDeclaration = interval;
    RangeNode *call = rangeNodeCreate(arena,RangeNodeCall,expr->path,expr->line,expr->column);
    call->a = callee;
    static const char *const labels[] = {"lower","upper"};
    for (int side = 0; side < 2; ++side) {
        RangeNode *argument = rangeNodeCreate(arena,RangeNodeArgument,expr->path,expr->line,expr->column);
        argument->name = labels[side];
        argument->a = side ? expr->b : expr->a;
        rangeNodeAppend(arena,call,argument);
    }
    expr->lowered = call;
    RangeNode *type = specialize(typer,scope,interval,NULL,context,expr);
    return call->type = typeConstructionOf(typer,scope,call,type,call->items,call->itemCount,context);
}

/* `a + b` and `-a`: the function the operator names on the operand's type.
 * Its parameter and result are typed in that type, as a method's are, so
 * inside Int<bits: 8> `#name` is Int<bits: 8>. A function with a body is
 * called: that call, typed, is what runs in the operator's place. A builtin
 * one is the C primitive its name selects, lowered where the operator is. */
static RangeNode *typeOperator(Typer *typer, SourceScope *scope, RangeNode *expr, RangeNode *operand,
                               RangeNode *right, RangeNode *context)
{
    RangeNode *function = operand && operand->kind == RangeNodeSpecialization
        ? operatorFunction(operand->resolvedDeclaration,expr->name,expr->kind == RangeNodeBinary) : NULL;
    char t[160];
    describeType(t,sizeof(t),operand);
    if (!function) {
        if (expr->kind == RangeNodeBinary && !right) (void)typeOf(typer,scope,expr->b,NULL,context);
        typeError(typer,expr,"'%s' is not declared on %s",expr->name,t);
        return NULL;
    }
    if ((function->flags & RangeFlagBuiltin) && (same(expr->name,"!") || shortCircuit(function))
        && operand->resolvedDeclaration != typer->boolean)
        typeError(typer,expr,"builtin '%s' is a C primitive of the condition type only; %s declares it",expr->name,t);
    expr->resolvedDeclaration = function;
    SourceScope ownerScope = {.owner=operand->resolvedDeclaration};
    SourceScope functionScope = {.owner=function,.parent=&ownerScope};
    if (expr->kind == RangeNodeBinary) {
        RangeNode *parameter = declaredType(typer,&functionScope,function->items[0],operand);
        if (!right) right = typeOf(typer,scope,expr->b,parameter,context);
        if (!right) return NULL;
        if (parameter == operand && right != operand && optionalWrapped(typer,parameter,NULL) != right && !deferredType(typer,right)) {
            char r[160]; describeType(r,sizeof(r),right);
            typeError(typer,expr,"operator '%s' requires matching types; found %s and %s",expr->name,t,r);
            return NULL;
        }
        char what[160]; snprintf(what,sizeof(what),"the right operand of '%s'",expr->name);
        coerce(typer,expr->b,parameter,right,what);
    }
    RangeNode *output = function->b;
    RangeNode *type = output ? resolveTypeReference(typer,&functionScope,output->name,output->generics,output->flags,operand,output) : NULL;
    if (!(function->flags & RangeFlagBuiltin)) {
        // The call the operator stands for, already typed: receiver.op(other: b).
        RangeArena *arena = typer->report->arena;
        RangeNode *callee = rangeNodeCreate(arena,RangeNodeMemberAccess,expr->path,expr->line,expr->column);
        callee->a = expr->a;
        callee->resolvedDeclaration = function;
        callee->type = type;
        RangeNode *call = rangeNodeCreate(arena,RangeNodeCall,expr->path,expr->line,expr->column);
        call->a = callee;
        call->type = type;
        if (expr->kind == RangeNodeBinary) {
            RangeNode *argument = rangeNodeCreate(arena,RangeNodeArgument,expr->path,expr->line,expr->column);
            argument->name = function->items[0]->name;
            argument->a = expr->b;
            rangeNodeAppend(arena,call,argument);
        }
        expr->lowered = call;
    }
    return type;
}

static RangeNode *typeSwitch(Typer *, SourceScope *, RangeNode *, RangeNode *, RangeNode *, RangeNode *);
static RangeNode *typeExpression(Typer *, SourceScope *, RangeNode *, RangeNode *, RangeNode *);

/* A local of a block in scope whose statement is not typed yet: it is
 * declared later than where it is read. Names a pattern binds are declared
 * by their case tests. */
static int declaredLater(SourceScope *scope, const RangeNode *declaration)
{
    if ((declaration->kind != RangeNodeLet && declaration->kind != RangeNodeState) || (declaration->flags & RangeFlagTyped)) return 0;
    for (; scope; scope = scope->parent)
        if (scope->owner && scope->owner->kind == RangeNodeBlock && !same(scope->owner->name,"bindings"))
            for (size_t i = 0; i < scope->owner->itemCount; ++i) if (scope->owner->items[i] == declaration) return 1;
    return 0;
}

/* The local, binding, or parameter a splice `#name` names: one declared, in
 * the scopes the #graph block is written in, before it. */
static RangeNode *spliceLocal(SourceScope *scope, const char *name)
{
    for (SourceScope *at = scope; at; at = at->parent) {
        RangeNode *owner = at->owner;
        for (size_t i = 0; owner && owner->kind != RangeNodeUnit && i < owner->itemCount; ++i) {
            RangeNode *item = owner->items[i];
            if ((rangeNodeDeclaresValue(item->kind) || item->kind == RangeNodeParameter) && same(item->name,name)
                && !declaredLater(scope,item)) return item;
        }
    }
    return NULL;
}

/* Whether the macro's target declares field `name`: its kind's C shape, or
 * the shape of a kind its macro type admits. */
static int targetField(RangeArena *arena, const RangeNode *macro, const char *name)
{
    if (!macro->b) return 0;
    if (!(macro->b->flags & RangeFlagMacroType)) return rangeGraphField(rangeGraphType(arena,macro->b->name),name) != NULL;
    for (size_t i = 0; i < arena->graphTypes->itemCount; ++i) {
        RangeNode *shape = arena->graphTypes->items[i];
        if (appliesMacro(shape->resolvedDeclaration,macro->b->resolvedDeclaration) && rangeGraphField(shape,name)) return 1;
    }
    return 0;
}

/* Quoted code is typed where it lands; its splices are typed where the
 * macro runs. `#x` is the macro's local x or the target's field x, never
 * both. A nested macro's splices are its own. */
static void typeSplices(Typer *typer, SourceScope *scope, RangeNode *node)
{
    if (!node || node->kind == RangeNodeMacro) return;
    if (spliceChain(node)) {
        RangeNode *root = node;
        while (root->kind != RangeNodeEnvironment) root = root->a;
        RangeNode *local = spliceLocal(scope,root->name);
        int field = targetField(typer->report->arena,typer->macro,root->name);
        if (local && field) typeError(typer,root,"#%s names both a macro local and a target field",root->name);
        else if (!local && !field) typeError(typer,root,"#%s is neither a macro local nor a target field",root->name);
        else {
            root->resolvedDeclaration = local;
            (void)typeOf(typer,scope,node,NULL,NULL);
        }
        return;
    }
    typeSplices(typer,scope,node->a); typeSplices(typer,scope,node->b); typeSplices(typer,scope,node->c);
    typeSplices(typer,scope,node->generics); typeSplices(typer,scope,node->annotations); typeSplices(typer,scope,node->rhsReference);
    for (size_t i = 0; i < node->itemCount; ++i) typeSplices(typer,scope,node->items[i]);
}

/* An expression's type. A case test's narrowing holds beyond it only
 * through `&` and `|`; reads of a narrowed value read its payload. */
static RangeNode *typeOf(Typer *typer, SourceScope *scope, RangeNode *expr, RangeNode *expected, RangeNode *context)
{
    if (!expr) return NULL;
    if (expr->narrowed) return expr->type; /* a read narrowed where it is written keeps that narrowing */
    expr->lowered = NULL; /* typing records it afresh */
    size_t mark = typer->narrowedCount;
    int logic = expr->kind == RangeNodeBinary && (same(expr->name,"&") || same(expr->name,"|"));
    RangeNode *type;
    if (logic && same(expr->name,"|")) {
        type = typeEither(typer,scope,expr,context);
        expr->type = type;
    } else type = typeExpression(typer,scope,expr,expected,context);
    if (!logic && !(expr->lowered && expr->lowered->kind == RangeNodeCaseTest)) typer->narrowedCount = mark;
    type = narrowedRead(typer,expr,type);
    return type;
}

static RangeNode *typeExpression(Typer *typer, SourceScope *scope, RangeNode *expr, RangeNode *expected, RangeNode *context)
{
    if (!expr) return NULL;
    RangeNode *type = NULL;
    switch (expr->kind) {
    case RangeNodeInteger: case RangeNodeBool: case RangeNodeString:
        type = typeLiteral(typer,expr,expr,expected);
        break;
    case RangeNodeName: {
        RangeNode *declaration = nameLookup(typer->report,scope,expr);
        expr->resolvedDeclaration = declaration;
        if (declaration && declaredLater(scope,declaration)) {
            typeError(typer,expr,"'%s' is read before its declaration",expr->name);
            break;
        }
        if (!declaration && receiverCase(typer,context,expr->name)) {
            expr->lowered = caseTest(typer->report->arena,expr,receiverSubject(typer->report->arena,expr),expr->name,NULL);
            type = typeCaseTest(typer,scope,expr->lowered,context);
            break;
        }
        if (!declaration) break;
        if (rangeNodeDeclaresValue(declaration->kind) || declaration->kind == RangeNodeParameter) {
            if (declaration->flags & RangeFlagMany) typeError(typer,expr,"'%s' holds @many storage and is not a value",expr->name);
            // The type was computed where the name was declared, in this same
            // context; a use does not re-derive it (or rerun its laws).
            else if (declaration->type) type = declaration->type;
            else {
                // `let a: b  let b: a` has no type: each is the other's.
                size_t depth = typer->typingCount;
                for (size_t i = 0; i < depth; ++i)
                    if (typer->typing[i] == declaration) {
                        typeError(typer,declaration,"the type of '%s' depends on itself",declaration->name);
                        depth = SIZE_MAX;
                        break;
                    }
                if (depth == SIZE_MAX) break;
                if (depth == sizeof(typer->typing)/sizeof(*typer->typing)) { typeError(typer,expr,"'%s' is derived through too many values to type",expr->name); break; }
                typer->typing[typer->typingCount++] = declaration;
                type = declaredType(typer,scope,declaration,context);
                --typer->typingCount;
            }
        } else if (declaration->kind == RangeNodeFunction) typeError(typer,expr,"'%s' is a function; call it",expr->name);
        else if (typer->macro && (declaration->kind == RangeNodeConstruct || declaration->kind == RangeNodeEnum)) {
            // In a macro a type's name is that declaration, a value of its
            // grammar kind: `written.output != Bool` compares declarations.
            RangeNode *kind = declaration->grammarDefinition;
            if (kind && kind->kind == RangeNodeConstruct) type = specialize(typer,NULL,kind,NULL,NULL,expr);
        } else if (declaration->kind == RangeNodeTypeParameter || declaration->kind == RangeNodeConstruct || declaration->kind == RangeNodeEnum)
            typeError(typer,expr,"'%s' names a type, not a value",expr->name);
        if (isFunctionType(type) && (expr != typer->closureSite || !isFunctionType(expected))) {
            typeError(typer,expr,"'%s' holds a closure: call it, as in %s(…), or pass it on to a function-typed parameter; "
                      "it runs only while the call it was passed to runs, so it is not stored, returned, or held in a value",
                      expr->name,expr->name);
            type = NULL;
        }
        break;
    }
    case RangeNodeClosure:
        if (expr != typer->closureSite || !isFunctionType(expected)) {
            typeError(typer,expr,"a closure is an argument for a function-typed parameter, as in xs.filter(where: { x in … }); "
                      "it runs only while that call runs, so it is not stored, returned, or held in a value");
            break;
        }
        type = typeClosure(typer,scope,expr,expected,context);
        break;
    case RangeNodeCase: {
        // `.red`: a case of the enum the context expects.
        RangeNode *enumeration = caseContext(typer,contextualEnum(typer,expr,expected),expr->name);
        RangeNode *entry = enumeration ? namedCase(typer,enumeration,expr->name,expr) : NULL;
        if (!entry) break;
        if (entry->itemCount) { typeError(typer,expr,"case '%s' carries a payload; write .%s(…)",entry->name,entry->name); break; }
        expr->resolvedDeclaration = entry;
        type = enumeration;
        break;
    }
    case RangeNodeMemberAccess: {
        RangeNode *optional = optionalPath(typer,scope,expr->a,context);
        RangeNode *owner = optional ? optional->resolvedDeclaration : typePath(typer->report,scope,expr->a);
        if (owner) {
            // `Light.red` is a case; `Outer.Inner` names a type.
            if (nestedDeclaration(owner,expr->name,strlen(expr->name))) {
                typeError(typer,expr,"'%s.%s' names a type, not a value",owner->name,expr->name);
                break;
            }
            if (owner->kind != RangeNodeEnum) { typeError(typer,expr,"'%s' names a type, not a value",owner->name); break; }
            RangeNode *enumeration = optional ? optional : pathEnum(typer,scope,owner,expr->a,expected,context,expr);
            RangeNode *entry = enumeration ? namedCase(typer,enumeration,expr->name,expr) : NULL;
            if (!entry) break;
            if (entry->itemCount) { typeError(typer,expr,"case '%s' carries a payload; write %s.%s(…)",entry->name,owner->name,entry->name); break; }
            expr->resolvedDeclaration = entry;
            type = enumeration;
            break;
        }
        RangeNode *receiver = typeOf(typer,scope,expr->a,NULL,context);
        if (!receiver) break;
        if (deferredType(typer,receiver)) { type = receiver; break; }
        if (receiver->kind == RangeNodeTypeParameter) { typeError(typer,expr,"type parameter %s has no members",receiver->name); break; }
        if (isMacroType(receiver)) { type = macroTypeMember(typer,receiver,expr->name,expr); break; }
        RangeNode *declaration = receiver->resolvedDeclaration;
        if (isEnum(receiver) && enumCase(declaration,expr->name)) {
            // `phase.loading`: whether phase holds the case.
            expr->lowered = caseTest(typer->report->arena,expr,expr->a,expr->name,NULL);
            type = typeCaseTest(typer,scope,expr->lowered,context);
            break;
        }
        RangeNode *member = findMember(declaration,expr->name);
        expr->resolvedDeclaration = member;
        if (member) {
            if (member->flags & RangeFlagMany) typeError(typer,expr,"'%s' holds @many storage and is not a value",expr->name);
            else type = memberType(typer,declaration,member,receiver);
        } else if (findFunction(declaration,expr->name)) typeError(typer,expr,"'%s.%s' is a function; call it",declaration->name,expr->name);
        else { char t[160]; describeType(t,sizeof(t),receiver); typeError(typer,expr,"%s has no %s '%s'",t,isEnum(receiver) ? "case" : "member",expr->name); }
        break;
    }
    case RangeNodeCall:
        type = typeCall(typer,scope,expr,expected,context);
        break;
    case RangeNodeEnvironment: {
        // A splice of a macro local is that local.
        if (expr->resolvedDeclaration) { type = expr->resolvedDeclaration->type; break; }
        // `#cases`: the field the macro's target kind declares. A target
        // with no grammar declaration has fields without Range types; a
        // field C has no adapter for is reported where the macro resolves.
        RangeNode *target = typer->macro && typer->macro->b ? typer->macro->b->resolvedDeclaration : NULL;
        if (target && target->kind == RangeNodeMacro) {
            RangeNode *kind = macroTypeNamed(typer,target->name,expr);
            type = kind ? macroTypeMember(typer,kind,expr->name,expr) : NULL;
            break;
        }
        if (!target || target->kind != RangeNodeConstruct) break;
        RangeNode *member = findMember(target,expr->name);
        if (!member) { typeError(typer,expr,"%s has no member '%s'",target->name,expr->name); break; }
        type = memberType(typer,target,member,selfSpecialization(typer,target));
        break;
    }
    case RangeNodeEmission:
        if (!typer->macro) { typeError(typer,expr,"#graph is written only in a macro's body"); break; }
        typeSplices(typer,scope,expr->b);
        break;
    case RangeNodePattern:
        // A case test's pattern argument anywhere else.
        if (expr->integer == RangePatternBind)
            typeError(typer,expr,"'let %s' binds a payload field only in a case test",expr->a->name);
        else typeError(typer,expr,"'_' stands for a payload field only in a case test");
        break;
    case RangeNodeSwitch:
        type = typeSwitch(typer,scope,expr,expected,context,typer->output);
        break;
    case RangeNodeUnary: {
        if (same(expr->name,"-") && expr->a && expr->a->kind == RangeNodeInteger) {
            // -128 is one literal: the law sees the negative value.
            type = typeLiteral(typer,expr->a,expr,expected);
            break;
        }
        RangeNode *operand = typeOf(typer,scope,expr->a,expected,context);
        if (macroOperand(typer,operand)) type = typer->deferred; /* its operator is chosen at macro time */
        else if (operand) type = typeOperator(typer,scope,expr,operand,NULL,context);
        break;
    }
    case RangeNodeBinary: {
        const char *op = expr->name;
        if (same(op,"..<")) { type = typeInterval(typer,scope,expr,context); break; }
        int comparison = same(op,"<") || same(op,">") || same(op,"<=") || same(op,">=");
        int equality = same(op,"=") || same(op,"!=");
        RangeNode *want = comparison || equality ? NULL : expected;
        RangeNode *left, *right = NULL;
        // A literal or `.case` takes the other operand's type when that side is neither.
        int rightFirst = contextual(expr->a) && !contextual(expr->b);
        if (rightFirst) {
            right = typeOf(typer,scope,expr->b,want,context);
            left = typeOf(typer,scope,expr->a,right ? right : want,context);
        } else left = typeOf(typer,scope,expr->a,want,context);
        if (!equality) {
            // Any other operator calls the function its left operand's type
            // declares; on a value of a macro type, that is chosen at macro time.
            if (macroOperand(typer,left)) {
                if (!rightFirst) (void)typeOf(typer,scope,expr->b,NULL,context);
                type = typer->deferred;
            } else if (left) type = typeOperator(typer,scope,expr,left,right,context);
            else if (!rightFirst) (void)typeOf(typer,scope,expr->b,NULL,context);
            break;
        }
        if (!rightFirst) right = typeOf(typer,scope,expr->b,deferredType(typer,left) ? NULL : left,context);
        if (!left || !right) break;
        // `=` gives Bool: the built-in structural comparison, or the type's equality function.
        if (deferredType(typer,left) || deferredType(typer,right)) { type = typer->booleanType; break; }
        if (left != right) {
            // A kind's value compares with a value of a macro type it applies,
            // and `maybe = 5` with the present case holding 5.
            RangeNode *leftWrapped = optionalWrapped(typer,left,NULL), *rightWrapped = optionalWrapped(typer,right,NULL);
            if (converts(left,right)) right = left;
            else if (converts(right,left)) left = right;
            else if (leftWrapped && (leftWrapped == right || converts(leftWrapped,right))) { coerce(typer,expr->b,left,right,"operand"); right = left; }
            else if (rightWrapped && (rightWrapped == left || converts(rightWrapped,left))) { coerce(typer,expr->a,right,left,"operand"); left = right; }
        }
        if (left != right) {
            char l[160], r[160]; describeType(l,sizeof(l),left); describeType(r,sizeof(r),right);
            typeError(typer,expr,"operator '%s' requires matching types; found %s and %s",op,l,r);
            break;
        }
        noteEquality(typer,left,expr);
        type = typer->booleanType;
        break;
    }
    default: break; /* unsupported forms are reported already */
    }
    expr->type = type;
    return type;
}

static void typeBlock(Typer *, SourceScope *, RangeNode *, RangeNode *, RangeNode *);
static RangeNode *typeSwitch(Typer *, SourceScope *, RangeNode *, RangeNode *, RangeNode *, RangeNode *);

/* Whether control cannot reach the end of `node`: it returns, breaks, or
 * continues on every path, or ends the program through @diagnostic. `break`
 * and `continue` leave the innermost loop; a switch is never their target. A
 * loop nested here ends its own breaks, so they do not leave `node`. */
static int exits(const RangeNode *node, int breaking)
{
    if (!node) return 0;
    switch (node->kind) {
    case RangeNodeReturn: return 1;
    case RangeNodeBreak: case RangeNodeContinue: return breaking;
    case RangeNodeBlock:
        for (size_t i = 0; i < node->itemCount; ++i) if (exits(node->items[i],breaking)) return 1;
        return 0;
    case RangeNodeSwitch:
        if (!node->itemCount) return 0;
        for (size_t i = 0; i < node->itemCount; ++i) {
            RangeNode *entry = node->items[i];
            if (!exits(entry->a ? entry->a : entry->b,breaking)) return 0;
        }
        return 1;
    case RangeNodeExpressionStatement:
        return node->a && node->a->kind == RangeNodeAttribute && macroBuiltin(node->a->resolvedDeclaration,"diagnostic");
    default: return 0;
    }
}

/* The function a construct or enum declares with @iteration, which `for … in`
 * calls; *count is how many it declares. The role, not a name, selects it. */
static RangeNode *iterationFunction(const RangeNode *declaration, size_t *count)
{
    RangeNode *found = NULL;
    *count = 0;
    if (declaration && (declaration->kind == RangeNodeConstruct || declaration->kind == RangeNodeEnum))
        for (size_t i = 0; i < declaration->itemCount; ++i)
            if (declaration->items[i]->kind == RangeNodeFunction && appliesBuiltin(declaration->items[i],"iteration")) {
                found = declaration->items[i];
                ++*count;
            }
    return found;
}

/* The @iteration law, checked in C: a type declares at most one such function,
 * and it takes one Int position and returns an optional (the enum applying
 * @optional), absent past the end. The function's own types are known. */
static void checkIteration(Typer *typer, RangeNode *declaration)
{
    size_t count = 0;
    (void)iterationFunction(declaration,&count);
    if (count > 1) {
        typeError(typer,declaration,"%s '%s' declares %zu @iteration functions; a type declares exactly one",
            rangeNodeKindName(declaration->kind),declaration->name,count);
        return;
    }
    RangeNode *function = iterationFunction(declaration,&count);
    if (!function) return;
    RangeNode *integer = typer->integer ? specialize(typer,NULL,typer->integer,NULL,NULL,typer->integer) : NULL;
    RangeNode *output = function->type;
    int position = function->itemCount == 1 && integer && function->items[0]->type == integer;
    int optional = isEnum(output) && appliesBuiltin(output->resolvedDeclaration,"optional");
    if (!position || !optional)
        typeError(typer,function,"@iteration function '%s' of '%s' must take one Int position and return an optional, such as (let at: Int): Element?",
            function->name,declaration->name);
}

/* The @insertion law, checked in C: a type declares at most one such function,
 * and it takes one element and adds it. When the type also declares an
 * @iteration function, the element is the type that function yields. */
static void checkInsertion(Typer *typer, RangeNode *declaration)
{
    size_t count = 0;
    RangeNode *function = insertionFunction(declaration,&count);
    if (count > 1) {
        typeError(typer,declaration,"%s '%s' declares %zu @insertion functions; a type declares at most one",
            rangeNodeKindName(declaration->kind),declaration->name,count);
        return;
    }
    if (!function) return;
    RangeNode *iteration = iterationFunction(declaration,&count);
    RangeNode *element = count == 1 && iteration->type ? optionalWrapped(typer,iteration->type,NULL) : NULL;
    if (function->itemCount != 1 || (element && function->items[0]->type != element)) {
        char t[160] = "one element";
        if (element) { char e[140]; describeType(e,sizeof(e),element); snprintf(t,sizeof(t),"one %s, the element its @iteration function yields",e); }
        typeError(typer,function,"@insertion function '%s' of '%s' must take %s",function->name,declaration->name,t);
    }
}

/* `@print(…)` and `@diagnostic(…)` in runtime code: one message, a String or
 * an interpolated literal whose parts are integers, booleans, or strings. */
static void typeEffect(Typer *typer, SourceScope *scope, RangeNode *attribute, RangeNode *context)
{
    RangeNode *macro = NULL;
    for (size_t u = 0; u < typer->report->count && !macro; ++u) for (size_t i = 0; i < typer->report->units[u]->itemCount; ++i) {
        RangeNode *candidate = typer->report->units[u]->items[i];
        if (candidate->kind == RangeNodeMacro && !candidate->b && same(candidate->name,attribute->name)) { macro = candidate; break; }
    }
    if (!macro) return; /* undeclared macros are reported already */
    attribute->resolvedDeclaration = macro;
    // @warning runs only at macro time; elsewhere code generation reports it.
    if (!macroBuiltin(macro,"print") && !macroBuiltin(macro,"diagnostic") && !(typer->macro && macroBuiltin(macro,"warning")))
        return;
    if (attribute->itemCount != 1) { typeError(typer,attribute,"@%s requires one message",macro->name); return; }
    // The message is the effect's one parameter: a String.
    RangeNode *message = attribute->items[0]->a, *expected = NULL;
    if (macro->itemCount == 1) {
        SourceScope effect = {.owner=macro};
        expected = declaredType(typer,&effect,macro->items[0],NULL);
    }
    RangeNode *actual = typeOf(typer,scope,message,expected,context);
    char what[160]; snprintf(what,sizeof(what),"argument '%s' of '@%s'",macro->itemCount == 1 ? macro->items[0]->name : "message",macro->name);
    expectType(typer,attribute,expected,actual,what);
    if (message->kind != RangeNodeString) return;
    for (size_t i = 0; i < message->itemCount; ++i) {
        RangeNode *part = message->items[i];
        if (part->flags & RangeFlagLiteral) continue;
        RangeNode *type = typeOf(typer,scope,part->a,NULL,context);
        if (!type) continue;
        // At macro time a declaration is written as its name.
        if (typer->macro && macroTimeType(typer,type)) continue;
        if (type->kind == RangeNodeSpecialization && (type->resolvedDeclaration == typer->integer
            || type->resolvedDeclaration == typer->boolean
            || (isEnum(type) && !enumPayloads(type->resolvedDeclaration))
            || (message->type && type->resolvedDeclaration == message->type->resolvedDeclaration))) continue;
        char name[160]; describeType(name,sizeof(name),type);
        typeError(typer,part->a,"@%s cannot write %s",macro->name,name);
    }
}

static void typeStatementOnly(Typer *, SourceScope *, RangeNode *, RangeNode *, RangeNode *);

/* A statement's case tests narrow nothing beyond it. */
static void typeStatement(Typer *typer, SourceScope *scope, RangeNode *node, RangeNode *context, RangeNode *output)
{
    size_t mark = typer->narrowedCount;
    typeStatementOnly(typer,scope,node,context,output);
    typer->narrowedCount = mark;
    // A local is declared once its statement is typed: later ones may read it.
    if (node && (node->kind == RangeNodeLet || node->kind == RangeNodeState)) node->flags |= RangeFlagTyped;
}

static void typeStatementOnly(Typer *typer, SourceScope *scope, RangeNode *node, RangeNode *context, RangeNode *output)
{
    if (!node) return;
    switch (node->kind) {
    case RangeNodeBlock: typeBlock(typer,scope,node,context,output); break;
    case RangeNodeLet: case RangeNodeState:
        if (node->typeName && (node->flags & RangeFlagApplication)) {
            // `let r: step(x: 1)` calls a function; a construct here is construction.
            if (!lookupFunction(typer->report,scope,node->typeName)) {
                node->type = typeConstruction(typer,scope,node,node->typeName,node->generics,node->flags,node->items,node->itemCount,context);
                break;
            }
            RangeNode *callee = rangeNodeCreate(typer->report->arena,RangeNodeName,node->path,node->line,node->column);
            callee->name = node->typeName;
            callee->generics = node->generics;
            // The call, over the written arguments, is the value typing records beside it.
            RangeNode *call = rangeNodeCreate(typer->report->arena,RangeNodeCall,node->path,node->line,node->column);
            call->a = callee;
            for (size_t i = 0; i < node->itemCount; ++i) rangeNodeAppend(typer->report->arena,call,node->items[i]);
            node->lowered = call;
            node->type = typeOf(typer,scope,call,NULL,context);
            break;
        }
        node->type = declaredType(typer,scope,node,context);
        // A local names a value: `let v: Int` alone states a type, and only a
        // construct's member may leave its value to construction.
        if ((node->typeName || (node->flags & RangeFlagRequired)) && !(node->flags & RangeFlagApplication)
            && !declarationValue(node) && !optionalWithoutValue(node))
            typeError(typer,node,"'%s' needs an initial value",node->name);
        break;
    case RangeNodeAssign: {
        RangeNode *target = node->a;
        if (target && target->kind == RangeNodeMemberAccess) {
            // `p.x: 5` changes a state member of a state value.
            RangeNode *expected = typeOf(typer,scope,target,NULL,context);
            RangeNode *member = target->resolvedDeclaration, *root = target;
            while (root->kind == RangeNodeMemberAccess) {
                if (root->resolvedDeclaration && root->resolvedDeclaration->kind != RangeNodeState)
                    typeError(typer,node,"cannot assign through %s '%s'",rangeNodeKindName(root->resolvedDeclaration->kind),root->name);
                root = root->a;
            }
            if (root->kind == RangeNodeName && root->resolvedDeclaration && root->resolvedDeclaration->kind != RangeNodeState)
                typeError(typer,node,"cannot assign through %s '%s'",rangeNodeKindName(root->resolvedDeclaration->kind),root->name);
            if (member) {
                RangeNode *actual = typeOf(typer,scope,node->b,expected,context);
                char what[160]; snprintf(what,sizeof(what),"assignment to '%s'",member->name);
                coerce(typer,node->b,expected,actual,what);
            }
            break;
        }
        if (!target || target->kind != RangeNodeName) { sourceDiagnostic(typer->report,node,0,"not-implemented","assignment to this target is not implemented"); break; }
        RangeNode *declaration = sourceLookup(typer->report,scope,target->name,0);
        target->resolvedDeclaration = declaration;
        if (!declaration) break;
        if (declaration->kind != RangeNodeState) { typeError(typer,node,"cannot assign to %s '%s'",rangeNodeKindName(declaration->kind),target->name); break; }
        // The state's type was computed where it was declared; an assignment does not re-derive it.
        RangeNode *expected = declaration->type ? declaration->type : declaredType(typer,scope,declaration,context);
        RangeNode *actual = typeOf(typer,scope,node->b,expected,context);
        char what[160]; snprintf(what,sizeof(what),"assignment to '%s'",target->name);
        coerce(typer,node->b,expected,actual,what);
        break;
    }
    case RangeNodeWhile: {
        // A while without a condition is the loop `for … in` is written as; it ends at break.
        if (node->a) {
            RangeNode *condition = typeOf(typer,scope,node->a,typer->booleanType,context);
            expectType(typer,node->a,typer->booleanType,condition,"condition");
        }
        typer->loops += 1;
        typeStatement(typer,scope,node->b,context,output);
        typer->loops -= 1;
        break;
    }
    case RangeNodeFor: {
        // The sequence is typed first: its type's @iteration function is the
        // member the loop calls, its one argument the position.
        RangeNode *loop = node->a;
        if (!loop || loop->itemCount != 3) break;
        SourceScope body = {.owner=loop,.parent=scope};
        RangeNode *sequence = loop->items[0];
        typeStatement(typer,&body,sequence,context,output);
        RangeNode *type = sequence->type;
        if (!type) break;
        size_t count = 0;
        RangeNode *function = type->kind == RangeNodeSpecialization ? iterationFunction(type->resolvedDeclaration,&count) : NULL;
        if (count != 1) {
            char t[160]; describeType(t,sizeof(t),type);
            if (count) typeError(typer,rangeNodeRHS(sequence),"'for … in' needs one @iteration function; %s declares %zu",t,count);
            else typeError(typer,rangeNodeRHS(sequence),"'for … in' cannot iterate %s: it declares no @iteration function",t);
            break;
        }
        RangeNode *next = loop->items[2]->b->items[0]->a; /* the subject of the switch over the next element */
        next->a->resolvedDeclaration = function;
        typeStatement(typer,&body,loop->items[1],context,output);
        typeStatement(typer,&body,loop->items[2],context,output);
        break;
    }
    case RangeNodeBreak: case RangeNodeContinue:
        if (!typer->loops)
            typeError(typer,node,"'%s' is only allowed inside a loop%s",node->kind == RangeNodeBreak ? "break" : "continue",
                      typer->closures ? "; a closure's body does not leave a loop around the closure" : "");
        break;
    case RangeNodeReturn:
        if (!output && typer->inferring) {
            // A closure whose result is inferred: its first return decides it.
            if (!node->a) { typeError(typer,node,"return a value: the result of this closure is not known"); break; }
            RangeNode *actual = typeOf(typer,scope,node->a,typer->inferred,context);
            if (!typer->inferred) typer->inferred = actual;
            else coerce(typer,node->a,typer->inferred,actual,"return");
            break;
        }
        if (output) {
            if (!node->a && unitType(typer,output)) break; /* a unit result, such as Void, needs no value */
            if (!node->a) { char t[160]; describeType(t,sizeof(t),output); typeError(typer,node,"return requires %s",t); break; }
            coerce(typer,node->a,output,typeOf(typer,scope,node->a,output,context),"return");
        } else if (node->a) {
            (void)typeOf(typer,scope,node->a,NULL,context);
            typeError(typer,node,"this function returns no value");
        }
        break;
    case RangeNodeSwitch:
        (void)typeSwitch(typer,scope,node,NULL,context,output);
        break;
    case RangeNodeExpressionStatement:
        if (node->a && node->a->kind == RangeNodeAttribute) typeEffect(typer,scope,node->a,context);
        else if (node->a) (void)typeOf(typer,scope,node->a,NULL,context);
        break;
    default: break; /* declarations, and forms reported as not implemented */
    }
}

/* ---- patterns ----
 * A switch covers every combination of its case tests' subjects, by its
 * arms or a default, and runs exactly one arm; an arm that no earlier arm
 * leaves anything for is an error. Coverage is the usefulness of a pattern
 * vector over the rows before it (Maranget's algorithm), one column per
 * subject: an enum case splits a column into its payload fields; values and
 * rows with a guard cover nothing for the rows after them. */

static int patternWild(const RangeNode *pattern)
{
    return !pattern || pattern->integer == RangePatternAny || pattern->integer == RangePatternBind;
}

static RangeNode *patternCase(const RangeNode *pattern)
{
    return pattern && pattern->integer == RangePatternCase ? pattern->resolvedDeclaration : NULL;
}

static RangeNode *patternField(const RangeNode *pattern, size_t index)
{
    return pattern && (pattern->flags & RangeFlagApplication) && index < pattern->itemCount ? pattern->items[index]->a : NULL;
}

static int literalValue(const RangeNode *value, long long *out)
{
    if (!value) return 0;
    if (value->kind == RangeNodeInteger || value->kind == RangeNodeBool) { *out = value->integer; return 1; }
    if (value->kind == RangeNodeUnary && same(value->name,"-") && value->a && value->a->kind == RangeNodeInteger) {
        *out = -value->a->integer;
        return 1;
    }
    return 0;
}

static int sameValuePattern(const RangeNode *a, const RangeNode *b)
{
    long long x, y;
    return a && b && a->integer == RangePatternValue && b->integer == RangePatternValue
        && literalValue(a->a,&x) && literalValue(b->a,&y) && x == y;
}

/* Rows and the vector specialized to one case: its payload fields replace the column. */
static int usefulCase(Typer *typer, RangeNode ***rows, size_t count, RangeNode **q, RangeNode **types, size_t width,
                      RangeNode *entry)
{
    RangeArena *arena = typer->report->arena;
    size_t arity = entry->itemCount, w = arity + width - 1;
    RangeNode **ntypes = rangeArenaAllocate(arena,(w ? w : 1) * sizeof(*ntypes));
    for (size_t i = 0; i < arity; ++i) ntypes[i] = caseFieldType(typer,types[0],entry->items[i]);
    for (size_t i = 1; i < width; ++i) ntypes[arity + i - 1] = types[i];
    RangeNode ***nrows = rangeArenaAllocate(arena,(count ? count : 1) * sizeof(*nrows));
    size_t n = 0;
    for (size_t r = 0; r <= count; ++r) {
        RangeNode **source = r < count ? rows[r] : q;
        if (r < count && !patternWild(source[0]) && patternCase(source[0]) != entry) continue;
        RangeNode **row = rangeArenaAllocate(arena,(w ? w : 1) * sizeof(*row));
        for (size_t i = 0; i < arity; ++i) row[i] = patternWild(source[0]) ? NULL : patternField(source[0],i);
        for (size_t i = 1; i < width; ++i) row[arity + i - 1] = source[i];
        if (r < count) nrows[n++] = row; else q = row;
    }
    return useful(typer,nrows,n,q,ntypes,w);
}

static int useful(Typer *typer, RangeNode ***rows, size_t count, RangeNode **q, RangeNode **types, size_t width)
{
    if (!width) return count == 0;
    RangeArena *arena = typer->report->arena;
    RangeNode *head = q[0], *type = types[0];
    if (head && head->integer == RangePatternCase) {
        RangeNode *entry = patternCase(head);
        return entry ? usefulCase(typer,rows,count,q,types,width,entry) : 1;
    }
    RangeNode ***rest = rangeArenaAllocate(arena,(count ? count : 1) * sizeof(*rest));
    size_t n = 0;
    if (!patternWild(head)) {
        // A value or a relation: only rows that are wild here or the same value remain.
        for (size_t r = 0; r < count; ++r)
            if (patternWild(rows[r][0]) || sameValuePattern(rows[r][0],head)) rest[n++] = rows[r] + 1;
        return useful(typer,rest,n,q + 1,types + 1,width - 1);
    }
    if (isEnum(type)) {
        RangeNode *declaration = type->resolvedDeclaration;
        int complete = 1;
        size_t cases = 0;
        for (size_t i = 0; i < declaration->itemCount; ++i) {
            RangeNode *entry = declaration->items[i];
            if (entry->kind != RangeNodeEnumCase) continue;
            ++cases;
            int found = 0;
            for (size_t r = 0; r < count && !found; ++r) found = patternCase(rows[r][0]) == entry;
            if (!found) complete = 0;
        }
        if (!cases) return 0; /* no value to match */
        if (complete) {
            for (size_t i = 0; i < declaration->itemCount; ++i)
                if (declaration->items[i]->kind == RangeNodeEnumCase
                    && usefulCase(typer,rows,count,q,types,width,declaration->items[i])) return 1;
            return 0;
        }
    }
    for (size_t r = 0; r < count; ++r) if (patternWild(rows[r][0])) rest[n++] = rows[r] + 1;
    return useful(typer,rest,n,q + 1,types + 1,width - 1);
}

static void typePattern(Typer *typer, SourceScope *scope, RangeNode *pattern, RangeNode *type, RangeNode *context)
{
    if (!pattern) return;
    pattern->type = type;
    if (deferredType(typer,type)) {
        // Which cases the subject has is known at macro time: what the
        // pattern binds is known then too.
        if (pattern->integer == RangePatternBind) pattern->a->type = type;
        else if (pattern->integer == RangePatternValue) (void)typeOf(typer,scope,pattern->a,NULL,context);
        else for (size_t i = 0; i < pattern->itemCount; ++i) typePattern(typer,scope,pattern->items[i]->a,type,context);
        return;
    }
    char t[160]; describeType(t,sizeof(t),type);
    switch (pattern->integer) {
    case RangePatternAny: return;
    case RangePatternBind: pattern->a->type = type; return;
    case RangePatternCase: {
        // `.name` is always a case of the subject's type. The case `for … in`
        // writes without a name is the payload case of the @optional
        // declaration, whose payload is the element.
        if (!type) return;
        RangeNode *entry = NULL;
        if (!pattern->name) {
            (void)optionalWrapped(typer,type,&entry);
            if (!entry) { typeError(typer,pattern,"'for … in' unwraps an optional element; found %s",t); return; }
        } else if (!isEnum(type)) {
            typeError(typer,pattern,"'.%s' matches an enum case, but the subject is %s",pattern->name,t);
            return;
        } else entry = namedCase(typer,type,pattern->name,pattern);
        if (!entry) return;
        pattern->resolvedDeclaration = entry;
        if (!(pattern->flags & RangeFlagApplication)) return; /* `.value` matches any payload */
        if (!entry->itemCount) { typeError(typer,pattern,"case '%s' has no payload to match",entry->name); return; }
        if (pattern->itemCount != entry->itemCount) {
            typeError(typer,pattern,"case '%s' has %zu payload fields; the pattern matches %zu",entry->name,entry->itemCount,pattern->itemCount);
            return;
        }
        for (size_t i = 0; i < entry->itemCount; ++i) {
            RangeNode *argument = pattern->items[i], *field = entry->items[i];
            if (argument->name && !same(argument->name,field->name))
                typeError(typer,argument,"payload field %zu of '%s' is %s",i + 1,entry->name,
                          labeledField(field) ? field->name : "unlabeled");
            argument->resolvedDeclaration = field;
            typePattern(typer,scope,argument->a,caseFieldType(typer,type,field),context);
        }
        return;
    }
    case RangePatternValue: {
        RangeNode *actual = typeOf(typer,scope,pattern->a,type,context);
        expectType(typer,pattern->a,type,actual,"pattern");
        // A literal that names a case of a literal enum is that case's pattern.
        if (isEnum(type) && actual == type) {
            RangeNode *value = pattern->a, *entry = NULL;
            if (isLiteral(value)) entry = literalCase(type->resolvedDeclaration,value);
            else if (value->resolvedDeclaration && value->resolvedDeclaration->kind == RangeNodeEnumCase) entry = value->resolvedDeclaration;
            if (entry) { pattern->integer = RangePatternCase; pattern->resolvedDeclaration = entry; pattern->name = entry->name; return; }
        }
        // Any other value is compared with `=`.
        if (actual == type) noteEquality(typer,type,pattern);
        return;
    }
    }
}


/* The type a switch expression has, from its arms' values: the first arm's,
 * or the optional one arm's value promotes the others to. */
static RangeNode *armsType(Typer *typer, RangeNode *node, RangeNode *type, RangeNode *arm, RangeNode *actual)
{
    if (!type || !actual || type == actual) return type ? type : actual;
    if (deferredType(typer,type) || deferredType(typer,actual)) return typer->deferred;
    if (optionalWrapped(typer,type,NULL) == actual) {
        coerce(typer,arm,type,actual,"an arm of a switch expression");
        return type;
    }
    if (optionalWrapped(typer,actual,NULL) == type) {
        // An earlier arm's value is promoted to the optional this one yields.
        for (size_t i = 0; i < node->itemCount && node->items[i]->a != arm; ++i) {
            RangeNode *earlier = node->items[i]->a;
            if (earlier && (earlier->promoted ? earlier->promoted : earlier->type) == type)
                coerce(typer,earlier,actual,type,"an arm of a switch expression");
        }
        return actual;
    }
    char t[160], a[160]; describeType(t,sizeof(t),type); describeType(a,sizeof(a),actual);
    typeError(typer,arm,"the arms of a switch expression yield one type; this arm yields %s, an earlier one %s",a,t);
    return type;
}

/* A row's patterns, each typed with its subject's type. */
static void typeRow(Typer *typer, SourceScope *scope, RangeNode *row, RangeNode **types, size_t width, RangeNode *context)
{
    if (row->integer != RangePatternRow) { typePattern(typer,scope,row,types[0],context); return; }
    for (size_t k = 0; k < width && k < row->itemCount; ++k) typePattern(typer,scope,row->items[k],types[k],context);
}

/* `switch { condition: body, … }`: every arm must be reachable, and unless
 * a default ends it, the arms' case tests must cover every combination of
 * their subjects' cases. */
static void typeConditionCoverage(Typer *typer, RangeNode *node)
{
    RangeArena *arena = typer->report->arena;
    ConditionShape shape;
    conditionShape(arena,node,&shape);
    size_t width = shape.width;
    RangeNode **types = rangeArenaAllocate(arena,(width ? width : 1) * sizeof(*types));
    RangeNode **cases = rangeArenaAllocate(arena,(width ? width : 1) * sizeof(*cases));
    for (size_t k = 0; k < width; ++k) {
        types[k] = shape.subjects[k]->type;
        cases[k] = isEnum(types[k]) ? types[k]->resolvedDeclaration : NULL;
    }
    int *reached = rangeArenaAllocate(arena,(shape.count ? shape.count : 1) * sizeof(*reached));
    char missing[512] = "";
    int complete = conditionCoverage(arena,typer,&shape,types,cases,reached,missing,sizeof(missing));
    RangeNode *reported = NULL;
    for (size_t i = 0; i < shape.count; ++i) {
        RangeNode *entry = shape.arms[i];
        if (reached[i] || (entry->flags & RangeFlagImplicit) || entry == reported) continue;
        reported = entry;
        if (entry->flags & RangeFlagLiteral) typeError(typer,entry,"'default' is never reached: the arms above match every value");
        else typeError(typer,entry->items[0]->b,"this condition is already handled by earlier arms");
    }
    if (complete) return;
    if (!*missing) { typeError(typer,node,"switch must be exhaustive; add a default"); return; }
    int many = strchr(missing,',') != NULL;
    typeError(typer,node,"switch must be exhaustive: %s %s not handled; add %s or a default",missing,
              many ? "are" : "is",many ? "arms for them" : "an arm for it");
}

/* A switch statement, or, with RangeFlagValue, a switch expression: its type
 * is the one its arms yield, each typed with `expected` (or, without one,
 * with the first value's type) as context, as any value is. An arm that does
 * not yield is a block that must diverge. A switch over conditions has no
 * subjects; the switch a for loop lowers to has one. */
static RangeNode *typeSwitch(Typer *typer, SourceScope *scope, RangeNode *node, RangeNode *expected, RangeNode *context, RangeNode *output)
{
    size_t errors = typer->report->errors;
    RangeArena *arena = typer->report->arena;
    size_t width = node->c ? node->c->itemCount : 1;
    RangeNode **types = rangeArenaAllocate(arena,(width ? width : 1) * sizeof(*types));
    int typed = 1;
    for (size_t k = 0; k < width; ++k) {
        types[k] = typeOf(typer,scope,node->c ? node->c->items[k] : node->a,NULL,context);
        typed &= types[k] != NULL;
    }
    int value = (node->flags & RangeFlagValue) != 0;
    RangeNode *type = NULL;
    for (size_t i = 0; i < node->itemCount; ++i) {
        RangeNode *entry = node->items[i];
        size_t narrowed = typer->narrowedCount; /* what the arm's condition narrows holds in its body */
        if ((entry->flags & RangeFlagLiteral) && i + 1 != node->itemCount)
            typeError(typer,entry,"'default' must be the last arm of a switch");
        for (size_t j = 0; j < entry->itemCount; ++j) {
            // The parser checked where the row binds; its condition sees its bindings.
            RangeNode *row = entry->items[j], *bindings = row->c;
            typeRow(typer,scope,row,types,width,context);
            if (row->b) {
                SourceScope bound = {.owner=bindings ? bindings : entry,.parent=scope};
                expectType(typer,row->b,typer->booleanType,typeOf(typer,&bound,row->b,typer->booleanType,context),"condition");
            }
        }
        SourceScope body = {.owner=entry->c ? entry->c : entry,.parent=scope};
        if (entry->a) {
            RangeNode *actual = typeOf(typer,&body,entry->a,expected ? expected : type,context);
            type = armsType(typer,node,type,entry->a,actual);
            typer->narrowedCount = narrowed;
            continue;
        }
        typeBlock(typer,&body,entry->b,context,output);
        typer->narrowedCount = narrowed;
        if (value && !exits(entry->b,typer->loops > 0))
            typeError(typer,entry->b,"an arm of a switch expression yields a value or diverges; this block ends without return, break, continue, or @diagnostic");
    }
    if (value && !type && typer->report->errors == errors)
        typeError(typer,node,"no arm of this switch expression yields a value");
    node->type = type;
    if (!typed || typer->report->errors != errors) return type;
    if (!width) { typeConditionCoverage(typer,node); return type; }
    // Each row must match something the earlier ones do not; together they
    // must match every value, or every combination of the subjects' values.
    // A row with a condition covers nothing for the rows after it.
    size_t capacity = 1;
    for (size_t i = 0; i < node->itemCount; ++i) capacity += node->items[i]->itemCount + 1;
    RangeNode ***rows = rangeArenaAllocate(arena,capacity * sizeof(*rows));
    size_t count = 0;
    for (size_t i = 0; i < node->itemCount; ++i) {
        RangeNode *entry = node->items[i];
        size_t patterns = (entry->flags & RangeFlagLiteral) ? 1 : entry->itemCount;
        for (size_t j = 0; j < patterns; ++j) {
            RangeNode *pattern = (entry->flags & RangeFlagLiteral) ? NULL : entry->items[j];
            RangeNode **row = rangeArenaAllocate(arena,width * sizeof(*row));
            patternRow(pattern,row,width);
            // A default the compiler wrote for a lowering may be unreachable.
            if (!useful(typer,rows,count,row,types,width) && !(entry->flags & RangeFlagImplicit)) {
                if (pattern) typeError(typer,pattern,"this pattern is already handled by earlier arms");
                else typeError(typer,entry,"'default' is never reached: the arms above match every value");
            }
            if (!pattern || !pattern->b) rows[count++] = row;
        }
    }
    RangeNode **wild = rangeArenaAllocate(arena,width * sizeof(*wild));
    patternRow(NULL,wild,width);
    if (!useful(typer,rows,count,wild,types,width)) return type;
    char t[480] = "";
    for (size_t k = 0, used = 0; k < width; ++k) {
        char one[160]; describeType(one,sizeof(one),types[k]);
        used += (size_t)snprintf(t + used,sizeof(t) > used ? sizeof(t) - used : 0,"%s%s",k ? ", " : "",one);
    }
    char missing[512] = "";
    RangeNode *subject = types[0];
    size_t length = 0;
    if (isEnum(subject))
        for (size_t i = 0; i < subject->resolvedDeclaration->itemCount; ++i) {
            RangeNode *entry = subject->resolvedDeclaration->items[i];
            if (entry->kind != RangeNodeEnumCase || !usefulCase(typer,rows,count,wild,types,1,entry)) continue;
            if (length + strlen(entry->name) + 8 < sizeof(missing))
                length += (size_t)snprintf(missing + length,sizeof(missing) - length,"%s'.%s'",length ? ", " : "",entry->name);
        }
    if (length) typeError(typer,node,"switch over %s must be exhaustive: %s %s not handled; add %s or a default",t,missing,
                          strchr(missing,',') ? "are" : "is",strchr(missing,',') ? "those cases" : "that case");
    else typeError(typer,node,"switch over %s must be exhaustive; add a default",t);
    return type;
}

static void typeBlock(Typer *typer, SourceScope *parent, RangeNode *block, RangeNode *context, RangeNode *output)
{
    if (!block) return;
    SourceScope scope = {.owner=block,.parent=parent};
    for (size_t i = 0; i < block->itemCount; ++i) typeStatement(typer,&scope,block->items[i],context,output);
}

static void typeFunction(Typer *typer, SourceScope *parent, RangeNode *function, RangeNode *context)
{
    if (function->flags & RangeFlagTyped) return;
    function->flags |= RangeFlagTyped;
    SourceScope scope = {.owner=function,.parent=parent};
    // An operator takes its right operand, or nothing when it is prefix.
    if (function->typeName && operatorName(function->name)) {
        int prefix = same(function->name,"-") || same(function->name,"!");
        int binary = !same(function->name,"!");
        if (!((binary && function->itemCount == 1) || (prefix && function->itemCount == 0)))
            typeError(typer,function,"operator '%s' takes %s; %s.%s takes %zu",function->name,
                      prefix && binary ? "one parameter, the right operand, or none as a prefix" : prefix ? "no parameters" : "one parameter, the right operand",
                      function->typeName,function->name,function->itemCount);
    }
    // `&` and `|` are the condition type's short-circuit logic, and they join
    // the patterns and conditions of a switch label: no other type declares them.
    if (function->typeName && (same(function->name,"&") || same(function->name,"|"))
        && (!(function->flags & RangeFlagBuiltin) || !context || context->resolvedDeclaration != typer->boolean))
        typeError(typer,function,"'%s' is reserved for Bool logic; %s cannot declare it",
                  function->name,function->typeName);
    // A method's receiver is specialized by the receiver's own parameters.
    if (function->typeName && context) methodReceiver(typer->report,function)->type = context;
    TyperContext outer = typerSave(typer);
    typer->narrowedFloor = typer->narrowedCount;
    typer->loops = 0;
    typer->inferring = 0;
    typer->closures = 0;
    typer->closureSite = NULL;
    typer->macro = NULL; /* a function a macro instantiates is not macro code */
    typer->function = function;
    for (size_t i = 0; i < function->itemCount; ++i) function->items[i]->type = declaredType(typer,&scope,function->items[i],context);
    RangeNode *output = function->b
        ? resolveTypeReference(typer,&scope,function->b->name,function->b->generics,function->b->flags,context,function->b) : NULL;
    function->type = output;
    typer->output = output;
    if (function->a) typeBlock(typer,&scope,function->a,context,output);
    typerRestore(typer,outer);
}

/* A macro's body is typed as a function's is, returning no value, in place
 * and once, as it is first applied: its parameters, its locals, and
 * top-level functions are in scope; `#field` is the field its target kind
 * declares; #graph code is typed where it lands, its splices here. Typing at
 * the first application reports what the source pass would then, and a body
 * with anything unresolved or mistyped does not run. A macro never applied
 * is typed after macro time; the source pass checked it. */
static void typeMacro(Typer *typer, SourceScope *parent, RangeNode *macro, int diagnose)
{
    if (!macro->a || (macro->flags & RangeFlagTyped)) return; /* a @builtin macro has no body */
    size_t errors = typer->report->errors;
    if (diagnose) diagnoseSourceNode(typer->report,parent,macro,0);
    macro->flags |= RangeFlagTyped;
    SourceScope scope = {.owner=macro,.parent=parent};
    TyperContext outer = typerSave(typer);
    typer->narrowedFloor = typer->narrowedCount;
    typer->function = NULL;
    typer->output = NULL;
    typer->macro = macro;
    for (size_t i = 0; i < macro->itemCount; ++i) macro->items[i]->type = declaredType(typer,&scope,macro->items[i],NULL);
    typeBlock(typer,&scope,macro->a,NULL,NULL);
    checkMutations(typer,macro->a);
    typerRestore(typer,outer);
    if (typer->report->errors != errors) macro->flags |= RangeFlagInvalid;
}

/* Two written types are the same when they are spelled alike: name, flags,
 * and generic arguments. Used where types are not resolved: generic templates. */
static int sameTypeSyntax(const RangeNode *x, const RangeNode *y)
{
    if (!x || !y) return x == y;
    if (x->kind != y->kind || !same(x->name ? x->name : "",y->name ? y->name : "") || x->integer != y->integer
        || x->flags != y->flags || x->itemCount != y->itemCount) return 0;
    if (!sameTypeSyntax(x->a,y->a) || !sameTypeSyntax(x->generics,y->generics)) return 0;
    for (size_t i = 0; i < x->itemCount; ++i) if (!sameTypeSyntax(x->items[i],y->items[i])) return 0;
    return 1;
}

/* Overloads differ in their labels or parameter types. Two functions of one
 * scope with the same name, labels, and parameter types are ambiguous: no
 * call could choose between them. */
static void checkOverloads(Typer *typer, RangeNode *owner)
{
    for (size_t i = 0; i < owner->itemCount; ++i) {
        RangeNode *second = owner->items[i];
        if (second->kind != RangeNodeFunction) continue;
        for (size_t j = 0; j < i; ++j) {
            RangeNode *first = owner->items[j];
            if (first->kind != RangeNodeFunction || !same(first->name,second->name) || first->itemCount != second->itemCount) continue;
            int differ = 0;
            for (size_t k = 0; k < first->itemCount && !differ; ++k) {
                RangeNode *x = first->items[k], *y = second->items[k];
                if (!same(x->name,y->name)) differ = 1;
                else if (x->type && y->type) differ = x->type != y->type;
                else differ = (x->flags & ~RangeFlagBinding) != (y->flags & ~RangeFlagBinding) || !sameTypeSyntax(x->b,y->b);
            }
            if (differ) continue;
            char origin[512];
            if (first->emittedBy) snprintf(origin,sizeof(origin),"first emitted by @%s at %s:%d",first->emittedBy->name,first->emittedBy->path,first->emittedBy->line);
            else snprintf(origin,sizeof(origin),"first declared at %s:%d",first->path,first->line);
            RangeNode *at = second->emittedBy ? second->emittedBy : second;
            sourceDiagnostic(typer->report,at,0,"type","ambiguous: %s is declared twice with the same signature; %s",second->name,origin);
            break;
        }
    }
}

static void typeConstruct(Typer *, SourceScope *, RangeNode *);

/* A case's payload fields are typed in the enum, specialized by its own
 * parameters; its methods see that specialization as `self`. */
static void typeEnum(Typer *typer, SourceScope *parent, RangeNode *declaration)
{
    RangeNode *context = selfSpecialization(typer,declaration);
    SourceScope scope = {.owner=declaration,.parent=parent};
    for (size_t i = 0; i < declaration->itemCount; ++i) {
        RangeNode *item = declaration->items[i];
        if (item->kind == RangeNodeEnumCase)
            for (size_t j = 0; j < item->itemCount; ++j) item->items[j]->type = declaredType(typer,&scope,item->items[j],context);
        else if (item->kind == RangeNodeConstruct) typeConstruct(typer,&scope,item);
        else if (item->kind == RangeNodeEnum) typeEnum(typer,&scope,item);
    }
    // Methods are typed once every case's payload is; a generic one per instance.
    for (size_t i = 0; i < declaration->itemCount; ++i)
        if (declaration->items[i]->kind == RangeNodeFunction && !genericTemplate(declaration->items[i]))
            typeFunction(typer,&scope,declaration->items[i],context);
    checkIteration(typer,declaration);
    checkInsertion(typer,declaration);
    checkOverloads(typer,declaration);
}

/* The first member of `declaration`, at `index` or later, that a member
 * default refers to by bare name: defaults run in declaration order, so they
 * see only the members before them. */
static RangeNode *laterMember(RangeNode *declaration, size_t index, RangeNode *node)
{
    if (!node || node->kind == RangeNodeFunction || node->kind == RangeNodeConstruct || node->kind == RangeNodeEnum) return NULL;
    RangeNode *target = node->kind == RangeNodeName ? node->resolvedDeclaration : NULL;
    for (size_t i = index; target && i < declaration->itemCount; ++i)
        if (declaration->items[i] == target) return target;
    RangeNode *found = laterMember(declaration,index,node->a);
    if (!found) found = laterMember(declaration,index,node->b);
    for (size_t i = 0; !found && i < node->itemCount; ++i) found = laterMember(declaration,index,node->items[i]);
    return found;
}

/* `let height: width` and `let area: width * 2` are defaults computed at
 * construction from the members declared before them, supplied or defaulted.
 * Unlike `derived`, they are evaluated once. */
static void checkMemberDefaults(Typer *typer, RangeNode *declaration)
{
    for (size_t i = 0; i < declaration->itemCount; ++i) {
        RangeNode *member = declaration->items[i];
        if (!constructionInput(member)) continue;
        RangeNode *later = NULL;
        if (member->typeName && !(member->flags & RangeFlagApplication)) {
            // A bare name: a member copied, or a type required.
            RangeNode *named = !member->generics && !(member->flags & RangeFlagOptional) ? findMember(declaration,member->typeName) : NULL;
            for (size_t j = i; named && j < declaration->itemCount; ++j) if (declaration->items[j] == named) later = named;
        } else if (member->typeName) {
            for (size_t j = 0; !later && j < member->itemCount; ++j) later = laterMember(declaration,i,member->items[j]);
        } else later = laterMember(declaration,i,rangeNodeRHS(member));
        if (later == member)
            typeError(typer,member,"the default of '%s' refers to '%s' itself",member->name,member->name);
        else if (later)
            typeError(typer,member,"the default of '%s' refers to '%s', which is declared after it; a default sees only the members before it",
                      member->name,later->name);
    }
}

/* A member's type in its construct's own specialization, once. */
static void typeMember(Typer *typer, SourceScope *scope, RangeNode *item, RangeNode *context)
{
    if (item->flags & RangeFlagTyped) return;
    item->flags |= RangeFlagTyped;
    if (item->typeName && (item->flags & RangeFlagApplication)) {
        // A member initialized by construction, e.g. `state from: Point(x: 0)`.
        if (!lookupFunction(typer->report,scope,item->typeName))
            item->type = typeConstruction(typer,scope,item,item->typeName,item->generics,item->flags,
                                          item->items,item->itemCount,context);
        else typeError(typer,item,"member '%s' cannot be initialized by calling '%s'",item->name,item->typeName);
        return;
    }
    item->type = declaredType(typer,scope,item,context);
}

static void typeConstruct(Typer *typer, SourceScope *parent, RangeNode *declaration)
{
    RangeNode *context = selfSpecialization(typer,declaration);
    SourceScope scope = {.owner=declaration,.parent=parent};
    for (size_t i = 0; i < declaration->itemCount; ++i) {
        RangeNode *item = declaration->items[i];
        if (rangeNodeDeclaresValue(item->kind)) typeMember(typer,&scope,item,context);
        else if (item->kind == RangeNodeFunction && !genericTemplate(item)) typeFunction(typer,&scope,item,context);
        else if (item->kind == RangeNodeConstruct) typeConstruct(typer,&scope,item);
        else if (item->kind == RangeNodeEnum) typeEnum(typer,&scope,item);
    }
    checkMemberDefaults(typer,declaration);
    checkIteration(typer,declaration);
    checkInsertion(typer,declaration);
    checkOverloads(typer,declaration);
}

static int builtinMember(const RangeNode *member)
{
    if (!rangeNodeDeclaresValue(member->kind) || !member->c) return 0;
    for (size_t i = 0; i < member->c->itemCount; ++i)
        if (same(member->c->items[i]->name,"builtin")) return 1;
    return 0;
}

/* ---- layout --------------------------------------------------------------
 * A construct with a builtin `storage` member is a scalar exactly that many
 * bits wide; its other members are its meaning, not separate storage. Any
 * other construct lays its members out in order with natural alignment. A
 * @many member is an 8-byte address. C reads widths from the specialization
 * it materialized; it never names a construct or a generic. */

static RangeNode *builtinValue(RangeNode *specialization, RangeNode *member)
{
    RangeNode *value = rangeNodeRHS(member);
    if (value && value->kind == RangeNodeName && specialization->generics)
        for (size_t i = 0; i < specialization->generics->itemCount; ++i)
            if (same(specialization->generics->items[i]->name,value->name)) return rangeNodeRHS(specialization->generics->items[i]);
    return value;
}

static long long storageBits(Typer *typer, RangeNode *specialization, RangeNode *storage)
{
    RangeNode *value = rangeNodeRHS(storage);
    if (value && value->kind == RangeNodeName && specialization->generics)
        for (size_t i = 0; i < specialization->generics->itemCount; ++i)
            if (same(specialization->generics->items[i]->name,value->name)) { value = rangeNodeRHS(specialization->generics->items[i]); break; }
    if (!value || value->kind != RangeNodeInteger) {
        sourceDiagnostic(typer->report,storage,0,"layout","builtin 'storage' requires an integer bit width");
        return 0;
    }
    return value->integer;
}

/* Grammar constructs describe C's graph nodes: C provides their values at
 * compile time, and they have no runtime layout. */
static int graphConstruct(Typer *typer, const RangeNode *declaration)
{
    RangeNode *shapes = typer->report->arena->graphTypes;
    for (size_t i = 0; shapes && i < shapes->itemCount; ++i)
        if (shapes->items[i]->resolvedDeclaration == declaration) return 1;
    return 0;
}

static int layoutOf(Typer *, RangeNode *, RangeNode *);

/* A member's type in a specialization of a construct. */
static RangeNode *memberTypeIn(Typer *typer, RangeNode *type, size_t index)
{
    RangeNode *declaration = type->resolvedDeclaration, *member = declaration->items[index];
    if (type->layout == 2 && type->memberTypes) return type->memberTypes[index];
    if (!parametric(declaration)) return member->type;
    SourceScope scope = {.owner=declaration};
    return declaredType(typer,&scope,member,type);
}

/* Whether a value of `type` holds a value of `target` in its own bytes,
 * through construct members and enum payloads stored inline. */
typedef struct { RangeNode *seen[64]; size_t count; } Containment;

static int containsInline(Typer *typer, RangeNode *type, RangeNode *target, Containment *visit)
{
    if (type == target) return 1;
    if (!type || type->kind != RangeNodeSpecialization || type->scalarBits) return 0;
    RangeNode *declaration = type->resolvedDeclaration;
    if (graphConstruct(typer,declaration)) return 0;
    for (size_t i = 0; i < visit->count; ++i) if (visit->seen[i] == type) return 0;
    if (visit->count == sizeof(visit->seen)/sizeof(*visit->seen)) return 1; /* too deep to tell: store it out of line */
    visit->seen[visit->count++] = type;
    size_t field = 0;
    for (size_t i = 0; i < declaration->itemCount; ++i) {
        RangeNode *item = declaration->items[i];
        if (declaration->kind == RangeNodeEnum) {
            if (item->kind != RangeNodeEnumCase) continue;
            for (size_t j = 0; j < item->itemCount; ++j, ++field) {
                if (type->layout == 2 && type->memberBoxed && type->memberBoxed[field]) continue;
                RangeNode *fieldType = type->layout == 2 && type->memberTypes ? type->memberTypes[field]
                    : caseFieldType(typer,type,item->items[j]);
                if (containsInline(typer,fieldType,target,visit)) return 1;
            }
        } else if (rangeNodeDeclaresValue(item->kind) && !builtinMember(item) && !(item->flags & RangeFlagMany)
                   && containsInline(typer,memberTypeIn(typer,type,i),target,visit)) return 1;
    }
    return 0;
}

/* A union: a tag, then the largest case's payload inline. A field whose type
 * contains the union itself, directly or through constructs and other enums,
 * is stored out of line in a reference-counted block like @many storage, with
 * one slot. A union without payloads is a scalar: just its tag. */
static int layoutVariant(Typer *typer, RangeNode *specialization, RangeNode *at)
{
    RangeNode *declaration = specialization->resolvedDeclaration;
    size_t cases = 0, fields = 0;
    for (size_t i = 0; i < declaration->itemCount; ++i)
        if (declaration->items[i]->kind == RangeNodeEnumCase) { ++cases; fields += declaration->items[i]->itemCount; }
    size_t tag = cases <= 256 ? 1 : cases <= 65536 ? 2 : 4;
    specialization->variantTag = (int)tag;
    if (!fields) {
        int bits = 1;
        while (bits < 32 && ((size_t)1 << bits) < cases) ++bits;
        specialization->scalarBits = bits;
        specialization->scalarSigned = 0;
        specialization->size = specialization->alignment = tag;
        specialization->layout = 2;
        return 1;
    }
    RangeArena *arena = typer->report->arena;
    specialization->memberOffsets = rangeArenaAllocate(arena,fields * sizeof(size_t));
    specialization->memberTypes = rangeArenaAllocate(arena,fields * sizeof(RangeNode *));
    specialization->memberBoxed = rangeArenaAllocate(arena,fields);
    size_t *sizes = rangeArenaAllocate(arena,fields * sizeof(size_t)), payloadAlignment = 1;
    int known = 1;
    for (size_t i = 0, k = 0; i < declaration->itemCount; ++i) {
        RangeNode *entry = declaration->items[i];
        if (entry->kind != RangeNodeEnumCase) continue;
        for (size_t j = 0; j < entry->itemCount; ++j, ++k) {
            RangeNode *type = caseFieldType(typer,specialization,entry->items[j]);
            specialization->memberTypes[k] = type;
            specialization->memberOffsets[k] = SIZE_MAX;
            Containment visit = {.count=0};
            specialization->memberBoxed[k] = type && type->kind == RangeNodeSpecialization
                && containsInline(typer,type,specialization,&visit);
            size_t alignment;
            if (specialization->memberBoxed[k]) { sizes[k] = 8; alignment = 8; }
            else if (!type || type->kind != RangeNodeSpecialization || !layoutOf(typer,type,entry->items[j])) {
                known = 0;
                specialization->integer = 1; /* the cause lies in a field's type, reported there */
                continue;
            } else { sizes[k] = type->size; alignment = type->alignment; }
            if (alignment > payloadAlignment) payloadAlignment = alignment;
        }
    }
    if (!known) { specialization->layout = 2; specialization->size = specialization->alignment = 0; return 0; }
    size_t start = (tag + payloadAlignment - 1) / payloadAlignment * payloadAlignment, end = start;
    for (size_t i = 0, k = 0; i < declaration->itemCount; ++i) {
        RangeNode *entry = declaration->items[i];
        if (entry->kind != RangeNodeEnumCase) continue;
        size_t offset = start;
        for (size_t j = 0; j < entry->itemCount; ++j, ++k) {
            size_t alignment = specialization->memberBoxed[k] ? 8 : specialization->memberTypes[k]->alignment;
            offset = (offset + alignment - 1) / alignment * alignment;
            specialization->memberOffsets[k] = offset;
            offset += sizes[k];
        }
        if (offset > end) end = offset;
    }
    size_t alignment = payloadAlignment > tag ? payloadAlignment : tag;
    specialization->alignment = alignment;
    specialization->size = (end + alignment - 1) / alignment * alignment;
    specialization->layout = 2;
    (void)at;
    return 1;
}

static int layoutOf(Typer *typer, RangeNode *specialization, RangeNode *at)
{
    if (!specialization || specialization->kind != RangeNodeSpecialization) return 0;
    if (specialization->layout == 2) return specialization->size || specialization->alignment;
    RangeNode *declaration = specialization->resolvedDeclaration;
    char name[160];
    if (specialization->layout == 1) {
        describeType(name,sizeof(name),specialization);
        sourceDiagnostic(typer->report,at,0,"layout","%s has no layout: it contains itself",name);
        return 0;
    }
    // A grammar kind's values and a macro type's are declarations, which
    // exist only up to macro time.
    if (graphConstruct(typer,declaration) || declaration->kind == RangeNodeMacro) {
        specialization->layout = 2;
        specialization->integer = 1; /* graph value: runtime uses report it */
        return 0;
    }
    specialization->layout = 1;
    if (declaration->kind == RangeNodeEnum) return layoutVariant(typer,specialization,at);
    size_t size = 0, alignment = 1;
    int known = 1;
    RangeNode *storage = NULL, *sign = NULL, *bytes = NULL;
    for (size_t i = 0; i < declaration->itemCount; ++i) {
        if (builtinMember(declaration->items[i]) && same(declaration->items[i]->name,"storage")) storage = declaration->items[i];
        if (builtinMember(declaration->items[i]) && same(declaration->items[i]->name,"signed")) sign = declaration->items[i];
        if (builtinMember(declaration->items[i]) && same(declaration->items[i]->name,"bytes")) bytes = declaration->items[i];
    }
    if (bytes) {
        // UTF-8 bytes held by C: an address, a byte count, and the block that
        // owns them, or zero for a literal's bytes in the executable. Its
        // other members are its meaning, not separate storage.
        size = 24;
        alignment = 8;
    } else if (storage) {
        long long bits = storageBits(typer,specialization,storage);
        RangeNode *signedness = sign ? builtinValue(specialization,sign) : NULL;
        if (sign && (!signedness || signedness->kind != RangeNodeBool))
            sourceDiagnostic(typer->report,sign,0,"layout","builtin 'signed' requires a boolean");
        specialization->scalarBits = bits > 0 && bits <= 64 ? (int)bits : 0;
        specialization->scalarSigned = signedness && signedness->kind == RangeNodeBool && signedness->integer;
        if (bits <= 0 || bits > 64) {
            if (bits > 64) sourceDiagnostic(typer->report,storage,0,"layout","scalars wider than 64 bits are not implemented");
            known = 0;
        } else {
            size = (size_t)((bits + 7) / 8);
            alignment = size <= 1 ? 1 : size <= 2 ? 2 : size <= 4 ? 4 : 8;
            size = alignment; /* a scalar occupies its aligned width */
        }
    } else {
        // Member types computed for the declaration hold for every
        // specialization unless a type parameter is involved.
        int parametric = 0;
        if (declaration->generics) for (size_t i = 0; i < declaration->generics->itemCount; ++i)
            if (declaration->generics->items[i]->kind == RangeNodeTypeParameter) parametric = 1;
        SourceScope scope = {.owner=declaration};
        RangeArena *arena = typer->report->arena;
        size_t items = declaration->itemCount ? declaration->itemCount : 1;
        specialization->memberOffsets = rangeArenaAllocate(arena,items * sizeof(size_t));
        specialization->memberTypes = rangeArenaAllocate(arena,items * sizeof(RangeNode *));
        for (size_t i = 0; i < declaration->itemCount; ++i) {
            specialization->memberOffsets[i] = SIZE_MAX;
            specialization->memberTypes[i] = NULL;
        }
        for (size_t i = 0; i < declaration->itemCount; ++i) {
            RangeNode *member = declaration->items[i];
            if (!rangeNodeDeclaresValue(member->kind) || builtinMember(member)) continue;
            size_t memberSize, memberAlignment;
            RangeNode *type = NULL;
            if (member->flags & RangeFlagMany) { memberSize = 8; memberAlignment = 8; }
            else {
                type = parametric ? declaredType(typer,&scope,member,specialization) : member->type;
                if (!type || type->kind != RangeNodeSpecialization || !layoutOf(typer,type,member)) {
                    known = 0;
                    specialization->integer = 1; /* the cause lies in a member's type, reported there */
                    continue;
                }
                memberSize = type->size; memberAlignment = type->alignment;
            }
            size = (size + memberAlignment - 1) / memberAlignment * memberAlignment;
            specialization->memberOffsets[i] = size;
            specialization->memberTypes[i] = type;
            size += memberSize;
            if (memberAlignment > alignment) alignment = memberAlignment;
        }
        size = (size + alignment - 1) / alignment * alignment;
    }
    specialization->layout = 2;
    if (!known) { specialization->size = 0; specialization->alignment = 0; return 0; }
    specialization->size = size;
    specialization->alignment = alignment;
    return 1;
}

/* ---- mutation -------------------------------------------------------------
 * A method changes its receiver when it assigns one of its construct's members,
 * calls a sibling that does, or calls the slot builtins resize and write. Such a
 * method may only be called on a state value: `state` is what permits change. */

static RangeNode *ownerOf(Typer *typer, const RangeNode *function)
{
    if (!function->typeName) return NULL;
    RangeNode *owner = sourceLookup(typer->report,NULL,function->typeName,2);
    return owner && owner->kind == RangeNodeConstruct ? owner : NULL;
}

static int memberOf(const RangeNode *owner, const RangeNode *node)
{
    for (size_t i = 0; owner && node && i < owner->itemCount; ++i) if (owner->items[i] == node) return 1;
    return 0;
}

static int mutates(Typer *, RangeNode *);

static int mutatesIn(Typer *typer, RangeNode *owner, RangeNode *node)
{
    if (!node) return 0;
    if (node->kind == RangeNodeFunction || node->kind == RangeNodeConstruct) return 0;
    if (node->kind == RangeNodeAssign) {
        RangeNode *root = node->a;
        while (root && root->kind == RangeNodeMemberAccess) root = root->a;
        if (root && root->kind == RangeNodeName && memberOf(owner,root->resolvedDeclaration)) return 1;
    }
    if (node->kind == RangeNodeCall && node->a && node->a->kind == RangeNodeName) {
        RangeNode *callee = node->a->resolvedDeclaration;
        if (callee && callee->kind == RangeNodeFunction && memberOf(owner,callee) && mutates(typer,callee)) return 1;
    }
    if (mutatesIn(typer,owner,node->a) || mutatesIn(typer,owner,node->b) || mutatesIn(typer,owner,node->c)
        || mutatesIn(typer,owner,node->lowered)) return 1;
    for (size_t i = 0; i < node->itemCount; ++i) if (mutatesIn(typer,owner,node->items[i])) return 1;
    return 0;
}

static int mutates(Typer *typer, RangeNode *function)
{
    if (function->flags & RangeFlagMutationKnown) return (function->flags & RangeFlagMutating) != 0;
    function->flags |= RangeFlagMutationKnown; /* recursion assumes no change until shown */
    int result = (function->flags & RangeFlagBuiltin) ? same(function->name,"resize") || same(function->name,"write")
        : mutatesIn(typer,ownerOf(typer,function),function->a);
    if (result) function->flags |= RangeFlagMutating;
    return result;
}

static void checkMutations(Typer *typer, RangeNode *node)
{
    if (!node) return;
    if (node->kind == RangeNodeCall && node->a && node->a->kind == RangeNodeMemberAccess) {
        RangeNode *function = node->a->resolvedDeclaration;
        if (function && function->kind == RangeNodeFunction && mutates(typer,function)) {
            RangeNode *root = node->a->a;
            while (root && root->kind == RangeNodeMemberAccess) root = root->a;
            RangeNode *declaration = root && root->kind == RangeNodeName ? root->resolvedDeclaration : NULL;
            if (!declaration || declaration->kind != RangeNodeState)
                typeError(typer,node,"'%s' changes its receiver, which must be declared with state",function->name);
        }
    }
    checkMutations(typer,node->a); checkMutations(typer,node->b); checkMutations(typer,node->c);
    checkMutations(typer,node->lowered);
    for (size_t i = 0; i < node->itemCount; ++i) checkMutations(typer,node->items[i]);
}

/* The function `=` calls on values of a type: the `=` with a body the type
 * declares, written or emitted. Without one, `=` is C's built-in structural
 * comparison. */
static RangeNode *equalityFunction(const RangeNode *type)
{
    RangeNode *function = type && type->kind == RangeNodeSpecialization ? operatorFunction(type->resolvedDeclaration,"=",1) : NULL;
    return function && !(function->flags & RangeFlagBuiltin) ? function : NULL;
}

/* Whether `=` can compare values of `type`. A type with an equality function
 * calls it; any other type is compared structurally, which needs every
 * stored member, or every payload field, to be comparable in turn. A type
 * already being compared counts as comparable, so recursive enums are. On
 * failure, `why` says which field stops it. */
static int comparable(Typer *typer, RangeNode *type, Comparing *visit, char *why, size_t size)
{
    char name[160]; describeType(name,sizeof(name),type);
    if (!type || type->kind != RangeNodeSpecialization) { snprintf(why,size,"%s is not a value type",name); return 0; }
    RangeNode *declaration = type->resolvedDeclaration;
    if (equalityFunction(type)) return 1;
    for (size_t i = 0; i < visit->count; ++i) if (visit->seen[i] == type) return 1;
    if (visit->count == sizeof(visit->seen)/sizeof(*visit->seen)) { snprintf(why,size,"%s nests too deeply to compare",name); return 0; }
    visit->seen[visit->count++] = type;
    if (!layoutOf(typer,type,declaration)) { snprintf(why,size,"%s has no runtime layout",name); return 0; }
    if (type->scalarBits || bytesType(type)) return 1;
    char inner[512];
    if (type->variantTag) {
        for (size_t i = 0, k = 0; i < declaration->itemCount; ++i) {
            RangeNode *entry = declaration->items[i];
            if (entry->kind != RangeNodeEnumCase) continue;
            for (size_t j = 0; j < entry->itemCount; ++j, ++k) {
                if (comparable(typer,type->memberTypes[k],visit,inner,sizeof(inner))) continue;
                char field[160]; describeType(field,sizeof(field),type->memberTypes[k]);
                snprintf(why,size,"payload field '%s' of case '%s' is %s%s%s",entry->items[j]->name,entry->name,field,
                         type->memberTypes[k] && type->memberTypes[k]->kind == RangeNodeSpecialization ? ", and " : "",
                         type->memberTypes[k] && type->memberTypes[k]->kind == RangeNodeSpecialization ? inner : "");
                return 0;
            }
        }
        return 1;
    }
    for (size_t i = 0; i < declaration->itemCount; ++i) {
        if (!type->memberOffsets || type->memberOffsets[i] == SIZE_MAX) continue;
        RangeNode *member = declaration->items[i];
        if (member->flags & RangeFlagMany) {
            snprintf(why,size,"field '%s' of %s is @many storage, which the structural '=' does not compare",member->name,name);
            return 0;
        }
        if (comparable(typer,type->memberTypes[i],visit,inner,sizeof(inner))) continue;
        char field[160]; describeType(field,sizeof(field),type->memberTypes[i]);
        snprintf(why,size,"field '%s' is %s, and %s",member->name,field,inner);
        return 0;
    }
    return 1;
}

static void checkEqualities(Typer *typer)
{
    for (size_t i = 0; i < typer->equalityCount; ++i) {
        RangeNode *type = typer->equalities[i].type;
        Comparing visit = {.count=0};
        char why[512], name[160];
        if (comparable(typer,type,&visit,why,sizeof(why))) {
            if (!equalityFunction(type))
                sourceDiagnostic(typer->report,typer->equalities[i].at,1,"C-implementation","'=' here is C's built-in structural comparison: "
                    "every stored member, or the case then its payload fields; it is emitted only for the types a program compares");
            continue;
        }
        describeType(name,sizeof(name),type);
        typer->instance = typer->equalities[i].in;
        typeError(typer,typer->equalities[i].at,"'=' cannot compare %s: %s",name,why);
        typer->instance = NULL;
    }
}

/* The integer and boolean literal rules select the default integer and the
 * condition type; C names neither. */
static RangeNode *literalFamily(Typer *typer, const char *spelling)
{
    for (size_t u = 0; u < typer->report->count; ++u) for (size_t i = 0; i < typer->report->units[u]->itemCount; ++i) {
        RangeNode *macro = typer->report->units[u]->items[i];
        if (macro->kind != RangeNodeMacro || !macro->literalPattern || !macro->literalDefault) continue;
        if (literalMatch(typer->vm,macro,macro->literalPattern,spelling)) return macro->literalDefault;
    }
    return NULL;
}

/* ---- written code ----
 * Written code is read once and never changed: what the compiler finds lives
 * beside it. Each leaf declaration, a function, a macro, the entry block, a
 * member, an enum case, or a construct's generics, is kept with the hash of
 * what was written when it is read: parsed units before any macro runs, and
 * what a #graph block or an extension adds as it joins. The #graph door adds
 * declarations to units and constructs, never inside a leaf. */
static void noteWritten(Typer *typer, RangeNode *node)
{
    if (!node || node->kind == RangeNodeExtension) return; /* its members are kept where they land */
    if (node->kind == RangeNodeUnit || node->kind == RangeNodeConstruct || node->kind == RangeNodeEnum) {
        noteWritten(typer,node->generics);
        for (size_t i = 0; i < node->itemCount; ++i) noteWritten(typer,node->items[i]);
        return;
    }
    if (typer->writtenCount == typer->writtenCapacity) {
        typer->writtenCapacity = typer->writtenCapacity ? typer->writtenCapacity * 2 : 256;
        void *grown = rangeArenaAllocate(typer->report->arena,typer->writtenCapacity * sizeof(*typer->written));
        if (typer->writtenCount) memcpy(grown,typer->written,typer->writtenCount * sizeof(*typer->written));
        typer->written = grown;
    }
    typer->written[typer->writtenCount].node = node;
    typer->written[typer->writtenCount++].hash = rangeWrittenHash(node);
}

/* The first leaf declaration, in `path` or anywhere, whose written code
 * changed after it was read; NULL when none did. */
static RangeNode *writtenChanged(Typer *typer, const char *path)
{
    for (size_t i = 0; i < typer->writtenCount; ++i) {
        RangeNode *node = typer->written[i].node;
        if ((!path || same(node->path,path)) && rangeWrittenHash(node) != typer->written[i].hash) return node;
    }
    return NULL;
}

/* A change to written code is C's mistake, reported where it was written. */
static void diagnoseWritten(Typer *typer)
{
    RangeNode *changed = writtenChanged(typer,NULL);
    if (changed) sourceDiagnostic(typer->report,changed,0,"internal","C changed %s%s%s%s after reading it",
        rangeNodeKindName(changed->kind),changed->name ? " '" : "",changed->name ? changed->name : "",changed->name ? "'" : "");
}

static Typer *newTyper(SourceReport *report, Resolver *vm)
{
    Typer *typer = rangeArenaAllocate(report->arena,sizeof(*typer));
    *typer = (Typer){.report=report,.vm=vm};
    typer->specializations = rangeNodeCreate(report->arena,RangeNodeBlock,"<compiler>",1,1);
    typer->functionTypes = rangeNodeCreate(report->arena,RangeNodeBlock,"<compiler>",1,1);
    typer->deferred = rangeNodeCreate(report->arena,RangeNodeType,"<compiler>",1,1);
    typer->deferred->name = "a value known at macro time";
    return typer;
}

/* What the language's declarations give the typer before any macro runs:
 * the integer default and the condition type. */
static void typerLanguage(Typer *typer)
{
    SourceReport *report = typer->report;
    typer->integer = literalFamily(typer,"0");
    typer->boolean = literalFamily(typer,"true");
    if (typer->boolean) typer->booleanType = specialize(typer,NULL,typer->boolean,NULL,NULL,typer->boolean);
    if (typer->boolean && typer->boolean->kind == RangeNodeEnum) {
        // Conditions branch on zero, and comparisons produce 0 or 1: the
        // condition enum's false case is tag 0 and its true case tag 1.
        RangeNode *no = enumCase(typer->boolean,"false"), *yes = enumCase(typer->boolean,"true");
        if (!no || !yes || no->integer != 0 || yes->integer != 1 || enumPayloads(typer->boolean))
            sourceDiagnostic(report,typer->boolean,0,"layout","%s is the condition type, so it needs case false, then case true, without payloads",
                typer->boolean->name);
    }
}

/* ---- typing on demand ----
 * Macro time runs code before typing in order reaches it: a function is
 * typed when it is first called, a construct's members when it is first
 * constructed, a member when `.value` reads its initializer, and a macro's
 * body when it is first applied. Each is typed once, from the top level, in
 * the scopes it is declared in. Typing sees the program as it stands then:
 * code typed before a later round emits what it names reports it missing,
 * and keeps that report. */

/* The scopes a declaration sees around it, innermost first: the constructs
 * and enums enclosing it, then its unit; NULL when no unit holds it. */
static SourceScope *enclosingScope(Typer *typer, RangeNode *declaration, SourceScope scopes[33])
{
    RangeNode *chain[32];
    for (size_t u = 0; u < typer->report->count; ++u) {
        size_t count = 0;
        if (!enclosing(typer->report->units[u],declaration,chain,&count,32)) continue;
        scopes[count] = (SourceScope){.owner=typer->report->units[u]};
        for (size_t i = count; i-- > 0;) scopes[i] = (SourceScope){.owner=chain[i],.parent=&scopes[i + 1]};
        return &scopes[0];
    }
    return NULL;
}

/* A function the evaluator calls, typed in its owner's own specialization
 * as typing in order types it. Returns whether it may run. */
static int typeOnDemand(Typer *typer, RangeNode *function)
{
    if (!(function->flags & RangeFlagTyped)) {
        SourceScope scopes[33];
        size_t errors = typer->report->errors;
        TyperContext outer = typerTop(typer);
        typeFunction(typer,enclosingScope(typer,function,scopes),function,function->owner ? selfSpecialization(typer,function->owner) : NULL);
        typerRestore(typer,outer);
        if (typer->report->errors != errors) function->flags |= RangeFlagInvalid;
    }
    return !(function->flags & RangeFlagInvalid);
}

/* A construct's members, before it is first constructed. */
static void typeMembersOnDemand(Typer *typer, RangeNode *declaration)
{
    int pending = 0;
    for (size_t i = 0; i < declaration->itemCount; ++i)
        pending |= rangeNodeDeclaresValue(declaration->items[i]->kind) && !(declaration->items[i]->flags & RangeFlagTyped);
    if (!pending) return;
    SourceScope scopes[33], scope = {.owner=declaration,.parent=enclosingScope(typer,declaration,scopes)};
    TyperContext outer = typerTop(typer);
    RangeNode *context = selfSpecialization(typer,declaration);
    for (size_t i = 0; i < declaration->itemCount; ++i)
        if (rangeNodeDeclaresValue(declaration->items[i]->kind)) typeMember(typer,&scope,declaration->items[i],context);
    typerRestore(typer,outer);
}

/* A construct's member whose initializer `.value` reads. */
static void typeValueOnDemand(Typer *typer, RangeNode *member)
{
    SourceScope scopes[33], *scope = member->flags & RangeFlagTyped ? NULL : enclosingScope(typer,member,scopes);
    if (!scope || scope->owner->kind != RangeNodeConstruct) return; /* only a construct's members are typed on their own */
    TyperContext outer = typerTop(typer);
    typeMember(typer,scope,member,selfSpecialization(typer,scope->owner));
    typerRestore(typer,outer);
}

/* A macro's body, before its first application runs it. Returns whether it may run. */
static int typeMacroOnDemand(Typer *typer, RangeMacroApplication *app)
{
    RangeNode *macro = app->declaration;
    if (!(macro->flags & RangeFlagTyped)) {
        SourceScope unit = {.owner=app->unit};
        TyperContext outer = typerTop(typer);
        typeMacro(typer,&unit,macro,1);
        typerRestore(typer,outer);
    }
    return !(macro->flags & RangeFlagInvalid);
}

/* Type the program, after macro time: what macros left untyped, and the
 * checks that need every declaration. The typer is kept for code
 * generation: generic methods are lowered per concrete specialization, which
 * substitutes and lays out new types. */
static void typeCheck(Typer *typer)
{
    SourceReport *report = typer->report;
    Resolver *vm = typer->vm;
    if (setjmp(vm->failure) != 0) { sourceDiagnostic(report,NULL,0,"type","%s",vm->error); return; }
    // The entry block returns the default integer: the process exit status.
    RangeNode *status = typer->integer ? specialize(typer,NULL,typer->integer,NULL,NULL,typer->integer) : NULL;
    for (size_t u = 0; u < report->count; ++u) {
        SourceScope unit = {.owner=report->units[u]};
        for (size_t i = 0; i < report->units[u]->itemCount; ++i) {
            RangeNode *item = report->units[u]->items[i];
            if (item->kind == RangeNodeConstruct) typeConstruct(typer,&unit,item);
            else if (item->kind == RangeNodeEnum) typeEnum(typer,&unit,item);
            else if (item->kind == RangeNodeMacro) typeMacro(typer,&unit,item,0); /* never applied */
            else if (item->kind == RangeNodeFunction && genericTemplate(item)) continue; /* typed per instance */
            else if (item->kind == RangeNodeFunction) {
                typeFunction(typer,&unit,item,NULL);
                if (appliesBuiltin(item,"iteration"))
                    typeError(typer,item,"@iteration function '%s' must be a method of the type it iterates",item->name);
                if (appliesBuiltin(item,"insertion"))
                    typeError(typer,item,"@insertion function '%s' must be a method of the type it adds to",item->name);
                if (same(item->name,"="))
                    typeError(typer,item,"'=' must be declared on the type it compares, in the type or an extension of it");
                else if (operatorName(item->name))
                    typeError(typer,item,"'%s' must be declared on the type of its left operand, in the type or an extension of it",item->name);
            }
            else if (item->kind == RangeNodeMain && !(item->flags & RangeFlagTyped)) {
                item->flags |= RangeFlagTyped;
                item->type = status;
                typer->output = status;
                typeBlock(typer,&unit,item->a,NULL,status);
                typer->output = NULL;
            }
        }
    }
    drainLaws(typer); /* the specializations and literals typing met */
    for (size_t u = 0; u < report->count; ++u) checkOverloads(typer,report->units[u]);
    for (size_t u = 0; u < report->count; ++u) checkMutations(typer,report->units[u]);
    for (size_t i = 0; i < typer->instanceCount; ++i) checkMutations(typer,typer->instances[i].instance);
    checkEqualities(typer);
    // Every type the program mentions gets a layout, or a reason it has none.
    for (size_t i = 0; i < typer->specializations->itemCount; ++i) {
        RangeNode *specialization = typer->specializations->items[i];
        if (specialization->layout == 2 || layoutOf(typer,specialization,specialization->resolvedDeclaration)
            || specialization->integer) continue;
        char name[160]; describeType(name,sizeof(name),specialization);
        sourceDiagnostic(report,specialization->resolvedDeclaration,0,"layout","%s has no layout",name);
    }
    drainLaws(typer); /* the specializations comparing and layout met */
}

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
 * with none when typing reported the problem already. */

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
 * each name to: its parameters, locals, and bindings. A closure's frame
 * continues in the one it was written in, which is alive while it runs: a
 * closure runs only while the call it is passed to runs. */
typedef struct EvalBinding { RangeNode *declaration; RangeValue value; struct EvalBinding *next; } EvalBinding;
typedef struct EvalFrame {
    struct EvalFrame *parent;
    EvalBinding *bindings;
    RangeValue *self;    /* the receiver of the running method, changed in place */
    RangeNode *function; /* the running function: its receiver and its value generics */
    RangeNode *output;   /* what its `return` gives */
} EvalFrame;

/* How evaluation goes on: normally, or leaving through return (the value in
 * returned), break, continue, or a failure (the message at, or none). */
enum { EvalNormal, EvalReturn, EvalBreak, EvalContinue, EvalFailed };

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
} Eval;

static size_t nativeMemberIndex(RangeNode *, RangeNode *);
static int evalExpression(Eval *, EvalFrame *, RangeNode *, RangeValue *);
static int evalStatement(Eval *, EvalFrame *, RangeNode *);
static int evalInvoke(Eval *, RangeNode *, RangeValue *, RangeValue *, RangeNode *, RangeValue *);
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

static int evalStep(Eval *eval, RangeNode *at)
{
    return ++eval->steps > 100000 ? evalFail(eval,at,"compile-time evaluation step limit exceeded") : EvalNormal;
}

static RangeValue *evalNamed(EvalFrame *frame, const RangeNode *declaration)
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

static int evalTruth(RangeValue value)
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
static int evalWrite(Eval *eval, RangeValue value, RangeNode *at, const char **text, size_t *length)
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

static void typeMembersOnDemand(Typer *, RangeNode *);
static void typeValueOnDemand(Typer *, RangeNode *);

/* A declaration's members and functions include what its written macros
 * emit, so a use of it at macro time first applies those that have not run:
 * `#cases.first()` needs the functions @collection gives Array. A failure
 * there fails the application that needed it. */
static void evalPrepare(Eval *eval, RangeNode *declaration)
{
    Resolver *vm = eval->vm;
    for (size_t i = 0; declaration->c && i < declaration->c->itemCount; ++i) {
        RangeNode *attribute = declaration->c->items[i];
        RangeMacroApplication *app = attribute->macroApplication;
        if (compilerAttribute(declaration,attribute) || !app || app->applied) continue;
        app->applied = 1;
        RangeNode *emitted = vm->emitted, *unit = vm->unit;
        int skip = vm->skipEmission;
        vm->unit = app->unit ? app->unit : unit;
        for (size_t u = 0; u < vm->count; ++u)
            for (size_t j = 0; j < vm->units[u]->itemCount; ++j)
                if (vm->units[u]->items[j] == declaration) vm->unit = vm->units[u];
        vm->skipEmission = 0;
        mergeEmitted(vm,runMacroApplication(vm,attribute));
        vm->emitted = emitted; vm->unit = unit; vm->skipEmission = skip;
    }
}

/* `.value` of a member kind: its initializer, known at macro time. A literal
 * is a value of no type yet, which takes its use's type; anything else is
 * typed where it is declared and run without a receiver, so a read of
 * another member is not known. */
static int evalInitializer(Eval *eval, RangeNode *declaration, RangeNode *at, RangeValue *out)
{
    RangeGraphValue raw = rangeGraphStoredField(eval->vm->arena,declaration,"value");
    RangeNode *rhs = raw.kind == RangeGraphNode ? raw.node : NULL;
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
        status = evalInvoke(eval,append,out,&element,at,&ignored);
    }
    return status;
}

/* `#field` of the target, or `.field` of a declaration: what C's adapter
 * holds there, as the value its grammar member's type says. An element of
 * `#macros`, an application, reads as the Macro it applies: its name. */
static int evalField(Eval *eval, RangeNode *owner, const char *name, RangeNode *at, RangeValue *out)
{
    RangeArena *arena = eval->vm->arena;
    RangeNode *shape = owner->graphType ? owner->graphType : owner->kind == RangeNodeAttribute ? rangeGraphType(arena,"Macro") : NULL;
    if (!rangeGraphField(shape,name) || (!owner->graphType && !same(name,"name")))
        return evalFail(eval,at,"field '%s' is not declared by @type %s",name,shape ? shape->name : rangeNodeKindName(owner->kind));
    if (same(name,"value") && rangeNodeDeclaresValue(owner->kind)) return evalInitializer(eval,owner,at,out);
    RangeGraphValue raw = rangeGraphStoredField(arena,owner,name);
    RangeNode *grammar = owner->graphType ? grammarDeclaration(eval->vm,owner) : shape->resolvedDeclaration;
    RangeNode *member = grammar ? findMember(grammar,name) : NULL;
    if (!member && raw.kind == RangeGraphNodes)
        return evalFail(eval,at,"reflection field '%s' has no Range type: %s declares no member '%s' in the loaded grammar",
                        name,grammar ? grammar->name : shape->name,name);
    RangeNode *type = member ? memberType(eval->typer,grammar,member,selfSpecialization(eval->typer,grammar)) : NULL;
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
    if (attribute->itemCount != 1) return evalStop(eval);
    const char *text; size_t length;
    int status = evalText(eval,frame,attribute->items[0]->a,&text,&length);
    if (status) return status;
    if (warning) {
        RangeNode *at = eval->application && eval->application->attribute ? eval->application->attribute : attribute;
        if (eval->vm->report && !eval->vm->skipEmission) sourceDiagnostic(eval->vm->report,at,1,"macro","%.*s",(int)length,text);
        return EvalNormal;
    }
    if (!print) return evalFail(eval,attribute,"%.*s",(int)length,text);
    printf("%.*s\n",(int)length,text);
    return EvalNormal;
}

/* A spliced value becomes the source a person would have written there: a
 * declaration or a name, a reference; a literal or a scalar, a literal. A
 * target field spliced alone is the node or the name C holds there. */
static int evalSplice(Eval *eval, EvalFrame *frame, RangeNode *at, RangeNode **out)
{
    RangeArena *arena = eval->vm->arena;
    RangeValue value;
    if (at->kind == RangeNodeEnvironment && !at->resolvedDeclaration && !at->narrowed) {
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

/* A C primitive a function declares with @builtin, on its receiver: one
 * byte of the bytes primitive, or the slot primitives on the receiver's one
 * @many member. */
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
        RangeValue *values = evalValues(eval,(size_t)index);
        memcpy(values,slots->values,((size_t)index < slots->count ? (size_t)index : slots->count) * sizeof(*values));
        *slots = (RangeValue){.kind=ValueSlots,.values=values,.count=(size_t)index};
        return EvalNormal;
    }
    if (index < 0 || (size_t)index >= slots->count) return evalFail(eval,at,"slot index is outside the @many storage");
    if (same(function->name,"read")) { *out = slots->values[index]; return EvalNormal; }
    evalOwn(eval,slots);
    slots->values[index] = arguments[1];
    return EvalNormal;
}

static int typeOnDemand(Typer *, RangeNode *);

/* Run `function` with these arguments, one per parameter in order, on
 * `self` when it is a method: its body, or the C primitive it declares. */
static int evalInvoke(Eval *eval, RangeNode *function, RangeValue *self, RangeValue *arguments, RangeNode *at, RangeValue *out)
{
    *out = (RangeValue){0};
    int status;
    if (!typeOnDemand(eval->typer,function)) return evalStop(eval);
    for (size_t i = 0; i < function->itemCount; ++i)
        if ((status = evalAdopt(eval,&arguments[i],function->items[i]->type,at))) return status;
    if (function->flags & RangeFlagBuiltin) return evalBuiltin(eval,function,self,arguments,at,out);
    if (!function->a) return evalFail(eval,at,"'%s' has no body to run at macro time",function->name);
    if (++eval->depth > 64) return evalFail(eval,at,"compile-time call depth exceeded");
    EvalFrame frame = {.self=self,.function=function,.output=function->type};
    for (size_t i = 0; i < function->itemCount; ++i) evalBind(eval,&frame,function->items[i],arguments[i]);
    status = evalStatement(eval,&frame,function->a);
    --eval->depth;
    if (status == EvalReturn) { *out = eval->returned; return EvalNormal; }
    if (status) return status;
    if (function->type && !unitType(eval->typer,function->type))
        return evalFail(eval,at,"'%s' ended without returning a value",function->name);
    return EvalNormal;
}

/* `where(element)`: the closure's body with its parameters bound, in the
 * frame where it was written. It yields its one expression, or what `return`
 * gives; `return` ends the closure only. */
static int evalCallClosure(Eval *eval, RangeValue *closure, RangeValue *arguments, RangeNode *at, RangeValue *out)
{
    RangeNode *literal = closure->node;
    RangeNode *type = literal->type && literal->type->kind == RangeNodeFunctionType ? literal->type : NULL;
    if (++eval->depth > 64) return evalFail(eval,at,"compile-time call depth exceeded");
    EvalFrame frame = {.parent=closure->frame,.self=closure->frame->self,.function=closure->frame->function,
                       .output=type ? type->a : NULL};
    int status = EvalNormal;
    for (size_t i = 0; i < literal->itemCount && !status; ++i) {
        status = evalAdopt(eval,&arguments[i],literal->items[i]->type,at);
        evalBind(eval,&frame,literal->items[i],arguments[i]);
    }
    RangeNode *value = closureResult(eval->typer,literal);
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
        if (!status && type && i < entry->itemCount) status = evalAdopt(eval,&payload[i],caseFieldType(eval->typer,type,entry->items[i]),arguments[i]);
        if (status) return status;
    }
    *out = (RangeValue){.kind=ValueCase,.type=type,.node=entry,.values=payload,.count=count};
    return EvalNormal;
}

/* `Point(x: 1)`: each stored member is its argument or its default, which
 * sees the members before it; @many storage starts with no slots. A scalar's
 * or a bytes value's single input is the value itself. */
static int evalConstruct(Eval *eval, EvalFrame *frame, RangeNode *type, RangeNode **arguments, size_t count, RangeNode *at,
                         RangeValue *out)
{
    if (!type || type->kind != RangeNodeSpecialization) return evalStop(eval);
    RangeNode *declaration = type->resolvedDeclaration;
    evalPrepare(eval,declaration);
    typeMembersOnDemand(eval->typer,declaration);
    EvalFrame defaults = {0};
    int status, bits, isSigned;
    if (bytesDeclaration(declaration) || scalarShape(type,&bits,&isSigned)) {
        RangeNode *value = count ? arguments[0]->a : NULL;
        EvalFrame *in = frame;
        for (size_t i = 0; !value && i < declaration->itemCount; ++i)
            if (constructionInput(declaration->items[i])) { value = declarationValue(declaration->items[i]); in = &defaults; }
        status = evalExpression(eval,in,value,out);
        return status ? status : evalAdopt(eval,out,type,at);
    }
    RangeValue instance = {.kind=ValueInstance,.type=type,.count=declaration->itemCount};
    instance.values = evalValues(eval,instance.count);
    defaults.self = &instance;
    for (size_t i = 0; i < instance.count; ++i) {
        RangeNode *member = declaration->items[i], *value = NULL;
        if (!rangeNodeDeclaresValue(member->kind) || builtinMember(member)) continue;
        if (member->flags & RangeFlagMany) { instance.values[i] = (RangeValue){.kind=ValueSlots}; continue; }
        for (size_t j = 0; j < count; ++j) if (arguments[j]->resolvedDeclaration == member) value = arguments[j]->a;
        if (value) status = evalExpression(eval,frame,value,&instance.values[i]);
        else if ((value = declarationValue(member)) == member)
            status = evalConstruct(eval,&defaults,member->type,member->items,member->itemCount,member,&instance.values[i]);
        else if (value) status = evalExpression(eval,&defaults,value,&instance.values[i]);
        else continue; /* a required input: typing reports it missing */
        if (!status) status = evalAdopt(eval,&instance.values[i],member->type,value);
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
    if (expr->lowered || expr->narrowed) return NULL; /* it runs as something else, or reads a payload */
    if (expr->kind == RangeNodeName) {
        RangeValue *bound = evalNamed(frame,expr->resolvedDeclaration);
        if (bound) return bound;
        size_t member = evalMember(frame->self,expr->resolvedDeclaration);
        if (member == SIZE_MAX) return NULL;
        evalOwn(eval,frame->self);
        return &frame->self->values[member];
    }
    if (expr->kind != RangeNodeMemberAccess) return NULL;
    RangeValue *owner = evalPlace(eval,frame,expr->a);
    size_t member = owner ? evalMember(owner,expr->resolvedDeclaration) : SIZE_MAX;
    if (member == SIZE_MAX) return NULL;
    evalOwn(eval,owner);
    return &owner->values[member];
}

/* A call: a case with its payload, a construction, a closure a parameter
 * holds, or the function typing chose, on the receiver it is called on (in
 * place, so a method changing it changes the place) or, for a sibling, the
 * running method's. On a value known only at macro time, the function its
 * type declares with the call's name and labels. */
static int evalCall(Eval *eval, EvalFrame *frame, RangeNode *call, RangeValue *out)
{
    RangeNode *callee = call->a, *target = callee->resolvedDeclaration;
    if (target && target->kind == RangeNodeEnumCase) return evalCase(eval,frame,call->type,target,call->items,call->itemCount,out);
    if (target && (target->kind == RangeNodeConstruct || target->kind == RangeNodeEnum || target->kind == RangeNodeTypeParameter))
        return evalConstruct(eval,frame,call->type,call->items,call->itemCount,call,out);
    RangeValue receiver = {0}, *self = NULL, *arguments = evalValues(eval,call->itemCount);
    int status;
    if (callee->kind == RangeNodeMemberAccess) {
        self = evalPlace(eval,frame,callee->a);
        if (!self && (status = evalExpression(eval,frame,callee->a,&receiver))) return status;
        if (!self) self = &receiver;
    } else if (target && target->kind == RangeNodeFunction && target->typeName) self = frame->self;
    for (size_t i = 0; i < call->itemCount; ++i)
        if ((status = evalExpression(eval,frame,call->items[i]->a,&arguments[i]))) return status;
    if (target && (target->kind == RangeNodeParameter || rangeNodeDeclaresValue(target->kind))) {
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
    return evalInvoke(eval,target,self,arguments,call,out);
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
        status = evalInvoke(eval,function,&left,&right,at,&result);
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

/* A builtin operator's C primitive, by its operand's layout: scalar
 * arithmetic and comparison, trapping where native code traps, Bool's `!`,
 * and the join of two bytes values. */
static int evalPrimitive(Eval *eval, RangeNode *expr, RangeValue left, RangeValue right, RangeValue *out)
{
    const char *op = expr->name;
    char name[160]; describeType(name,sizeof(name),left.type);
    int bits, isSigned;
    if (same(op,"!") && left.kind == ValueCase) { *out = evalBool(eval,!evalTruth(left)); return EvalNormal; }
    if (same(op,"+") && left.kind == ValueText && right.kind == ValueText) {
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
        return evalAdopt(eval,out,expr->type,expr);
    }
    RangeNode *function = expr->resolvedDeclaration && expr->resolvedDeclaration->kind == RangeNodeFunction ? expr->resolvedDeclaration : NULL;
    int logic = binary && (same(op,"&") || same(op,"|")), equality = binary && (same(op,"=") || same(op,"!="));
    RangeValue left, right = {0};
    if ((status = evalExpression(eval,frame,expr->a,&left))) return status;
    if (binary && !logic && (status = evalExpression(eval,frame,expr->b,&right))) return status;
    if (equality) {
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
    if (logic && shortCircuit(function)) {
        if (evalTruth(left) == same(op,"|")) { *out = evalBool(eval,evalTruth(left)); return EvalNormal; }
        if ((status = evalExpression(eval,frame,expr->b,&right))) return status;
        *out = evalBool(eval,evalTruth(right));
        return EvalNormal;
    }
    if (logic && (status = evalExpression(eval,frame,expr->b,&right))) return status;
    if (function->flags & RangeFlagBuiltin) return evalPrimitive(eval,expr,left,right,out);
    return evalInvoke(eval,function,&left,&right,expr,out);
}

/* ---- expressions ---- */

/* A value generic: the constant of the running function's instance, or of
 * the receiver's specialization. */
static RangeNode *evalGeneric(EvalFrame *frame, RangeNode *declaration)
{
    if (declaration->kind != RangeNodeLet) return NULL;
    RangeNode *generics = frame->function && frame->function->kind == RangeNodeFunction ? frame->function->generics : NULL;
    for (size_t i = 0; generics && i < generics->itemCount; ++i) if (generics->items[i] == declaration) return declaration->a;
    RangeNode *self = frame->self && frame->self->type && frame->self->type->kind == RangeNodeSpecialization ? frame->self->type : NULL;
    RangeNode *declared = self ? self->resolvedDeclaration->generics : NULL;
    for (size_t i = 0; declared && i < declared->itemCount; ++i)
        if (declared->items[i] == declaration && self->generics && i < self->generics->itemCount) return rangeNodeRHS(self->generics->items[i]);
    return NULL;
}

/* A name: a value of the frame, the receiver, a member of it, a value
 * generic, or a construct or enum, which is the declaration. */
static int evalName(Eval *eval, EvalFrame *frame, RangeNode *expr, RangeValue *out)
{
    RangeNode *declaration = expr->resolvedDeclaration;
    RangeValue *bound = evalNamed(frame,declaration);
    if (bound) { *out = *bound; return EvalNormal; }
    if (declaration && frame->self && frame->function && declaration == frame->function->receiver) { *out = *frame->self; return EvalNormal; }
    size_t member = evalMember(frame->self,declaration);
    if (member != SIZE_MAX) { *out = frame->self->values[member]; return EvalNormal; }
    RangeNode *constant = declaration ? evalGeneric(frame,declaration) : NULL;
    if (constant) {
        EvalFrame none = {0};
        int status = evalExpression(eval,&none,constant,out);
        return status ? status : evalAdopt(eval,out,declaration->type,expr);
    }
    if (declaration && (declaration->kind == RangeNodeConstruct || declaration->kind == RangeNodeEnum)) {
        *out = (RangeValue){.kind=ValueDeclaration,.node=declaration};
        return EvalNormal;
    }
    return evalFail(eval,expr,"the value of '%s' is not known at macro time",expr->name);
}

/* `a.name`: a case named through its enum, a member of an instance, a reflection field of a declaration, the byte count
 * of text, or, on a value known only at macro time, whether it holds a case. */
static int evalMemberAccess(Eval *eval, EvalFrame *frame, RangeNode *expr, RangeValue *out)
{
    RangeNode *member = expr->resolvedDeclaration;
    if (member && member->kind == RangeNodeEnumCase) {
        *out = (RangeValue){.kind=ValueCase,.type=expr->type,.node=member};
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
        evalBind(eval,frame,pattern->a->resolvedDeclaration ? pattern->a->resolvedDeclaration : pattern->a,value);
        return EvalNormal;
    case RangePatternCase: {
        RangeNode *declaration = value.kind == ValueCase && value.type ? value.type->resolvedDeclaration : NULL;
        RangeNode *entry = pattern->resolvedDeclaration ? pattern->resolvedDeclaration : enumCase(declaration,pattern->name);
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

/* A switch runs its first arm whose rows match: a row's patterns match the
 * subjects, and its condition holds. A switch expression is the value its
 * arm yields; an arm that is a block runs as a statement. */
static int evalSwitch(Eval *eval, EvalFrame *frame, RangeNode *node, RangeValue *out)
{
    size_t width = node->c ? node->c->itemCount : 1;
    RangeValue *subjects = evalValues(eval,width);
    RangeNode **vector = rangeArenaAllocate(eval->vm->arena,(width ? width : 1) * sizeof(*vector));
    int status;
    *out = (RangeValue){0};
    for (size_t k = 0; k < width; ++k)
        if ((status = evalExpression(eval,frame,node->c ? node->c->items[k] : node->a,&subjects[k]))) return status;
    for (size_t i = 0; i < node->itemCount; ++i) {
        RangeNode *entry = node->items[i];
        int chosen = (entry->flags & RangeFlagLiteral) != 0;
        for (size_t j = 0; !chosen && j < entry->itemCount; ++j) {
            RangeNode *row = entry->items[j];
            patternRow(row,vector,width);
            chosen = 1;
            for (size_t k = 0; chosen && k < width; ++k)
                if (vector[k] && (status = evalMatch(eval,frame,vector[k],subjects[k],&chosen))) return status;
            if (chosen && row->b) {
                RangeValue condition;
                if ((status = evalExpression(eval,frame,row->b,&condition))) return status;
                chosen = evalTruth(condition);
            }
        }
        if (!chosen) continue;
        if (!entry->a) return evalStatement(eval,frame,entry->b);
        status = evalExpression(eval,frame,entry->a,out);
        return status ? status : evalAdopt(eval,out,node->type,entry->a);
    }
    return EvalNormal;
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
            *out = (RangeValue){.kind=ValueText,.type=expr->type,.text=out->text,.length=out->length};
    }
    return evalAdopt(eval,out,expr->type,expr);
}

/* An expression as written: what its own kind computes. */
static int evalPlain(Eval *eval, EvalFrame *frame, RangeNode *expr, RangeValue *out)
{
    int status = evalStep(eval,expr);
    if (status) return status;
    switch (expr->kind) {
    case RangeNodeInteger: case RangeNodeBool: case RangeNodeString: return evalLiteral(eval,frame,expr,out);
    case RangeNodeName: return evalName(eval,frame,expr,out);
    case RangeNodeEnvironment:
        // A splice of a macro local, or a field of the application's target.
        if (expr->resolvedDeclaration) return evalName(eval,frame,expr,out);
        if (!eval->application) return evalFail(eval,expr,"'#%s' is read outside a macro application",expr->name);
        return evalField(eval,eval->application->target,expr->name,expr,out);
    case RangeNodeCase:
        if (!expr->resolvedDeclaration) return evalStop(eval);
        *out = (RangeValue){.kind=ValueCase,.type=expr->type,.node=expr->resolvedDeclaration};
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
        if (eval->vm->skipEmission || (expr->flags & RangeFlagShape)) return EvalNormal;
        return evalEmit(eval,frame,expr);
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
static int evalExpression(Eval *eval, EvalFrame *frame, RangeNode *expr, RangeValue *out)
{
    *out = (RangeValue){0};
    if (!expr) return EvalNormal;
    int status = evalPlain(eval,frame,expr->lowered ? expr->lowered : expr,out);
    if (!status && expr->narrowed) {
        if (out->kind != ValueCase || out->node != expr->narrowed || out->count != 1)
            return evalFail(eval,expr,"this narrowed value holds no payload");
        *out = out->values[0];
    }
    if (!status && expr->promoted) status = evalPromote(eval,out,expr->promoted,expr);
    return status;
}

/* ---- statements ---- */

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
    case RangeNodeLet: case RangeNodeState: {
        // `let p: Point(x: 1)` constructs; `let r: step(x: 1)` calls; a bare
        // name that resolved to a value copies it.
        RangeNode *initial = declarationValue(node);
        if (initial == node) status = evalConstruct(eval,frame,node->type,node->items,node->itemCount,node,&value);
        else status = evalExpression(eval,frame,initial,&value);
        if (!status) status = evalAdopt(eval,&value,node->type,node);
        if (!status) evalBind(eval,frame,node,value);
        return status;
    }
    case RangeNodeAssign: {
        RangeNode *target = node->a->type ? node->a->type : node->a->resolvedDeclaration ? node->a->resolvedDeclaration->type : NULL;
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

static int typeMacroOnDemand(Typer *, RangeMacroApplication *);

/* Run an application against its target: its macro body, or with `shape`
 * only its shape-only #graph blocks. A failure is the application's (fail
 * reports it); returns 0 when the body stopped on a problem typing reported. */
static int evalApplication(Resolver *vm, RangeMacroApplication *app, int shape)
{
    Eval eval = {.vm=vm,.typer=vm->typer,.application=app};
    EvalFrame frame = {0};
    RangeNode *body = app->declaration->a;
    int status = EvalNormal;
    if (shape) {
        for (size_t i = 0; !status && body && i < body->itemCount; ++i) {
            RangeNode *emission = body->items[i]->kind == RangeNodeExpressionStatement ? body->items[i]->a : NULL;
            if (emission && emission->kind == RangeNodeEmission && (emission->flags & RangeFlagShape)) status = evalEmit(&eval,&frame,emission);
        }
    } else if (!typeMacroOnDemand(vm->typer,app)) return 0;
    else status = evalStatement(&eval,&frame,body);
    if (status == EvalFailed && eval.message) fail(vm,eval.at,"%s",eval.message);
    return status != EvalFailed;
}

/* ---- native code -----------------------------------------------------------
 * Lowers typed Range to ARM64. A scalar (a type with a storage primitive) lives
 * in a 64-bit register, sign- or zero-extended by the width its storage and
 * signed primitives declare. Any other value lives in memory and expressions
 * carry its address. Calling convention, internal to Range: a method receives
 * its receiver's address in x0 and parameters after it; scalars pass by value,
 * aggregates by address (the callee copies); an aggregate result is written to
 * the address the caller passes in x8. Generic constructs' methods are compiled
 * once per concrete specialization, with type parameters substituted.
 *
 * Builtin operators are C primitives: each enforces its operand type's range
 * (the @integer law) at runtime where the compiler cannot prove it, writing a
 * located message and exiting 134. Operators with bodies are calls. Every function is compiled, reached or not,
 * so each missing mechanism is reported; forms not lowered yet are reported as
 * not implemented. */

/* A branch to patch once its target is known: its position and encoding. */
typedef struct { size_t at; uint32_t base; } NativeJump;
/* An alias slot names another binding's storage; it does not own the value.
 * A packed one is a member inside an aggregate, a scalar at its own size. */
typedef struct { RangeNode *declaration; int32_t offset; RangeNode *type; int alias, packed; } NativeSlot;
typedef struct { size_t at; RangeNode *function; RangeNode *self; } NativeCall;
typedef struct { size_t at; uint32_t branch; const char *message; } NativeTrap;
typedef struct { RangeNode *function, *self; size_t offset; int compiled; } NativeInstance;
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

/* What a body runs in: its receiver and its function. A body inlined into
 * another, a callee's or a closure's, runs in its own context; outer is the
 * context it was inlined from, whose receiver substitutes its types too. */
typedef struct NativeContext {
    RangeNode *owner, *self, *function;
    int32_t selfSlot;
    struct NativeContext *outer;
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
typedef struct NativeRegion {
    RangeNode *function, *resultType;
    int32_t result, stack;
    int resultKind, valueDepth;
    size_t slots, temps;
    NativeJump *returns; size_t returnCount, returnCapacity;
    struct NativeRegion *outer;
} NativeRegion;

typedef struct {
    SourceReport *report;
    Typer *typer;
    RangeMachine machine;
    int failed;
    /* The function being compiled. */
    RangeNode *owner, *self, *output, *function;
    int32_t frame, selfSlot, resultSlot;
    NativeContext *outer;  /* the context the running body was inlined from */
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

/* Substitute a construct's type parameters with `self`'s arguments. A
 * specialization mentioning them becomes a new concrete specialization, whose
 * laws run like any other. */
static RangeNode *nativeSubstitute(Native *native, RangeNode *type, RangeNode *self)
{
    if (!type || !self || !self->resolvedDeclaration || !self->resolvedDeclaration->generics) return type;
    RangeNode *declared = self->resolvedDeclaration->generics;
    if (type->kind == RangeNodeTypeParameter) {
        for (size_t i = 0; i < declared->itemCount && self->generics && i < self->generics->itemCount; ++i)
            if (declared->items[i] == type) return self->generics->items[i]->resolvedType;
        return type;
    }
    if (type->kind != RangeNodeSpecialization || !type->generics) return type;
    RangeArena *arena = native->report->arena;
    RangeNode *generics = rangeNodeCreate(arena,RangeNodeBlock,type->path,type->line,type->column);
    generics->name = "genericMembers";
    int changed = 0;
    for (size_t i = 0; i < type->generics->itemCount; ++i) {
        RangeNode *copy = rangeArenaAllocate(arena,sizeof(*copy));
        *copy = *type->generics->items[i];
        if (copy->kind == RangeNodeTypeParameter) {
            copy->resolvedType = nativeSubstitute(native,copy->resolvedType,self);
            changed |= copy->resolvedType != type->generics->items[i]->resolvedType;
        }
        rangeNodeAppend(arena,generics,copy);
    }
    if (!changed) return type;
    int created = 0;
    RangeNode *specialization = internSpecialization(native->typer,type->resolvedDeclaration,generics,&created);
    if (created) checkLaws(native->typer,specialization,NULL,type->resolvedDeclaration);
    return specialization;
}

/* A type of a body running in `self`, inlined from `outer`: each receiver
 * substitutes the type parameters it declares. */
static RangeNode *nativeTypeIn(Native *native, RangeNode *type, RangeNode *self, NativeContext *outer)
{
    type = nativeSubstitute(native,type,self);
    for (; outer; outer = outer->outer) type = nativeSubstitute(native,type,outer->self);
    return type;
}

static RangeNode *nativeType(Native *native, RangeNode *type) { return nativeTypeIn(native,type,native->self,native->outer); }

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

static size_t nativeMemberIndex(RangeNode *declaration, RangeNode *member)
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

/* `.value(number: 7)`: build a case of `type` at frame offset `destination`,
 * or in a temporary; a union without payloads is its tag in x0. */
static RangeNode *nativeVariant(Native *native, RangeNode *at, RangeNode *type, RangeNode *entry,
                                RangeNode **arguments, size_t count, int32_t destination)
{
    int kind = nativeKind(native,type,at);
    if (kind == NativeNone || !entry) return NULL;
    if (kind == NativeScalar) {
        nativeConstant(native,0,(uint64_t)entry->integer);
        native->resultTemp = -1;
        return type;
    }
    int temporary = !destination;
    if (temporary) destination = nativeReserve(native,type->size,type->alignment);
    nativeFrameAddress(native,0,destination);
    nativeZero(native,0,type->size);
    nativeConstant(native,1,(uint64_t)entry->integer);
    nativeEmit(native,armStoreSized((size_t)type->variantTag,1,0,0));
    size_t first = nativeFirstField(type->resolvedDeclaration,entry);
    for (size_t j = 0; j < entry->itemCount; ++j) {
        RangeNode *field = entry->items[j], *value = NULL;
        for (size_t i = 0; i < count; ++i) if (arguments[i]->resolvedDeclaration == field) value = arguments[i]->a;
        if (!value || nativeKind(native,type->memberTypes[first + j],field) == NativeNone || !nativeExpression(native,value)) continue;
        nativeStoreField(native,at,type,first + j,destination,nativeTakeTemp(native));
    }
    if (temporary) nativeTrackTemp(native,destination,type);
    else native->resultTemp = -1;
    nativeFrameAddress(native,0,destination);
    return type;
}

/* Construct `type` at frame offset `destination` (an aggregate), or into x0 (a
 * scalar). Arguments populate the members they name; the rest take their
 * defaults; @many storage starts empty. */
static RangeNode *nativeConstruct(Native *native, RangeNode *at, RangeNode *type, RangeNode **arguments,
                                  size_t count, int32_t destination)
{
    int kind = nativeKind(native,type,at);
    if (kind == NativeNone) return NULL;
    RangeNode *declaration = type->resolvedDeclaration;
    if (kind == NativeScalar) {
        // A scalar's single input is the value itself.
        native->resultTemp = -1;
        if (count) return nativeExpression(native,arguments[0]->a), type;
        for (size_t i = 0; i < declaration->itemCount; ++i)
            if (constructionInput(declaration->items[i]) && declarationValue(declaration->items[i])) {
                nativeExpression(native,declarationValue(declaration->items[i]));
                return type;
            }
        nativeEmit(native,armMovz(0,0,0));
        return type;
    }
    int temporary = !destination;
    if (temporary) destination = nativeReserve(native,type->size ? type->size : 1,type->alignment);
    if (bytesType(type)) {
        // Like a scalar, a bytes construct's single input is the value itself:
        // `String("hi")` is the literal's bytes, and `String()` its default's.
        RangeNode *value = count ? arguments[0]->a : NULL;
        for (size_t i = 0; !value && i < declaration->itemCount; ++i)
            if (constructionInput(declaration->items[i])) value = declarationValue(declaration->items[i]);
        nativeFrameAddress(native,0,destination);
        nativeZero(native,0,type->size);
        if (value) {
            if (!nativeExpression(native,value)) return NULL;
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
        RangeNode *memberType = type->memberTypes[i], *value = NULL;
        for (size_t j = 0; j < count; ++j) if (arguments[j]->resolvedDeclaration == member) value = arguments[j]->a;
        int memberKind = nativeKind(native,memberType,member);
        if (memberKind == NativeNone) continue;
        if (!value) value = declarationValue(member);
        if (value == member) {
            nativeConstruct(native,member,memberType,member->items,member->itemCount,destination + (int32_t)offset);
            if (memberKind == NativeScalar) { nativeFrameAddress(native,1,destination); nativeStoreScalar(native,0,1,offset,memberType); }
            continue;
        }
        if (!value) continue; /* required inputs are enforced by the type checker */
        nativeExpression(native,value);
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
        if (!type || native->slots[i].alias || type->scalarBits || !nativeSharesSlots(type)) continue;
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
    SourceScope scope = {.owner=declaration};
    RangeNode *element = resolveTypeReference(native->typer,&scope,member->typeName,member->generics,
                                              member->flags & ~RangeFlagMany,self,member);
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

static RangeNode *nativeElementOf(Native *native, RangeNode *type, RangeNode *member)
{
    SourceScope scope = {.owner=type->resolvedDeclaration};
    return resolveTypeReference(native->typer,&scope,member->typeName,member->generics,member->flags & ~RangeFlagMany,type,member);
}

static NativeInstance *nativeInstance(Native *, RangeNode *, RangeNode *);

static void nativeCallFunction(Native *native, RangeNode *function, RangeNode *self)
{
    NativeCall site = {.at=nativeEmit(native,armBl(0)),.function=function,.self=self};
    NATIVE_PUSH(native->calls,native->callCount,native->callCapacity,site);
    nativeInstance(native,function,self);
}

/* x0 = 1 when the values in x0 and x1 (scalars, or aggregates' addresses) are
 * equal. A type's equality function is called as x0.=(other: x1); any other
 * type is compared structurally: scalars directly, other values through a
 * subroutine emitted once per type a program compares. */
static int nativeEquals(Native *native, RangeNode *type, RangeNode *at)
{
    RangeNode *function = equalityFunction(type);
    Comparing visit = {.count=0};
    char why[512];
    if (!function && !comparable(native->typer,type,&visit,why,sizeof(why))) {
        char name[160], in[160] = "";
        describeType(name,sizeof(name),type);
        if (native->self) { char self[140]; describeType(self,sizeof(self),native->self); snprintf(in,sizeof(in)," (in %s)",self); }
        sourceDiagnostic(native->report,at,0,"type","'=' cannot compare %s: %s%s",name,why,in);
        native->failed = 1;
        return 0;
    }
    if (function) {
        // The receiver is an address: a scalar is passed through the stack.
        if (type->scalarBits) { nativeEmit(native,armPush(0)); nativeEmit(native,armAddImm(0,31,0)); }
        nativeCallFunction(native,function,type);
        if (type->scalarBits) nativeEmit(native,armAddImm(31,31,16));
        native->resultTemp = -1;
        return 1;
    }
    if (type->scalarBits) { nativeEmit(native,armCmp(0,1)); nativeEmit(native,armCset(0,RangeEQ)); return 1; }
    nativeCallHelper(native,type,NativeEqual);
    return 1;
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
    if (!nativeEquals(native,fieldType,fieldType->resolvedDeclaration)) return;
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
                RangeNode *element = nativeElementOf(native,type,member);
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

static NativeInstance *nativeInstance(Native *native, RangeNode *function, RangeNode *self)
{
    for (size_t i = 0; i < native->instanceCount; ++i)
        if (native->instances[i].function == function && native->instances[i].self == self) return &native->instances[i];
    NativeInstance instance = {.function=function,.self=self};
    NATIVE_PUSH(native->instances,native->instanceCount,native->instanceCapacity,instance);
    return &native->instances[native->instanceCount - 1];
}

static int nativeConcreteInstance(Typer *typer, size_t index)
{
    size_t count = typeParameterCount(typer->instances[index].declaration);
    for (size_t k = 0; k < count; ++k) if (!nativeConcrete(typer->instances[index].types[k])) return 0;
    return 1;
}

/* A call of a generic function's instance typed with the enclosing
 * construct's type parameters calls the instance for this specialization's
 * types, typed on first use like any other. */
static RangeNode *nativeGenericTarget(Native *native, RangeNode *target, RangeNode *at)
{
    Typer *typer = native->typer;
    for (size_t i = 0; i < typer->instanceCount; ++i) {
        if (typer->instances[i].instance != target || nativeConcreteInstance(typer,i)) continue;
        RangeNode *declaration = typer->instances[i].declaration, **values = typer->instances[i].values;
        size_t count = typeParameterCount(declaration);
        RangeNode **bound = rangeArenaAllocate(native->report->arena,(count ? count : 1) * sizeof(*bound));
        for (size_t k = 0; k < count; ++k) {
            bound[k] = nativeType(native,typer->instances[i].types[k]);
            if (!nativeConcrete(bound[k])) {
                char type[160]; describeType(type,sizeof(type),bound[k]);
                nativeMissing(native,at,"'%s' is called with %s, which no specialization substitutes here",declaration->name,type);
                return NULL;
            }
        }
        size_t errors = native->report->errors;
        RangeNode *instance = instantiate(typer,declaration,bound,values,at,NULL);
        checkMutations(typer,instance);
        if (native->report->errors != errors) native->failed = 1;
        return instance;
    }
    return target;
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
    NativeRegion region = {.function=function,.resultType=output,.resultKind=kind,.outer=native->region,
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
    NativeContext saved = {.owner=native->owner,.self=native->self,.function=native->function,
                           .selfSlot=native->selfSlot,.outer=native->outer};
    native->owner = context->owner; native->self = context->self; native->function = context->function;
    native->selfSlot = context->selfSlot; native->outer = context->outer;
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
    native->owner = saved.owner; native->self = saved.self; native->function = saved.function;
    native->selfSlot = saved.selfSlot; native->outer = saved.outer;
    native->resultTemp = -1;
    if (kind == NativeScalar) nativeLoad(native,0,region.result);
    else if (kind == NativeAggregate) { nativeTrackTemp(native,region.result,output); nativeFrameAddress(native,0,region.result); }
    return output;
}

/* `xs.filter(where: { m in m.unread })`: the callee's body inline, its
 * receiver's address and its parameters in slots, each closure bound to its
 * parameter. A function-typed argument that is itself a parameter passes on
 * the closure it holds. */
static RangeNode *nativeInline(Native *native, RangeNode *call, RangeNode *target)
{
    RangeNode *callee = call->a, *self = NULL;
    // Inlining ends only if no such function reaches itself: through the
    // bodies it inlines, or, more deeply, through the closures they call.
    size_t depth = 0;
    for (NativeRegion *region = native->region; region; region = region->outer) ++depth;
    for (NativeRegion *region = native->region; region && region->function; region = region->outer)
        if (region->function == target) depth = SIZE_MAX;
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
    NativeContext caller = {.owner=native->owner,.self=native->self,.function=native->function,
                            .selfSlot=native->selfSlot,.outer=native->outer};
    size_t slots = native->slotCount, closures = native->closureCount;
    for (size_t i = 0; i < call->itemCount && i < target->itemCount; ++i) {
        RangeNode *parameter = target->items[i], *value = call->items[i]->a;
        if (parameter->flags & RangeFlagFunction) {
            NativeClosure bound = {.parameter=parameter,.closure=value,.context=&caller,.slots=slots,.closures=closures};
            if (value->kind != RangeNodeClosure) {
                NativeClosure *passed = value->kind == RangeNodeName ? nativeClosureOf(native,value->resolvedDeclaration) : NULL;
                if (!passed) { nativeMissing(native,value,"no closure is bound to '%s' here",value->name ? value->name : "this argument"); return NULL; }
                bound = *passed;
                bound.parameter = parameter;
            }
            NATIVE_PUSH(native->closures,native->closureCount,native->closureCapacity,bound);
            continue;
        }
        RangeNode *type = nativeTypeIn(native,parameter->type,self,&caller);
        int kind = nativeKind(native,type,parameter);
        if (kind == NativeNone) return NULL;
        int32_t offset = kind == NativeAggregate ? nativeReserve(native,type->size ? type->size : 1,type->alignment) : nativeReserve(native,8,8);
        if (!nativeArgument(native,value,type,kind,offset)) return NULL;
        NativeSlot slot = {.declaration=parameter,.offset=offset,.type=type};
        NATIVE_PUSH(native->slots,native->slotCount,native->slotCapacity,slot);
    }
    NativeContext context = {.owner=self ? self->resolvedDeclaration : NULL,.self=self,.function=target,
                             .selfSlot=selfSlot,.outer=&caller};
    RangeNode *output = target->type ? nativeTypeIn(native,target->type,self,&caller) : NULL;
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
    for (size_t i = 0; i < count && i < call->itemCount; ++i) {
        types[i] = nativeTypeIn(native,literal->items[i]->type,closure.context->self,closure.context->outer);
        int kind = nativeKind(native,types[i],literal->items[i]);
        if (kind == NativeNone) return NULL;
        offsets[i] = kind == NativeAggregate ? nativeReserve(native,types[i]->size ? types[i]->size : 1,types[i]->alignment) : nativeReserve(native,8,8);
        if (!nativeArgument(native,call->items[i]->a,types[i],kind,offsets[i])) return NULL;
    }
    NativeHidden hidden = {.slotFrom=closure.slots,.slotTo=native->slotCount,.closureFrom=closure.closures,.closureTo=native->closureCount};
    NATIVE_PUSH(native->hidden,native->hiddenCount,native->hiddenCapacity,hidden);
    size_t slots = native->slotCount;
    for (size_t i = 0; i < count; ++i) {
        NativeSlot slot = {.declaration=literal->items[i],.offset=offsets[i],.type=types[i]};
        NATIVE_PUSH(native->slots,native->slotCount,native->slotCapacity,slot);
    }
    RangeNode *output = literal->type ? nativeTypeIn(native,literal->type->a,closure.context->self,closure.context->outer) : NULL;
    RangeNode *result = nativeRegion(native,call,NULL,output,closure.context,literal->a,closureResult(native->typer,literal),slots);
    native->hiddenCount -= 1;
    return result;
}

static RangeNode *nativeCall(Native *native, RangeNode *call)
{
    RangeNode *callee = call->a, *target = callee ? callee->resolvedDeclaration : NULL;
    if (target && target->kind == RangeNodeParameter && isFunctionType(target->type)) return nativeCallClosure(native,call,target);
    if (target && target->kind == RangeNodeFunction && !target->typeName && target->generics && native->self) {
        target = nativeGenericTarget(native,target,call);
        if (!target) return NULL;
    }
    if (target && (target->kind == RangeNodeConstruct || target->kind == RangeNodeEnum || target->kind == RangeNodeTypeParameter))
        return nativeConstruct(native,call,nativeType(native,call->type),call->items,call->itemCount,0);
    if (target && target->kind == RangeNodeEnumCase)
        return nativeVariant(native,call,nativeType(native,call->type),target,call->items,call->itemCount,0);
    if (!target || target->kind != RangeNodeFunction) { nativeMissing(native,call,"native call target is not implemented"); return NULL; }
    if (nativeInlined(target)) return nativeInline(native,call,target);
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
        return nativeSubstitute(native,target->type,self);
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
    RangeNode *output = nativeSubstitute(native,target->type,self);
    int outputKind = output ? nativeKind(native,output,call) : NativeNone;
    int32_t result = 0;
    if (outputKind == NativeAggregate) result = nativeReserve(native,output->size ? output->size : 1,output->alignment);
    for (size_t i = registers; i-- > 0;) nativeEmit(native,armPop((int)i));
    if (result) nativeFrameAddress(native,8,result);
    NativeCall site = {.at=nativeEmit(native,armBl(0)),.function=target,.self=self};
    NATIVE_PUSH(native->calls,native->callCount,native->callCapacity,site);
    nativeInstance(native,target,self);
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
    RangeNodeKind kind = expr->lowered ? expr->lowered->kind : expr->kind;
    if (kind == RangeNodeName) {
        RangeNode *declaration = expr->resolvedDeclaration;
        if (declaration && native->function && declaration == native->function->receiver && native->owner) {
            // The receiver, whose address the method holds.
            nativeLoad(native,0,native->selfSlot);
            return native->self;
        }
        NativeSlot *slot = nativeSlotOf(native,declaration);
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
    if (kind == RangeNodeMemberAccess && !(expr->resolvedDeclaration && expr->resolvedDeclaration->kind == RangeNodeEnumCase)) {
        int innerSlot = 0;
        RangeNode *receiver = nativeAddress(native,expr->a,&innerSlot);
        if (!receiver) return NULL;
        if (bytesType(receiver) && expr->resolvedDeclaration && builtinMember(expr->resolvedDeclaration)
            && same(expr->resolvedDeclaration->name,"count")) {
            // The byte count is the bytes primitive's second word.
            nativeEmit(native,armAddImm(0,0,8));
            return nativeType(native,expr->type);
        }
        size_t index = nativeMemberIndex(receiver->resolvedDeclaration,expr->resolvedDeclaration);
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
    if (!optional || !expr->narrowed) return optional;
    *frameSlot = 0;
    size_t field = nativeFirstField(optional->resolvedDeclaration,expr->narrowed);
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

/* What typing lowered an expression to, if anything, is compiled in its
 * place, and a promoted value becomes the present case holding it. Only a
 * call, construction, switch expression, slot read, or promotion produces a
 * temporary; any other expression reports none, whatever its operands left
 * behind. */
static RangeNode *nativeExpression(Native *native, RangeNode *expr)
{
    RangeNode *runs = expr && expr->lowered ? expr->lowered : expr;
    RangeNode *type = nativeExpressionValue(native,runs);
    int construction = runs && (runs->kind == RangeNodeCall || runs->kind == RangeNodeSwitch);
    if (!runs || (!construction && !(runs->resolvedDeclaration
        && runs->resolvedDeclaration->kind == RangeNodeEnumCase))) native->resultTemp = -1;
    return type && expr->promoted ? nativePromote(native,expr,nativeType(native,expr->promoted)) : type;
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

/* A value generic in a body: the constant of this function instance, or of
 * the receiver's specialization. Returns 0 when the name is not one. */
static int nativeValueGeneric(Native *native, RangeNode *expr)
{
    RangeNode *declaration = expr->resolvedDeclaration, *value = NULL;
    if (!declaration || declaration->kind != RangeNodeLet) return 0;
    RangeNode *generics = native->function && native->function->kind == RangeNodeFunction ? native->function->generics : NULL;
    RangeNode *declared = native->owner ? native->owner->generics : NULL;
    int found = 0;
    for (size_t i = 0; generics && i < generics->itemCount && !found; ++i)
        if (generics->items[i] == declaration) { value = declaration->a; found = 1; }
    for (size_t i = 0; declared && i < declared->itemCount && !found; ++i)
        if (declared->items[i] == declaration) {
            found = 1;
            if (native->self->generics && i < native->self->generics->itemCount) value = rangeNodeRHS(native->self->generics->items[i]);
        }
    if (!found) return 0;
    RangeNodeKind kind; long long integer; const char *text;
    if (!value || !lawInputs(value,&kind,&integer,&text) || kind == RangeNodeString) {
        nativeMissing(native,expr,"value generic '%s' needs an integer or boolean literal natively",expr->name);
        return 1;
    }
    nativeConstant(native,0,(uint64_t)integer);
    native->resultTemp = -1;
    return 1;
}

static RangeNode *nativeSwitch(Native *, RangeNode *);
static RangeNode *nativeCaseTest(Native *, RangeNode *);

static RangeNode *nativeExpressionValue(Native *native, RangeNode *expr)
{
    if (!expr) return NULL;
    RangeNode *type = nativeType(native,expr->type);
    if (isEnum(type) && isLiteral(expr)) /* a literal naming a case, such as true */
        return nativeVariant(native,expr,type,literalCase(type->resolvedDeclaration,expr),NULL,0,0);
    if (expr->resolvedDeclaration && expr->resolvedDeclaration->kind == RangeNodeEnumCase
        && (expr->kind == RangeNodeCase || expr->kind == RangeNodeMemberAccess))
        return nativeVariant(native,expr,type,expr->resolvedDeclaration,NULL,0,0);
    switch (expr->kind) {
    case RangeNodeInteger:
        if (nativeKind(native,type,expr) != NativeScalar) return NULL;
        nativeConstant(native,0,(uint64_t)expr->integer);
        return type;
    case RangeNodeBool:
        nativeConstant(native,0,expr->integer ? 1 : 0);
        return type;
    case RangeNodeString: {
        // A literal is its UTF-8 bytes in __text: the value holds their
        // address and count, the layout the bytes primitive declares.
        if (expr->itemCount != 1 || !(expr->items[0]->flags & RangeFlagLiteral)) {
            nativeMissing(native,expr,"runtime string interpolation is not implemented");
            return NULL;
        }
        if (nativeKind(native,type,expr) != NativeAggregate || !bytesType(type)) {
            nativeMissing(native,expr,"string literals need a construct with the bytes primitive");
            return NULL;
        }
        int32_t value = nativeReserve(native,type->size,8);
        NativeText text = {.at=nativeEmit(native,armAdr(1,0)),.bytes=expr->items[0]->name,.length=(size_t)expr->items[0]->integer};
        NATIVE_PUSH(native->texts,native->textCount,native->textCapacity,text);
        nativeConstant(native,2,text.length);
        nativeFrameAddress(native,0,value);
        nativeEmit(native,armStr(1,0,0));
        nativeEmit(native,armStr(2,0,8));
        nativeEmit(native,armStr(31,0,16)); /* no block: the bytes are in the executable */
        return type;
    }
    case RangeNodeName: case RangeNodeMemberAccess: {
        if (expr->kind == RangeNodeName && nativeValueGeneric(native,expr)) return type;
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
        if (type->scalarBits == 64 && type->scalarSigned) {
            char name[160]; describeType(name,sizeof(name),type);
            nativeEmit(native,armNegs(0,0));
            nativeTrap(native,armBcond(RangeVS,0),expr,"result of '-' does not fit %s",name);
        } else {
            nativeEmit(native,armNeg(0,0));
            nativeFits(native,type,expr,"-");
        }
        return type;
    }
    case RangeNodeBinary: {
        const char *op = expr->name;
        if (shortCircuit(expr->resolvedDeclaration)) {
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
        if (same(op,"=") || same(op,"!=")) {
            if (!nativeEquals(native,operand,expr)) return NULL;
            if (same(op,"!=")) { nativeEmit(native,armCmpImm(0,0)); nativeEmit(native,armCset(0,RangeEQ)); }
            return type;
        }
        // A builtin operator is the C primitive its name selects for its
        // operand's layout: joining for bytes, arithmetic and comparison on
        // a scalar's storage.
        if (nativeKind(native,operand,expr) != NativeScalar && same(op,"+") && bytesType(operand)) return nativeJoin(native,expr,operand);
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

/* Stream a message to fd: literal parts as bytes, interpolated integers in
 * decimal, enum values without payloads (booleans among them) as their case
 * names, strings as their bytes. */
static void nativeWriteMessage(Native *native, int fd, RangeNode *message)
{
    int literal = message->kind == RangeNodeString;
    size_t parts = literal ? message->itemCount : 1;
    for (size_t i = 0; i < parts; ++i) {
        RangeNode *part = literal ? message->items[i] : NULL;
        if (part && (part->flags & RangeFlagLiteral)) { nativeWriteText(native,fd,part->name,(size_t)part->integer); continue; }
        RangeNode *value = part ? part->a : message;
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
}

/* @print writes to standard output; @diagnostic writes a located message to
 * standard error and exits 134, as a law violation does. */
static void nativeEffect(Native *native, RangeNode *node, RangeNode *attribute)
{
    RangeNode *macro = attribute->resolvedDeclaration;
    int print = macroBuiltin(macro,"print");
    if (!print && !macroBuiltin(macro,"diagnostic")) {
        nativeMissing(native,node,"runtime macro application '@%s' is not implemented",attribute->name);
        return;
    }
    if (attribute->itemCount != 1) return; /* reported by the type checker */
    if (!print) {
        char location[512];
        snprintf(location,sizeof(location),"%s:%d:%d: ",attribute->path,attribute->line,attribute->column);
        const char *prefix = rangeArenaIntern(native->report->arena,location,strlen(location));
        nativeWriteText(native,2,prefix,strlen(prefix));
    }
    nativeWriteMessage(native,print ? 1 : 2,attribute->items[0]->a);
    nativeWriteText(native,print ? 1 : 2,"\n",1);
    if (!print) {
        nativeEmit(native,armMovz(0,134,0));
        rangeCallImport(&native->machine,"_exit");
    }
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
        RangeNode *type = nativeType(native,node->type);
        int kind = nativeKind(native,type,node);
        if (kind == NativeNone) break;
        // A bare name that resolved to a value is a copy; to a type, a requirement.
        RangeNode *value = declarationValue(node);
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
            break;
        }
        int32_t offset = nativeNewSlot(native,node,type,kind);
        if (value) {
            if (!nativeExpression(native,value)) break;
            int moved = nativeTakeTemp(native);
            nativeFrameAddress(native,1,offset);
            nativeCopyValue(native,1,0,type,!moved);
        } else nativeMissing(native,node,"'%s' has no initial value",node->name); /* the type checker rejects it */
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
        size_t top = native->machine.size, exit = 0;
        nativeEnter(native,1,top);
        if (node->a) { /* without a condition, the loop ends only at break */
            nativeCondition(native,node->a);
            exit = nativeEmit(native,armCbz(0,0));
        }
        nativeStatement(native,node->b);
        nativeEmit(native,armB(-(int32_t)((native->machine.size - top) / 4)));
        if (node->a) nativeBranchHere(native,exit,armCbz(0,0));
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
    case RangeNodeExpressionStatement:
        if (node->a && node->a->kind == RangeNodeAttribute) nativeEffect(native,node,node->a);
        else nativeExpression(native,node->a);
        break;
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
        RangeNode *entry = pattern->resolvedDeclaration;
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
        if (!nativeEquals(native,type,pattern)) return;
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
        RangeNode *target = bind->binding->resolvedDeclaration ? bind->binding->resolvedDeclaration : bind->binding;
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
    return nativeType(native,test->type);
}

/* A switch statement, or a switch expression (RangeFlagValue): each arm that
 * yields leaves the value in one frame slot, a scalar or the aggregate itself
 * holding its own references, which the expression then is, as a temporary.
 * Only the chosen arm is evaluated. Returns the expression's type. */
static RangeNode *nativeSwitch(Native *native, RangeNode *node)
{
    int value = (node->flags & RangeFlagValue) != 0;
    RangeNode *valueType = value ? nativeType(native,node->type) : NULL;
    int valueKind = value ? nativeKind(native,valueType,node) : NativeNone;
    if (value && valueKind == NativeNone) return NULL;
    // Each subject is evaluated once, in order, into its own slot.
    size_t width = node->c ? node->c->itemCount : 1;
    NativePlace places[width];
    RangeNode *types[width];
    for (size_t k = 0; k < width; ++k) {
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
        for (size_t j = 0; entry->c && j < entry->c->itemCount; ++j) {
            RangeNode *binding = entry->c->items[j], *bindingType = nativeType(native,binding->type);
            int bindingKind = nativeKind(native,bindingType,binding);
            if (bindingKind == NativeNone) continue;
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
        int fallible = !(entry->flags & RangeFlagLiteral);
        for (size_t j = 0; fallible && j < entry->itemCount; ++j) {
            RangeNode *pattern = entry->items[j], *patterns[width];
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
    native->targetCount = 0;
    native->self = instance->self;
    native->owner = instance->self ? instance->self->resolvedDeclaration : NULL;
    native->slotCount = 0; native->returnCount = 0; native->frame = 0;
    native->valueDepth = 0; native->stackResetCount = 0;
    native->tempCount = 0; native->resultTemp = -1;
    native->selfSlot = 0; native->resultSlot = 0;
    native->outer = NULL; native->region = NULL; native->closureCount = 0; native->hiddenCount = 0;
    nativeEmit(native,armPushFrame());
    nativeEmit(native,armAddImm(29,31,0)); /* mov x29, sp */
    size_t frameHigh = nativeEmit(native,armSubImmHigh(31,31,0));
    size_t frameLow = nativeEmit(native,armSubImm(31,31,0));
    RangeNode *body = function->kind == RangeNodeMain ? function->a : function->a;
    native->output = function->kind == RangeNodeMain ? function->type : nativeType(native,function->type);
    int outputKind = native->output ? nativeKind(native,native->output,function) : NativeScalar;
    if (outputKind == NativeAggregate) { native->resultSlot = nativeReserve(native,8,8); nativeStore(native,8,native->resultSlot); }
    int base = 0;
    if (native->owner) { native->selfSlot = nativeReserve(native,8,8); nativeStore(native,0,native->selfSlot); base = 1; }
    if (function->kind == RangeNodeFunction) {
        if (function->itemCount + (size_t)base > 8) nativeMissing(native,function,"functions with more than 8 parameters are not implemented");
        for (size_t i = 0; i < function->itemCount && i + (size_t)base < 8; ++i) {
            RangeNode *parameter = function->items[i], *type = nativeType(native,parameter->type);
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
 * abort would, without the delay of a crash report. */
static void nativeTraps(Native *native)
{
    size_t *messages = calloc(native->trapCount ? native->trapCount : 1,sizeof(*messages));
    if (!messages) abort();
    for (size_t i = 0; i < native->trapCount; ++i) {
        NativeTrap *trap = &native->traps[i];
        int32_t words = (int32_t)((native->machine.size - trap->at) / 4);
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
    }
    free(messages);
}

/* A specialization is concrete when no type argument is a type parameter. */
static int nativeConcrete(const RangeNode *type)
{
    if (!type || type->kind != RangeNodeSpecialization) return 0;
    for (size_t i = 0; type->generics && i < type->generics->itemCount; ++i) {
        RangeNode *generic = type->generics->items[i];
        if (generic->kind == RangeNodeTypeParameter && !nativeConcrete(generic->resolvedType)) return 0;
        if (generic->kind != RangeNodeTypeParameter && !rangeNodeRHS(generic)) return 0; /* a required value not supplied */
    }
    return 1;
}

/* A specialization over graph constructs or macro types (Array<Macro> and
 * Array<@member> in the grammar) holds compile-time graph values that C
 * provides; it has no runtime instance. */
static int nativeGraphValues(Native *native, const RangeNode *type)
{
    return macroTimeType(native->typer,type);
}

/* A construct's methods are compiled for each concrete specialization. A
 * construct with type parameters is generic, as a generic function is: its
 * methods are compiled per specialization when called, so Array<Point>'s
 * `=`, and Point's `=` with it, exist only if such arrays are compared. */
static void nativeMethods(Native *native, RangeNode *construct)
{
    if (parametric(construct)) return;
    for (size_t i = 0; i < native->typer->specializations->itemCount; ++i) {
        RangeNode *self = native->typer->specializations->items[i];
        if (self->resolvedDeclaration != construct || !nativeConcrete(self) || nativeGraphValues(native,self)) continue;
        for (size_t j = 0; j < construct->itemCount; ++j) {
            RangeNode *function = construct->items[j];
            // A type's function '=' is compiled only when the type is compared.
            if (function->kind == RangeNodeFunction && !(function->flags & (RangeFlagBuiltin | RangeFlagExtern))
                && !same(function->name,"=") && !genericTemplate(function) && !nativeInlined(function))
                nativeInstance(native,function,self);
        }
    }
}

/* Compile the entry block, every function, and every method of every concrete
 * specialization; write the executable when nothing is missing. Returns 1
 * when an executable was written. */
static int emitNative(SourceReport *report, Typer *typer, const char *path)
{
    Native native = {.report=report,.typer=typer};
    RangeNode *entry = NULL;
    size_t entries = 0;
    for (size_t u = 0; u < report->count; ++u) for (size_t i = 0; i < report->units[u]->itemCount; ++i)
        if (report->units[u]->items[i]->kind == RangeNodeMain) { entry = report->units[u]->items[i]; ++entries; }
    if (entries > 1) { sourceDiagnostic(report,entry,0,"entry","the program has %zu entry blocks; it needs one",entries); return 0; }
    if (entry) nativeInstance(&native,entry,NULL);
    for (size_t u = 0; u < report->count; ++u) for (size_t i = 0; i < report->units[u]->itemCount; ++i) {
        RangeNode *item = report->units[u]->items[i];
        if (item->kind == RangeNodeFunction && !(item->flags & (RangeFlagBuiltin | RangeFlagExtern)) && !genericTemplate(item)
            && !nativeInlined(item))
            nativeInstance(&native,item,NULL);
    }
    // Generic functions: one compiled function per concrete instantiation. One
    // typed with an enclosing construct's type parameter is compiled through
    // the concrete instances its callers' specializations substitute.
    // A generic method's instance is compiled for its receiver's specialization.
    for (size_t i = 0; i < typer->instanceCount; ++i) {
        RangeNode *context = typer->instances[i].context;
        int graph = 0; /* one a macro calls with its graph values runs only at macro time */
        for (size_t k = 0; k < typeParameterCount(typer->instances[i].declaration); ++k)
            graph |= nativeGraphValues(&native,typer->instances[i].types[k]);
        if (!nativeConcreteInstance(typer,i) || (context && (!nativeConcrete(context) || nativeGraphValues(&native,context)))
            || graph || nativeInlined(typer->instances[i].instance)) continue;
        nativeInstance(&native,typer->instances[i].instance,context);
    }
    for (size_t u = 0; u < report->count; ++u) for (size_t i = 0; i < report->units[u]->itemCount; ++i)
        if (report->units[u]->items[i]->kind == RangeNodeConstruct || report->units[u]->items[i]->kind == RangeNodeEnum)
            nativeMethods(&native,report->units[u]->items[i]);
    // Compiling may reach new instances and subroutines, and a subroutine may
    // reach further ones of both; the entry block stays first.
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
        NativeInstance *instance = nativeInstance(&native,native.calls[i].function,native.calls[i].self);
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
    free(native.closures); free(native.hidden);
    return written;
}

/* Compiler driver: compile source directories, with parser and literal probes. */
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

int main(int argc, char **argv)
{
    RangeArena arena;
    rangeArenaInit(&arena);
    int treeMode = 0;
    const char *literalMacro = NULL, *literalInput = NULL;
    int first = 1;
    int option = first;
    if (argc > option + 2 && strcmp(argv[option],"--match-literal") == 0) {
        literalMacro=argv[option + 1]; literalInput=argv[option + 2]; first=option + 3;
    }
    else if (argc > option && strcmp(argv[option], "--tree") == 0) { treeMode = 1; first = option + 1; }
    const char *output = "a.out";
    if (!treeMode && !literalMacro && argc > first + 1 && strcmp(argv[first],"-o") == 0) { output = argv[first + 1]; first += 2; }
    if (first >= argc) { fprintf(stderr, "usage: compiler [-o executable | --tree | --match-literal macro text] files-or-directories...\n"); return 64; }
    Sources sources = {0};
    RangeNode **units = NULL;
    int status = 66;
    rangeGraphInitTypes(&arena);
    if (argv[first][0] == '-') { fprintf(stderr,"unsupported option: %s\n",argv[first]); status=64; goto cleanup; }
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
    }
    if (!treeMode && !literalMacro) {
        SourceReport report = {.arena=&arena,.units=units,.count=unitCount};
        char error[512];
        int resolved = unitCount && resolveGraphApplications(&arena,units,unitCount,error,sizeof(error));
        if (unitCount && !resolved) sourceDiagnostic(&report,NULL,0,"resolution","%s",error);
        // Build the graph, apply macros and merge their output, then resolve names.
        Typer *typer = resolved && !failures ? diagnoseMacroApplications(&report) : NULL;
        for (size_t u = 0; u < unitCount; ++u) diagnoseSourceNode(&report,NULL,units[u],0);
        diagnoseDuplicates(&report);
        for (size_t u = 0; u < unitCount; ++u) diagnoseBuiltinFunctions(&report,units[u]);
        if (typer) typeCheck(typer);
        // Native code is generated from a complete, well-typed graph only.
        int written = typer && !report.errors && emitNative(&report,typer,output);
        if (typer) diagnoseWritten(typer);
        writeSourceDiagnostics(&report,stderr);
        if (report.errors || failures) {
            fprintf(stderr,"compilation failed: %zu errors, %zu C implementation warnings\n",report.errors+(size_t)failures,report.warnings);
            status = 65;
        } else {
            if (written) fprintf(stderr,"wrote %s; %zu C implementation warnings\n",output,report.warnings);
            else fprintf(stderr,"checked %zu sources; no entry block, so no executable was written; %zu C implementation warnings\n",unitCount,report.warnings);
            status = 0;
        }
        goto cleanup;
    }
    if (literalMacro && !failures) {
        char error[512]; int matched = 0;
        if (!matchLiteralRule(&arena,units,unitCount,literalMacro,literalInput,&matched,error,sizeof(error))) {
            fprintf(stderr,"%s\n",error); failures += 1;
        } else printf("match=%s\n",matched ? "true" : "false");
    }
    status = failures ? 65 : 0;
cleanup:
    free(units);
    free(sources.paths);
    rangeArenaDestroy(&arena);
    return status;
}
