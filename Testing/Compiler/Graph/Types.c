/* Types: interned specializations, contextual literals, laws per
 * specialization, and checked calls, operators, and assignments. */
#define main rangeCompilerMain
#include "../../../Language/Compiler/Source/compiler.c"
#undef main
#include <assert.h>
#include <unistd.h>

typedef struct {
    RangeArena arena;
    RangeNode **units;
    size_t count;
    RangeNode *project;
    SourceReport report;
} Compiled;

/* The compiler's normal order over the real language sources plus a project. */
static void compile(Compiled *c, const char *project)
{
    rangeArenaInit(&c->arena); rangeGraphInitTypes(&c->arena);
    Sources sources = {0};
    const char *directories[] = {"Language/Grammar","Language/Macros","Language/Types"};
    for (size_t i = 0; i < 3; ++i) assert(collectSources(&c->arena,&sources,directories[i],0));
    c->units = rangeArenaAllocate(&c->arena,(sources.count + 1) * sizeof(*c->units));
    c->count = 0;
    char error[512];
    // Language identity is by repo-relative path, as the test build names it.
    char cwd[4096];
    assert(getcwd(cwd,sizeof(cwd)));
    size_t prefix = strlen(cwd);
    for (size_t i = 0; i < sources.count; ++i) {
        size_t size = 0;
        char *text = readFile(sources.paths[i],&size);
        assert(text);
        const char *path = sources.paths[i];
        assert(!strncmp(path,cwd,prefix) && path[prefix] == '/');
        path += prefix + 1;
        c->units[c->count] = rangeParseUnit(&c->arena,path,text,size,error,sizeof(error));
        free(text);
        if (!c->units[c->count]) fprintf(stderr,"%s\n",error);
        assert(c->units[c->count]);
        ++c->count;
    }
    free(sources.paths);
    c->project = rangeParseUnit(&c->arena,"Project.range",project,strlen(project),error,sizeof(error));
    if (!c->project) fprintf(stderr,"%s\n",error);
    assert(c->project);
    c->units[c->count++] = c->project;
    c->report = (SourceReport){.arena=&c->arena,.units=c->units,.count=c->count};
    int ok = resolveGraphApplications(&c->arena,c->units,c->count,error,sizeof(error));
    if (!ok) fprintf(stderr,"%s\n",error);
    assert(ok);
    diagnoseMacroApplications(&c->report);
    for (size_t u = 0; u < c->count; ++u) diagnoseSourceNode(&c->report,NULL,c->units[u],0);
    diagnoseDuplicates(&c->report);
    for (size_t u = 0; u < c->count; ++u) diagnoseBuiltinFunctions(&c->report,c->units[u]);
    typeCheck(&c->report);
}

static SourceDiagnostic *reported(Compiled *c, const char *category, const char *text)
{
    for (SourceDiagnostic *d = c->report.first; d; d = d->next)
        if (!d->warning && same(d->category,category) && strstr(d->message,text)) return d;
    return NULL;
}

static size_t errorsIn(Compiled *c, const char *category)
{
    size_t count = 0;
    for (SourceDiagnostic *d = c->report.first; d; d = d->next)
        if (!d->warning && same(d->category,category)) count += d->uses;
    return count;
}

static RangeNode *named(RangeNode *owner, const char *name)
{
    for (size_t i = 0; i < owner->itemCount; ++i) if (same(owner->items[i]->name,name)) return owner->items[i];
    return NULL;
}

static RangeNode *local(Compiled *c, const char *function, const char *name)
{
    RangeNode *body = named(c->project,function)->a;
    RangeNode *node = named(body,name);
    assert(node);
    return node;
}

static void expectDescription(RangeNode *type, const char *text)
{
    char buffer[160];
    describeType(buffer,sizeof(buffer),type);
    if (!same(buffer,text)) fprintf(stderr,"expected %s; got %s\n",text,buffer);
    assert(same(buffer,text));
}

int main(void)
{
    Compiled c;

    // The language sources type-check; only runtime gaps and deferred forms remain.
    compile(&c,"function nothing() {}");
    assert(!errorsIn(&c,"type") && !errorsIn(&c,"law"));
    assert(!reported(&c,"not-implemented","optional"));
    assert(!reported(&c,"layout",""));
    RangeNode *append = NULL;
    for (size_t u = 0; u < c.count && !append; ++u) {
        RangeNode *array = named(c.units[u],"Array");
        if (array && array->kind == RangeNodeConstruct) append = named(array,"append");
    }
    assert(append && append->items[0]->type && append->items[0]->type->kind == RangeNodeTypeParameter);
    rangeArenaDestroy(&c.arena);

    // Literals take the type their context requires; the law runs on the supplied value.
    compile(&c,"function widths() { let a: 0 let b: Int<bits: 64, signed: true> "
        "state narrow: Int<bits: 8> narrow: 100 narrow: 800 let same: (narrow + 1) let ok: true }");
    RangeNode *a = local(&c,"widths","a"), *b = local(&c,"widths","b"), *narrow = local(&c,"widths","narrow");
    assert(a->type && a->type->kind == RangeNodeSpecialization && a->type == b->type);
    expectDescription(a->type,"Int<bits: 64, signed: true>");
    expectDescription(narrow->type,"Int<bits: 8, signed: true>");
    assert(narrow->type != a->type && local(&c,"widths","same")->type == narrow->type);
    expectDescription(local(&c,"widths","ok")->type,"Bool");
    SourceDiagnostic *law = reported(&c,"law","Int<bits: 8, signed: true> does not satisfy @integer");
    assert(law && strstr(law->message,"Integer value does not fit") && law->uses == 1 && law->at->line == 1);
    assert(errorsIn(&c,"type") == 0);
    rangeArenaDestroy(&c.arena);

    // Specialization substitutes type parameters through members and calls.
    compile(&c,"function arrays() { state xs: Array<Int> xs.append(value: 7) "
        "let n: (xs.count) let r: (xs.read(at: 0) + 1) let e: (xs.isEmpty()) "
        "state narrow: Array<Int<bits: 8>> narrow.append(value: 300) }");
    expectDescription(local(&c,"arrays","xs")->type,"Array<Element: Int<bits: 64, signed: true>>");
    assert(local(&c,"arrays","n")->type == local(&c,"arrays","r")->type);
    expectDescription(local(&c,"arrays","r")->type,"Int<bits: 64, signed: true>");
    expectDescription(local(&c,"arrays","e")->type,"Bool");
    assert(errorsIn(&c,"type") == 0);
    assert(reported(&c,"law","Int<bits: 8, signed: true> does not satisfy @integer"));
    rangeArenaDestroy(&c.arena);

    // Refusals: mixed widths, non-Bool conditions, labels, members, generics, storage, immutability.
    compile(&c,"function refuse() { let a: 0 state narrow: Int<bits: 8> "
        "let mixed: (a + narrow) if a {} let neg: -true let nope: (a.missing) "
        "state xs: Array<Int> xs.append(value: true) xs.append(7) xs.nothing() let slots: (xs.elements) "
        "let bare: Array let twice: Array<Int, Int> let wide: Int<width: 8> a: 5 }");
    assert(reported(&c,"type","operator '+' requires matching types; found Int<bits: 64, signed: true> and Int<bits: 8, signed: true>"));
    assert(reported(&c,"type","condition requires Bool; found Int<bits: 64, signed: true>"));
    assert(reported(&c,"type","operator '-' requires an integer type; found Bool"));
    assert(reported(&c,"type","Int<bits: 64, signed: true> has no member 'missing'"));
    assert(reported(&c,"type","argument 'value' of 'append' requires Int<bits: 64, signed: true>; found Bool"));
    assert(reported(&c,"type","argument 1 of 'append' requires label 'value'"));
    assert(reported(&c,"type","Array<Element: Int<bits: 64, signed: true>> has no function 'nothing'"));
    assert(reported(&c,"type","'elements' holds @many storage and is not a value"));
    assert(reported(&c,"type","'Array' requires generic Element"));
    assert(reported(&c,"type","'Array' takes 1 type arguments; 2 supplied"));
    assert(reported(&c,"type","'Int' has no generic named 'width'"));
    assert(reported(&c,"type","cannot assign to let 'a'"));
    rangeArenaDestroy(&c.arena);

    // Layout: scalars from their storage width, constructs from members in order.
    compile(&c,"construct Pair { let flag: Bool let count: Int } "
        "construct Bytes { let a: Int<bits: 8> let b: Int<bits: 8> let c: Int<bits: 12> } "
        "construct Loop { let again: Loop } "
        "function layouts() { let a: 0 state b: Int<bits: 8> state w: Int<bits: 12> let t: true "
        "state xs: Array<Int> let p: Pair let q: Bytes let s: \"\" state maybe: Int<bits: 8>? }");
    struct { const char *name; size_t size, alignment; } expected[] = {
        {"a",8,8}, {"b",1,1}, {"w",2,2}, {"t",1,1}, {"xs",24,8}, {"p",16,8}, {"q",4,2}, {"maybe",2,1}};
    for (size_t i = 0; i < sizeof(expected)/sizeof(*expected); ++i) {
        RangeNode *type = local(&c,"layouts",expected[i].name)->type;
        assert(type && type->layout == 2);
        if (type->size != expected[i].size || type->alignment != expected[i].alignment)
            fprintf(stderr,"%s: size %zu alignment %zu\n",expected[i].name,type->size,type->alignment);
        assert(type->size == expected[i].size && type->alignment == expected[i].alignment);
    }
    // The bytes primitive: an address and a byte count.
    assert(local(&c,"layouts","s")->type->size == 16 && local(&c,"layouts","s")->type->alignment == 8);
    expectDescription(local(&c,"layouts","maybe")->type,"Optional<Wrapped: Int<bits: 8, signed: true>>");
    assert(reported(&c,"layout","Loop has no layout: it contains itself"));
    // Only root causes are reported; types that merely contain them stay quiet.
    for (SourceDiagnostic *d = c.report.first; d; d = d->next)
        assert(!same(d->category,"layout") || strstr(d->message,"contains itself"));
    rangeArenaDestroy(&c.arena);

    puts("types: language sources, contextual literals, laws per specialization, substitution, refusals, layout=pass");
    return 0;
}
