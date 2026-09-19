#define main rangeCompilerMain
#include "../../../Language/Compiler/Source/compiler.c"
#undef main
#include <assert.h>

static SourceDiagnostic *diagnostic(SourceReport *report, const char *category, const char *text)
{
    for (SourceDiagnostic *d = report->first; d; d = d->next)
        if (same(d->category,category) && strstr(d->message,text)) return d;
    return NULL;
}

static SourceReport collect(RangeArena *arena, const char *source, const char *definitions)
{
    rangeArenaInit(arena); rangeGraphInitTypes(arena);
    RangeNode **units = rangeArenaAllocate(arena,2*sizeof(*units));
    const char *sources[] = {source,definitions};
    const char *paths[] = {"Source.range","Definitions.range"};
    size_t count = definitions ? 2 : 1;
    char error[512];
    for (size_t i = 0; i < count; ++i) {
        units[i] = rangeParseUnit(arena,paths[i],sources[i],strlen(sources[i]),error,sizeof(error));
        if (!units[i]) fprintf(stderr,"%s\n",error);
        assert(units[i]);
    }
    SourceReport report = {.arena=arena,.units=units,.count=count};
    for (size_t i = 0; i < count; ++i) diagnoseSourceNode(&report,NULL,units[i],0);
    return report;
}

int main(void)
{
    RangeArena arena;
    const char *source = "construct Packet { let words: Array<Word> let label: Label } "
        "function send(let input: Input): Output { let copy: input return copy }";
    SourceReport report = collect(&arena,source,NULL);
    assert(report.errors == 5);
    const char *missing[] = {"'Array'","'Word'","'Label'","'Input'","'Output'"};
    for (size_t i = 0; i < 5; ++i) {
        SourceDiagnostic *d = diagnostic(&report,"undeclared",missing[i]);
        assert(d && same(d->at->path,"Source.range") && d->at->column > 0);
    }
    assert(!diagnostic(&report,"undeclared","'input'"));
    assert(!diagnostic(&report,"undeclared","'copy'"));
    rangeArenaDestroy(&arena);
    report = collect(&arena,source,"construct Array<let Element: Word> {} construct Word {} "
        "construct Label {} construct Input {} construct Output {}");
    assert(!report.errors && !report.warnings);
    rangeArenaDestroy(&arena);

    report = collect(&arena,"construct Number {} function f(let Bool: Number): Bool { return Bool }",NULL);
    assert(report.errors == 1 && diagnostic(&report,"undeclared","'Bool'"));
    rangeArenaDestroy(&arena);
    report = collect(&arena,"construct Kind {} function echo<let Element: Kind>(let value: Element): Element "
        "{ let copy: value return copy }",NULL);
    assert(!report.errors);
    rangeArenaDestroy(&arena);
    report = collect(&arena,"construct Box { let earlier: later let later: 1 }",NULL);
    assert(!report.errors); /* dependency checking owns ordering; this name exists */
    rangeArenaDestroy(&arena);

    report = collect(&arena,"macro inspect(): Macro {}",NULL);
    assert(report.errors == 1 && diagnostic(&report,"undeclared","C graph shape but no Range declaration"));
    rangeArenaDestroy(&arena);
    report = collect(&arena,"construct Box { let a: Missing let b: Missing }",NULL);
    assert(report.errors == 1 && diagnostic(&report,"undeclared","'Missing'")->uses == 2);
    rangeArenaDestroy(&arena);

    source = "construct Construct {} macro inspect(): Construct { "
        "let selected: #members.filter(named: \"payload\").first if selected.isTarget {} }";
    report = collect(&arena,source,"construct Bag { function filter(let named: Bag): Bag { return named } "
        "function first(): Bag { return Bag } function isTarget(): Bag { return Bag } }");
    assert(!report.errors);
    assert(diagnostic(&report,"C-implementation","filter(named:)"));
    assert(diagnostic(&report,"C-implementation","'.first'"));
    assert(diagnostic(&report,"C-implementation","'.isTarget'"));
    rangeArenaDestroy(&arena);

    report = collect(&arena,"// .first filter(named:)\nfunction text() { return \".first filter(named:) .isTarget\" }",NULL);
    assert(!report.errors && report.warnings == 1);
    assert(!diagnostic(&report,"C-implementation","hard-coded"));
    rangeArenaDestroy(&arena);
    report = collect(&arena,"@builtin(\"diagnostic\") macro say(let message: Text) "
        "@builtin(\"literal\") macro pattern(let regex: Text): Macro "
        "@pattern(\"[0-9]+\") macro inspect(): Construct { @say(\"a diagnostic\") }",
        "construct Text {} construct Macro {} construct Construct {}");
    assert(!report.errors && !report.warnings); /* explicit primitive metadata */
    rangeArenaDestroy(&arena);
    report = collect(&arena,"@builtin(missingTag) macro example()",NULL);
    assert(diagnostic(&report,"undeclared","'missingTag'"));
    rangeArenaDestroy(&arena);

    report = collect(&arena,"construct Packet {} function make() { let packet: Packet() }",NULL);
    assert(diagnostic(&report,"not-implemented","value construction for 'Packet'"));
    rangeArenaDestroy(&arena);
    puts("source diagnostics: all references, scopes, late definitions, C shortcuts, metadata, construction=pass");
    return 0;
}
