#define _XOPEN_SOURCE 700
#include "model.h"
#include <limits.h>
#include <regex.h>
#include <setjmp.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* Resolution context; ordinary Range execution is not implemented here. */
typedef struct {
    RangeArena *arena;
    RangeNode **units;
    size_t count;
    char *error;
    size_t errorSize;
    jmp_buf failure;
    RangeNode *emitted; /* declarations emitted by the running application */
    RangeNode *unit;    /* unit holding the running application's target */
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

/* Resolve declaration queries without executing the macro's deferred body. */
static RangeGraphValue graphEval(Resolver *, RangeMacroApplication *, RangeNode *);

static RangeGraphValue graphNode(RangeNode *node)
{
    return (RangeGraphValue){.kind=node ? RangeGraphNode : RangeGraphNone,.node=node};
}

static RangeGraphValue graphBinding(Resolver *vm, RangeMacroApplication *app, RangeGraphBinding *binding)
{
    if (binding->state == 2) return binding->value;
    if (binding->state == 1) fail(vm,binding->definition,"cyclic graph member '%s'",binding->definition->name);
    RangeNode *rhs = rangeNodeRHS(binding->definition);
    if (!rhs) fail(vm,binding->definition,"graph member RHS is not supported yet");
    binding->state = 1;
    binding->value = graphEval(vm,app,rhs);
    binding->state = 2;
    return binding->value;
}

static RangeGraphValue graphProperty(Resolver *vm, RangeMacroApplication *app,
                                    RangeGraphValue receiver, const char *name, RangeNode *at)
{
    if (receiver.kind == RangeGraphNodes && same(name,"first"))
        return graphNode(receiver.count ? receiver.nodes[0] : NULL);
    if (receiver.kind != RangeGraphNode) fail(vm,at,"graph value has no property '%s'",name);
    RangeNode *node = receiver.node;
    RangeNode *field = rangeGraphField(node->graphType,name);
    if (!field) fail(vm,at,"field '%s' is not declared by @type %s",name,
        node->graphType ? node->graphType->name : rangeNodeKindName(node->kind));
    if (same(name,"value") && (node->kind == RangeNodeMember || node->kind == RangeNodeLocal)) {
        if (node->kind == RangeNodeLocal) {
            for (size_t i = 0; i < app->count; ++i)
                if (app->bindings[i].definition == node) return graphBinding(vm,app,&app->bindings[i]);
        }
    }
    RangeGraphValue value = rangeGraphStoredField(vm->arena,node,name);
    if (!(field->flags & RangeFlagMany) && value.kind == RangeGraphNodes)
        return graphNode(value.count ? value.nodes[0] : NULL);
    return value;
}

static const char *graphText(Resolver *vm, RangeGraphValue value, RangeNode *at)
{
    if (value.kind == RangeGraphText) return value.text;
    if (value.kind == RangeGraphNode && value.node->kind == RangeNodeString
        && value.node->itemCount == 1 && (value.node->items[0]->flags & RangeFlagLiteral))
        return value.node->items[0]->name;
    fail(vm,at,"graph filter requires a string name");
    return NULL;
}

static RangeGraphValue graphEval(Resolver *vm, RangeMacroApplication *app, RangeNode *node)
{
    switch (node->kind) {
    case RangeNodeEnvironment:
        return graphProperty(vm,app,graphNode(app->target),node->name,node);
    case RangeNodeMemberAccess:
        return graphProperty(vm,app,graphEval(vm,app,node->a),node->name,node);
    case RangeNodeName:
        for (size_t i = 0; i < app->count; ++i)
            if (same(app->bindings[i].definition->name,node->name))
                return graphBinding(vm,app,&app->bindings[i]);
        fail(vm,node,"unresolved graph member '%s'",node->name);
        break;
    case RangeNodeInteger: case RangeNodeBool: case RangeNodeString:
        return graphNode(node);
    case RangeNodeCall: {
        if (!node->a || node->a->kind != RangeNodeMemberAccess || !same(node->a->name,"filter")
            || node->itemCount != 1 || !same(node->items[0]->name,"named"))
            fail(vm,node,"graph resolution currently supports filter(named:) calls only");
        RangeGraphValue list = graphEval(vm,app,node->a->a);
        if (list.kind != RangeGraphNodes) fail(vm,node,"graph filter requires member nodes");
        const char *name = graphText(vm,graphEval(vm,app,node->items[0]->a),node);
        RangeGraphValue result = {.kind=RangeGraphNodes};
        result.nodes = rangeArenaAllocate(vm->arena,list.count * sizeof(*result.nodes));
        for (size_t i = 0; i < list.count; ++i)
            if (same(list.nodes[i]->name,name)) result.nodes[result.count++] = list.nodes[i];
        return result;
    }
    default: fail(vm,node,"unsupported graph expression '%s'",rangeNodeKindName(node->kind));
    }
    return (RangeGraphValue){0};
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
        if (!candidate->b || !type || candidate->b->resolvedDeclaration != type) continue;
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

static void resolveGraphTarget(Resolver *vm, RangeNode *target)
{
    if (!target->graphType) return;
    RangeNode *attributes = target->c;
    if (attributes) for (size_t a = 0; a < attributes->itemCount; ++a) {
        RangeNode *attribute = attributes->items[a], *unit = NULL;
        attribute->macroApplication = NULL;
        if (same(attribute->name,"builtin")
            || (target->kind == RangeNodeFunction && same(attribute->name,"extern"))) continue;
        RangeNode *macro = resolveMacroDeclaration(vm,attribute,target,&unit);
        if (macroBuiltin(macro,"literal")) continue; /* registered compiler primitive */
        if (attribute->itemCount || macro->itemCount)
            fail(vm,attribute,"parameterized macro graph resolution is not implemented");
        RangeMacroApplication *app = rangeArenaAllocate(vm->arena,sizeof(*app));
        *app = (RangeMacroApplication){.declaration=macro,.target=target,.unit=unit,.attribute=attribute};
        if (macro->a) {
            app->bindings = rangeArenaAllocate(vm->arena,macro->a->itemCount * sizeof(*app->bindings));
            for (size_t i = 0; i < macro->a->itemCount; ++i) {
                RangeNode *member = macro->a->items[i];
                if (member->kind != RangeNodeLocal) continue;
                for (size_t j = 0; j < app->count; ++j)
                    if (same(app->bindings[j].definition->name,member->name))
                        fail(vm,member,"duplicate graph member '%s'",member->name);
                app->bindings[app->count++] = (RangeGraphBinding){.definition=member};
            }
        }
        attribute->resolvedDeclaration = macro;
        attribute->macroApplication = app;
        for (size_t i = 0; i < app->count; ++i)
            if (rangeNodeHasContextReference(app->bindings[i].definition))
                (void)graphBinding(vm,app,&app->bindings[i]);
    }
    if (target->kind == RangeNodeConstruct)
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
        : (node->kind == RangeNodeLocal || node->kind == RangeNodeMember) ? "Member" : NULL;
    if (type) {
        node->graphType = rangeGraphType(vm->arena,type);
        if (!node->graphType) fail(vm,node,"missing @type %s",type);
    }
    if (node->graphType) {
        type = node->graphType->name;
        /* These are physical storage adapters, not a list of permitted fields. */
        static const char *const storage[] = {"name","target","members","graph","macros","generics","value",
            "receiver","parameters","output","body","cases"};
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

static int literalMatch(Resolver *vm, RangeNode *at, const char *pattern, const char *input)
{
    regex_t regex;
    int code = regcomp(&regex,pattern,REG_EXTENDED);
    char detail[256];
    if (code) {
        regerror(code,&regex,detail,sizeof(detail));
        fail(vm,at,"invalid literal regex: %s",detail);
    }
    regmatch_t match;
    code = input ? regexec(&regex,input,1,&match,0) : REG_NOMATCH;
    if (code && code != REG_NOMATCH) {
        regerror(code,&regex,detail,sizeof(detail));
        regfree(&regex);
        fail(vm,at,"literal regex matching failed: %s",detail);
    }
    int matched = !code && match.rm_so == 0 && match.rm_eo >= 0
        && (size_t)match.rm_eo == strlen(input);
    regfree(&regex);
    return matched;
}

/* A builtin macro is `@builtin macro name`; its name selects the C primitive. */
static int macroBuiltin(RangeNode *node, const char *name)
{
    if (!node || node->kind != RangeNodeMacro || !node->c || !same(node->name,name)) return 0;
    for (size_t i = 0; i < node->c->itemCount; ++i)
        if (same(node->c->items[i]->name,"builtin")) return 1;
    return 0;
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

static void validateTargetReferences(Resolver *vm, RangeNode *node, RangeNode *type)
{
    if (!node || node->kind == RangeNodeEmission) return; /* deferred code */
    if (node->kind == RangeNodeEnvironment) {
        if (!type) fail(vm,node,"#%s requires a declared macro target",node->name);
        if (!rangeGraphField(type,node->name))
            fail(vm,node,"field '%s' is not declared by @type %s",node->name,type->name);
    }
    validateTargetReferences(vm,node->a,type); validateTargetReferences(vm,node->b,type);
    validateTargetReferences(vm,node->c,type); validateTargetReferences(vm,node->generics,type);
    for (size_t i = 0; i < node->itemCount; ++i) validateTargetReferences(vm,node->items[i],type);
}

static void linkGrammarNodes(Resolver *vm, RangeNode *node)
{
    if (!node) return;
    node->grammarDefinition = node->graphType ? node->graphType->resolvedDeclaration : NULL;
    if (node->kind == RangeNodeMacro) {
        RangeNode *shape = NULL;
        if (node->b) {
            if (node->b->flags || node->b->generics)
                fail(vm,node->b,"macro target requires one declaration type");
            shape = rangeGraphType(vm->arena,node->b->name);
            if (!shape) fail(vm,node->b,"unknown macro target type '%s'",node->b->name);
            node->b->resolvedDeclaration = shape->resolvedDeclaration ? shape->resolvedDeclaration : shape;
        }
        validateTargetReferences(vm,node->a,shape);
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
            if (field->kind != RangeNodeMember || !rangeGraphField(shape,field->name))
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
            if (construct->kind != RangeNodeConstruct || !isLanguageNode(construct) || !construct->c) continue;
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

static void resolveLiteralDefaults(Resolver *vm, RangeNode *node)
{
    if (!node) return;
    if (node->kind == RangeNodeInteger || node->kind == RangeNodeBool) {
        const char *spelling = node->kind == RangeNodeBool ? (node->integer ? "true" : "false") : node->name;
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

/* Link plain top-level output references without replacing their source nodes.
 * Missing declarations and specialization remain deferred during inspection. */
static void resolveGraphOutputs(Resolver *vm)
{
    for (size_t u = 0; u < vm->count; ++u) {
        for (size_t i = 0; i < vm->units[u]->itemCount; ++i) {
            RangeNode *function = vm->units[u]->items[i];
            if (function->kind != RangeNodeFunction || function->generics) continue;
            RangeNode *output = function->b;
            if (!output || output->kind != RangeNodeName || output->flags || output->generics) continue;
            RangeNode *declaration = NULL;
            for (size_t v = 0; v < vm->count; ++v) {
                for (size_t j = 0; j < vm->units[v]->itemCount; ++j) {
                    RangeNode *candidate = vm->units[v]->items[j];
                    if (candidate->kind != RangeNodeConstruct || !same(candidate->name,output->name)) continue;
                    if (declaration) fail(vm,output,"ambiguous graph output '%s'",output->name);
                    declaration = candidate;
                }
            }
            output->resolvedDeclaration = declaration;
        }
    }
}

static int resolveGraphApplications(RangeArena *arena, RangeNode **units, size_t count,
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
        resolveGraphOutputs(vm);
        for (size_t u = 0; u < count; ++u)
            for (size_t i = 0; i < units[u]->itemCount; ++i) resolveGraphTarget(vm,units[u]->items[i]);
        registerLiteralDefaults(vm);
        for (size_t u = 0; u < count; ++u) resolveLiteralDefaults(vm,units[u]);
        ok = 1;
    }
    free(vm);
    return ok;
}

/* Compile-time validation works on graph values, never concrete type names.
 * Runtime execution, construction, and language type checking are separate. */
typedef struct MetaLocal {
    const char *name;
    RangeGraphValue value;
    int mutable;
    struct MetaLocal *next;
} MetaLocal;
typedef struct MetaScope {
    struct MetaScope *parent;
    MetaLocal *locals;
    RangeMacroApplication *application;
} MetaScope;
typedef struct {
    Resolver *vm;
    unsigned steps;
    unsigned depth;
    int splicing; /* evaluating a #name splice inside #graph */
} MetaEval;

static void metaStep(MetaEval *eval, RangeNode *at)
{
    if (++eval->steps > 100000) fail(eval->vm,at,"compile-time evaluation step limit exceeded");
}

static RangeGraphValue metaScalar(MetaEval *eval, RangeNode *at, RangeNodeKind kind, long long value)
{
    RangeNode *node = rangeNodeCreate(eval->vm->arena,kind,at->path,at->line,at->column);
    node->integer = value;
    return graphNode(node);
}

static long long metaNumber(MetaEval *eval, RangeGraphValue value, RangeNode *at)
{
    if (value.kind != RangeGraphNode || value.node->kind != RangeNodeInteger)
        fail(eval->vm,at,"compile-time arithmetic requires numeric graph values");
    return value.node->integer;
}

static int metaBoolean(MetaEval *eval, RangeGraphValue value, RangeNode *at)
{
    if (value.kind != RangeGraphNode || value.node->kind != RangeNodeBool)
        fail(eval->vm,at,"compile-time condition requires a boolean graph value");
    return value.node->integer != 0;
}

static MetaLocal *metaLocal(MetaScope *scope, const char *name)
{
    for (; scope; scope = scope->parent)
        for (MetaLocal *local = scope->locals; local; local = local->next)
            if (same(local->name,name)) return local;
    return NULL;
}

static void metaBind(MetaEval *eval, MetaScope *scope, RangeNode *node, RangeGraphValue value)
{
    for (MetaLocal *local = scope->locals; local; local = local->next)
        if (same(local->name,node->name)) fail(eval->vm,node,"duplicate compile-time local '%s'",node->name);
    MetaLocal *local = rangeArenaAllocate(eval->vm->arena,sizeof(*local));
    *local = (MetaLocal){.name=node->name,.value=value,.mutable=(node->flags & RangeFlagMutable)!=0,.next=scope->locals};
    scope->locals = local;
}

static RangeNode *metaDeclaration(MetaEval *eval, RangeNode *at, RangeNodeKind kind, const char *name)
{
    RangeNode *found = NULL;
    for (size_t u = 0; u < eval->vm->count; ++u) for (size_t i = 0; i < eval->vm->units[u]->itemCount; ++i) {
        RangeNode *node = eval->vm->units[u]->items[i];
        if (node->kind != kind || !same(node->name,name)) continue;
        if (kind == RangeNodeMacro && node->b) continue; /* standalone effect invocation */
        if (found) fail(eval->vm,at,"ambiguous compile-time declaration '%s'",name);
        found = node;
    }
    if (!found) fail(eval->vm,at,"unresolved compile-time declaration '%s'",name);
    at->resolvedDeclaration = found;
    return found;
}

static RangeGraphValue metaExpression(MetaEval *, MetaScope *, RangeNode *);
static int metaStatement(MetaEval *, MetaScope *, RangeNode *, RangeGraphValue *);

/* A splice is a #name chain such as #element or #element.name; the whole
 * chain runs at macro time. */
static int spliceChain(const RangeNode *node)
{
    while (node && (node->kind == RangeNodeMemberAccess || node->kind == RangeNodeCall)) node = node->a;
    return node && node->kind == RangeNodeEnvironment;
}

/* A spliced value becomes the source a person would have written there. */
static RangeNode *spliceNode(MetaEval *eval, RangeNode *at, RangeGraphValue value)
{
    RangeArena *arena = eval->vm->arena;
    if (value.kind == RangeGraphNodes)
        fail(eval->vm,at,"cannot splice a list of %zu declarations",value.count);
    if (value.kind == RangeGraphNone) fail(eval->vm,at,"splice has no value");
    RangeNode *node = value.kind == RangeGraphNode ? value.node : NULL;
    if (node && (node->kind == RangeNodeInteger || node->kind == RangeNodeBool || node->kind == RangeNodeString)) {
        RangeNode *copy = rangeArenaAllocate(arena,sizeof(*copy));
        *copy = *node;
        copy->path = at->path; copy->line = at->line; copy->column = at->column;
        return copy;
    }
    const char *name = value.kind == RangeGraphText ? value.text : node->name;
    if (!name) fail(eval->vm,at,"cannot splice an unnamed %s",rangeNodeKindName(node->kind));
    RangeNode *reference = rangeNodeCreate(arena,RangeNodeName,at->path,at->line,at->column);
    reference->name = name;
    reference->resolvedDeclaration = node;
    return reference;
}

/* `let x: #element` becomes `let x: Element`: a spliced name in a
 * declaration RHS takes the type position, as the parser would place it. */
static void spliceDeclarationType(RangeNode *copy, const RangeNode *original)
{
    if ((copy->kind != RangeNodeMember && copy->kind != RangeNodeLocal) || copy->typeName
        || copy->itemCount != 1 || copy->items[0]->kind != RangeNodeArgument
        || !spliceChain(original->items[0]->a) || copy->items[0]->a->kind != RangeNodeName) return;
    RangeNode *reference = copy->items[0]->a;
    copy->typeName = reference->name;
    copy->itemCount = 0;
    if (!(copy->flags & ~RangeFlagMutable)) copy->rhsReference = reference;
}

/* Copy one quoted declaration for this application, filling its splices.
 * Nested macro declarations keep their own splices for their own runs. */
static RangeNode *emitNode(MetaEval *eval, MetaScope *scope, RangeNode *node, int splice)
{
    if (!node) return NULL;
    RangeNode *attribute = scope->application->attribute;
    if (splice && spliceChain(node)) {
        int outer = eval->splicing;
        eval->splicing = 1;
        RangeGraphValue value = metaExpression(eval,scope,node);
        eval->splicing = outer;
        RangeNode *spliced = spliceNode(eval,node,value);
        spliced->emittedBy = attribute;
        return spliced;
    }
    if (node->kind == RangeNodeMacro) splice = 0;
    RangeNode *copy = rangeArenaAllocate(eval->vm->arena,sizeof(*copy));
    *copy = *node;
    copy->emittedBy = attribute;
    copy->resolvedDeclaration = NULL;
    copy->macroApplication = NULL;
    copy->items = NULL; copy->itemCount = 0; copy->itemCapacity = 0;
    copy->a = emitNode(eval,scope,node->a,splice);
    copy->b = emitNode(eval,scope,node->b,splice);
    copy->c = emitNode(eval,scope,node->c,splice);
    copy->generics = emitNode(eval,scope,node->generics,splice);
    copy->annotations = emitNode(eval,scope,node->annotations,splice);
    copy->rhsReference = emitNode(eval,scope,node->rhsReference,splice);
    for (size_t i = 0; i < node->itemCount; ++i)
        rangeNodeAppend(eval->vm->arena,copy,emitNode(eval,scope,node->items[i],splice));
    if (splice) spliceDeclarationType(copy,node);
    return copy;
}

static RangeGraphValue metaCall(MetaEval *eval, MetaScope *scope, RangeNode *call)
{
    if (!call->a || call->a->kind != RangeNodeName || call->a->generics)
        fail(eval->vm,call,"compile-time calls require a plain function reference");
    RangeNode *function = metaDeclaration(eval,call->a,RangeNodeFunction,call->a->name);
    if (!function->a || function->generics || function->flags || function->typeName
        || (function->c && function->c->itemCount))
        fail(eval->vm,call,"unsupported compile-time function declaration");
    if (call->itemCount != function->itemCount)
        fail(eval->vm,call,"compile-time call argument count differs from '%s'",function->name);
    if (++eval->depth > 64) fail(eval->vm,call,"compile-time call depth exceeded");
    MetaScope arguments = {0};
    // Evaluate once, in source order. Labels select actual parameter declarations.
    for (size_t i = 0; i < call->itemCount; ++i) {
        RangeNode *argument = call->items[i], *parameter = NULL;
        for (size_t j = 0; j < function->itemCount; ++j)
            if (same(argument->name,function->items[j]->name)) parameter = function->items[j];
        if (!parameter || parameter->flags || parameter->itemCount)
            fail(eval->vm,argument,"compile-time call requires an explicit label for each plain parameter");
        metaBind(eval,&arguments,parameter,metaExpression(eval,scope,argument->a));
    }
    RangeGraphValue result = {0};
    if (!metaStatement(eval,&arguments,function->a,&result))
        fail(eval->vm,function,"compile-time function did not return a value");
    --eval->depth;
    return result;
}

static RangeGraphValue metaExpression(MetaEval *eval, MetaScope *scope, RangeNode *node)
{
    if (!node) return (RangeGraphValue){0};
    metaStep(eval,node);
    switch (node->kind) {
    case RangeNodeInteger: case RangeNodeBool: case RangeNodeString: return graphNode(node);
    case RangeNodeName: {
        MetaLocal *local = metaLocal(scope,node->name);
        if (!local) fail(eval->vm,node,"unresolved compile-time local '%s'",node->name);
        return local->value;
    }
    case RangeNodeEnvironment: {
        if (!scope->application) fail(eval->vm,node,"graph context is unavailable in this function");
        if (!eval->splicing) return graphEval(eval->vm,scope->application,node);
        // Inside #graph, #name is a macro local or a target field, never both.
        MetaLocal *local = metaLocal(scope,node->name);
        RangeNode *field = rangeGraphField(scope->application->target->graphType,node->name);
        if (local && field) fail(eval->vm,node,"#%s names both a macro local and a target field",node->name);
        if (local) return local->value;
        if (!field) fail(eval->vm,node,"#%s is neither a macro local nor a target field",node->name);
        return graphEval(eval->vm,scope->application,node);
    }
    case RangeNodeEmission:
        if (!scope->application || !eval->vm->emitted)
            fail(eval->vm,node,"#graph requires a macro application");
        for (size_t i = 0; i < node->b->itemCount; ++i)
            rangeNodeAppend(eval->vm->arena,eval->vm->emitted,emitNode(eval,scope,node->b->items[i],1));
        return (RangeGraphValue){0};
    case RangeNodeMemberAccess: {
        RangeGraphValue receiver = metaExpression(eval,scope,node->a);
        if (same(node->name,"isTarget")) {
            if (receiver.kind != RangeGraphNone && receiver.kind != RangeGraphNode)
                fail(eval->vm,node,"isTarget requires a selected graph node");
            return metaScalar(eval,node,RangeNodeBool,receiver.kind == RangeGraphNode);
        }
        if (!scope->application) fail(eval->vm,node,"graph reflection requires a macro context");
        RangeGraphValue value = graphProperty(eval->vm,scope->application,receiver,node->name,node);
        if (same(node->name,"value") && receiver.kind == RangeGraphNode
            && receiver.node->kind == RangeNodeMember && value.kind == RangeGraphNode) {
            // A declaration initializer is evaluated outside the inspecting
            // macro's locals. Unsupported declaration-name lookup fails there.
            MetaScope initializer = {0};
            return metaExpression(eval,&initializer,value.node);
        }
        return value;
    }
    case RangeNodeCall:
        if (node->a && node->a->kind == RangeNodeMemberAccess && same(node->a->name,"filter")) {
            if (node->itemCount != 1 || !same(node->items[0]->name,"named"))
                fail(eval->vm,node,"graph filter requires one named argument");
            RangeGraphValue list = metaExpression(eval,scope,node->a->a);
            if (list.kind != RangeGraphNodes) fail(eval->vm,node,"graph filter requires member nodes");
            const char *name = graphText(eval->vm,metaExpression(eval,scope,node->items[0]->a),node);
            RangeGraphValue result = {.kind=RangeGraphNodes};
            result.nodes = rangeArenaAllocate(eval->vm->arena,list.count * sizeof(*result.nodes));
            for (size_t i = 0; i < list.count; ++i)
                if (same(list.nodes[i]->name,name)) result.nodes[result.count++] = list.nodes[i];
            return result;
        }
        return metaCall(eval,scope,node);
    case RangeNodeUnary: {
        RangeGraphValue operand = metaExpression(eval,scope,node->a);
        if (same(node->name,"!")) return metaScalar(eval,node,RangeNodeBool,!metaBoolean(eval,operand,node));
        long long value = metaNumber(eval,operand,node);
        if (!same(node->name,"-")) fail(eval->vm,node,"unsupported compile-time unary operator");
        if (value == LLONG_MIN) fail(eval->vm,node,"compile-time numeric storage overflow");
        return metaScalar(eval,node,RangeNodeInteger,-value);
    }
    case RangeNodeBinary: {
        RangeGraphValue left = metaExpression(eval,scope,node->a);
        if (same(node->name,"&&") || same(node->name,"||")) {
            int value = metaBoolean(eval,left,node);
            if ((same(node->name,"&&") && value) || (same(node->name,"||") && !value))
                value = metaBoolean(eval,metaExpression(eval,scope,node->b),node);
            return metaScalar(eval,node,RangeNodeBool,value);
        }
        RangeGraphValue right = metaExpression(eval,scope,node->b);
        if (same(node->name,"==") || same(node->name,"!=")) {
            int equal = left.kind == right.kind;
            if (equal && left.kind == RangeGraphNode) {
                RangeNode *a=left.node, *b=right.node;
                if (a->kind == b->kind && (a->kind == RangeNodeInteger || a->kind == RangeNodeBool))
                    equal = a->integer == b->integer;
                else equal = a == b;
            } else if (equal && left.kind != RangeGraphNone)
                fail(eval->vm,node,"unsupported compile-time equality operands");
            return metaScalar(eval,node,RangeNodeBool,same(node->name,"==") ? equal : !equal);
        }
        long long a=metaNumber(eval,left,node), b=metaNumber(eval,right,node), value=0;
        if (same(node->name,"<")) return metaScalar(eval,node,RangeNodeBool,a < b);
        if (same(node->name,">")) return metaScalar(eval,node,RangeNodeBool,a > b);
        if (same(node->name,"<=")) return metaScalar(eval,node,RangeNodeBool,a <= b);
        if (same(node->name,">=")) return metaScalar(eval,node,RangeNodeBool,a >= b);
        int overflow = 0;
        if (same(node->name,"+")) overflow = __builtin_add_overflow(a,b,&value);
        else if (same(node->name,"-")) overflow = __builtin_sub_overflow(a,b,&value);
        else if (same(node->name,"*")) overflow = __builtin_mul_overflow(a,b,&value);
        else if (same(node->name,"/")) {
            if (!b) fail(eval->vm,node,"compile-time division by zero");
            if (a == LLONG_MIN && b == -1) overflow = 1;
            else value = a / b;
        } else fail(eval->vm,node,"unsupported compile-time binary operator");
        if (overflow) fail(eval->vm,node,"compile-time numeric storage overflow");
        return metaScalar(eval,node,RangeNodeInteger,value);
    }
    case RangeNodeAttribute: {
        RangeNode *macro = metaDeclaration(eval,node,RangeNodeMacro,node->name);
        if (!macroBuiltin(macro,"diagnostic") || macro->a || macro->generics || macro->itemCount != 1)
            fail(eval->vm,node,"unsupported compile-time macro effect");
        if (node->itemCount != 1 || (node->items[0]->name && !same(node->items[0]->name,macro->items[0]->name)))
            fail(eval->vm,node,"diagnostic builtin requires one message argument");
        const char *message = graphText(eval->vm,metaExpression(eval,scope,node->items[0]->a),node);
        fail(eval->vm,node,"%s",message);
    }
    default: fail(eval->vm,node,"unsupported compile-time expression '%s'",rangeNodeKindName(node->kind));
    }
}

static int metaStatement(MetaEval *eval, MetaScope *scope, RangeNode *node, RangeGraphValue *returned)
{
    if (!node) return 0;
    metaStep(eval,node);
    if (node->annotations) fail(eval->vm,node,"statement annotations are not supported in compile-time validation");
    switch (node->kind) {
    case RangeNodeBlock: {
        MetaScope block = {.parent=scope,.application=scope->application};
        for (size_t i = 0; i < node->itemCount; ++i)
            if (metaStatement(eval,&block,node->items[i],returned)) return 1;
        return 0;
    }
    case RangeNodeLocal: {
        if (node->flags & ~(RangeFlagMutable|RangeFlagApplication))
            fail(eval->vm,node,"unsupported compile-time local declaration");
        if ((node->flags & RangeFlagApplication) && node->typeName && !node->a) {
            // Declaration RHS applications use the parser's type-position storage.
            // Resolve the name as a function; no type-name cast or scalar shortcut.
            RangeNode target = {.kind=RangeNodeName,.name=node->typeName,.path=node->path,
                .line=node->line,.column=node->column,.generics=node->generics};
            RangeNode call = {.kind=RangeNodeCall,.a=&target,.items=node->items,.itemCount=node->itemCount,
                .path=node->path,.line=node->line,.column=node->column};
            metaBind(eval,scope,node,metaCall(eval,scope,&call));
            return 0;
        }
        RangeNode *rhs = rangeNodeRHS(node);
        if (!rhs) fail(eval->vm,node,"compile-time local requires an expression; construction is not implemented");
        metaBind(eval,scope,node,metaExpression(eval,scope,rhs));
        return 0;
    }
    case RangeNodeAssign: {
        if (!node->a || node->a->kind != RangeNodeName) fail(eval->vm,node,"compile-time assignment requires a local name");
        MetaLocal *local = metaLocal(scope,node->a->name);
        if (!local || !local->mutable) fail(eval->vm,node,"compile-time assignment requires a state local");
        local->value = metaExpression(eval,scope,node->b);
        return 0;
    }
    case RangeNodeIf:
        return metaStatement(eval,scope,metaBoolean(eval,metaExpression(eval,scope,node->a),node) ? node->b : node->c,returned);
    case RangeNodeWhile:
        while (metaBoolean(eval,metaExpression(eval,scope,node->a),node))
            if (metaStatement(eval,scope,node->b,returned)) return 1;
        return 0;
    case RangeNodeReturn:
        *returned = metaExpression(eval,scope,node->a);
        return 1;
    case RangeNodeExpressionStatement:
        (void)metaExpression(eval,scope,node->a);
        return 0;
    default: fail(eval->vm,node,"unsupported compile-time statement '%s'",rangeNodeKindName(node->kind));
    }
}

static int compilerAttribute(RangeNode *target, RangeNode *attribute)
{
    return same(attribute->name,"builtin")
        || (target->kind == RangeNodeFunction && same(attribute->name,"extern"))
        || macroBuiltin(attribute->resolvedDeclaration,"literal");
}

/* Run one application. Its #graph output is collected and returned only when
 * the whole body succeeds, so a failed application emits nothing. */
static RangeNode *runMacroApplication(Resolver *vm, RangeNode *attribute)
{
    RangeMacroApplication *app = attribute->macroApplication;
    if (!app) fail(vm,attribute,"macro application was not resolved");
    if (app->declaration->c) for (size_t j = 0; j < app->declaration->c->itemCount; ++j)
        if (same(app->declaration->c->items[j]->name,"builtin")) {
            if (!macroBuiltin(app->declaration,"literal") && !macroBuiltin(app->declaration,"diagnostic"))
                fail(vm,attribute,"no C primitive is implemented for builtin macro '%s'",app->declaration->name);
            fail(vm,attribute,"builtin target effects are not supported by compile-time validation");
        }
    RangeNode *emitted = rangeNodeCreate(vm->arena,RangeNodeBlock,attribute->path,attribute->line,attribute->column);
    vm->emitted = emitted;
    MetaEval eval = {.vm=vm};
    MetaScope scope = {.application=app};
    RangeGraphValue returned = {0};
    (void)metaStatement(&eval,&scope,app->declaration->a,&returned);
    vm->emitted = NULL;
    return emitted;
}

/* Emitted and written declarations join the graph through the same path as
 * parsed source: shape, grammar identity, macro targets, literal defaults. */
static void resolveMergedNode(Resolver *vm, RangeNode *node)
{
    validateGraphShape(vm,node,node->source);
    linkGrammarNodes(vm,node);
    resolveGraphTarget(vm,node);
    resolveLiteralDefaults(vm,node);
}

/* An extension names its declaration; its members move there and resolve in
 * that declaration's scope, so an emitted `Element` finds Array<Element>. */
static void mergeExtension(Resolver *vm, RangeNode *extension)
{
    RangeNode *subject = extension->a, *declaration = NULL;
    if (!subject || subject->kind != RangeNodeName)
        fail(vm,extension,"#name splices are only valid inside #graph");
    for (size_t u = 0; u < vm->count; ++u) for (size_t i = 0; i < vm->units[u]->itemCount; ++i) {
        RangeNode *candidate = vm->units[u]->items[i];
        if (!same(candidate->name,subject->name)) continue;
        if (candidate->kind == RangeNodeEnum)
            fail(vm,subject,"extending enum '%s' is not implemented",subject->name);
        if (candidate->kind != RangeNodeConstruct) continue;
        if (declaration) fail(vm,subject,"ambiguous extension of '%s'",subject->name);
        declaration = candidate;
    }
    if (!declaration) fail(vm,subject,"extension of undeclared '%s'",subject->name);
    for (size_t i = 0; i < extension->itemCount; ++i) {
        RangeNode *item = extension->items[i];
        if (item->kind == RangeNodeFunction) item->typeName = declaration->name;
        rangeNodeAppend(vm->arena,declaration,item);
        resolveMergedNode(vm,item);
    }
    extension->itemCount = 0;
    extension->resolvedDeclaration = declaration;
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

typedef struct {
    RangeArena *arena;
    RangeNode **units;
    size_t count;
    SourceDiagnostic *first, *last;
    size_t errors, warnings;
} SourceReport;

typedef struct SourceScope {
    RangeNode *owner;
    struct SourceScope *parent;
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
    if (warning) ++report->warnings;
    else ++report->errors;
}

static int sourceDeclaration(RangeNode *node)
{
    return node->kind == RangeNodeConstruct || node->kind == RangeNodeEnum
        || node->kind == RangeNodeFunction || node->kind == RangeNodeMacro
        || node->kind == RangeNodeMember || node->kind == RangeNodeParameter || node->kind == RangeNodeLocal;
}

static int sourceMatches(RangeNode *node, const char *name, int kind)
{
    if (!sourceDeclaration(node) || !same(node->name,name)) return 0;
    if (kind == 1) return node->kind == RangeNodeMacro;
    if (kind == 2) return node->kind == RangeNodeConstruct || node->kind == RangeNodeEnum;
    return node->kind != RangeNodeMacro;
}

static RangeNode *sourceLookup(SourceReport *report, SourceScope *scope,
                               const char *name, int kind)
{
    for (; scope; scope = scope->parent) {
        RangeNode *owner = scope->owner;
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

static RangeNode *sourceReference(SourceReport *report, SourceScope *scope,
                                  RangeNode *at, const char *name, int kind)
{
    if (!name || !*name) return NULL;
    const char *separator = strchr(name,'|');
    if (separator) {
        const char *left = rangeArenaIntern(report->arena,name,(size_t)(separator-name));
        (void)sourceReference(report,scope,at,left,kind);
        (void)sourceReference(report,scope,at,separator+1,kind);
        sourceDiagnostic(report,at,0,"not-implemented","union type resolution is not implemented");
        return NULL;
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

static void diagnoseType(SourceReport *report, SourceScope *scope, RangeNode *node)
{
    if (!node) return;
    (void)sourceReference(report,scope,node,node->name,2);
    diagnoseSourceNode(report,scope,node->generics,0);
    diagnoseType(report,scope,node->a); /* an explicit macro result type */
}

static void diagnoseSourceNode(SourceReport *report, SourceScope *scope, RangeNode *node, int metadata)
{
    if (!node) return;
    switch (node->kind) {
    case RangeNodeUnit: case RangeNodeBlock: {
        SourceScope block = {.owner=node,.parent=scope};
        for (size_t i = 0; i < node->itemCount; ++i) diagnoseSourceNode(report,&block,node->items[i],metadata);
        return;
    }
    case RangeNodeConstruct: case RangeNodeEnum: case RangeNodeFunction: case RangeNodeMacro: {
        SourceScope declaration = {.owner=node,.parent=scope};
        if (node->kind == RangeNodeFunction)
            (void)sourceReference(report,scope,node,node->typeName,2);
        if (node->kind == RangeNodeFunction || node->kind == RangeNodeMacro) diagnoseType(report,&declaration,node->b);
        if (node->kind == RangeNodeMacro && node->c && !macroBuiltin(node,"literal") && !macroBuiltin(node,"diagnostic"))
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
    case RangeNodeMember: case RangeNodeLocal: {
        RangeNode *declaration = sourceReference(report,scope,node,node->typeName,
            node->generics || (node->flags & RangeFlagOptional) ? 2 : 0);
        if (declaration && (node->flags & RangeFlagApplication)
            && (declaration->kind == RangeNodeConstruct || declaration->kind == RangeNodeEnum))
            sourceDiagnostic(report,node,0,"not-implemented","value construction for '%s' is not implemented",node->typeName);
        break;
    }
    case RangeNodeName:
        (void)sourceReference(report,scope,node,node->name,0);
        break;
    case RangeNodeMemberAccess:
        if (same(node->name,"first") || same(node->name,"isTarget"))
            sourceDiagnostic(report,node,1,"C-implementation","'.%s' is hard-coded in C; Range member dispatch is not implemented",node->name);
        break;
    case RangeNodeCall:
        if (node->a && node->a->kind == RangeNodeMemberAccess) {
            if (same(node->a->name,"filter") && node->itemCount == 1 && same(node->items[0]->name,"named"))
                sourceDiagnostic(report,node,1,"C-implementation","'filter(named:)' is hard-coded in C; Range method dispatch is not implemented");
            else sourceDiagnostic(report,node,0,"not-implemented","method call resolution for '%s' is not implemented",node->a->name);
        } else if (node->a && node->a->kind == RangeNodeName) {
            RangeNode *declaration = sourceLookup(report,scope,node->a->name,0);
            if (declaration && (declaration->kind == RangeNodeConstruct || declaration->kind == RangeNodeEnum))
                sourceDiagnostic(report,node,0,"not-implemented","value construction for '%s' is not implemented",node->a->name);
        }
        break;
    case RangeNodeAttribute: {
        if (same(node->name,"builtin") || same(node->name,"extern")) {
            metadata = 1; /* compiler metadata still contains source expressions */
            break;
        }
        if (node->name) {
            RangeNode *macro = sourceReference(report,scope,node,node->name,1);
            if (node->resolvedDeclaration) macro = node->resolvedDeclaration;
            metadata = macroBuiltin(macro,"literal") || macroBuiltin(macro,"diagnostic");
        }
        break;
    }
    case RangeNodeInteger:
        if (!metadata) sourceDiagnostic(report,node,1,"C-implementation",
            "numeric literal values use C signed 64-bit storage; Range literal materialization is not implemented");
        break;
    case RangeNodeBool:
        if (!metadata) sourceDiagnostic(report,node,1,"C-implementation",
            "boolean literal recognition and values are hard-coded in C; Range literal materialization is not implemented");
        break;
    case RangeNodeString:
        if (!metadata) sourceDiagnostic(report,node,1,"C-implementation",
            "string literal values are supplied by C; Range literal materialization is not implemented");
        break;
    case RangeNodeUnary: case RangeNodeBinary:
        sourceDiagnostic(report,node,1,"C-implementation",
            "operator '%s' uses the C scalar evaluator; Range operator dispatch is not implemented",node->name);
        break;
    case RangeNodeEmission: case RangeNodeExtension:
        return; /* quoted and extension code is checked where it lands */
    case RangeNodeClosure: case RangeNodeSwitch: case RangeNodeSyntaxTemplate:
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
        fprintf(output,"%s[%s]: %s",d->warning ? "warning" : "error",d->category,d->message);
        if (d->uses > 1) fprintf(output," (%zu uses in this source)",d->uses);
        fputc('\n',output);
    }
}

/* Macro application: written extensions merge first, then every application
 * runs once and its #graph output merges before the next round. Applications
 * introduced by emitted code run in a later round. This discovery order is a
 * bootstrap stand-in: the accepted design is a Datalog scheduler that orders
 * applications by what they read and write, reruns only reads a write changes,
 * and rejects cycles through absence or whole-list reads. */
enum { RangeMacroRounds = 16 };

/* Without a report, the first failure stops application (tests). With one,
 * each failure is recorded and the remaining applications still run. */
static void guarded(Resolver *vm, SourceReport *report, const char *category,
                    void (*step)(Resolver *, RangeNode *), RangeNode *node)
{
    if (!report) { step(vm,node); return; }
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

static int applyTarget(Resolver *vm, SourceReport *report, RangeNode *unit,
                       RangeNode *target, size_t *checked)
{
    if (!target->graphType) return 0;
    int ran = 0;
    if (target->c) for (size_t i = 0; i < target->c->itemCount; ++i) {
        RangeNode *attribute = target->c->items[i];
        if (compilerAttribute(target,attribute)) continue;
        // An unresolved application here comes from a merge that already failed.
        RangeMacroApplication *app = attribute->macroApplication;
        if (!app || app->applied) continue;
        app->applied = 1;
        ran = 1;
        ++*checked;
        vm->unit = unit;
        guarded(vm,report,"macro-validation",applyAndMerge,attribute);
    }
    // Members merged during this round wait for the next one.
    if (target->kind == RangeNodeConstruct)
        for (size_t i = 0, n = target->itemCount; i < n; ++i)
            ran |= applyTarget(vm,report,unit,target->items[i],checked);
    return ran;
}

static void applyMacros(Resolver *vm, SourceReport *report, size_t *checked)
{
    for (size_t u = 0; u < vm->count; ++u)
        for (size_t i = 0; i < vm->units[u]->itemCount; ++i)
            if (vm->units[u]->items[i]->kind == RangeNodeExtension)
                guarded(vm,report,"resolution",mergeExtension,vm->units[u]->items[i]);
    for (int round = 0; round < RangeMacroRounds; ++round) {
        int ran = 0;
        for (size_t u = 0; u < vm->count; ++u)
            for (size_t i = 0, n = vm->units[u]->itemCount; i < n; ++i)
                ran |= applyTarget(vm,report,vm->units[u],vm->units[u]->items[i],checked);
        if (!ran) return;
    }
    if (!report) fail(vm,NULL,"macro emission did not settle after %d rounds",RangeMacroRounds);
    sourceDiagnostic(report,NULL,0,"macro-validation","macro emission did not settle after %d rounds",RangeMacroRounds);
}

int validateMacroApplications(RangeArena *arena, RangeNode **units, size_t count,
    size_t *checked, char *error, size_t errorSize)
{
    *checked = 0;
    Resolver *vm = calloc(1,sizeof(*vm));
    if (!vm) { snprintf(error,errorSize,"cannot allocate macro validator"); return 0; }
    vm->arena=arena; vm->units=units; vm->count=count; vm->error=error; vm->errorSize=errorSize;
    int ok = 0;
    if (setjmp(vm->failure) == 0) {
        applyMacros(vm,NULL,checked);
        ok = 1;
    }
    if (!ok) *checked = 0;
    free(vm);
    return ok;
}

static void diagnoseMacroApplications(SourceReport *report)
{
    Resolver *vm = rangeArenaAllocate(report->arena,sizeof(*vm));
    *vm = (Resolver){.arena=report->arena,.units=report->units,.count=report->count,
        .error=rangeArenaAllocate(report->arena,512),.errorSize=512};
    size_t checked = 0;
    if (setjmp(vm->failure) == 0) applyMacros(vm,report,&checked);
    else sourceDiagnostic(report,NULL,0,"macro-validation","%s",vm->error);
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
    return node->kind == RangeNodeMember || node->kind == RangeNodeConstruct || node->kind == RangeNodeEnum;
}

static void diagnoseDuplicateMembers(SourceReport *report, RangeNode *construct)
{
    for (size_t i = 0; i < construct->itemCount; ++i) {
        RangeNode *item = construct->items[i];
        if (!scopeDeclaration(item) || !item->name) continue;
        for (size_t j = 0; j < i; ++j)
            if (scopeDeclaration(construct->items[j]) && same(construct->items[j]->name,item->name)) {
                diagnoseDuplicate(report,construct->items[j],item,construct->name);
                break;
            }
        if (item->kind == RangeNodeConstruct) diagnoseDuplicateMembers(report,item);
    }
}

static void diagnoseDuplicates(SourceReport *report)
{
    for (size_t u = 0; u < report->count; ++u) for (size_t i = 0; i < report->units[u]->itemCount; ++i) {
        RangeNode *item = report->units[u]->items[i];
        if (item->kind == RangeNodeConstruct) diagnoseDuplicateMembers(report,item);
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
    if (first >= argc) { fprintf(stderr, "usage: compiler [--tree | --match-literal macro text] files-or-directories...\n"); return 64; }
    Sources sources = {0};
    RangeNode **units = NULL;
    int status = 66;
    rangeGraphInitTypes(&arena);
    if (argv[first][0] == '-') { fprintf(stderr,"unsupported option: %s; native emission is not implemented yet\n",argv[first]); status=64; goto cleanup; }
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
        if (resolved && !failures) diagnoseMacroApplications(&report);
        for (size_t u = 0; u < unitCount; ++u) diagnoseSourceNode(&report,NULL,units[u],0);
        diagnoseDuplicates(&report);
        sourceDiagnostic(&report,NULL,0,"not-implemented","complete Range type checking and value materialization are not implemented");
        sourceDiagnostic(&report,NULL,0,"not-implemented","native code emission is not implemented; no executable was produced");
        writeSourceDiagnostics(&report,stderr);
        fprintf(stderr,"compilation failed: %zu errors, %zu C implementation warnings\n",report.errors+(size_t)failures,report.warnings);
        status = 65;
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
