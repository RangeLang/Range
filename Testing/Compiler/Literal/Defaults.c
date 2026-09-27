#define main rangeCompilerMain
#include "../../../Language/Compiler/Source/compiler.c"
#undef main
#include <assert.h>

int main(void)
{
    RangeArena arena; rangeArenaInit(&arena);
    char error[512];
    rangeGraphInitTypes(&arena);
    const char *core =
        "@builtin macro literal(let pattern: String): Macro "
        "@literal(\"[0-9]+\") macro number(): Construct {} "
        "@number construct Whole<let bits: 64> { let value: 0 } "
        "@literal(\"true|false\") macro truth(): Construct {} "
        "@truth construct Logical { let value: false } "
        "@literal(\"\\\".*\\\"\") macro quoted(): Construct {} "
        "@quoted construct Text { let value: \"\" }";
    const char *project =
        "@number construct ProjectNumber { let value: 9 } "
        "function start(): Whole { return 42 } function flag(): Logical { return true } "
        "function label(): Text { let count: 3 return \"count \\(count)\" }";
    RangeNode *units[3];
    units[0] = rangeParseUnit(&arena,RANGE_LANGUAGE_DIR "/Macros/Defaults.range",core,strlen(core),error,sizeof(error));
    units[1] = rangeParseUnit(&arena,"Project.range",project,strlen(project),error,sizeof(error));
    assert(units[0] && units[1]);
    assert(resolveGraphApplications(&arena,units,2,error,sizeof(error)));
    RangeNode *number=units[0]->items[1], *whole=units[0]->items[2], *logical=units[0]->items[4];
    assert(number->literalDefault == whole);
    assert(units[1]->items[1]->a->items[0]->a->resolvedType == whole);
    assert(units[1]->items[1]->a->items[0]->a->resolvedDeclaration == number);
    assert(units[1]->items[2]->a->items[0]->a->resolvedType == logical);
    // A string literal resolves by its quoted spelling, interpolation included.
    RangeNode *text=units[0]->items[6], *quoted=units[0]->items[5];
    RangeNode *interpolated=units[1]->items[3]->a->items[1]->a;
    assert(interpolated->kind == RangeNodeString && interpolated->itemCount == 2);
    assert(interpolated->resolvedType == text && interpolated->resolvedDeclaration == quoted);
    assert(rangeNodeRHS(text->items[0])->resolvedType == text);
    assert(rangeNodeRHS(whole->generics->items[0])->resolvedType == whole);
    assert(rangeNodeRHS(whole->generics->items[0])->integer == 64);
    assert(rangeNodeRHS(whole->items[0])->resolvedType == whole);
    assert(rangeNodeRHS(whole->items[0])->integer == 0);
    assert(whole->c->items[0]->macroApplication->declaration == number);
    const char *duplicate="@number construct Other {}";
    units[2]=rangeParseUnit(&arena,RANGE_LANGUAGE_DIR "/Macros/Other.range",duplicate,strlen(duplicate),error,sizeof(error));
    assert(units[2]);
    assert(!resolveGraphApplications(&arena,units,3,error,sizeof(error)));
    assert(strstr(error,"multiple Core constructs"));
    // A project attachment cannot substitute for the missing Core default.
    whole->path="OutsideCore.range";
    assert(!resolveGraphApplications(&arena,units,2,error,sizeof(error)));
    assert(strstr(error,"requires one Core construct"));
    whole->path=RANGE_LANGUAGE_DIR "/Macros/Defaults.range";
    const char *overlap="@literal(\"[0-9]+\") macro other(): Construct {} @other construct Other {}";
    units[2]=rangeParseUnit(&arena,RANGE_LANGUAGE_DIR "/Macros/Overlap.range",overlap,strlen(overlap),error,sizeof(error));
    assert(units[2]);
    assert(!resolveGraphApplications(&arena,units,3,error,sizeof(error)));
    assert(strstr(error,"ambiguous Core literal"));
    rangeArenaDestroy(&arena);
    puts("literal defaults: Core uniqueness, project isolation, number/bool/string links, self literals, missing and ambiguous=pass");
    return 0;
}
