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
    Typer *typer;
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
    c->typer = diagnoseMacroApplications(&c->report);
    for (size_t u = 0; u < c->count; ++u) diagnoseSourceNode(&c->report,NULL,c->units[u],0);
    diagnoseDuplicates(&c->report);
    for (size_t u = 0; u < c->count; ++u) diagnoseBuiltinFunctions(&c->report,c->units[u]);
    typeCheck(c->typer);
    assert(!writtenChanged(c->typer,NULL));
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
    compile(&c,"function widths() { let a: 0 let b: Int<bits: 64, signed: true>(0) "
        "state narrow: Int<bits: 8>(0) narrow: 100 narrow: 800 let same: (narrow + 1) let ok: true }");
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
    compile(&c,"function arrays() { state xs: Array<Int>() xs.append(value: 7) "
        "let n: (xs.count) let r: (xs.read(at: 0) + 1) let e: (xs.isEmpty()) "
        "state narrow: Array<Int<bits: 8>>() narrow.append(value: 300) }");
    expectDescription(local(&c,"arrays","xs")->type,"Array<Element: Int<bits: 64, signed: true>>");
    assert(local(&c,"arrays","n")->type == local(&c,"arrays","r")->type);
    expectDescription(local(&c,"arrays","r")->type,"Int<bits: 64, signed: true>");
    expectDescription(local(&c,"arrays","e")->type,"Bool");
    assert(errorsIn(&c,"type") == 0);
    assert(reported(&c,"law","Int<bits: 8, signed: true> does not satisfy @integer"));
    rangeArenaDestroy(&c.arena);

    // A law reads the declaration itself as the specialization sees it: the
    // generics' values are the specialization's, and what its own
    // application emitted is not among the members it sees.
    compile(&c,"macro sized(): Construct { "
        "let extra: #members.first(where: { member in member.name = \"extra\" }) "
        "let n: #generics.first(where: { generic in generic.name = \"n\" }) "
        "switch { extra.present: @diagnostic(\"sees what it emits\"), n.present & n.value > 2: @diagnostic(\"n is too big\"), default: {} } "
        "let zero: 0 #graph { extension #name { let extra: #zero } } } "
        "@sized construct Pair<T, let n: 1> { let first: T } "
        "function pairs(): Int { let small: Pair<Int, n: 2>(first: 1) let big: Pair<Bool, n: 3>(first: true) return small.extra + big.extra }");
    assert(!errorsIn(&c,"type"));
    SourceDiagnostic *big = reported(&c,"law","Pair<T: Bool, n: 3> does not satisfy @sized");
    assert(big && strstr(big->message,"n is too big"));
    assert(!reported(&c,"law","sees what it emits") && errorsIn(&c,"law") == 1);
    assert(named(named(c.project,"Pair"),"extra"));
    rangeArenaDestroy(&c.arena);

    // Refusals: mixed widths, non-Bool conditions, labels, members, generics, storage, immutability.
    compile(&c,"function refuse() { let a: 0 state narrow: Int<bits: 8> "
        "let mixed: (a + narrow) while a {} let neg: -true let nope: (a.missing) "
        "state xs: Array<Int> xs.append(value: true) xs.append(7) xs.nothing() let slots: (xs.elements) "
        "let bare: Array let twice: Array<Int, Int> let wide: Int<width: 8> a: 5 }");
    assert(reported(&c,"type","operator '+' requires matching types; found Int<bits: 64, signed: true> and Int<bits: 8, signed: true>"));
    assert(reported(&c,"type","condition requires Bool; found Int<bits: 64, signed: true>"));
    assert(reported(&c,"type","'-' is not declared on Bool"));
    assert(reported(&c,"type","Int<bits: 64, signed: true> has no member 'missing'"));
    assert(reported(&c,"type","argument 'value' of 'append' requires Int<bits: 64, signed: true>; found Bool"));
    assert(reported(&c,"type","argument 1 of 'append' requires label 'value'"));
    assert(reported(&c,"type","Array<Element: Int<bits: 64, signed: true>> has no function 'nothing'"));
    assert(reported(&c,"type","'elements' holds @many storage and is not a value"));
    assert(reported(&c,"type","'Array' requires generic Element"));
    assert(reported(&c,"type","'Array' takes 1 type arguments; 2 supplied"));
    assert(reported(&c,"type","'Int' has no generic named 'width'"));
    assert(reported(&c,"type","cannot assign to let 'a'"));
    // A local states its value; only construct members leave it to construction.
    assert(reported(&c,"type","'narrow' needs an initial value"));
    assert(!reported(&c,"type","'a' needs an initial value"));
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
    // The bytes primitive: an address, a byte count, and the owning block.
    assert(local(&c,"layouts","s")->type->size == 24 && local(&c,"layouts","s")->type->alignment == 8);
    expectDescription(local(&c,"layouts","maybe")->type,"Optional<Wrapped: Int<bits: 8, signed: true>>");
    assert(reported(&c,"layout","Loop has no layout: it contains itself"));
    // Only root causes are reported; types that merely contain them stay quiet.
    for (SourceDiagnostic *d = c.report.first; d; d = d->next)
        assert(!same(d->category,"layout") || strstr(d->message,"contains itself"));
    rangeArenaDestroy(&c.arena);

    // Written code is kept as it was read: a change to it is found.
    compile(&c,"function probe() { let a: 0 let b: a }");
    assert(!writtenChanged(c.typer,"Project.range"));
    RangeNode *read = local(&c,"probe","b")->rhsReference;
    assert(read && same(read->name,"a"));
    read->name = "c";
    assert(writtenChanged(c.typer,"Project.range") == named(c.project,"probe"));
    assert(!writtenChanged(c.typer,"Language/Types/Int.range"));
    rangeArenaDestroy(&c.arena);

    // A trailing closure fills the parameter it fits; its label stays as written.
    compile(&c,"function labels(let xs: Array<Int>): Bool { let flags: xs.map { x in return x > 1 } "
        "return xs.contains { x in return x > 1 } }");
    assert(!errorsIn(&c,"type"));
    expectDescription(local(&c,"labels","flags")->type,"Array<Element: Bool>");
    assert(!writtenChanged(c.typer,"Project.range"));
    rangeArenaDestroy(&c.arena);

    // An operator with a body and `..<` run as the calls typing lowers them to, beside the written code.
    compile(&c,"construct Money { let cents: Int function +(let other: Money): Money { return Money(cents: cents + other.cents) } } "
        "function sums(let a: Money, let b: Money): Money { let r: 0..<3 let total: a + b return total }");
    assert(!errorsIn(&c,"type"));
    RangeNode *sum = rangeNodeRHS(local(&c,"sums","total")), *span = rangeNodeRHS(local(&c,"sums","r"));
    assert(sum->kind == RangeNodeBinary && sum->lowered && sum->lowered->kind == RangeNodeCall);
    assert(span->kind == RangeNodeBinary && span->lowered && span->lowered->kind == RangeNodeCall && !span->itemCount);
    expectDescription(span->type,"Interval");
    assert(!writtenChanged(c.typer,"Project.range"));
    rangeArenaDestroy(&c.arena);

    // A case test runs as the test typing records beside the member access or call.
    compile(&c,"enum Phase { case idle case failed(reason: Int) "
        "function quiet(): Bool { return idle | failed(reason: 3) } } "
        "function check(let p: Phase): Int { switch { p.failed(let r) & r > 0: return r, p.idle | p.quiet(): return 0, default: {} } return 1 }");
    assert(!errorsIn(&c,"type"));
    RangeNode *test = named(c.project,"check")->a->items[0]->items[0]->items[0]->b->a;
    assert(test->kind == RangeNodeCall && test->lowered && test->lowered->kind == RangeNodeCaseTest);
    assert(!writtenChanged(c.typer,"Project.range"));
    rangeArenaDestroy(&c.arena);

    // A narrowed read keeps its written form; the present case it reads through is recorded beside it.
    compile(&c,"function sizes(let a: Int?, let b: Int?): Int { switch { a.present & b.present: return a + b, default: {} } return 0 }");
    assert(!errorsIn(&c,"type"));
    RangeNode *payload = named(c.project,"sizes")->a->items[0]->items[0]->b->items[0]->a->a;
    assert(payload->kind == RangeNodeName && same(payload->name,"a") && payload->narrowed && same(payload->narrowed->name,"present"));
    expectDescription(payload->type,"Int<bits: 64, signed: true>");
    assert(!writtenChanged(c.typer,"Project.range"));
    rangeArenaDestroy(&c.arena);

    // A promoted value keeps its written form and type; the optional it is promoted to is recorded beside it.
    compile(&c,"function wrap(let n: Int): Int? { return n } "
        "function pick(let flag: Bool): Int? { return switch { flag: 1, default: wrap(n: 2) } } "
        "function equal(let a: Int?): Bool { return a = 5 | a = -5 }");
    assert(!errorsIn(&c,"type") && !errorsIn(&c,"law"));
    RangeNode *wrapped = named(c.project,"wrap")->a->items[0]->a;
    assert(wrapped->kind == RangeNodeName && wrapped->promoted);
    expectDescription(wrapped->type,"Int<bits: 64, signed: true>");
    expectDescription(wrapped->promoted,"Optional<Wrapped: Int<bits: 64, signed: true>>");
    RangeNode *first = named(c.project,"pick")->a->items[0]->a->items[0]->a;
    assert(first->kind == RangeNodeInteger && first->promoted);
    RangeNode *five = named(c.project,"equal")->a->items[0]->a->a->b;
    assert(five->kind == RangeNodeInteger && five->promoted);
    assert(!writtenChanged(c.typer,"Project.range"));
    rangeArenaDestroy(&c.arena);

    // `let v: T?` keeps its written form; the absent case it starts as is recorded beside it.
    compile(&c,"construct Box { let size: Int? let label: Int } "
        "function boxes(let box: Box?): Int { let empty: Int? let made: Box(label: 1) "
        "switch { box.present & box.size.present: return 1, box.absent: return 0 } } "
        "macro probe(): Construct { let first: #members.first() "
        "switch { first.present(let m) & m.value.absent: @warning(\"starts absent\"), default: {} } } "
        "@probe construct Starts { let size: Int? }");
    assert(errorsIn(&c,"type") == 1);
    assert(reported(&c,"type","switch must be exhaustive: 'box.present & box.present.size.absent' is not handled"));
    RangeNode *empty = local(&c,"boxes","empty");
    assert(same(empty->typeName,"Int") && empty->lowered && empty->lowered->kind == RangeNodeCase && same(empty->lowered->name,"absent"));
    expectDescription(empty->type,"Optional<Wrapped: Int<bits: 64, signed: true>>");
    assert(named(named(c.project,"Box"),"size")->lowered);
    int starts = 0;
    for (SourceDiagnostic *d = c.report.first; d; d = d->next) starts |= d->warning && same(d->message,"starts absent");
    assert(starts);
    assert(!writtenChanged(c.typer,"Project.range"));
    rangeArenaDestroy(&c.arena);

    // `let r: step(x: 1)` keeps its written form; the call it makes is recorded beside it.
    compile(&c,"function step(let x: Int): Int { return x + 1 } function calls(): Int { let r: step(x: 1) return r }");
    assert(!errorsIn(&c,"type"));
    RangeNode *called = local(&c,"calls","r");
    assert(same(called->typeName,"step") && called->itemCount == 1 && !called->a);
    assert(called->lowered && called->lowered->kind == RangeNodeCall && called->lowered->items[0] == called->items[0]);
    expectDescription(called->type,"Int<bits: 64, signed: true>");
    assert(!writtenChanged(c.typer,"Project.range"));
    rangeArenaDestroy(&c.arena);

    // A type path is a requirement recorded beside the declaration, the same in
    // code typed in order and in code a macro runs first.
    compile(&c,"enum Outer { case a enum Inner { case x } } construct Keeps { let inner: Outer.Inner } "
        "function later(): Int { let i: Outer.Inner return 0 } function early(): Int { let j: Outer.Inner return 0 } "
        "macro calls(): Construct { let n: early() } @calls construct Applied {}");
    RangeNode *inner = named(named(c.project,"Keeps"),"inner");
    assert((inner->found & RangeFlagRequired) && !inner->typeName && inner->itemCount == 1);
    expectDescription(inner->type,"Inner");
    assert(reported(&c,"type","'i' needs an initial value") && reported(&c,"type","'j' needs an initial value"));
    assert(errorsIn(&c,"type") == 2);
    assert(!writtenChanged(c.typer,"Project.range"));
    rangeArenaDestroy(&c.arena);

    // `for … in` writes the case it unwraps without a name; typing resolves it beside the pattern.
    compile(&c,"function total(let xs: Array<Int>): Int { state sum: 0 for x in xs & x > 1 { sum: sum + x } "
        "for i in 0..<3 { sum: sum + i } return sum }");
    assert(!errorsIn(&c,"type"));
    RangeNode *loop = named(c.project,"total")->a->items[1]->a;
    RangeNode *unwrap = loop->items[2]->b->items[0]->items[0]->items[0];
    assert(unwrap->integer == RangePatternCase && !unwrap->name && unwrap->itemCount == 1);
    assert(unwrap->resolvedDeclaration && same(unwrap->resolvedDeclaration->name,"present"));
    assert(!writtenChanged(c.typer,"Project.range"));
    rangeArenaDestroy(&c.arena);

    // A closure whose body is one expression yields it; typing does not store it in the closure.
    compile(&c,"function anyBig(let xs: Array<Int>): Bool { return xs.contains { x in x > 9 } }");
    assert(!errorsIn(&c,"type"));
    RangeNode *closure = named(c.project,"anyBig")->a->items[0]->a->items[0]->a;
    assert(closure->kind == RangeNodeClosure && !closure->c);
    RangeNode *yields = closureResult(c.typer,NULL,closure);
    assert(yields && yields->kind == RangeNodeBinary && same(yields->name,">"));
    assert(!writtenChanged(c.typer,"Project.range"));
    rangeArenaDestroy(&c.arena);

    // A generic function is typed into each specialization: its own nodes
    // keep nothing from either, and each specialization finds its own types.
    compile(&c,"function sum<T>(let a: T, let b: T): T { return a + b } "
        "function sums(): Int { let small: Int<bits: 8>(1) let narrow: sum(a: small, b: small) return sum(a: 1, b: 2) }");
    assert(!errorsIn(&c,"type"));
    RangeNode *generic = named(c.project,"sum"), *plus = generic->a->items[0]->a, *specializations[2];
    size_t count = 0;
    for (size_t i = 0; i < c.typer->instances->itemCount; ++i)
        if (c.typer->instances->items[i]->resolvedDeclaration == generic && count < 2) specializations[count++] = c.typer->instances->items[i];
    assert(count == 2 && !generic->type && !plus->type && !plus->resolvedDeclaration);
    expectDescription(specializations[0],"sum<T: Int<bits: 8, signed: true>>");
    expectDescription(specializations[1],"sum<T: Int<bits: 64, signed: true>>");
    expectDescription(found(specializations[0],plus)->type,"Int<bits: 8, signed: true>");
    expectDescription(found(specializations[1],plus)->type,"Int<bits: 64, signed: true>");
    assert(found(specializations[0],generic)->type == found(specializations[0],plus)->type);
    assert(found(specializations[0],plus)->resolvedDeclaration && same(found(specializations[0],plus)->resolvedDeclaration->name,"+"));
    RangeNode *narrowed = local(&c,"sums","narrow")->lowered;
    assert(narrowed->kind == RangeNodeCall && narrowed->a->resolvedDeclaration == generic && narrowed->a->specialization == specializations[0]);
    assert(!writtenChanged(c.typer,"Project.range"));
    rangeArenaDestroy(&c.arena);

    // A generic construct's member is typed per specialization it is read in:
    // each keeps the absent case its optional starts as.
    compile(&c,"construct Box<T> { let v: T? } "
        "function boxes(let a: Box<Int>, let b: Box<Bool>): Bool { let x: a.v let y: b.v return x.absent & y.absent }");
    assert(!errorsIn(&c,"type"));
    RangeNode *boxes = named(c.project,"boxes"), *v = named(named(c.project,"Box"),"v");
    RangeNode *ints = boxes->items[0]->type, *bools = boxes->items[1]->type;
    expectDescription(ints,"Box<T: Int<bits: 64, signed: true>>");
    expectDescription(bools,"Box<T: Bool>");
    expectDescription(v->lowered->type,"Optional<Wrapped: T>");
    expectDescription(found(ints,v)->lowered->type,"Optional<Wrapped: Int<bits: 64, signed: true>>");
    expectDescription(found(bools,v)->lowered->type,"Optional<Wrapped: Bool>");
    assert(!writtenChanged(c.typer,"Project.range"));
    rangeArenaDestroy(&c.arena);

    puts("types: language sources, contextual literals, laws per specialization, substitution, refusals, layout, written code=pass");
    return 0;
}
