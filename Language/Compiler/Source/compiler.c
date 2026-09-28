#define _XOPEN_SOURCE 700
#include "model.h"
#include "native.h"
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
    int skipEmission;   /* law runs per specialization check; emission stays on the declaration */
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
    // A macro's own locals read their bound value; other declarations their RHS.
    if (same(name,"value") && rangeNodeDeclaresValue(node->kind))
        for (size_t i = 0; i < app->count; ++i)
            if (app->bindings[i].definition == node) return graphBinding(vm,app,&app->bindings[i]);
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
                if (!rangeNodeDeclaresValue(member->kind)) continue;
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
    *local = (MetaLocal){.name=node->name,.value=value,.mutable=node->kind == RangeNodeState,.next=scope->locals};
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

/* A macro's own top-level declarations are bound once per application. */
static int macroLocal(const RangeMacroApplication *app, const RangeNode *node)
{
    for (size_t i = 0; app && i < app->count; ++i)
        if (app->bindings[i].definition == node) return 1;
    return 0;
}

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
    if (!rangeNodeDeclaresValue(copy->kind) || copy->typeName
        || copy->itemCount != 1 || copy->items[0]->kind != RangeNodeArgument
        || !spliceChain(original->items[0]->a) || copy->items[0]->a->kind != RangeNodeName) return;
    RangeNode *reference = copy->items[0]->a;
    copy->typeName = reference->name;
    copy->itemCount = 0;
    if (!copy->flags) copy->rhsReference = reference;
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
        if (eval->vm->skipEmission) return (RangeGraphValue){0};
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
            && rangeNodeDeclaresValue(receiver.node->kind) && value.kind == RangeGraphNode
            && !macroLocal(scope->application,receiver.node)) {
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
    case RangeNodeLet: case RangeNodeState: {
        if (node->flags & ~RangeFlagApplication)
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
    RangeNode *emitted = rangeNodeCreate(vm->arena,RangeNodeBlock,attribute->path,attribute->line,attribute->column);
    // @many marks layout and @optional marks the `?` sugar's construct; applying
    // either has no compile-time effect.
    if (macroBuiltin(app->declaration,"many") || macroBuiltin(app->declaration,"optional")) return emitted;
    if (app->declaration->c) for (size_t j = 0; j < app->declaration->c->itemCount; ++j)
        if (same(app->declaration->c->items[j]->name,"builtin")) {
            if (!macroBuiltin(app->declaration,"literal") && !macroBuiltin(app->declaration,"diagnostic"))
                fail(vm,attribute,"no C primitive is implemented for builtin macro '%s'",app->declaration->name);
            fail(vm,attribute,"builtin target effects are not supported by compile-time validation");
        }
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
    int meta; /* inside a macro body: compile-time code over graph values */
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
        || rangeNodeDeclaresValue(node->kind) || node->kind == RangeNodeParameter;
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
    (void)sourceReference(report,scope,node,node->name,node->flags & RangeFlagMacroType ? 1 : 2);
    diagnoseSourceNode(report,scope,node->generics,0);
    diagnoseType(report,scope,node->a); /* an explicit macro result type */
}

static void diagnoseSourceNode(SourceReport *report, SourceScope *scope, RangeNode *node, int metadata)
{
    if (!node) return;
    switch (node->kind) {
    case RangeNodeUnit: case RangeNodeBlock: {
        SourceScope block = {.owner=node,.parent=scope,.meta=scope && scope->meta};
        for (size_t i = 0; i < node->itemCount; ++i) diagnoseSourceNode(report,&block,node->items[i],metadata);
        return;
    }
    case RangeNodeConstruct: case RangeNodeEnum: case RangeNodeFunction: case RangeNodeMacro: {
        SourceScope declaration = {.owner=node,.parent=scope,.meta=(scope && scope->meta) || node->kind == RangeNodeMacro};
        if (node->kind == RangeNodeFunction)
            (void)sourceReference(report,scope,node,node->typeName,2);
        if (node->kind == RangeNodeFunction || node->kind == RangeNodeMacro) diagnoseType(report,&declaration,node->b);
        if (macroBuiltin(node,"many"))
            sourceDiagnostic(report,node,0,"not-implemented","builtin macro 'many' has no runtime storage implementation");
        else if (macroBuiltin(node,"optional"))
            sourceDiagnostic(report,node,1,"C-implementation","'?' sugar resolves to the construct applying @optional in C");
        else if (node->kind == RangeNodeMacro && node->c && !macroBuiltin(node,"literal") && !macroBuiltin(node,"diagnostic"))
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
        RangeNode *declaration = sourceReference(report,scope,node,node->typeName,
            node->flags & RangeFlagMacroType ? 1 : node->generics || (node->flags & RangeFlagOptional) ? 2 : 0);
        if (declaration && (node->flags & RangeFlagApplication)
            && (declaration->kind == RangeNodeConstruct || declaration->kind == RangeNodeEnum))
            sourceDiagnostic(report,node,0,"not-implemented","value construction for '%s' is not implemented",node->typeName);
        break;
    }
    case RangeNodeName:
        (void)sourceReference(report,scope,node,node->name,node->flags & RangeFlagMacroType ? 1 : 0);
        break;
    case RangeNodeMemberAccess:
        /* Runtime member access is typed later; these are graph-value shortcuts. */
        if (scope && scope->meta && (same(node->name,"first") || same(node->name,"isTarget")))
            sourceDiagnostic(report,node,1,"C-implementation","'.%s' is hard-coded in C; Range member dispatch is not implemented",node->name);
        break;
    case RangeNodeCall:
        if (node->a && node->a->kind == RangeNodeMemberAccess && scope && scope->meta) {
            if (same(node->a->name,"filter") && node->itemCount == 1 && same(node->items[0]->name,"named"))
                sourceDiagnostic(report,node,1,"C-implementation","'filter(named:)' is hard-coded in C; Range method dispatch is not implemented");
            else sourceDiagnostic(report,node,0,"not-implemented","compile-time method call resolution for '%s' is not implemented",node->a->name);
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
    return rangeNodeDeclaresValue(node->kind) || node->kind == RangeNodeConstruct || node->kind == RangeNodeEnum;
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

static void diagnoseBuiltinFunctions(SourceReport *report, RangeNode *owner)
{
    size_t slots = 0;
    if (owner->kind == RangeNodeConstruct)
        for (size_t i = 0; i < owner->itemCount; ++i)
            if (rangeNodeDeclaresValue(owner->items[i]->kind) && appliesBuiltin(owner->items[i],"many")) ++slots;
    for (size_t i = 0; i < owner->itemCount; ++i) {
        RangeNode *item = owner->items[i];
        if (item->kind == RangeNodeConstruct) diagnoseBuiltinFunctions(report,item);
        if (builtinMember(item) && ((!same(item->name,"storage") && !same(item->name,"signed")) || owner->kind != RangeNodeConstruct))
            sourceDiagnostic(report,item,0,"not-implemented","no C primitive is implemented for builtin member '%s'",item->name);
        if (item->kind != RangeNodeFunction || !(item->flags & RangeFlagBuiltin)) continue;
        if (!slotPrimitive(item) || owner->kind != RangeNodeConstruct)
            sourceDiagnostic(report,item,0,"not-implemented","no C primitive is implemented for builtin function '%s'",item->name);
        else if (slots != 1)
            sourceDiagnostic(report,item,0,"builtin","builtin function '%s' requires exactly one @many member in %s; found %zu",
                item->name,owner->name,slots);
        else sourceDiagnostic(report,item,0,"not-implemented","builtin function '%s' has no runtime implementation for @many storage",item->name);
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

/* ---- types -------------------------------------------------------------
 * A type is a specialization: a construct plus one value per generic. Equal
 * specializations are interned to one node, so type equality is identity.
 * Inside a construct's own bodies its type parameters stand for themselves.
 * Literals take the type their context requires; a construct's laws (its
 * macro applications) run once per distinct specialization and once per
 * supplied literal. Emission stays on the declaration, so those runs only
 * check. Operators are C builtins for now, selected by the literal families
 * the language declares. */

typedef struct {
    SourceReport *report;
    Resolver *vm;                /* runs laws per specialization */
    RangeNode *specializations;  /* interned RangeNodeSpecialization nodes */
    RangeNode *integer, *boolean; /* constructs the integer and boolean literal rules select */
    RangeNode *booleanType;
} Typer;

static RangeNode *typeOf(Typer *, SourceScope *, RangeNode *, RangeNode *, RangeNode *);
static RangeNode *declaredType(Typer *, SourceScope *, RangeNode *, RangeNode *);
static RangeNode *resolveTypeReference(Typer *, SourceScope *, const char *, RangeNode *, int, RangeNode *, RangeNode *);

static void typeError(Typer *typer, RangeNode *at, const char *format, ...)
{
    char text[512]; va_list args; va_start(args,format);
    vsnprintf(text,sizeof(text),format,args); va_end(args);
    sourceDiagnostic(typer->report,at,0,"type","%s",text);
}

static void describeType(char *out, size_t size, const RangeNode *type)
{
    if (!type) { snprintf(out,size,"<unknown>"); return; }
    if (type->kind == RangeNodeTypeParameter) { snprintf(out,size,"%s",type->name); return; }
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

/* Run the construct's macro applications against this specialization, with
 * the supplied literal in place of the member it populates. */
static void checkLaws(Typer *typer, RangeNode *specialization, RangeNode *value, RangeNode *at)
{
    RangeNode *declaration = specialization->resolvedDeclaration;
    if (!declaration->c || !declaration->c->itemCount) return;
    if (!value) {
        if (specialization->flags & RangeFlagChecked) return;
        specialization->flags |= RangeFlagChecked;
    }
    RangeArena *arena = typer->report->arena;
    Resolver *vm = typer->vm;
    RangeNode *copy = rangeArenaAllocate(arena,sizeof(*copy));
    *copy = *declaration;
    copy->generics = specialization->generics;
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
        RangeMacroApplication *app = rangeArenaAllocate(arena,sizeof(*app));
        *app = (RangeMacroApplication){.declaration=declared->declaration,.target=copy,.unit=declared->unit,.attribute=attribute};
        jmp_buf outer;
        memcpy(outer,vm->failure,sizeof(outer));
        vm->skipEmission = 1;
        if (setjmp(vm->failure) == 0) {
            MetaEval eval = {.vm=vm};
            MetaScope scope = {.application=app};
            RangeGraphValue returned = {0};
            (void)metaStatement(&eval,&scope,app->declaration->a,&returned);
        } else {
            char type[160];
            describeType(type,sizeof(type),specialization);
            sourceDiagnostic(typer->report,at,0,"law","%s does not satisfy @%s: %s",type,app->declaration->name,vm->error);
        }
        vm->skipEmission = 0;
        memcpy(vm->failure,outer,sizeof(outer));
    }
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
        else checkLaws(typer,specialization,NULL,at);
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
            rangeNodeAppend(arena,generics,copy);
        }
    }
    int created = 0;
    RangeNode *specialization = internSpecialization(typer,declaration,generics,&created);
    specialization->flags |= RangeFlagChecked;
    return specialization;
}

static RangeNode *resolveTypeReference(Typer *typer, SourceScope *scope, const char *name,
                                       RangeNode *generics, int flags, RangeNode *context, RangeNode *at)
{
    if (!name || !*name || strchr(name,'|')) return NULL; /* unions are reported already */
    if (flags & RangeFlagMacroType) return NULL; /* macro types are not typed in this step */
    if (flags & RangeFlagOptional) {
        // `T?` is the construct applying @optional, specialized with T.
        RangeNode *optional = NULL;
        size_t found = 0;
        for (size_t u = 0; u < typer->report->count; ++u) for (size_t i = 0; i < typer->report->units[u]->itemCount; ++i) {
            RangeNode *candidate = typer->report->units[u]->items[i];
            if (candidate->kind == RangeNodeConstruct && appliesBuiltin(candidate,"optional")) { optional = candidate; ++found; }
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
    if (context && context->generics)
        for (size_t i = 0; i < context->generics->itemCount; ++i) {
            RangeNode *generic = context->generics->items[i];
            if (generic->kind == RangeNodeTypeParameter && same(generic->name,name)) return generic->resolvedType;
        }
    RangeNode *declaration = sourceLookup(typer->report,scope,name,2);
    if (!declaration || declaration->kind != RangeNodeConstruct) return NULL; /* undeclared is reported already */
    return specialize(typer,scope,declaration,generics,context,at);
}

static RangeNode *declaredType(Typer *typer, SourceScope *scope, RangeNode *node, RangeNode *context)
{
    if (node->kind == RangeNodeParameter)
        return node->b ? resolveTypeReference(typer,scope,node->b->name,node->b->generics,node->flags,context,node->b) : NULL;
    if (node->flags & RangeFlagMany) return NULL; /* @many storage is not a standalone value */
    if (node->a && node->a->kind == RangeNodeCall && node->typeName) return node->a->type; /* `let r: step(x: 1)` */
    // A bare name's resolved declaration decides its meaning: a value is
    // copied, a construct is a requirement.
    if (node->typeName && node->rhsReference && !node->generics) {
        RangeNode *value = sourceLookup(typer->report,scope,node->typeName,0);
        if (value && (rangeNodeDeclaresValue(value->kind) || value->kind == RangeNodeParameter) && value != node) {
            node->rhsReference->resolvedDeclaration = value;
            return typeOf(typer,scope,node->rhsReference,NULL,context);
        }
    }
    if (node->typeName) return resolveTypeReference(typer,scope,node->typeName,node->generics,node->flags,context,node);
    RangeNode *rhs = rangeNodeRHS(node);
    return rhs ? typeOf(typer,scope,rhs,NULL,context) : NULL;
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

static int isLiteral(const RangeNode *node)
{
    return node->kind == RangeNodeInteger || node->kind == RangeNodeBool || node->kind == RangeNodeString;
}

static int isInteger(Typer *typer, const RangeNode *type)
{
    return type && type->kind == RangeNodeSpecialization && typer->integer && type->resolvedDeclaration == typer->integer;
}

static void expectType(Typer *typer, RangeNode *at, RangeNode *expected, RangeNode *actual, const char *what)
{
    if (!expected || !actual || expected == actual) return;
    char want[160], got[160];
    describeType(want,sizeof(want),expected); describeType(got,sizeof(got),actual);
    typeError(typer,at,"%s requires %s; found %s",what,want,got);
}

/* The law checks `value`: the literal itself, or `-literal` as one value. */
static RangeNode *typeLiteral(Typer *typer, RangeNode *literal, RangeNode *value, RangeNode *expected)
{
    RangeNode *rule = literal->resolvedDeclaration;
    if (!rule || !rule->literalDefault) return NULL;
    RangeNode *declaration = rule->literalDefault, *type;
    if (expected && expected->kind == RangeNodeSpecialization && expected->resolvedDeclaration == declaration) type = expected;
    else type = specialize(typer,NULL,declaration,NULL,NULL,literal);
    if (type) {
        if (value != literal) value->resolvedDeclaration = rule;
        checkLaws(typer,type,value,value);
    }
    literal->type = type;
    return type;
}

static RangeNode *typeCall(Typer *typer, SourceScope *scope, RangeNode *call, RangeNode *context)
{
    RangeNode *callee = call->a, *function = NULL, *receiver = NULL;
    if (!callee) return NULL;
    if (callee->kind == RangeNodeName) {
        function = lookupFunction(typer->report,scope,callee->name);
        if (!function) {
            RangeNode *declaration = sourceLookup(typer->report,scope,callee->name,0);
            if (declaration && declaration->kind != RangeNodeConstruct && declaration->kind != RangeNodeEnum)
                typeError(typer,call,"'%s' is not a function",callee->name);
            return NULL; /* construction and undeclared names are reported already */
        }
        receiver = function->typeName ? context : NULL;
    } else if (callee->kind == RangeNodeMemberAccess) {
        receiver = typeOf(typer,scope,callee->a,NULL,context);
        if (!receiver) return NULL;
        if (receiver->kind == RangeNodeTypeParameter) { typeError(typer,callee,"type parameter %s has no functions",receiver->name); return NULL; }
        function = findFunction(receiver->resolvedDeclaration,callee->name);
        if (!function) {
            char type[160]; describeType(type,sizeof(type),receiver);
            typeError(typer,callee,"%s has no function '%s'",type,callee->name);
            return NULL;
        }
    } else {
        typeError(typer,call,"call target is not a function");
        return NULL;
    }
    callee->resolvedDeclaration = function;
    SourceScope functionScope = {.owner=function};
    if (call->itemCount != function->itemCount)
        typeError(typer,call,"'%s' takes %zu arguments; %zu supplied",function->name,function->itemCount,call->itemCount);
    for (size_t i = 0; i < call->itemCount && i < function->itemCount; ++i) {
        RangeNode *argument = call->items[i], *parameter = function->items[i];
        if (!argument->name || !same(argument->name,parameter->name))
            typeError(typer,argument,"argument %zu of '%s' requires label '%s'",i + 1,function->name,parameter->name);
        RangeNode *expected = declaredType(typer,&functionScope,parameter,receiver);
        RangeNode *actual = typeOf(typer,scope,argument->a,expected,context);
        char what[160];
        snprintf(what,sizeof(what),"argument '%s' of '%s'",parameter->name,function->name);
        expectType(typer,argument->a,expected,actual,what);
    }
    RangeNode *output = function->b;
    return output ? resolveTypeReference(typer,&functionScope,output->name,output->generics,output->flags,receiver,output) : NULL;
}

static RangeNode *typeOf(Typer *typer, SourceScope *scope, RangeNode *expr, RangeNode *expected, RangeNode *context)
{
    if (!expr) return NULL;
    RangeNode *type = NULL;
    switch (expr->kind) {
    case RangeNodeInteger: case RangeNodeBool: case RangeNodeString:
        type = typeLiteral(typer,expr,expr,expected);
        break;
    case RangeNodeName: {
        RangeNode *declaration = sourceLookup(typer->report,scope,expr->name,0);
        expr->resolvedDeclaration = declaration;
        if (!declaration) break;
        if (rangeNodeDeclaresValue(declaration->kind) || declaration->kind == RangeNodeParameter) {
            if (declaration->flags & RangeFlagMany) typeError(typer,expr,"'%s' holds @many storage and is not a value",expr->name);
            else type = declaredType(typer,scope,declaration,context);
        } else if (declaration->kind == RangeNodeFunction) typeError(typer,expr,"'%s' is a function; call it",expr->name);
        else if (declaration->kind == RangeNodeTypeParameter || declaration->kind == RangeNodeConstruct || declaration->kind == RangeNodeEnum)
            typeError(typer,expr,"'%s' names a type, not a value",expr->name);
        break;
    }
    case RangeNodeMemberAccess: {
        RangeNode *receiver = typeOf(typer,scope,expr->a,NULL,context);
        if (!receiver) break;
        if (receiver->kind == RangeNodeTypeParameter) { typeError(typer,expr,"type parameter %s has no members",receiver->name); break; }
        RangeNode *declaration = receiver->resolvedDeclaration;
        RangeNode *member = findMember(declaration,expr->name);
        expr->resolvedDeclaration = member;
        if (member) {
            if (member->flags & RangeFlagMany) typeError(typer,expr,"'%s' holds @many storage and is not a value",expr->name);
            else { SourceScope declarationScope = {.owner=declaration}; type = declaredType(typer,&declarationScope,member,receiver); }
        } else if (findFunction(declaration,expr->name)) typeError(typer,expr,"'%s.%s' is a function; call it",declaration->name,expr->name);
        else { char t[160]; describeType(t,sizeof(t),receiver); typeError(typer,expr,"%s has no member '%s'",t,expr->name); }
        break;
    }
    case RangeNodeCall:
        type = typeCall(typer,scope,expr,context);
        break;
    case RangeNodeUnary: {
        int logical = same(expr->name,"!");
        if (!logical && expr->a && expr->a->kind == RangeNodeInteger) {
            // -128 is one literal: the law sees the negative value.
            type = typeLiteral(typer,expr->a,expr,expected);
            break;
        }
        RangeNode *operand = typeOf(typer,scope,expr->a,logical ? typer->booleanType : expected,context);
        if (!operand) break;
        if (logical) { expectType(typer,expr->a,typer->booleanType,operand,"operator '!'"); type = typer->booleanType; }
        else if (!isInteger(typer,operand)) { char t[160]; describeType(t,sizeof(t),operand); typeError(typer,expr,"operator '-' requires an integer type; found %s",t); }
        else type = operand;
        break;
    }
    case RangeNodeBinary: {
        const char *op = expr->name;
        int logical = same(op,"&&") || same(op,"||");
        int comparison = same(op,"<") || same(op,">") || same(op,"<=") || same(op,">=");
        int equality = same(op,"==") || same(op,"!=");
        RangeNode *want = logical ? typer->booleanType : (comparison || equality) ? NULL : expected;
        RangeNode *left, *right;
        // A literal takes the other operand's type when that side is not a literal.
        if (isLiteral(expr->a) && !isLiteral(expr->b)) {
            right = typeOf(typer,scope,expr->b,want,context);
            left = typeOf(typer,scope,expr->a,right ? right : want,context);
        } else {
            left = typeOf(typer,scope,expr->a,want,context);
            right = typeOf(typer,scope,expr->b,left ? left : want,context);
        }
        if (!left || !right) break;
        if (left != right) {
            char l[160], r[160]; describeType(l,sizeof(l),left); describeType(r,sizeof(r),right);
            typeError(typer,expr,"operator '%s' requires matching types; found %s and %s",op,l,r);
            break;
        }
        if (logical) { expectType(typer,expr,typer->booleanType,left,"operator"); type = typer->booleanType; }
        else if (equality) type = typer->booleanType;
        else if (!isInteger(typer,left)) { char t[160]; describeType(t,sizeof(t),left); typeError(typer,expr,"operator '%s' requires an integer type; found %s",op,t); }
        else type = comparison ? typer->booleanType : left;
        break;
    }
    default: break; /* unsupported forms are reported already */
    }
    expr->type = type;
    return type;
}

static void typeBlock(Typer *, SourceScope *, RangeNode *, RangeNode *, RangeNode *);

static void typeStatement(Typer *typer, SourceScope *scope, RangeNode *node, RangeNode *context, RangeNode *output)
{
    if (!node) return;
    switch (node->kind) {
    case RangeNodeBlock: typeBlock(typer,scope,node,context,output); break;
    case RangeNodeLet: case RangeNodeState:
        if (node->typeName && (node->flags & RangeFlagApplication)) {
            // `let r: step(x: 1)` calls a function; a construct here is construction.
            if (!lookupFunction(typer->report,scope,node->typeName)) break; /* construction is reported already */
            RangeNode *callee = rangeNodeCreate(typer->report->arena,RangeNodeName,node->path,node->line,node->column);
            callee->name = node->typeName;
            RangeNode *call = rangeNodeCreate(typer->report->arena,RangeNodeCall,node->path,node->line,node->column);
            call->a = callee;
            for (size_t i = 0; i < node->itemCount; ++i) rangeNodeAppend(typer->report->arena,call,node->items[i]);
            node->a = call;
            node->type = typeOf(typer,scope,call,NULL,context);
            break;
        }
        node->type = declaredType(typer,scope,node,context);
        break;
    case RangeNodeAssign: {
        RangeNode *target = node->a;
        if (!target || target->kind != RangeNodeName) { sourceDiagnostic(typer->report,node,0,"not-implemented","assignment to a member path is not implemented"); break; }
        RangeNode *declaration = sourceLookup(typer->report,scope,target->name,0);
        target->resolvedDeclaration = declaration;
        if (!declaration) break;
        if (declaration->kind != RangeNodeState) { typeError(typer,node,"cannot assign to %s '%s'",rangeNodeKindName(declaration->kind),target->name); break; }
        RangeNode *expected = declaredType(typer,scope,declaration,context);
        RangeNode *actual = typeOf(typer,scope,node->b,expected,context);
        char what[160]; snprintf(what,sizeof(what),"assignment to '%s'",target->name);
        expectType(typer,node->b,expected,actual,what);
        break;
    }
    case RangeNodeIf: case RangeNodeWhile: {
        RangeNode *condition = typeOf(typer,scope,node->a,typer->booleanType,context);
        expectType(typer,node->a,typer->booleanType,condition,"condition");
        typeStatement(typer,scope,node->b,context,output);
        typeStatement(typer,scope,node->c,context,output);
        break;
    }
    case RangeNodeReturn:
        if (output) {
            if (!node->a) { char t[160]; describeType(t,sizeof(t),output); typeError(typer,node,"return requires %s",t); break; }
            expectType(typer,node->a,output,typeOf(typer,scope,node->a,output,context),"return");
        } else if (node->a) {
            (void)typeOf(typer,scope,node->a,NULL,context);
            typeError(typer,node,"this function returns no value");
        }
        break;
    case RangeNodeExpressionStatement:
        if (node->a && node->a->kind != RangeNodeAttribute) (void)typeOf(typer,scope,node->a,NULL,context);
        break;
    default: break; /* declarations, and forms reported as not implemented */
    }
}

static void typeBlock(Typer *typer, SourceScope *parent, RangeNode *block, RangeNode *context, RangeNode *output)
{
    if (!block) return;
    SourceScope scope = {.owner=block,.parent=parent};
    for (size_t i = 0; i < block->itemCount; ++i) typeStatement(typer,&scope,block->items[i],context,output);
}

static void typeFunction(Typer *typer, SourceScope *parent, RangeNode *function, RangeNode *context)
{
    SourceScope scope = {.owner=function,.parent=parent};
    for (size_t i = 0; i < function->itemCount; ++i) function->items[i]->type = declaredType(typer,&scope,function->items[i],context);
    RangeNode *output = function->b
        ? resolveTypeReference(typer,&scope,function->b->name,function->b->generics,function->b->flags,context,function->b) : NULL;
    function->type = output;
    if (function->a) typeBlock(typer,&scope,function->a,context,output);
}

static void typeConstruct(Typer *typer, SourceScope *parent, RangeNode *declaration)
{
    RangeNode *context = selfSpecialization(typer,declaration);
    SourceScope scope = {.owner=declaration,.parent=parent};
    for (size_t i = 0; i < declaration->itemCount; ++i) {
        RangeNode *item = declaration->items[i];
        if (rangeNodeDeclaresValue(item->kind)) {
            if (item->typeName && (item->flags & RangeFlagApplication)) continue;
            item->type = declaredType(typer,&scope,item,context);
        } else if (item->kind == RangeNodeFunction) typeFunction(typer,&scope,item,context);
        else if (item->kind == RangeNodeConstruct) typeConstruct(typer,&scope,item);
    }
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
    if (graphConstruct(typer,declaration)) {
        specialization->layout = 2;
        specialization->integer = 1; /* graph value: runtime uses report it */
        return 0;
    }
    specialization->layout = 1;
    size_t size = 0, alignment = 1;
    int known = 1;
    RangeNode *storage = NULL, *sign = NULL;
    for (size_t i = 0; i < declaration->itemCount; ++i) {
        if (builtinMember(declaration->items[i]) && same(declaration->items[i]->name,"storage")) storage = declaration->items[i];
        if (builtinMember(declaration->items[i]) && same(declaration->items[i]->name,"signed")) sign = declaration->items[i];
    }
    if (storage) {
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
        for (size_t i = 0; i < declaration->itemCount; ++i) {
            RangeNode *member = declaration->items[i];
            if (!rangeNodeDeclaresValue(member->kind) || builtinMember(member)) continue;
            size_t memberSize, memberAlignment;
            if (member->flags & RangeFlagMany) { memberSize = 8; memberAlignment = 8; }
            else {
                RangeNode *type = parametric ? declaredType(typer,&scope,member,specialization) : member->type;
                if (!type || type->kind != RangeNodeSpecialization || !layoutOf(typer,type,member)) {
                    known = 0;
                    specialization->integer = 1; /* the cause lies in a member's type, reported there */
                    continue;
                }
                memberSize = type->size; memberAlignment = type->alignment;
            }
            size = (size + memberAlignment - 1) / memberAlignment * memberAlignment + memberSize;
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

/* The integer and boolean literal rules select the constructs operators
 * apply to; C names neither. */
static RangeNode *literalFamily(Typer *typer, const char *spelling)
{
    for (size_t u = 0; u < typer->report->count; ++u) for (size_t i = 0; i < typer->report->units[u]->itemCount; ++i) {
        RangeNode *macro = typer->report->units[u]->items[i];
        if (macro->kind != RangeNodeMacro || !macro->literalPattern || !macro->literalDefault) continue;
        if (literalMatch(typer->vm,macro,macro->literalPattern,spelling)) return macro->literalDefault;
    }
    return NULL;
}

static void typeCheck(SourceReport *report)
{
    Resolver *vm = rangeArenaAllocate(report->arena,sizeof(*vm));
    *vm = (Resolver){.arena=report->arena,.units=report->units,.count=report->count,
        .error=rangeArenaAllocate(report->arena,512),.errorSize=512};
    Typer typer = {.report=report,.vm=vm};
    typer.specializations = rangeNodeCreate(report->arena,RangeNodeBlock,"<compiler>",1,1);
    if (setjmp(vm->failure) != 0) { sourceDiagnostic(report,NULL,0,"type","%s",vm->error); return; }
    typer.integer = literalFamily(&typer,"0");
    typer.boolean = literalFamily(&typer,"true");
    if (typer.boolean) typer.booleanType = specialize(&typer,NULL,typer.boolean,NULL,NULL,typer.boolean);
    // The entry block returns the default integer: the process exit status.
    RangeNode *status = typer.integer ? specialize(&typer,NULL,typer.integer,NULL,NULL,typer.integer) : NULL;
    for (size_t u = 0; u < report->count; ++u) {
        SourceScope unit = {.owner=report->units[u]};
        for (size_t i = 0; i < report->units[u]->itemCount; ++i) {
            RangeNode *item = report->units[u]->items[i];
            if (item->kind == RangeNodeConstruct) typeConstruct(&typer,&unit,item);
            else if (item->kind == RangeNodeFunction) typeFunction(&typer,&unit,item,NULL);
            else if (item->kind == RangeNodeMain) { item->type = status; typeBlock(&typer,&unit,item->a,NULL,status); }
        }
    }
    // Every type the program mentions gets a layout, or a reason it has none.
    for (size_t i = 0; i < typer.specializations->itemCount; ++i) {
        RangeNode *specialization = typer.specializations->items[i];
        if (specialization->layout == 2 || layoutOf(&typer,specialization,specialization->resolvedDeclaration)
            || specialization->integer) continue;
        char name[160]; describeType(name,sizeof(name),specialization);
        sourceDiagnostic(report,specialization->resolvedDeclaration,0,"layout","%s has no layout",name);
    }
}

/* ---- native code -----------------------------------------------------------
 * Lowers typed Range to ARM64. Values of scalar types live in 64-bit registers,
 * sign- or zero-extended by the width their storage primitive declares; each
 * local and parameter has an 8-byte frame slot. Operators are C builtins: each
 * enforces its operand type's range (the @integer law) at runtime where the
 * compiler cannot prove it, writing a located message and exiting 134. Every
 * function is compiled, reached or not, so each missing mechanism is reported.
 * Forms not lowered yet are reported as not implemented. */

typedef struct { RangeNode *declaration; int32_t offset; } NativeSlot;
typedef struct { size_t at; RangeNode *function; } NativeCall;
typedef struct { size_t at; uint32_t branch; const char *message; } NativeTrap;
typedef struct { size_t at; uint32_t branch; } NativeJump;

typedef struct {
    SourceReport *report;
    RangeMachine machine;
    int failed;
    NativeSlot *slots; size_t slotCount, slotCapacity;
    NativeJump *returns; size_t returnCount, returnCapacity;
    NativeCall *calls; size_t callCount, callCapacity;
    NativeTrap *traps; size_t trapCount, trapCapacity;
    RangeNode **functions; size_t *offsets; size_t functionCount, functionCapacity;
} Native;

#define NATIVE_PUSH(array,count,capacity,value) do { \
    if ((count) == (capacity)) { (capacity) = (capacity) ? (capacity) * 2 : 16; \
        (array) = realloc((array),(capacity) * sizeof(*(array))); if (!(array)) abort(); } \
    (array)[(count)++] = (value); } while (0)

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

/* Branch to a trap stub with a located message when the condition holds. */
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

static int32_t nativeSlot(Native *native, RangeNode *declaration)
{
    for (size_t i = 0; i < native->slotCount; ++i)
        if (native->slots[i].declaration == declaration) return native->slots[i].offset;
    return 0;
}

static int32_t nativeNewSlot(Native *native, RangeNode *declaration)
{
    int32_t offset = -8 * (int32_t)(native->slotCount + 1);
    NativeSlot slot = {.declaration=declaration,.offset=offset};
    NATIVE_PUSH(native->slots,native->slotCount,native->slotCapacity,slot);
    return offset;
}

static void nativeStore(Native *native, int rt, int32_t offset)
{
    if (offset >= -256) { nativeEmit(native,armStur(rt,29,offset)); return; }
    nativeEmit(native,armSubImm(9,29,(uint32_t)-offset));
    nativeEmit(native,armStr(rt,9,0));
}

static void nativeLoad(Native *native, int rt, int32_t offset)
{
    if (offset >= -256) { nativeEmit(native,armLdur(rt,29,offset)); return; }
    nativeEmit(native,armSubImm(9,29,(uint32_t)-offset));
    nativeEmit(native,armLdr(rt,9,0));
}

static int nativeScalar(Native *native, RangeNode *type, RangeNode *at)
{
    if (type && type->kind == RangeNodeSpecialization && type->scalarBits) return 1;
    char name[160]; describeType(name,sizeof(name),type);
    nativeMissing(native,at,"native values of %s are not implemented",name);
    return 0;
}

/* x0 holds a result of `type`; trap unless it fits the declared width. */
static void nativeFits(Native *native, RangeNode *type, RangeNode *at, const char *operation)
{
    if (type->scalarBits >= 64) return;
    nativeEmit(native,type->scalarSigned ? armSbfx(9,0,type->scalarBits) : armUbfx(9,0,type->scalarBits));
    nativeEmit(native,armCmp(9,0));
    char name[160]; describeType(name,sizeof(name),type);
    nativeTrap(native,armBcond(RangeNE,0),at,"result of '%s' does not fit %s",operation,name);
}

static void nativeExpression(Native *, RangeNode *);

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

static void nativeCall(Native *native, RangeNode *call)
{
    RangeNode *function = call->a ? call->a->resolvedDeclaration : NULL;
    if (!function || function->kind != RangeNodeFunction || call->a->kind != RangeNodeName) {
        nativeMissing(native,call,"native method calls are not implemented");
        return;
    }
    if (function->typeName) { nativeMissing(native,call,"native calls to '%s.%s' are not implemented",function->typeName,function->name); return; }
    if (function->flags & (RangeFlagBuiltin | RangeFlagExtern)) {
        nativeMissing(native,call,"native calls to builtin function '%s' are not implemented",function->name);
        return;
    }
    if (call->itemCount > 8) { nativeMissing(native,call,"calls with more than 8 arguments are not implemented"); return; }
    for (size_t i = 0; i < call->itemCount; ++i) {
        nativeExpression(native,call->items[i]->a);
        nativeEmit(native,armPush(0));
    }
    for (size_t i = call->itemCount; i-- > 0;) nativeEmit(native,armPop((int)i));
    NativeCall site = {.at=nativeEmit(native,armBl(0)),.function=function};
    NATIVE_PUSH(native->calls,native->callCount,native->callCapacity,site);
}

static void nativeExpression(Native *native, RangeNode *expr)
{
    if (!expr) return;
    switch (expr->kind) {
    case RangeNodeInteger:
        if (nativeScalar(native,expr->type,expr)) nativeConstant(native,0,(uint64_t)expr->integer);
        break;
    case RangeNodeBool:
        nativeConstant(native,0,expr->integer ? 1 : 0);
        break;
    case RangeNodeName: {
        int32_t offset = nativeSlot(native,expr->resolvedDeclaration);
        if (!offset) { nativeMissing(native,expr,"native access to '%s' is not implemented",expr->name); break; }
        nativeLoad(native,0,offset);
        break;
    }
    case RangeNodeUnary:
        nativeExpression(native,expr->a);
        if (same(expr->name,"!")) { nativeEmit(native,armCmpImm(0,0)); nativeEmit(native,armCset(0,RangeEQ)); break; }
        if (!nativeScalar(native,expr->type,expr)) break;
        if (expr->type->scalarBits == 64 && expr->type->scalarSigned) {
            char name[160]; describeType(name,sizeof(name),expr->type);
            nativeEmit(native,armNegs(0,0));
            nativeTrap(native,armBcond(RangeVS,0),expr,"result of '-' does not fit %s",name);
        } else {
            nativeEmit(native,armNeg(0,0));
            nativeFits(native,expr->type,expr,"-");
        }
        break;
    case RangeNodeBinary: {
        const char *op = expr->name;
        if (same(op,"&&") || same(op,"||")) {
            nativeExpression(native,expr->a);
            size_t skip = nativeEmit(native,same(op,"&&") ? armCbz(0,0) : armCbnz(0,0));
            nativeExpression(native,expr->b);
            uint32_t base = same(op,"&&") ? armCbz(0,0) : armCbnz(0,0);
            rangePatch(&native->machine,skip,base | (uint32_t)(((native->machine.size - skip) / 4) & 0x7FFFF) << 5);
            break;
        }
        RangeNode *operand = expr->a->type;
        nativeExpression(native,expr->a);
        nativeEmit(native,armPush(0));
        nativeExpression(native,expr->b);
        nativeEmit(native,armMov(1,0));
        nativeEmit(native,armPop(0));
        if (!nativeScalar(native,operand,expr)) break;
        int isSigned = operand->scalarSigned;
        int cond = same(op,"==") ? RangeEQ : same(op,"!=") ? RangeNE
            : same(op,"<") ? (isSigned ? RangeLT : RangeLO) : same(op,">") ? (isSigned ? RangeGT : RangeHI)
            : same(op,"<=") ? (isSigned ? RangeLE : RangeLS) : same(op,">=") ? (isSigned ? RangeGE : RangeHS) : -1;
        if (cond >= 0) { nativeEmit(native,armCmp(0,1)); nativeEmit(native,armCset(0,cond)); }
        else nativeArithmetic(native,expr,operand);
        break;
    }
    case RangeNodeCall:
        nativeCall(native,expr);
        break;
    default:
        nativeMissing(native,expr,"native %s expressions are not implemented",rangeNodeKindName(expr->kind));
        break;
    }
}

static void nativeStatement(Native *, RangeNode *);

static void nativeBlock(Native *native, RangeNode *block)
{
    for (size_t i = 0; block && i < block->itemCount; ++i) nativeStatement(native,block->items[i]);
}

static void nativeBranchHere(Native *native, size_t at, uint32_t base)
{
    int32_t words = (int32_t)((native->machine.size - at) / 4);
    uint32_t patched = (base & 0xFC000000u) == 0x14000000u ? armB(words) : base | ((uint32_t)words & 0x7FFFFu) << 5;
    rangePatch(&native->machine,at,patched);
}

static void nativeStatement(Native *native, RangeNode *node)
{
    if (!node) return;
    switch (node->kind) {
    case RangeNodeBlock: nativeBlock(native,node); break;
    case RangeNodeLet: case RangeNodeState: {
        if (!nativeScalar(native,node->type,node)) break;
        if (node->typeName && (node->flags & RangeFlagApplication) && !(node->a && node->a->kind == RangeNodeCall)) {
            nativeMissing(native,node,"value construction for '%s' is not implemented",node->typeName);
            break;
        }
        int32_t offset = nativeNewSlot(native,node);
        // A bare name that resolved to a value is a copy; to a type, a requirement.
        RangeNode *copied = node->rhsReference ? node->rhsReference->resolvedDeclaration : NULL;
        RangeNode *value = !node->typeName || (node->a && node->a->kind == RangeNodeCall) ? rangeNodeRHS(node)
            : copied && (rangeNodeDeclaresValue(copied->kind) || copied->kind == RangeNodeParameter) ? node->rhsReference : NULL;
        if (value) nativeExpression(native,value);
        else nativeEmit(native,armMovz(0,0,0)); /* a requirement without a value starts at zero */
        nativeStore(native,0,offset);
        break;
    }
    case RangeNodeAssign: {
        int32_t offset = nativeSlot(native,node->a ? node->a->resolvedDeclaration : NULL);
        if (!offset) { nativeMissing(native,node,"native assignment to this target is not implemented"); break; }
        nativeExpression(native,node->b);
        nativeStore(native,0,offset);
        break;
    }
    case RangeNodeIf: {
        nativeExpression(native,node->a);
        size_t otherwise = nativeEmit(native,armCbz(0,0));
        nativeStatement(native,node->b);
        if (node->c) {
            size_t end = nativeEmit(native,armB(0));
            nativeBranchHere(native,otherwise,armCbz(0,0));
            nativeStatement(native,node->c);
            nativeBranchHere(native,end,armB(0));
        } else nativeBranchHere(native,otherwise,armCbz(0,0));
        break;
    }
    case RangeNodeWhile: {
        size_t top = native->machine.size;
        nativeExpression(native,node->a);
        size_t exit = nativeEmit(native,armCbz(0,0));
        nativeStatement(native,node->b);
        nativeEmit(native,armB(-(int32_t)((native->machine.size - top) / 4)));
        nativeBranchHere(native,exit,armCbz(0,0));
        break;
    }
    case RangeNodeReturn: {
        if (node->a) nativeExpression(native,node->a);
        NativeJump jump = {.at=nativeEmit(native,armB(0)),.branch=armB(0)};
        NATIVE_PUSH(native->returns,native->returnCount,native->returnCapacity,jump);
        break;
    }
    case RangeNodeExpressionStatement:
        if (node->a && node->a->kind == RangeNodeAttribute)
            nativeMissing(native,node,"runtime macro application '@%s' is not implemented",node->a->name);
        else nativeExpression(native,node->a);
        break;
    default:
        nativeMissing(native,node,"native %s statements are not implemented",rangeNodeKindName(node->kind));
        break;
    }
}

/* One function or the entry block: frame, parameters, body, epilogue. A body
 * that ends without returning returns zero. */
static void nativeFunction(Native *native, RangeNode *function, RangeNode *body)
{
    NATIVE_PUSH(native->functions,native->functionCount,native->functionCapacity,function);
    native->offsets = realloc(native->offsets,native->functionCapacity * sizeof(*native->offsets));
    if (!native->offsets) abort();
    native->offsets[native->functionCount - 1] = native->machine.size;
    native->slotCount = 0; native->returnCount = 0;
    nativeEmit(native,armPushFrame());
    nativeEmit(native,armAddImm(29,31,0)); /* mov x29, sp */
    size_t frame = nativeEmit(native,armSubImm(31,31,0));
    if (function->kind == RangeNodeFunction) {
        if (function->itemCount > 8) nativeMissing(native,function,"functions with more than 8 parameters are not implemented");
        for (size_t i = 0; i < function->itemCount && i < 8; ++i) {
            RangeNode *parameter = function->items[i];
            if (!nativeScalar(native,parameter->type,parameter)) continue;
            nativeStore(native,(int)i,nativeNewSlot(native,parameter));
        }
        if (function->b && !nativeScalar(native,function->type,function->b)) return;
    }
    nativeBlock(native,body);
    nativeEmit(native,armMovz(0,0,0));
    for (size_t i = 0; i < native->returnCount; ++i) nativeBranchHere(native,native->returns[i].at,armB(0));
    nativeEmit(native,armAddImm(31,29,0)); /* mov sp, x29 */
    nativeEmit(native,armPopFrame());
    nativeEmit(native,armRet());
    size_t bytes = (native->slotCount * 8 + 15) / 16 * 16;
    if (bytes > 4095) nativeMissing(native,function,"frames larger than 4095 bytes are not implemented");
    else rangePatch(&native->machine,frame,armSubImm(31,31,(uint32_t)bytes));
}

/* Trap stubs: write the message to stderr, then exit with status 134, as an
 * abort would, without the delay of a crash report. */
static void nativeTraps(Native *native)
{
    size_t *stubs = calloc(native->trapCount ? native->trapCount : 1,sizeof(*stubs));
    size_t *messages = calloc(native->trapCount ? native->trapCount : 1,sizeof(*messages));
    if (!stubs || !messages) abort();
    for (size_t i = 0; i < native->trapCount; ++i) {
        NativeTrap *trap = &native->traps[i];
        stubs[i] = native->machine.size;
        int32_t words = (int32_t)((stubs[i] - trap->at) / 4);
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
    free(stubs); free(messages);
}

/* Compile every function and the entry block; write the executable when
 * nothing is missing. Returns 1 when an executable was written. */
static int emitNative(SourceReport *report, const char *path)
{
    Native native = {.report=report};
    RangeNode *entry = NULL;
    size_t entries = 0;
    for (size_t u = 0; u < report->count; ++u) for (size_t i = 0; i < report->units[u]->itemCount; ++i)
        if (report->units[u]->items[i]->kind == RangeNodeMain) { entry = report->units[u]->items[i]; ++entries; }
    if (entries > 1) { sourceDiagnostic(report,entry,0,"entry","the program has %zu entry blocks; it needs one",entries); return 0; }
    if (entry) nativeFunction(&native,entry,entry->a);
    for (size_t u = 0; u < report->count; ++u) for (size_t i = 0; i < report->units[u]->itemCount; ++i) {
        RangeNode *item = report->units[u]->items[i];
        if (item->kind == RangeNodeFunction && !(item->flags & (RangeFlagBuiltin | RangeFlagExtern)))
            nativeFunction(&native,item,item->a);
        else if (item->kind == RangeNodeConstruct)
            for (size_t j = 0; j < item->itemCount; ++j)
                if (item->items[j]->kind == RangeNodeFunction && !(item->items[j]->flags & RangeFlagBuiltin))
                    nativeMissing(&native,item->items[j],"native methods ('%s.%s') are not implemented",item->name,item->items[j]->name);
    }
    for (size_t i = 0; i < native.callCount; ++i) {
        size_t target = SIZE_MAX;
        for (size_t f = 0; f < native.functionCount; ++f)
            if (native.functions[f] == native.calls[i].function) target = native.offsets[f];
        if (target == SIZE_MAX) continue; /* reported where the function was compiled */
        rangePatch(&native.machine,native.calls[i].at,armBl((int32_t)((int64_t)target - (int64_t)native.calls[i].at) / 4));
    }
    nativeTraps(&native);
    int written = 0;
    if (!native.failed && entry) {
        char error[512];
        if (rangeWriteExecutable(&native.machine,0,path,error,sizeof(error))) written = 1;
        else sourceDiagnostic(report,NULL,0,"output","%s",error);
    }
    rangeMachineFree(&native.machine);
    free(native.slots); free(native.returns); free(native.calls); free(native.traps);
    free(native.functions); free(native.offsets);
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
        if (resolved && !failures) diagnoseMacroApplications(&report);
        for (size_t u = 0; u < unitCount; ++u) diagnoseSourceNode(&report,NULL,units[u],0);
        diagnoseDuplicates(&report);
        for (size_t u = 0; u < unitCount; ++u) diagnoseBuiltinFunctions(&report,units[u]);
        if (resolved && !failures) typeCheck(&report);
        // Native code is generated from a complete, well-typed graph only.
        int written = resolved && !failures && !report.errors && emitNative(&report,output);
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
