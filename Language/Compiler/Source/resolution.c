/* Resolution: reading the graph, literal rules, name lookup, and source
 * diagnostics. */
#define _XOPEN_SOURCE 700
#include "compiler.h"
#include <regex.h>
#include <setjmp.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int same(const char *a, const char *b) { return a && b && !strcmp(a,b); }

_Noreturn void fail(Resolver *vm, RangeNode *at, const char *format, ...)
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

/* The grammar declaration of a node's kind: the language's, or, in sources
 * without the language grammar, a top-level construct named like the kind. */
RangeNode *grammarDeclaration(Resolver *vm, RangeNode *node)
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
void resolveApplication(Resolver *vm, RangeNode *target, RangeNode *attribute)
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

void resolveGraphTarget(Resolver *vm, RangeNode *target)
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

void validateGraphShape(Resolver *vm, RangeNode *node, const char *source)
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

int literalMatch(Resolver *vm, RangeNode *at, const char *pattern, const char *input)
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
int macroBuiltin(RangeNode *node, const char *name)
{
    if (!node || node->kind != RangeNodeMacro || !node->c || !same(node->name,name)) return 0;
    for (size_t i = 0; i < node->c->itemCount; ++i)
        if (same(node->c->items[i]->name,"builtin")) return 1;
    return 0;
}

/* A builtin top-level function is `@builtin function name`; its name
 * selects the C primitive that runs where its body would. */
int builtinFunction(const RangeNode *node, const char *name)
{
    return node && node->kind == RangeNodeFunction && (node->flags & RangeFlagBuiltin) && !node->owner
        && !node->typeName && same(node->name,name);
}

/* A role marks the function C calls for a construct: @iteration for `for … in`
 * and @insertion for building reflection lists. Applying one has no
 * compile-time effect. */
int roleMacro(RangeNode *node)
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
        RANGE_LANGUAGE_DIR "/Functions", RANGE_LANGUAGE_DIR "/Grammar", RANGE_LANGUAGE_DIR "/Macros",
        RANGE_LANGUAGE_DIR "/Types"
    };
    if (!node->path) return 0;
    for (size_t i = 0; i < sizeof(directories)/sizeof(*directories); ++i) {
        size_t length = strlen(directories[i]);
        if (!strncmp(node->path,directories[i],length) && node->path[length] == '/') return 1;
    }
    return 0;
}

/* A macro type @name admits declarations that applied that macro. */
int appliesMacro(const RangeNode *declaration, const RangeNode *macro)
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

/* In macro code `#` names #target, the declaration the macro is attached
 * to; `#target.field` must exist on the target type, or on every kind a
 * macro type admits. #graph code splices macro locals too: typing checks it. */
static void validateTargetReferences(Resolver *vm, RangeNode *node, RangeNode *type, RangeNode *nominal)
{
    if (!node || node->kind == RangeNodeEmission) return; /* deferred code */
    if (node->kind == RangeNodeEnvironment && !same(node->name,"target"))
        fail(vm,node,"'#%s' names nothing here; in macro code, #target is the declaration the macro is attached to",node->name);
    if (node->kind == RangeNodeEnvironment && !type && !nominal) fail(vm,node,"#target requires a declared macro target");
    int field = node->kind == RangeNodeMemberAccess && node->a && node->a->kind == RangeNodeEnvironment && same(node->a->name,"target");
    if (field && nominal) {
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
    } else if (field && type && !rangeGraphField(type,node->name))
        fail(vm,node,"field '%s' is not declared by @type %s",node->name,type->name);
    validateTargetReferences(vm,node->a,type,nominal); validateTargetReferences(vm,node->b,type,nominal);
    validateTargetReferences(vm,node->c,type,nominal); validateTargetReferences(vm,node->generics,type,nominal);
    for (size_t i = 0; i < node->itemCount; ++i) validateTargetReferences(vm,node->items[i],type,nominal);
}

/* Whether quoted code splices only #target or `#target.field`, a single
 * node of the target's shape. A nested macro's splices are its own. */
static int shapeSplices(const RangeNode *shape, const RangeNode *node)
{
    if (!node || node->kind == RangeNodeMacro) return 1;
    if (spliceChain(node)) {
        if (node->kind == RangeNodeEnvironment) return same(node->name,"target");
        if (node->kind != RangeNodeMemberAccess || node->a->kind != RangeNodeEnvironment || !same(node->a->name,"target")) return 0;
        const RangeNode *field = rangeGraphField(shape,node->name);
        return field && !(field->flags & (RangeFlagMany | RangeFlagOptional));
    }
    if (!shapeSplices(shape,node->a) || !shapeSplices(shape,node->b) || !shapeSplices(shape,node->c)
        || !shapeSplices(shape,node->generics) || !shapeSplices(shape,node->annotations)
        || !shapeSplices(shape,node->rhsReference)) return 0;
    for (size_t i = 0; i < node->itemCount; ++i) if (!shapeSplices(shape,node->items[i])) return 0;
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
        if (emission && emission->kind == RangeNodeEmission && shapeSplices(shape,emission->b))
            emission->found |= RangeFlagShape;
    }
}

void linkGrammarNodes(Resolver *vm, RangeNode *node)
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

void resolveLiteralDefaults(Resolver *vm, RangeNode *node)
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

int matchLiteralRule(RangeArena *arena, RangeNode **units, size_t count,
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

/* The constructs and enums enclosing `node`, innermost first. */
int enclosing(RangeNode *within, RangeNode *node, RangeNode **chain, size_t *count, size_t capacity)
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
void resolveSignatureTypes(Resolver *vm, RangeNode *node, RangeNode *owner)
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

int resolveGraphApplications(RangeArena *arena, RangeNode **units, size_t count,
                             char *error, size_t errorSize)
{
    Resolver *vm = calloc(1,sizeof(*vm));
    if (!vm) { snprintf(error,errorSize,"cannot allocate graph resolver"); return 0; }
    vm->arena=arena; vm->units=units; vm->count=count; vm->error=error; vm->errorSize=errorSize;
    int ok = 0;
    if (setjmp(vm->failure) == 0) {
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

/* A splice is a # chain such as #element or #target.name; the whole chain
 * runs at macro time. `#element(…)` and `#target.name(…)` call the spliced
 * name where the code lands: only the name is spliced, since a declaration
 * value has fields and no functions. */
int spliceChain(const RangeNode *node)
{
    while (node && (node->kind == RangeNodeMemberAccess || node->kind == RangeNodeCall)) {
        const RangeNode *callee = node->kind == RangeNodeCall ? node->a : NULL;
        if (callee && (callee->kind == RangeNodeEnvironment
                       || (callee->kind == RangeNodeMemberAccess && callee->a && callee->a->kind == RangeNodeEnvironment
                           && same(callee->a->name,"target")))) return 0;
        node = node->a;
    }
    return node && node->kind == RangeNodeEnvironment;
}

/* `let x: #element` becomes `let x: Element`: a spliced name in a
 * declaration RHS takes the type position, as the parser would place it. */
void spliceDeclarationType(RangeNode *copy, const RangeNode *original)
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
int argumentFits(const RangeNode *argument, const RangeNode *function, size_t index)
{
    if (same(argument->name,function->items[index]->name)) return 1;
    return !argument->name && (argument->flags & RangeFlagImplicit) && trailingParameter(function) == index;
}

/* The function a construct or enum declares with @insertion, which C calls to
 * build a reflection list; *count is how many it declares. The role, not a
 * name, selects it. */
RangeNode *insertionFunction(const RangeNode *declaration, size_t *count)
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

void sourceDiagnostic(SourceReport *report, RangeNode *at, int warning,
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
RangeNode *methodReceiver(SourceReport *report, RangeNode *function)
{
    if (!function->receiver) {
        function->receiver = rangeNodeCreate(report->arena,RangeNodeLet,function->path,function->line,function->column);
        function->receiver->name = function->typeName;
    }
    return function->receiver;
}

RangeNode *sourceLookup(SourceReport *report, SourceScope *scope,
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
RangeNode *nameLookup(SourceReport *report, SourceScope *scope, const RangeNode *name)
{
    if (name->flags & RangeFlagEarlier)
        for (SourceScope *outer = scope; outer; outer = outer->parent)
            if (outer->owner && outer->owner->kind == RangeNodeBlock && same(outer->owner->name,"bindings")
                && bindingNamed(outer->owner,name->name))
                return sourceLookup(report,outer->parent,name->name,0);
    return sourceLookup(report,scope,name->name,0);
}

/* A declaration nested in a construct or an enum. */
RangeNode *nestedDeclaration(RangeNode *owner, const char *name, size_t length)
{
    for (size_t i = 0; owner && i < owner->itemCount; ++i) {
        RangeNode *item = owner->items[i];
        if ((item->kind == RangeNodeConstruct || item->kind == RangeNodeEnum) && item->name
            && !strncmp(item->name,name,length) && !item->name[length]) return item;
    }
    return NULL;
}

/* `Outer.Inner` names Inner through its owner; the first name resolves in scope. */
RangeNode *dottedLookup(SourceReport *report, SourceScope *scope, const char *name, int kind)
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
RangeNode *typePath(SourceReport *report, SourceScope *scope, RangeNode *expr)
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

const char *typePathText(SourceReport *report, RangeNode *expr)
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
int requiredPath(SourceReport *report, SourceScope *scope, RangeNode *node)
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

RangeNode *bindingNamed(const RangeNode *bindings, const char *name)
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

void diagnoseSourceNode(SourceReport *report, SourceScope *scope, RangeNode *node, int metadata)
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
        if (node->kind == RangeNodeMacro && (node->found & RangeFlagTyped)) return; /* diagnosed as it was typed, when first applied */
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
        else if (node->kind == RangeNodeMacro && node->c && !macroBuiltin(node,"literal"))
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
            node->found |= RangeFlagRequired;
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
    case RangeNodeAttribute: {
        if (same(node->name,"builtin") || same(node->name,"extern")) {
            metadata = 1; /* compiler metadata still contains source expressions */
            break;
        }
        if (node->name) {
            RangeNode *macro = sourceReference(report,scope,node,node->name,1);
            if (node->resolvedDeclaration) macro = node->resolvedDeclaration;
            metadata = macroBuiltin(macro,"literal");
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

void writeSourceDiagnostics(SourceReport *report, FILE *output)
{
    for (SourceDiagnostic *d = report->first; d; d = d->next) {
        if (d->at) fprintf(output,"%s:%d:%d: ",d->at->path,d->at->line,d->at->column);
        else fputs("compiler: ",output);
        fprintf(output,"%s[%s]: %s",d->warning == 2 ? "note" : d->warning ? "warning" : "error",d->category,d->message);
        if (d->uses > 1) fprintf(output," (%zu uses in this source)",d->uses);
        fputc('\n',output);
    }
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

/* Builtin functions are C primitives selected by name. resize, read, and write
 * act on their construct's @many member, so that construct needs exactly one. */
int slotPrimitive(const RangeNode *function)
{
    return same(function->name,"resize") || same(function->name,"read") || same(function->name,"write");
}

int appliesBuiltin(const RangeNode *node, const char *name)
{
    if (node->c) for (size_t i = 0; i < node->c->itemCount; ++i)
        if (macroBuiltin(node->c->items[i]->resolvedDeclaration,name)) return 1;
    return 0;
}

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

void diagnoseBuiltinFunctions(SourceReport *report, RangeNode *owner)
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
        if (builtinFunction(item,"print"))
            sourceDiagnostic(report,item,1,"C-implementation","builtin function 'print' writes through libSystem write in C, formatting "
                             "interpolated integers in C; at macro time it writes to the compiler's output");
        else if (builtinFunction(item,"diagnostic"))
            sourceDiagnostic(report,item,1,"C-implementation","builtin function 'diagnostic' writes its located message to standard error "
                             "and exits with status 134 in C; at macro time it fails the application; C treats a call of it as diverging");
        else if (builtinFunction(item,"warning"))
            sourceDiagnostic(report,item,1,"C-implementation","builtin function 'warning' reports a compile-time warning at the "
                             "application through C's diagnostics");
        else if (same(item->name,"="))
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

void diagnoseDuplicates(SourceReport *report)
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
