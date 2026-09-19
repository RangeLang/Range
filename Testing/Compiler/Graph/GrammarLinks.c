#define main rangeCompilerMain
#include "../../../Language/Compiler/Source/compiler.c"
#undef main
#include <assert.h>

static RangeNode *parse(RangeArena *arena, const char *path, const char *source)
{
    char error[512];
    RangeNode *unit = rangeParseUnit(arena,path,source,strlen(source),error,sizeof(error));
    if (!unit) fprintf(stderr,"%s\n",error);
    assert(unit);
    return unit;
}

static void reject(const char *source, const char *expected)
{
    RangeArena arena; rangeArenaInit(&arena); rangeGraphInitTypes(&arena);
    RangeNode *unit = parse(&arena,RANGE_LANGUAGE_DIR "/Grammar/BadGrammar.range",source);
    char error[512];
    assert(!resolveGraphApplications(&arena,&unit,1,error,sizeof(error)));
    if (!strstr(error,expected)) fprintf(stderr,"expected %s; got %s\n",expected,error);
    assert(strstr(error,expected));
    assert(strstr(error,"BadGrammar.range:"));
    rangeArenaDestroy(&arena);
}

int main(void)
{
    RangeArena arena; rangeArenaInit(&arena); rangeGraphInitTypes(&arena);
    // Only the three definition folders supply language-owned identities.
    RangeNode pathProbe = {0};
    const char *languagePaths[] = {
        RANGE_LANGUAGE_DIR "/Grammar/Return.range",
        RANGE_LANGUAGE_DIR "/Macros/Literal.range",
        RANGE_LANGUAGE_DIR "/Types/Int.range"
    };
    for (size_t i = 0; i < sizeof(languagePaths)/sizeof(*languagePaths); ++i) {
        pathProbe.path = languagePaths[i];
        assert(isLanguageNode(&pathProbe));
    }
    const char *otherPaths[] = {
        RANGE_LANGUAGE_DIR "/Compiler/Example.range",
        RANGE_LANGUAGE_DIR "/.range/Generated.range",
        RANGE_LANGUAGE_DIR "/TypesExtra/Int.range",
        "Project/Types/Int.range"
    };
    for (size_t i = 0; i < sizeof(otherPaths)/sizeof(*otherPaths); ++i) {
        pathProbe.path = otherPaths[i];
        assert(!isLanguageNode(&pathProbe));
    }
    const char *core =
        "construct Construct { let name: String let members: Array<Member> let generics: Array<Generic> let macros: Array<Macro> } "
        "construct Function { let name: String let parameters: Array<Parameter> let output: Construct? let body: Array<Return> } "
        "construct Member { let name: String let value: Any? } "
        "construct Return { let value: Any? } "
        "macro probe(): Construct { let chosen: #target.members.first }";
    RangeNode *units[] = {
        parse(&arena,RANGE_LANGUAGE_DIR "/Grammar/Grammar.range",core),
        parse(&arena,"Project.range",
            "@probe construct Box { let empty let value: 7 } "
            "construct Return { let unrelated: 0 } "
            "function start(): Box { let local return 42 } function finish() { return }")
    };
    char error[512];
    int ok = resolveGraphApplications(&arena,units,2,error,sizeof(error));
    if (!ok) fprintf(stderr,"%s\n",error);
    assert(ok);
    RangeNode *construct = units[0]->items[0], *function = units[0]->items[1];
    RangeNode *member = units[0]->items[2], *returns = units[0]->items[3];
    RangeNode *box = units[1]->items[0], *start = units[1]->items[2];
    assert(construct->grammarDefinition == construct);
    RangeNode *members = construct->items[1];
    assert(same(members->typeName,"Array"));
    assert(!(members->flags & (RangeFlagMany|RangeFlagOptional)));
    assert(members->generics->itemCount == 1);
    assert(!members->generics->items[0]->name);
    assert(same(members->generics->items[0]->a->name,"Member"));
    assert(box->grammarDefinition == construct);
    assert(start->grammarDefinition == function);
    assert(box->items[0]->grammarDefinition == member);
    assert(!rangeNodeRHS(box->items[0]));
    assert(start->a->items[0]->grammarDefinition == member);
    assert(start->a->items[1]->grammarDefinition == returns);
    assert(start->a->items[1]->a->integer == 42);
    assert(units[1]->items[3]->a->items[0]->grammarDefinition == returns);
    assert(!units[1]->items[3]->a->items[0]->a);
    assert(units[0]->items[4]->b->resolvedDeclaration == construct);
    assert(box->c->items[0]->macroApplication->bindings[0].value.node == box->items[0]);
    assert(rangeGraphStoredField(&arena,start->a->items[1],"value").node == start->a->items[1]->a);
    // Re-resolution must rebuild bindings without confusing Core and project names.
    assert(resolveGraphApplications(&arena,units,2,error,sizeof(error)));
    assert(start->a->items[1]->grammarDefinition == returns);
    // Merely placing a grammar-named construct in a project cannot claim the adapter.
    returns->path = "ProjectReturn.range";
    assert(resolveGraphApplications(&arena,units,2,error,sizeof(error)));
    assert(!start->a->items[1]->grammarDefinition);
    returns->path = RANGE_LANGUAGE_DIR "/Grammar/Grammar.range";
    assert(resolveGraphApplications(&arena,units,2,error,sizeof(error)));
    assert(start->a->items[1]->grammarDefinition == returns);
    RangeNode *arrays = parse(&arena,"Arrays.range",
        "construct Arrays { let nested: Array<Array<Member>> let named: Array<element: Member> } "
        "function compare() { return a < b }");
    RangeNode *nested = arrays->items[0]->items[0]->generics->items[0]->a;
    assert(same(nested->name,"Array"));
    assert(same(nested->generics->items[0]->a->name,"Member"));
    assert(same(arrays->items[0]->items[1]->generics->items[0]->name,"element"));
    assert(arrays->items[1]->a->items[0]->a->kind == RangeNodeBinary);
    const char *broken = "construct Broken { let members: Array<Member }";
    assert(!rangeParseUnit(&arena,"Broken.range",broken,strlen(broken),error,sizeof(error)));
    rangeArenaDestroy(&arena);

    reject("construct Return {} construct Return {}","ambiguous language grammar construct");
    reject("construct Return { let value: Any? let value: Any? }","duplicate language grammar field");
    reject("construct Return { let extra: Any? }","no C field adapter");
    // Structural syntax stays in C; old template annotations fail explicitly.
    RangeArena rejected; rangeArenaInit(&rejected);
    const char *template = "@syntax { return $value } construct Return { let value: Any? }";
    assert(!rangeParseUnit(&rejected,"Deferred.range",template,strlen(template),error,sizeof(error)));
    assert(strstr(error,"@syntax is deferred"));
    rangeArenaDestroy(&rejected);
    puts("grammar: identities without syntax macros, reflection, bare members, arrays, source isolation=pass");
    return 0;
}
