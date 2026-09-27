/* Each member keyword is its own node kind; @member names any kind that applied it. */
#define main rangeCompilerMain
#include "../../../Language/Compiler/Source/compiler.c"
#undef main
#include <assert.h>

#define GRAMMAR \
    "macro member(): Construct {} " \
    "@member construct Let { let name: String let value: Any? } " \
    "@member construct State { let name: String let value: Any? } " \
    "@member construct Derived { let name: String let value: Any? } " \
    "@member construct Binding { let name: String let value: Any? } " \
    "construct Construct { let name: String let members: Array<@member> } "

static RangeNode *parse(RangeArena *arena, const char *path, const char *source)
{
    char error[512];
    RangeNode *unit = rangeParseUnit(arena,path,source,strlen(source),error,sizeof(error));
    if (!unit) fprintf(stderr,"%s\n",error);
    assert(unit);
    return unit;
}

/* Grammar and project units resolve together; returns the error, if any. */
static int resolve(RangeArena *arena, RangeNode **units, const char *project, char *error)
{
    rangeArenaInit(arena); rangeGraphInitTypes(arena);
    units[0] = parse(arena,RANGE_LANGUAGE_DIR "/Grammar/Members.range",GRAMMAR);
    units[1] = parse(arena,"Project.range",project);
    return resolveGraphApplications(arena,units,2,error,512);
}

static void reject(const char *project, const char *expected)
{
    RangeArena arena; RangeNode *units[2]; char error[512];
    int ok = resolve(&arena,units,project,error);
    if (ok || !strstr(error,expected)) fprintf(stderr,"expected %s; got %s\n",expected,ok ? "success" : error);
    assert(!ok && strstr(error,expected));
    rangeArenaDestroy(&arena);
}

int main(void)
{
    RangeArena arena; RangeNode *units[2]; char error[512];

    // Each keyword selects its own shape and grammar declaration.
    int ok = resolve(&arena,units,
        "construct Box { let a: 1 state b: 2 derived c: 3 binding d: 4 } "
        "function start() { let local: 1 state counter: 0 }",error);
    if (!ok) fprintf(stderr,"%s\n",error);
    assert(ok);
    RangeNode *box = units[1]->items[0], *start = units[1]->items[1];
    const char *kinds[] = {"Let","State","Derived","Binding"};
    const RangeNodeKind nodes[] = {RangeNodeLet,RangeNodeState,RangeNodeDerived,RangeNodeBinding};
    for (size_t i = 0; i < 4; ++i) {
        assert(box->items[i]->kind == nodes[i] && !box->items[i]->flags);
        assert(same(box->items[i]->graphType->name,kinds[i]));
        assert(box->items[i]->grammarDefinition == units[0]->items[i + 1]);
    }
    // A let or state inside a function is the same kind as one in a construct.
    assert(start->a->items[0]->kind == RangeNodeLet && same(start->a->items[0]->graphType->name,"Let"));
    assert(start->a->items[1]->kind == RangeNodeState && same(start->a->items[1]->graphType->name,"State"));
    RangeNode *members = units[0]->items[5]->items[1];
    assert(members->generics->items[0]->a->flags & RangeFlagMacroType);
    assert(same(members->generics->items[0]->a->name,"member"));
    rangeArenaDestroy(&arena);

    // A concrete target admits one kind; a macro type admits every kind that applied it.
    ok = resolve(&arena,units,
        "macro grow(): State {} "
        "macro describe(): @member { let label: #name } "
        "construct Box { @grow state items: 0 @describe let a: 1 @describe binding b: 2 }",error);
    if (!ok) fprintf(stderr,"%s\n",error);
    assert(ok);
    RangeNode *grow = units[1]->items[0], *describe = units[1]->items[1];
    box = units[1]->items[2];
    assert(describe->b->resolvedDeclaration == units[0]->items[0]);
    assert(box->items[0]->c->items[0]->resolvedDeclaration == grow);
    assert(box->items[1]->c->items[0]->resolvedDeclaration == describe);
    assert(box->items[2]->c->items[0]->resolvedDeclaration == describe);
    assert(same(box->items[2]->c->items[0]->macroApplication->bindings[0].value.text,"b"));
    rangeArenaDestroy(&arena);

    reject("macro grow(): State {} construct Box { @grow let items: 0 }","no macro 'grow' targets Let");
    reject("macro describe(): @member {} macro describe(): State {} construct Box { @describe state a: 1 }",
           "ambiguous graph macro 'describe'");
    reject("macro describe(): @member { let bad: #members }",
           "field 'members' is not declared by Let, which applies @member");
    reject("macro describe(): @missing {}","unknown macro type '@missing'");
    reject("macro unused(): Construct {} macro describe(): @unused { let label: #name }",
           "no declaration kind applies @unused");
    puts("member kinds: shapes, grammar identities, macro types, nominal targets, rejections=pass");
    return 0;
}
