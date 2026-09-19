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
    if (same(name,"target") && node == app->declaration) return graphNode(app->target);
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
        return graphProperty(vm,app,graphNode(app->declaration),node->name,node);
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

static void resolveGraphTarget(Resolver *vm, RangeNode *target)
{
    if (target->kind != RangeNodeConstruct) return;
    RangeNode *attributes = target->c;
    if (attributes) for (size_t a = 0; a < attributes->itemCount; ++a) {
        RangeNode *attribute = attributes->items[a], *macro = NULL, *unit = NULL;
        for (size_t u = 0; u < vm->count; ++u) for (size_t m = 0; m < vm->units[u]->itemCount; ++m) {
            RangeNode *candidate = vm->units[u]->items[m];
            if (candidate->kind != RangeNodeMacro || !same(candidate->name,attribute->name)) continue;
            if (macro) fail(vm,attribute,"ambiguous graph macro '%s'",attribute->name);
            macro = candidate; unit = vm->units[u];
        }
        if (!macro) fail(vm,attribute,"unresolved graph macro '%s'",attribute->name);
        if (macro->b && !same(macro->b->name,"Construct"))
            fail(vm,attribute,"macro '%s' does not target Construct",macro->name);
        if (attribute->itemCount || macro->itemCount)
            fail(vm,attribute,"parameterized macro graph resolution is not implemented");
        RangeMacroApplication *app = rangeArenaAllocate(vm->arena,sizeof(*app));
        *app = (RangeMacroApplication){.declaration=macro,.target=target,.unit=unit};
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
        static const char *const storage[] = {"name","target","members","environment","macros","generics","value",
            "receiver","parameters","output","body"};
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

static int macroBuiltin(RangeNode *node, const char *tag)
{
    if (node->kind != RangeNodeMacro || !node->c) return 0;
    for (size_t i = 0; i < node->c->itemCount; ++i) {
        RangeNode *a = node->c->items[i];
        if (!same(a->name,"builtin") || a->itemCount != 1) continue;
        RangeNode *s = a->items[0]->a;
        if (s && s->kind == RangeNodeString && s->itemCount == 1
            && (s->items[0]->flags & RangeFlagLiteral) && same(s->items[0]->name,tag)) return 1;
    }
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
            if (!same(a->name,builtin ? builtin->name : "literal")) continue;
            if (!builtin) fail(vm,a,"literal builtin declaration is not loaded");
            for (size_t v = 0; v < vm->count; ++v) for (size_t k = 0; k < vm->units[v]->itemCount; ++k) {
                RangeNode *candidate = vm->units[v]->items[k];
                if (candidate != builtin && candidate->kind == RangeNodeMacro && same(candidate->name,builtin->name))
                    fail(vm,a,"ambiguous literal macro declaration '%s'",builtin->name);
            }
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

static void linkGrammarNodes(Resolver *vm, RangeNode *node)
{
    if (!node) return;
    node->grammarDefinition = node->graphType ? node->graphType->resolvedDeclaration : NULL;
    if (node->kind == RangeNodeMacro && node->b) {
        RangeNode *shape = rangeGraphType(vm->arena,node->b->name);
        if (shape) node->b->resolvedDeclaration = shape->resolvedDeclaration;
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

static int matchLiteralRule(RangeArena *arena, RangeNode **units, size_t count,
    const char *name, const char *input, int *matched, char *error, size_t errorSize)
{
    Resolver *vm = calloc(1,sizeof(*vm));
    if (!vm) { snprintf(error,errorSize,"cannot allocate literal matcher"); return 0; }
    vm->arena=arena; vm->units=units; vm->count=count; vm->error=error; vm->errorSize=errorSize;
    int ok = 0;
    if (setjmp(vm->failure) == 0) {
        registerLiteralRules(vm);
        RangeNode *macro = NULL;
        for (size_t u = 0; u < count; ++u) for (size_t i = 0; i < units[u]->itemCount; ++i) {
            RangeNode *node = units[u]->items[i];
            if (node->kind != RangeNodeMacro || !same(node->name,name)) continue;
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
        for (size_t u = 0; u < count; ++u)
            for (size_t i = 0; i < units[u]->itemCount; ++i) resolveGraphTarget(vm,units[u]->items[i]);
        resolveGraphOutputs(vm);
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
        if (found) fail(eval->vm,at,"ambiguous compile-time declaration '%s'",name);
        found = node;
    }
    if (!found) fail(eval->vm,at,"unresolved compile-time declaration '%s'",name);
    at->resolvedDeclaration = found;
    return found;
}

static RangeGraphValue metaExpression(MetaEval *, MetaScope *, RangeNode *);
static int metaStatement(MetaEval *, MetaScope *, RangeNode *, RangeGraphValue *);

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
    case RangeNodeEnvironment:
        if (!scope->application) fail(eval->vm,node,"graph context is unavailable in this function");
        return graphEval(eval->vm,scope->application,node);
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

static void validateMacroTarget(MetaEval *eval, RangeNode *target, size_t *checked)
{
    if (target->kind != RangeNodeConstruct) return;
    if (target->c) for (size_t i = 0; i < target->c->itemCount; ++i) {
        RangeMacroApplication *app = target->c->items[i]->macroApplication;
        if (!app) fail(eval->vm,target->c->items[i],"macro application was not resolved");
        if (app->declaration->c) for (size_t j = 0; j < app->declaration->c->itemCount; ++j)
            if (same(app->declaration->c->items[j]->name,"builtin"))
                fail(eval->vm,target->c->items[i],"builtin construct effects are not supported by compile-time validation");
        MetaScope scope = {.application=app};
        RangeGraphValue returned = {0};
        (void)metaStatement(eval,&scope,app->declaration->a,&returned);
        ++*checked;
    }
    for (size_t i = 0; i < target->itemCount; ++i) validateMacroTarget(eval,target->items[i],checked);
}

static int validateMacroApplications(RangeArena *arena, RangeNode **units, size_t count,
    size_t *checked, char *error, size_t errorSize)
{
    *checked = 0;
    Resolver *vm = calloc(1,sizeof(*vm));
    if (!vm) { snprintf(error,errorSize,"cannot allocate macro validator"); return 0; }
    vm->arena=arena; vm->units=units; vm->count=count; vm->error=error; vm->errorSize=errorSize;
    int ok = 0;
    if (setjmp(vm->failure) == 0) {
        MetaEval eval = {.vm=vm};
        for (size_t u = 0; u < count; ++u) for (size_t i = 0; i < units[u]->itemCount; ++i)
            validateMacroTarget(&eval,units[u]->items[i],checked);
        ok = 1;
    }
    if (!ok) *checked = 0;
    free(vm);
    return ok;
}

/* Compiler driver: load source directories, parse their graph, and inspect it. */
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


/* Flat per-source dumps; reject duplicate names before writing any files. */
static const char *sourceName(const char *path)
{
    const char *slash = strrchr(path, '/');
    return slash ? slash + 1 : path;
}

static int emitGraphs(RangeArena *arena, RangeNode **units, size_t count,
                      const char *directory)
{
    if (!*directory) { fprintf(stderr, "graph output directory is empty\n"); return 0; }
    for (size_t i = 0; i < count; ++i) {
        for (size_t j = 0; j < i; ++j) {
            if (!strcmp(sourceName(units[i]->path), sourceName(units[j]->path))) {
                fprintf(stderr, "duplicate graph output name: %s\n", sourceName(units[i]->path));
                return 0;
            }
        }
    }
    char *folder = (char *)rangeArenaIntern(arena, directory, strlen(directory));
    for (char *p = folder + 1; ; ++p) {
        if (*p && *p != '/') continue;
        char saved = *p;
        *p = '\0';
        if (mkdir(folder, 0755) != 0 && errno != EEXIST) return sourceError(folder);
        *p = saved;
        if (!saved) break;
    }
    for (size_t i = 0; i < count; ++i) {
        const char *name = sourceName(units[i]->path);
        const char *extension = strrchr(name, '.');
        size_t stem = extension ? (size_t)(extension - name) : strlen(name);
        size_t length = strlen(directory) + stem + 6;
        char *path = rangeArenaAllocate(arena, length);
        snprintf(path, length, "%s/%.*s.txt", directory, (int)stem, name);
        FILE *output = fopen(path, "w");
        if (!output) return sourceError(path);
        rangeGraphWrite(output, units[i]);
        int failed = ferror(output);
        if (fclose(output) != 0) failed = 1;
        if (failed) return sourceError(path);
        printf("graph=%s\n", path);
    }
    return 1;
}

int main(int argc, char **argv)
{
    RangeArena arena;
    rangeArenaInit(&arena);
    int treeMode = 0, validationMode = 0;
    const char *literalMacro = NULL, *literalInput = NULL;
    const char *graphDirectory = NULL;
    int first = 1;
    int option = first;
    if (argc > option + 2 && strcmp(argv[option],"--match-literal") == 0) {
        literalMacro=argv[option + 1]; literalInput=argv[option + 2]; first=option + 3;
    }
    else if (argc > option && strcmp(argv[option], "--validate-macros") == 0) { validationMode = 1; first = option + 1; }
    else if (argc > option && strcmp(argv[option], "--tree") == 0) { treeMode = 1; first = option + 1; }
    else if (argc > option + 1 && strcmp(argv[option], "--emit-graph") == 0) { graphDirectory = argv[option + 1]; first = option + 2; }
    if (first >= argc) { fprintf(stderr, "usage: compiler [--tree | --emit-graph directory | --match-literal macro text | --validate-macros] files-or-directories...\n"); return 64; }
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
    long counts[RangeNodeKindCount];
    memset(counts, 0, sizeof(counts));
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
        for (size_t item = 0; item < unit->itemCount; ++item) {
            counts[unit->items[item]->kind] += 1;
        }
    }
    if (!treeMode && !literalMacro && !failures) {
        char error[512];
        if (!resolveGraphApplications(&arena, units, unitCount, error, sizeof(error))) {
            fprintf(stderr,"%s\n",error);
            failures += 1;
        }
    }
    if (graphDirectory && !failures && !emitGraphs(&arena, units, unitCount, graphDirectory)) {
        status = 74;
        goto cleanup;
    }
    if (literalMacro && !failures) {
        char error[512]; int matched = 0;
        if (!matchLiteralRule(&arena,units,unitCount,literalMacro,literalInput,&matched,error,sizeof(error))) {
            fprintf(stderr,"%s\n",error); failures += 1;
        } else printf("match=%s\n",matched ? "true" : "false");
    }
    if (validationMode && !failures) {
        char error[512]; size_t checked;
        if (!validateMacroApplications(&arena,units,unitCount,&checked,error,sizeof(error))) {
            fprintf(stderr,"%s\n",error); failures += 1;
        } else printf("validated-macro-applications=%zu\n",checked);
    }
    status = failures ? 65 : 0;
    if (treeMode || graphDirectory || literalMacro || validationMode) goto cleanup;
    printf("resolved-sources=%zu nodes=%zu construct=%ld enum=%ld function=%ld macro=%ld main=%ld failures=%d\n",
           sources.count, arena.nodeCount, counts[RangeNodeConstruct], counts[RangeNodeEnum],
           counts[RangeNodeFunction], counts[RangeNodeMacro], counts[RangeNodeMain],
           failures);
cleanup:
    free(units);
    free(sources.paths);
    rangeArenaDestroy(&arena);
    return status;
}
