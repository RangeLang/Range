/* #graph emission: macros add ordinary code, which is checked where it lands. */
#define main rangeCompilerMain
#include "../../../Language/Compiler/Source/compiler.c"
#undef main
#include <assert.h>

typedef struct {
    RangeArena arena;
    RangeNode *unit;
    SourceReport report;
} Compiled;

/* The compiler's normal order: build the graph, apply macros, resolve names. */
static void compile(Compiled *compiled, const char *source)
{
    rangeArenaInit(&compiled->arena); rangeGraphInitTypes(&compiled->arena);
    char error[512];
    compiled->unit = rangeParseUnit(&compiled->arena,"Emission.range",source,strlen(source),error,sizeof(error));
    if (!compiled->unit) fprintf(stderr,"%s\n",error);
    assert(compiled->unit);
    compiled->report = (SourceReport){.arena=&compiled->arena,.units=&compiled->unit,.count=1};
    int ok = resolveGraphApplications(&compiled->arena,&compiled->unit,1,error,sizeof(error));
    if (!ok) fprintf(stderr,"%s\n",error);
    assert(ok);
    diagnoseMacroApplications(&compiled->report);
    diagnoseSourceNode(&compiled->report,NULL,compiled->unit,0);
    diagnoseDuplicates(&compiled->report);
}

static int reported(Compiled *compiled, const char *category, const char *text)
{
    for (SourceDiagnostic *d = compiled->report.first; d; d = d->next)
        if (!d->warning && same(d->category,category) && strstr(d->message,text)) return 1;
    return 0;
}

static RangeNode *declaration(RangeNode *owner, const char *name)
{
    for (size_t i = 0; i < owner->itemCount; ++i)
        if (same(owner->items[i]->name,name)) return owner->items[i];
    return NULL;
}

#define CORE "construct Construct {} construct Truth {} construct Text {} " \
    "@builtin macro diagnostic(let message: Text) "

int main(void)
{
    Compiled c;

    // A collection-shaped macro extends its target; bare names resolve there.
    compile(&c,CORE
        "macro collection(): Construct { "
        "let element: #generics.filter(named: \"Element\").first "
        "#graph { extension #name { "
        "state count: 0 state capacity: 0 state elements: #element "
        "function isEmpty(): Truth { return count == 0 } } } } "
        "@collection construct Array<Element> {} "
        "extension Array { let written: capacity }");
    RangeNode *array = declaration(c.unit,"Array");
    assert(array && array->itemCount == 5);
    RangeNode *elements = declaration(array,"elements");
    assert(elements && same(elements->typeName,"Element"));
    assert(elements->emittedBy == array->c->items[0]);
    assert(elements->rhsReference && elements->rhsReference->resolvedDeclaration == array->generics->items[0]);
    RangeNode *isEmpty = declaration(array,"isEmpty");
    assert(isEmpty && isEmpty->kind == RangeNodeFunction && same(isEmpty->typeName,"Array"));
    assert(declaration(array,"written") && !declaration(array,"written")->emittedBy);
    assert(!reported(&c,"undeclared","") && !reported(&c,"macro-validation",""));
    assert(!reported(&c,"duplicate",""));
    rangeArenaDestroy(&c.arena);

    // Splices take literal values and field text; emitted declarations join the unit.
    compile(&c,CORE
        "macro label(): Construct { let width: 8 "
        "#graph { construct Label { let size: #width let owner: #name } } } "
        "construct Owner {} @label construct Box {}");
    RangeNode *label = declaration(c.unit,"Label");
    assert(label && label->emittedBy);
    RangeNode *size = declaration(label,"size");
    assert(size && size->itemCount == 1 && size->items[0]->a->kind == RangeNodeInteger
        && size->items[0]->a->integer == 8);
    RangeNode *owner = declaration(label,"owner");
    assert(owner && same(owner->typeName,"Box"));
    assert(!reported(&c,"undeclared","") && !reported(&c,"macro-validation",""));
    rangeArenaDestroy(&c.arena);

    // Duplicates follow the ordinary per-scope rule, however they arrive.
    compile(&c,CORE
        "macro greeter(): Construct { #graph { construct Hello {} } } "
        "macro counted(): Construct { #graph { extension #name { let count: 0 } } } "
        "@greeter construct A {} @greeter construct B {} "
        "@counted construct Tally { let count: 1 }");
    assert(reported(&c,"duplicate","@greeter emits 'Hello', which is declared more than once in the program"));
    assert(reported(&c,"duplicate","@counted emits 'count', which is declared more than once in Tally"));
    rangeArenaDestroy(&c.arena);

    // Emitted code may apply macros; they run in a later round.
    compile(&c,CORE
        "macro mark(): Construct { #graph { extension #name { let marked: 1 } } } "
        "macro build(): Construct { #graph { @mark construct Built {} } } "
        "@build construct Seed {}");
    RangeNode *built = declaration(c.unit,"Built");
    assert(built && declaration(built,"marked"));
    assert(!reported(&c,"macro-validation",""));
    rangeArenaDestroy(&c.arena);

    // Missing extension subjects, ambiguous splices, and failed applications.
    compile(&c,CORE "extension Missing { let value: 1 }");
    assert(reported(&c,"resolution","extension of undeclared 'Missing'"));
    rangeArenaDestroy(&c.arena);
    compile(&c,CORE
        "macro clash(): Construct { let name: 1 #graph { construct Clash { let value: #name } } } "
        "@clash construct Box {}");
    assert(reported(&c,"macro-validation","#name names both a macro local and a target field"));
    assert(!declaration(c.unit,"Clash"));
    rangeArenaDestroy(&c.arena);
    compile(&c,CORE
        "macro partial(): Construct { #graph { construct Partial {} } @diagnostic(\"stop\") } "
        "@partial construct Box {}");
    assert(reported(&c,"macro-validation","stop") && !declaration(c.unit,"Partial"));
    rangeArenaDestroy(&c.arena);

    // Emission that keeps producing new applications is reported, not looped.
    compile(&c,CORE
        "macro grow(): Construct { #graph { @grow construct Again {} } } "
        "@grow construct Seed {}");
    assert(reported(&c,"macro-validation","macro emission did not settle after 16 rounds"));
    rangeArenaDestroy(&c.arena);

    puts("macro emission: extensions, splices, landing scope, duplicates, rounds, failures=pass");
    return 0;
}
