/* Macro application: shape and application rounds, merging what
 * applications emit, and the laws typing queues. */
#define _XOPEN_SOURCE 700
#include "compiler.h"
#include <setjmp.h>
#include <stdio.h>
#include <string.h>

int compilerAttribute(RangeNode *target, RangeNode *attribute)
{
    return same(attribute->name,"builtin")
        || (target->kind == RangeNodeFunction && same(attribute->name,"extern"))
        || macroBuiltin(attribute->resolvedDeclaration,"literal");
}

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
RangeNode *runMacroApplication(Resolver *vm, RangeNode *attribute)
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

void mergeEmitted(Resolver *vm, RangeNode *emitted)
{
    for (size_t i = 0; i < emitted->itemCount; ++i) {
        RangeNode *node = emitted->items[i];
        if (node->kind == RangeNodeExtension) { mergeExtension(vm,node); continue; }
        rangeNodeAppend(vm->arena,vm->unit,node);
        resolveMergedNode(vm,node);
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

/* Apply every macro. The type checker exists from the start, so macro time
 * can type what it runs; the typer returned finishes in typeCheck. */
Typer *diagnoseMacroApplications(SourceReport *report)
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
 * the supplied literal in the member it populates. A run reads the
 * declaration itself as the specialization sees it: a generic's value is the
 * specialization's, and that member's is the literal. A literal's outcome is
 * reused for every equal literal of the same type. */
static void checkLaws(Typer *typer, RangeNode *specialization, RangeNode *value, RangeNode *at)
{
    RangeNode *declaration = specialization->resolvedDeclaration;
    if (!declaration->c || !declaration->c->itemCount) return;
    if (!value) {
        if (specialization->found & RangeFlagChecked) return;
        specialization->found |= RangeFlagChecked;
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
    RangeNode *holder = NULL;
    if (value) {
        size_t holders = 0;
        holder = literalHolder(declaration,value,&holders);
        if (holders != 1) {
            sourceDiagnostic(typer->report,at,0,"not-implemented",
                "literal materialization for '%s' is not implemented: %zu members hold a %s literal",
                declaration->name,holders,value->resolvedDeclaration->name);
            return;
        }
    }
    size_t items = declaration->itemCount;
    for (size_t i = 0; i < declaration->c->itemCount; ++i) {
        RangeNode *attribute = declaration->c->items[i];
        RangeMacroApplication *declared = attribute->macroApplication;
        if (!declared || compilerAttribute(declaration,attribute) || !declared->declaration->a) continue;
        if (macroBuiltin(declared->declaration,"many")) continue;
        RangeMacroApplication *app = rangeArenaAllocate(arena,sizeof(*app));
        *app = (RangeMacroApplication){.declaration=declared->declaration,.target=declaration,.unit=declared->unit,
            .attribute=attribute,.specialization=specialization,.slot=holder,.literal=value,.items=items};
        jmp_buf outer;
        memcpy(outer,vm->failure,sizeof(outer));
        if (setjmp(vm->failure) == 0) (void)evalApplication(vm,app,0);
        else {
            char type[160], text[768];
            describeType(type,sizeof(type),specialization);
            snprintf(text,sizeof(text),"%s does not satisfy @%s: %s",type,app->declaration->name,vm->error);
            sourceDiagnostic(typer->report,at,0,"law","%s",text);
            if (failureCount < sizeof(failures)/sizeof(*failures))
                failures[failureCount++] = rangeArenaIntern(arena,text,strlen(text));
        }
        memcpy(vm->failure,outer,sizeof(outer));
    }
    if (known) {
        known->failures = rangeArenaAllocate(arena,(failureCount ? failureCount : 1) * sizeof(*known->failures));
        memcpy(known->failures,failures,failureCount * sizeof(*failures));
        known->failureCount = failureCount;
    }
}

/* A law to run once typing is back at the top level. */
void queueLaws(Typer *typer, RangeNode *specialization, RangeNode *value, RangeNode *at)
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
void drainLaws(Typer *typer)
{
    for (size_t i = 0; i < typer->queuedCount; ++i)
        checkLaws(typer,typer->queued[i].type,typer->queued[i].value,typer->queued[i].at);
    typer->queuedCount = 0;
}
