/* Target identity selects the declaration and supplies every #field lookup. */
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

static void resolve(RangeArena *arena, RangeNode **units, size_t count)
{
    char error[512];
    int ok = resolveGraphApplications(arena,units,count,error,sizeof(error));
    if (!ok) fprintf(stderr,"%s\n",error);
    assert(ok);
}

static RangeMacroApplication *application(RangeNode *target, RangeNode *macro)
{
    RangeNode *attribute = target->c->items[0];
    RangeMacroApplication *app = attribute->macroApplication;
    assert(attribute->resolvedDeclaration == macro);
    assert(app && app->declaration == macro && app->target == target);
    assert(macro->b->resolvedDeclaration == graphTypeIdentity(target));
    return app;
}

static RangeGraphValue binding(RangeMacroApplication *app, const char *name)
{
    for (size_t i = 0; i < app->count; ++i) if (same(app->bindings[i].definition->name,name)) {
        assert(app->bindings[i].state == 2);
        return app->bindings[i].value;
    }
    assert(0 && "binding is missing");
    return (RangeGraphValue){0};
}

static void reject(const char *source, const char *expected)
{
    RangeArena arena; rangeArenaInit(&arena); rangeGraphInitTypes(&arena);
    RangeNode *unit = parse(&arena,"Rejected.range",source);
    char error[512];
    int ok = resolveGraphApplications(&arena,&unit,1,error,sizeof(error));
    if (ok || !strstr(error,expected)) fprintf(stderr,"expected %s; got %s\n",expected,error);
    assert(!ok && strstr(error,expected) && strstr(error,"Rejected.range:"));
    rangeArenaDestroy(&arena);
}

int main(void)
{
    RangeArena arena; rangeArenaInit(&arena); rangeGraphInitTypes(&arena);
    RangeNode *macros = parse(&arena,"Macros.range",
        "macro inspect(): Construct { let name: \"local\" let members: 0 "
        "let targetName: #name let chosen: #members.filter(named: \"payload\").first "
        "let config: #generics.first let attached: #macros.first } "
        "macro inspect(): Function { let targetName: #name let parameters: #parameters "
        "let output: #output let body: #body } "
        "macro inspect(): Enum { let targetName: #name let chosen: #cases.first } "
        "macro inspect(): Macro { let targetName: #name let targetType: #target "
        "let body: #body let original: #body.members.first let expansions: #body.environment }");
    RangeNode *targets = parse(&arena,"Targets.range",
        "@inspect construct First<let width: 8> { let payload: 11 "
        "@inspect function nested() {} } "
        "@inspect construct Second<let width: 16> { let payload: 22 } "
        "@inspect function start(let input: Any): First { return 0 } "
        "@inspect enum Choice { case alpha case beta } "
        "@inspect macro recipe(): Construct { let original: #members.first "
        "#environment { @diagnostic(\"deferred target source\") } }");
    RangeNode *grammar = parse(&arena,RANGE_LANGUAGE_DIR "/Grammar/Nodes.range",
        "construct Construct { let name: String let members: Array<Member> "
        "let generics: Array<Generic> let macros: Array<Macro> } "
        "construct Function { let name: String let parameters: Array<Parameter> "
        "let output: Construct? let body: Array<Return> } "
        "construct Enum { let name: String let cases: Array<EnumCase> let macros: Array<Macro> } "
        "construct Macro { let name: String let target: Construct? }");
    RangeNode *units[] = {targets,macros,grammar};
    RangeNode *first = targets->items[0], *second = targets->items[1];
    RangeNode *function = targets->items[2], *enumeration = targets->items[3], *recipe = targets->items[4];
    // Also prove the bootstrap shapes work before language grammar identities load.
    for (size_t count = 2; count <= 3; ++count) {
        resolve(&arena,units,count);
        RangeMacroApplication *a = application(first,macros->items[0]);
        RangeMacroApplication *b = application(second,macros->items[0]);
        assert(a != b);
        assert(same(binding(a,"targetName").text,"First"));
        assert(same(binding(b,"targetName").text,"Second"));
        assert(binding(a,"chosen").node == first->items[0]);
        assert(binding(b,"chosen").node == second->items[0]);
        assert(binding(a,"config").node == first->generics->items[0]);
        assert(binding(b,"config").node == second->generics->items[0]);
        assert(binding(a,"attached").node == first->c->items[0]);
        RangeMacroApplication *f = application(function,macros->items[1]);
        assert(binding(f,"parameters").nodes[0] == function->items[0]);
        assert(binding(f,"output").node == first);
        assert(binding(f,"body").node == function->a);
        assert(same(binding(application(first->items[1],macros->items[1]),"targetName").text,"nested"));
        RangeMacroApplication *e = application(enumeration,macros->items[2]);
        assert(binding(e,"chosen").node == enumeration->items[0]);
        RangeMacroApplication *m = application(recipe,macros->items[3]);
        assert(same(binding(m,"targetName").text,"recipe"));
        assert(binding(m,"targetType").node == graphTypeIdentity(first));
        assert(binding(m,"body").node == recipe->a);
        assert(binding(m,"original").node == recipe->a->items[0]);
        assert(binding(m,"expansions").count == 1);
    }
    // Rendering reflected bodies must use the target's source, across files.
    FILE *out = tmpfile(); assert(out);
    rangeGraphWrite(out,targets);
    rewind(out);
    char rendered[16384]; size_t bytes = fread(rendered,1,sizeof(rendered)-1,out);
    rendered[bytes] = '\0'; fclose(out);
    assert(strstr(rendered,"original: let original: #members.first"));
    assert(strstr(rendered,"deferred target source"));
    RangeNode *reordered[] = {grammar,macros,targets};
    RangeNode *swap = macros->items[0]; macros->items[0] = macros->items[2]; macros->items[2] = swap;
    resolve(&arena,reordered,3);
    application(first,macros->items[2]); application(enumeration,macros->items[0]);
    rangeArenaDestroy(&arena);

    reject("macro mark(): Construct {} macro mark(): Construct {} @mark construct Box {}",
           "ambiguous graph macro 'mark' for target Construct");
    reject("macro mark(): Function {} @mark construct Box {}","no macro 'mark' targets Construct");
    reject("macro mark() {} @mark construct Box {}","no macro 'mark' targets Construct");
    reject("macro mark(): Missing {}","unknown macro target type 'Missing'");
    reject("macro mark(): Construct? {}","macro target requires one declaration type");
    reject("macro mark(): Array<Construct> {}","macro target requires one declaration type");
    reject("macro mark(): Construct { let old: #target.members }","field 'target' is not declared by @type Construct");
    reject("macro mark(): Construct { let old: #body }","field 'body' is not declared by @type Construct");
    reject("macro mark(): Function { if false { let bad: #members } }","field 'members' is not declared by @type Function");
    reject("macro mark() { let bad: #name }","#name requires a declared macro target");

    // Primitive annotation spelling is overloadable by target too.
    rangeArenaInit(&arena); rangeGraphInitTypes(&arena);
    RangeNode *literal = parse(&arena,"LiteralTargets.range",
        "@builtin(\"literal\") macro spelling(let pattern: Text): Macro "
        "macro spelling(): Construct { let targetName: #name } "
        "@spelling(\"[0-9]+\") macro digits(): Construct {} "
        "macro digits(): Function {} "
        "@digits construct Quantity {} @digits function start() {} "
        "@spelling construct Tagged {}");
    resolve(&arena,&literal,1);
    application(literal->items[4],literal->items[2]);
    application(literal->items[5],literal->items[3]);
    application(literal->items[6],literal->items[1]);
    assert(literal->items[2]->c->items[0]->resolvedDeclaration == literal->items[0]);
    assert(!literal->items[6]->literalPattern);
    char error[512]; int matched = 0;
    assert(matchLiteralRule(&arena,&literal,1,"digits","42",&matched,error,sizeof(error)) && matched);
    rangeArenaDestroy(&arena);
    puts("macro targets: direct fields, identities, overloads, isolation, reflection, rejections=pass");
    return 0;
}
