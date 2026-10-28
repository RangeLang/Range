/* Target identity selects the declaration and supplies every #field lookup. */
#define main rangeCompilerMain
#include "../WholeCompiler.c"
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
        "let targetName: #target.name let chosen: #target.members "
        "let config: #target.generics let attached: #target.macros "
        "let width: #target.generics.first { generic in generic.name = \"width\" } "
        "let missing: #target.members.first { member in member.name = \"absent\" } } "
        "macro inspect(): Function { let targetName: #target.name let parameters: #target.parameters "
        "let output: #target.output let body: #target.body } "
        "macro inspect(): Enum { let targetName: #target.name let chosen: #target.cases } "
        "macro inspect(): Macro { let targetName: #target.name let targetType: #target.target "
        "let body: #target.body let original: #target.body.members let expansions: #target.body.graph }");
    RangeNode *targets = parse(&arena,"Targets.range",
        "@inspect construct First<let width: 8> { let payload: 11 "
        "@inspect function nested() {} } "
        "@inspect construct Second<let width: 16> { let payload: 22 } "
        "@inspect function start(let input: Any): First { return 0 } "
        "@inspect enum Choice { case alpha case beta } "
        "@inspect macro recipe(): Construct { let original: #target.members "
        "#graph { construct Deferred {} } }");
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
        assert(same(rangeGraphStoredField(&arena,first,"name").text,"First") && same(rangeGraphStoredField(&arena,second,"name").text,"Second"));
        assert(rangeGraphStoredField(&arena,first,"members").nodes[0] == first->items[0]);
        assert(rangeGraphStoredField(&arena,second,"members").nodes[0] == second->items[0]);
        assert(rangeGraphStoredField(&arena,first,"generics").nodes[0] == first->generics->items[0]);
        assert(rangeGraphStoredField(&arena,first,"macros").nodes[0] == first->c->items[0]);
        application(function,macros->items[1]);
        assert(rangeGraphStoredField(&arena,function,"parameters").nodes[0] == function->items[0]);
        assert(rangeGraphStoredField(&arena,function,"output").node == first);
        assert(rangeGraphStoredField(&arena,function,"body").node == function->a);
        application(first->items[1],macros->items[1]);
        application(enumeration,macros->items[2]);
        assert(rangeGraphStoredField(&arena,enumeration,"cases").nodes[0] == enumeration->items[0]);
        application(recipe,macros->items[3]);
        assert(rangeGraphStoredField(&arena,recipe,"target").node == graphTypeIdentity(first));
        assert(rangeGraphStoredField(&arena,recipe,"body").node == recipe->a);
        RangeGraphValue original = rangeGraphStoredField(&arena,recipe->a,"members"), expansions = rangeGraphStoredField(&arena,recipe->a,"graph");
        assert(original.nodes[0] == recipe->a->items[0]);
        assert(expansions.count == 1);
        assert(recipe->a->items[1]->kind == RangeNodeExpressionStatement);
        assert(expansions.nodes[0] == recipe->a->items[1]->a);
        assert(recipe->a->source == targets->source);
        assert(original.nodes[0]->source == targets->source);
        assert(expansions.nodes[0]->source == targets->source);
    }
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
    reject("macro mark(): Construct { let old: #target.target.members }","field 'target' is not declared by @type Construct");
    reject("macro mark(): Construct { let old: #target.body }","field 'body' is not declared by @type Construct");
    reject("macro mark(): Function { switch { false: { let bad: #target.members }, default: {} } }","field 'members' is not declared by @type Function");
    reject("macro mark() { let bad: #target.name }","#target requires a declared macro target");
    // `#` names #target, the declaration the macro is attached to, and #graph;
    // the target's fields are members of #target.
    reject("macro mark(): Construct { let old: #members }",
           "'#members' names nothing here; in macro code, #target is the declaration the macro is attached to");

    // Primitive annotation spelling is overloadable by target too.
    rangeArenaInit(&arena); rangeGraphInitTypes(&arena);
    RangeNode *literal = parse(&arena,"LiteralTargets.range",
        "@builtin macro literal(let pattern: Text): Macro "
        "macro literal(): Construct { let targetName: #target.name } "
        "@literal(\"[0-9]+\") macro digits(): Construct {} "
        "macro digits(): Function {} "
        "@digits construct Quantity {} @digits function start() {} "
        "@literal construct Tagged {}");
    resolve(&arena,&literal,1);
    application(literal->items[4],literal->items[2]);
    application(literal->items[5],literal->items[3]);
    application(literal->items[6],literal->items[1]);
    assert(literal->items[2]->c->items[0]->resolvedDeclaration == literal->items[0]);
    assert(!literal->items[6]->literalPattern);
    char error[512]; int matched = 0;
    assert(matchLiteralRule(&arena,&literal,1,"digits","42",&matched,error,sizeof(error)) && matched);
    rangeArenaDestroy(&arena);
    puts("macro targets: identities, field adapters, overloads, isolation, rejections=pass");
    return 0;
}
