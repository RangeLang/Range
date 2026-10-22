/* Inspect pointer identity, not just a matching printed name. */
#define main rangeCompilerMain
#include "../../../Language/Compiler/Source/compiler.c"
#undef main
#include <assert.h>

int main(void)
{
    RangeArena arena;
    rangeArenaInit(&arena);
    char error[512];
    rangeGraphInitTypes(&arena);
    const char *sources[] = {
        ("function start(): Whole { return 42 } function deferred(): Missing { return 0 } "
         "function throughCall(): Whole { return start() } function finish() { return } "
         "function take(let w: Whole, let m: Missing): Whole { return w }"),
        "@integer construct Whole<let bits: 64, let signed: true> { let value: 0  function same(let other: Whole): Whole { return other } }",
        "macro integer(): Construct { let bits: #generics let first: #generics.first(named: \"bits\") }"
    };
    RangeNode *units[3];
    for (size_t i = 0; i < 3; ++i) {
        units[i] = rangeParseUnit(&arena,"output-links.range",sources[i],strlen(sources[i]),error,sizeof(error));
        assert(units[i]);
    }
    assert(resolveGraphApplications(&arena,units,3,error,sizeof(error)));
    RangeNode *function = units[0]->items[0], *construct = units[1]->items[0];
    assert(function->b->resolvedDeclaration == construct);
    assert(rangeGraphStoredField(&arena,function,"output").node == construct);
    assert(!units[0]->items[1]->b->resolvedDeclaration);
    RangeMacroApplication *app = construct->c->items[0]->macroApplication;
    assert(app && app->target == construct && app->declaration == units[2]->items[0]);
    // A field chain resolves with the application; a call is Range code and
    // waits until the application runs.
    assert(app->bindings[0].state == 2 && app->bindings[0].value.kind == RangeGraphNodes);
    assert(app->bindings[0].value.nodes[0] == construct->generics->items[0]);
    assert(rangeNodeRHS(app->bindings[0].value.nodes[0])->integer == 64);
    assert(app->bindings[1].state == 0);
    assert(function->a->items[0]->a->integer == 42);
    RangeNode *call = units[0]->items[2]->a->items[0]->a;
    assert(units[0]->items[2]->b->resolvedDeclaration == construct);
    assert(call->kind == RangeNodeCall && same(call->a->name,"start"));
    assert(units[0]->items[3]->a->items[0]->kind == RangeNodeReturn);
    assert(!units[0]->items[3]->a->items[0]->a);
    assert(rangeNodeRHS(construct->items[0])->integer == 0);
    // Parameter.type and Function.receiver are declarations, absent when unresolved.
    RangeNode *take = units[0]->items[4], *method = construct->items[1];
    assert(rangeGraphStoredField(&arena,take->items[0],"type").node == construct);
    assert(rangeGraphStoredField(&arena,take->items[1],"type").kind == RangeGraphNone);
    assert(rangeGraphStoredField(&arena,take,"receiver").kind == RangeGraphNone);
    assert(rangeGraphStoredField(&arena,method,"receiver").node == construct);
    assert(rangeGraphStoredField(&arena,method->items[0],"type").node == construct);
    rangeNodeAppend(&arena,units[1],rangeNodeCreate(&arena,RangeNodeConstruct,"duplicate.range",1,1));
    units[1]->items[1]->name = "Whole";
    assert(!resolveGraphApplications(&arena,units,3,error,sizeof(error)));
    assert(strstr(error,"ambiguous graph output 'Whole'"));
    rangeArenaDestroy(&arena);
    puts("graph output links: identity, macro, actual value, deferred, parameter types, receivers, ambiguity=pass");
    return 0;
}
