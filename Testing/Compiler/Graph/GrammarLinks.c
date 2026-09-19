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

#define BUILTIN "@builtin(\"syntax\") macro syntax(): Construct "

int main(void)
{
    RangeArena arena; rangeArenaInit(&arena); rangeGraphInitTypes(&arena);
    // Only the three definition folders supply language-owned identities.
    RangeNode pathProbe = {0};
    const char *languagePaths[] = {
        RANGE_LANGUAGE_DIR "/Grammar/Return.range",
        RANGE_LANGUAGE_DIR "/Macros/Syntax.range",
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
    const char *core = BUILTIN
        "@syntax { construct $name { $members } } "
        "construct Construct { let name: String let members: Array<Member> let generics: Array<Generic> let macros: Array<Macro> } "
        "@syntax { function $name($parameters): $output { $body } } "
        "@syntax { function $name($parameters) { $body } } "
        "construct Function { let name: String let parameters: @many Parameter? let output: Construct? let body: @many Return? } "
        "@syntax { let $name: $value } @syntax { let $name } "
        "construct Member { let name: String let value: Any? } "
        "@syntax { return // trivia is immaterial\n $value } @syntax { return } "
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
    RangeNode *construct = units[0]->items[1], *function = units[0]->items[2];
    RangeNode *member = units[0]->items[3], *returns = units[0]->items[4];
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
    assert(units[0]->items[5]->b->resolvedDeclaration == construct);
    assert(box->c->items[0]->macroApplication->bindings[0].value.node == box->items[0]);
    RangeNode *syntax = returns->c->items[0];
    assert(syntax->resolvedDeclaration == units[0]->items[0]);
    assert(syntax->syntaxCaptures->itemCount == 1);
    assert(syntax->syntaxCaptures->items[0]->resolvedDeclaration == returns->items[0]);
    assert(returns->c->items[1]->syntaxCaptures->itemCount == 0);
    // Re-resolution must rebuild bindings without confusing Core and project names.
    assert(resolveGraphApplications(&arena,units,2,error,sizeof(error)));
    assert(start->a->items[1]->grammarDefinition == returns);
    // Merely placing a grammar-named construct in a project cannot claim the adapter.
    units[0]->items[4]->path = "ProjectReturn.range";
    assert(!resolveGraphApplications(&arena,units,2,error,sizeof(error)));
    assert(strstr(error,"requires a Core grammar construct"));
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

    reject("@syntax { return } construct Return {}","builtin declaration is not loaded");
    reject(BUILTIN BUILTIN,"ambiguous syntax builtin");
    reject("@builtin(\"syntax\") macro syntax(): Member","requires Core macro");
    reject(BUILTIN "@syntax { return $missing } construct Return { let value: Any? }","not a field of Return");
    reject(BUILTIN "@syntax { return $value $value } construct Return { let value: Any? }","duplicate syntax capture");
    reject(BUILTIN "@syntax { yield $value } construct Return { let value: Any? }","unsupported C syntax template");
    reject(BUILTIN "@syntax { mystery } construct Mystery {}","no C syntax adapter");
    reject(BUILTIN "@syntax { return } construct Return {} @syntax { return } construct Return {}","ambiguous Core grammar construct");
    reject(BUILTIN "@syntax construct Return {}","requires a template block");
    reject(BUILTIN "@syntax { return } construct Return { let value: Any? let value: Any? }","duplicate Core grammar field");
    reject(BUILTIN "@syntax { return } construct Return { let extra: Any? }","no C field adapter");
    reject(BUILTIN "construct Outer { @syntax { return } construct Return {} }","top-level Core grammar construct");
    puts("Core grammar: node/field identities, macro target, bare members, source isolation, invalid templates=pass");
    return 0;
}
