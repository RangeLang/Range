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
        "function start(): Whole { return 42 } function deferred(): Missing { return 0 }",
        "@integer construct Whole<let bits: 64, let signed: true> { let value: 0 }",
        "macro integer(): Construct { let bits: #target.generics.filter(named: \"bits\").first }"
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
    assert(app->bindings[0].value.node == construct->generics->items[0]);
    assert(rangeNodeRHS(app->bindings[0].value.node)->integer == 64);
    assert(function->a->items[0]->a->integer == 42);
    assert(rangeNodeRHS(construct->items[0])->integer == 0);
    rangeNodeAppend(&arena,units[1],rangeNodeCreate(&arena,RangeNodeConstruct,"duplicate.range",1,1));
    units[1]->items[1]->name = "Whole";
    assert(!resolveGraphApplications(&arena,units,3,error,sizeof(error)));
    assert(strstr(error,"ambiguous graph output 'Whole'"));
    rangeArenaDestroy(&arena);
    puts("graph output links: identity, macro, actual value, deferred, ambiguity=pass");
    return 0;
}
