#define main rangeCompilerMain
#include "../../../Language/Compiler/Source/compiler.c"
#undef main
#include <assert.h>
#include <dirent.h>

static void validate(const char *source, const char *expected, size_t count)
{
    RangeArena arena; rangeArenaInit(&arena); rangeGraphInitTypes(&arena);
    char error[512];
    RangeNode *unit = rangeParseUnit(&arena,RANGE_LANGUAGE_DIR "/Types/Validation.range",
        source,strlen(source),error,sizeof(error));
    if (!unit) fprintf(stderr,"%s\n",error);
    assert(unit);
    int ok = resolveGraphApplications(&arena,&unit,1,error,sizeof(error));
    if (!ok) fprintf(stderr,"%s\n",error);
    assert(ok);
    size_t checked = 999;
    ok = validateMacroApplications(&arena,&unit,1,&checked,error,sizeof(error));
    if (expected) {
        if (ok || !strstr(error,expected)) fprintf(stderr,"expected %s; got %s\n",expected,error);
        assert(!ok && strstr(error,expected));
        assert(strstr(error,".range:"));
        assert(!checked);
    } else {
        if (!ok) fprintf(stderr,"%s\n",error);
        assert(ok && checked == count);
        // Each application runs once; a second pass finds nothing new to apply.
        assert(validateMacroApplications(&arena,&unit,1,&checked,error,sizeof(error)));
        assert(checked == 0);
    }
    rangeArenaDestroy(&arena);
}

/* Textual edits, pairs of from and to ending in NULL, applied to every
 * language source as it loads, so a test can vary the language itself. */
static const char *const *languageEdits;

static char *editOnce(char *text, size_t *size, const char *languageFrom, const char *languageTo)
{
    size_t from = strlen(languageFrom), to = strlen(languageTo), count = 0;
    for (char *at = strstr(text,languageFrom); at; at = strstr(at + from,languageFrom)) ++count;
    if (!count) return text;
    char *edited = malloc(*size + count * to + 1), *out = edited, *in = text;
    assert(edited);
    for (char *at; (at = strstr(in,languageFrom)); in = at + from) {
        memcpy(out,in,(size_t)(at - in)); out += at - in;
        memcpy(out,languageTo,to); out += to;
    }
    strcpy(out,in);
    *size = strlen(edited);
    free(text);
    return edited;
}

static char *editLanguage(char *text, size_t *size)
{
    for (size_t i = 0; languageEdits && languageEdits[i]; i += 2) text = editOnce(text,size,languageEdits[i],languageEdits[i + 1]);
    return text;
}

/* The language sources, as relative paths so their declarations are the
 * language's. Reflection lists are Array values and `first` returns an
 * Optional, so macros that reflect need them. */
static size_t loadLanguage(RangeArena *arena, RangeNode **units, size_t capacity)
{
    static const char *const directories[] = {"Language/Grammar", "Language/Macros", "Language/Types"};
    size_t count = 0;
    char error[512];
    for (size_t d = 0; d < 3; ++d) {
        DIR *directory = opendir(directories[d]);
        assert(directory);
        for (struct dirent *entry; (entry = readdir(directory));) {
            size_t length = strlen(entry->d_name);
            if (length < 7 || strcmp(entry->d_name + length - 6,".range")) continue;
            char path[512]; snprintf(path,sizeof(path),"%s/%s",directories[d],entry->d_name);
            size_t size; char *text = readFile(path,&size);
            assert(text && count < capacity);
            text = editLanguage(text,&size);
            units[count] = rangeParseUnit(arena,rangeArenaIntern(arena,path,strlen(path)),text,size,error,sizeof(error));
            free(text);
            if (!units[count]) fprintf(stderr,"%s\n",error);
            assert(units[count]);
            ++count;
        }
        closedir(directory);
    }
    return count;
}

/* As validate, with the language loaded; count is the applications beyond
 * the language's own, each construct's default @equatable among them. */
static void validateLanguage(const char *source, const char *expected, size_t count)
{
    static size_t baseline = SIZE_MAX;
    for (int pass = baseline == SIZE_MAX ? 0 : 1; pass < 2; ++pass) {
        RangeArena arena; rangeArenaInit(&arena); rangeGraphInitTypes(&arena);
        RangeNode *units[64]; char error[512];
        size_t n = loadLanguage(&arena,units,63);
        if (pass) {
            units[n] = rangeParseUnit(&arena,"Project.range",source,strlen(source),error,sizeof(error));
            if (!units[n]) fprintf(stderr,"%s\n",error);
            assert(units[n]);
            ++n;
        }
        int ok = resolveGraphApplications(&arena,units,n,error,sizeof(error));
        if (!ok) fprintf(stderr,"%s\n",error);
        assert(ok);
        size_t checked = 999;
        ok = validateMacroApplications(&arena,units,n,&checked,error,sizeof(error));
        if (!pass) { if (!ok) fprintf(stderr,"%s\n",error); assert(ok); baseline = checked; }
        else if (expected) {
            if (ok || !strstr(error,expected)) fprintf(stderr,"expected %s; got %s\n",expected,ok ? "success" : error);
            assert(!ok && strstr(error,expected) && strstr(error,".range:"));
        } else {
            if (!ok) fprintf(stderr,"%s\n",error);
            if (ok && checked != baseline + count) fprintf(stderr,"checked %zu, expected %zu\n",checked - baseline,count);
            assert(ok && checked == baseline + count);
        }
        rangeArenaDestroy(&arena);
    }
}

#define EFFECT "@builtin macro diagnostic(let message: TextValue) "
#define POLICY \
    "macro assess(): Construct { " \
    "switch #members.first(where: { m in m.name = \"payload\" }), #generics.first(where: { g in g.name = \"ceiling\" }) { " \
    ".absent & _: @diagnostic(\"missing payload\"), " \
    "_ & .absent: @diagnostic(\"missing ceiling\"), " \
    ".present(let payload) & .present(let ceiling) & !accepts(limit: ceiling.value, candidate: payload.value): " \
    "@diagnostic(\"source policy rejected\"), " \
    ".present & .present: {} } } " \
    "function accepts(let candidate: SomeNumber, let limit: SomeNumber): SomeTruth { " \
    "state remaining: candidate state consumed: 0 " \
    "while remaining > 0 { remaining: remaining - 1 consumed: consumed + 1 } " \
    "return consumed <= limit } "

static void validateInteger(const char *source, int accepted)
{
    if (accepted) validateLanguage(source,NULL,2); /* @integer and the default @equatable */
    else validateLanguage(source,"Integer value does not fit the declared bits and signedness",0);
}

int main(void)
{
    // Exercise the actual Range rule independently of unfinished compilation.
    validateInteger("@integer construct Wide<let bits: 128, let signed: true> { let value: 0 }",1);
    validateInteger("@integer construct Narrow<let bits: 8, let signed: true> { let value: 128 }",0);
    validateInteger("@integer construct Negative<let bits: 8, let signed: true> { let value: -128 }",1);
    validateLanguage("@integer construct Empty<let bits: 0, let signed: true> { let value: 0 }","Integer bits must be positive",0);
    validateLanguage("@integer construct Unsized<let signed: true> { let value: 0 }","Construct must specify value, bits and signed",0);
    validateInteger("@integer construct Unsigned<let bits: 8, let signed: false> { let value: -1 }",0);
    validateLanguage(POLICY "@assess construct Parcel<let ceiling: 7> { let payload: 7 }",NULL,2);
    validateLanguage(POLICY "@assess construct Parcel<let ceiling: 7> { let payload: 8 }","source policy rejected",0);
    validateLanguage(POLICY "@assess construct Parcel<let ceiling: 8> { let payload: 8 }",NULL,2);
    validateLanguage(POLICY "@assess construct Parcel<let ceiling: 7> { let payload: 3 + 4 }",NULL,2);
    validateLanguage(POLICY "@assess construct Parcel<let ceiling: 7> {}","missing payload",0);
    validateLanguage(POLICY "@assess construct Parcel { let payload: 1 }","missing ceiling",0);
    validateLanguage(POLICY "@assess construct First<let ceiling: 7> { let payload: 7 } "
                    "@assess construct Second<let ceiling: 2> { let payload: 2 }",NULL,4);
    validateLanguage(POLICY "@assess construct First<let ceiling: 7> { let payload: 7 } "
                    "@assess construct Second<let ceiling: 2> { let payload: 3 }","source policy rejected",0);
    validateLanguage("macro assess(): Construct { switch #members.first() { .present(let m) & m.value < 0: @diagnostic(\"negative\"), default: {} } } "
                     "macro assess(): Function { switch #parameters.first() { .absent: @diagnostic(\"missing input\"), .present: {} } } "
                     "@assess construct Parcel { let payload: 8 } @assess function start(let input: Any) {}",NULL,3);
    validate(EFFECT "macro diagnostic(): Construct {} macro assess(): Function { @diagnostic(\"selected effect\") } "
                    "@assess function start() {}","selected effect",0);
    // Whole rule bodies are executed. Reversing the source condition changes validity.
#define FIRST_VALUE "switch #members.first() { .absent: {}, .present(let m): { "
    validateLanguage("macro assess(): Construct { " FIRST_VALUE "switch m.value < 10 { .true: @diagnostic(\"too small\"), .false: {} } } } } "
                     "@assess construct Parcel { let payload: 8 }","too small",0);
    validateLanguage("macro assess(): Construct { " FIRST_VALUE "switch m.value > 10 { .true: @diagnostic(\"too large\"), .false: {} } } } } "
                     "@assess construct Parcel { let payload: 8 }",NULL,2);
    // No concrete type, helper, or parameter spelling is an intrinsic;
    // builtin macros are selected by their own names.
    validate("@builtin macro diagnostic(let text: RenamedText) "
             "@builtin macro literal(let pattern: RenamedText): Macro "
             "@literal(\"[0-9]+\") macro decimalRule(): Construct { "
             "switch small(text: #name) { .false: @diagnostic(\"too big\"), .true: {} } } "
             "function small(let text: RenamedText): RenamedTruth { return text = \"Quantity\" } "
             "@decimalRule construct Quantity { let storage: 3 }",NULL,1);
    validate(EFFECT "macro assess(): Construct { switch false & absent { .true: @diagnostic(\"bad\"), .false: {} } "
                    "switch true | absent { .true: { let ok: true }, .false: {} } } @assess construct Parcel {}",NULL,1);
    validate("macro assess(): Construct { let fixed: 0 fixed: 1 } @assess construct Parcel {}","state local",0);
    validate("macro assess(): Construct { let result: 1 / 0 } @assess construct Parcel {}","division by zero",0);
    validate("macro assess(): Construct { let result: 9223372036854775807 + 1 } @assess construct Parcel {}","numeric storage overflow",0);
    validate("macro assess(): Construct { while true {} } @assess construct Parcel {}","step limit",0);
    validate("function recurse(): Any { return recurse() } "
             "macro assess(): Construct { let result: recurse() } @assess construct Parcel {}","call depth",0);
    validate("function helper(): Any { #graph {} return 0 } "
             "macro assess(): Construct { let value: helper() } @assess construct Parcel {}","#graph requires a macro application",0);
    validate("macro assess(): Construct { @unknown(\"bad\") } @assess construct Parcel {}","unresolved compile-time declaration",0);
    validate("function f(let a: Any, let b: Any): Any { return a } "
             "macro assess(): Construct { let result: f(a: 1, a: 2) } @assess construct Parcel {}","duplicate compile-time local",0);
    validate("macro assess(): Construct { switch 1 { .true: {}, .false: {} } } @assess construct Parcel {}","case pattern matches an enum value",0);
    // switch runs at compile time: literal, relational, and `|` labels, a
    // binding with a condition, default, text, and switch expressions.
#define SIZES "macro assess(): Construct { " FIRST_VALUE "let n: m.value " \
    "switch n { 1 | 2: @diagnostic(\"small\"), < 0: @diagnostic(\"negative\"), " \
    "let big & big > 100: @diagnostic(\"big \\(big)\"), = 7: @diagnostic(\"seven\"), default: {} } } } } "
    validateLanguage(SIZES "@assess construct Parcel { let payload: 500 }","big 500",0);
    validateLanguage(SIZES "@assess construct Parcel { let payload: 2 }","small",0);
    validateLanguage(SIZES "@assess construct Parcel { let payload: -3 }","negative",0);
    validateLanguage(SIZES "@assess construct Parcel { let payload: 7 }","seven",0);
    validateLanguage(SIZES "@assess construct Parcel { let payload: 50 }",NULL,2);
    validateLanguage("macro assess(): Construct { let kind: switch #members.first() { .present: \"filled\", .absent: \"empty\" } "
                     "@diagnostic(\"\\(#name) is \\(kind)\") } @assess construct Parcel {}","Parcel is empty",0);
    validateLanguage("macro assess(): Construct { let size: switch #members.first() { .present(let m): switch m.value { 3: 30, default: 0 }, .absent: 0 } "
                     "switch size = 30 { .true: @diagnostic(\"thirty\"), .false: {} } } @assess construct Parcel { let payload: 3 }","thirty",0);
    validate(EFFECT "macro assess(): Construct { switch #name { \"Parcel\": @diagnostic(\"named\"), default: {} } } "
                    "@assess construct Parcel {}","named",0);
    validate("macro assess(): Construct { switch true { .true: {} } } @assess construct Parcel {}","'.false' is not handled",0);
    validate("macro assess(): Construct { switch 1 { 1: {} } } @assess construct Parcel {}","must be exhaustive; add a default",0);
    validate("macro assess(): Construct { switch 1 { default: {}, 1: {} } } @assess construct Parcel {}","'default' must be the last arm",0);
    validate("macro assess(): Construct { switch true { .true: {}, .false: {}, default: {} } } @assess construct Parcel {}","'default' is never reached",0);
    validate("macro assess(): Construct { switch 1 { .value(let n): {}, default: {} } } @assess construct Parcel {}","case pattern matches an enum value",0);
    // Compile-time values include enum values with payloads. The optional is
    // the enum applying @optional, whatever it and its cases are named.
#define CASES "@builtin macro diagnostic(let text: RenamedText) @builtin macro optional(): Enum " \
    "@optional enum Maybe<Value> { case nothing case just(Value) } " \
    "enum Shape { case circle(radius: Size) case square(Size) case empty } " \
    "function half(let n: Size): Size? { switch n < 0 { .true: return .nothing, .false: {} } return n / 2 } " \
    "function shape(let n: Size): Shape { switch n { 0: return .empty, 1: return Shape.circle(radius: 5), default: return .square(n) } } "
    validate(CASES "macro assess(): Construct { switch half(n: 8) { .nothing: @diagnostic(\"none\"), "
                   ".just(let v) & v > 10: @diagnostic(\"big\"), .just(4): @diagnostic(\"four\"), .just(let v): {} } } "
                   "@assess construct Parcel {}","four",0);
    validate(CASES "macro assess(): Construct { switch half(n: -1) { .nothing: @diagnostic(\"none\"), .just(let v): {} } } "
                   "@assess construct Parcel {}","none",0);
    validate(CASES "macro assess(): Construct { let w: switch shape(n: 9) { .square(let w) | .circle(radius: let w): w, .empty: 0 } "
                   "switch w = 9 { .true: {}, .false: @diagnostic(\"wrong payload\") } "
                   "switch shape(n: 1) = Shape.circle(radius: 5) { .true: {}, .false: @diagnostic(\"unequal\") } "
                   "switch half(n: 6) = 3 { .true: {}, .false: @diagnostic(\"not promoted\") } "
                   "switch half(n: -2) = .nothing { .true: {}, .false: @diagnostic(\"not absent\") } "
                   "let held: Size?.just(5) switch held { .just(5): {}, default: @diagnostic(\"not held\") } } "
                   "@assess construct Parcel {}",NULL,2); /* @optional is an application too */
    validate(CASES "macro assess(): Construct { switch half(n: 2) { .nothing: {} } } @assess construct Parcel {}",
             "compile-time switch over Maybe must be exhaustive: '.just' is not handled",0);
    validate(CASES "macro assess(): Construct { switch shape(n: 2) { .circle(let r): {}, .square(let s): {}, .empty: {}, default: {} } } "
                   "@assess construct Parcel {}","'default' is never reached",0);
    validate(CASES "macro assess(): Construct { switch shape(n: 2) { .square(let s): {}, .square(3): {}, default: {} } } "
                   "@assess construct Parcel {}","already handled by earlier arms",0);
    validate(CASES "macro assess(): Construct { switch shape(n: 2) { .round: {}, default: {} } } @assess construct Parcel {}",
             "Shape has no case 'round'",0);
    validate(CASES "macro assess(): Construct { switch shape(n: 2) { .empty(let x): {}, default: {} } } @assess construct Parcel {}",
             "case 'empty' has no payload to match",0);
    validate(CASES "macro assess(): Construct { let v: .empty } @assess construct Parcel {}","needs a context that names its enum",0);
    // A compile-time switch over several subjects: rows, grouped positions,
    // and conditions on one row or on the whole label.
    validate(CASES "macro assess(): Construct { switch half(n: 8), shape(n: 2) { "
                   ".just(let v) & .square(let s) & v = s * 2: @diagnostic(\"rows \\(v) \\(s)\"), _ & _: {} } } "
                   "@assess construct Parcel {}","rows 4 2",0);
    validate(CASES "macro assess(): Construct { switch half(n: -1), shape(n: 0) { "
                   "(.nothing | .just) & .empty: @diagnostic(\"grouped\"), _ & _: {} } } @assess construct Parcel {}","grouped",0);
    validate(CASES "macro assess(): Construct { switch half(n: 8), shape(n: 0) { "
                   "(.just & .empty | .nothing & .square) & false: @diagnostic(\"guarded\"), "
                   ".nothing & .empty | .just & .empty & true: @diagnostic(\"second row\"), _ & _: {} } } "
                   "@assess construct Parcel {}","second row",0);
    validate(CASES "macro assess(): Construct { switch half(n: 2), shape(n: 0) { .nothing & _: {}, .just & .empty: {} } } "
                   "@assess construct Parcel {}",
             "compile-time switch over 2 subjects must be exhaustive: '.just & .circle', '.just & .square' are not handled",0);
    validate(CASES "macro assess(): Construct { switch half(n: 2), shape(n: 0) { _ & .empty: {}, .just & .empty: {}, default: {} } } "
                   "@assess construct Parcel {}","this row is already handled by earlier arms",0);
    validate(CASES "macro assess(): Construct { switch half(n: 2), shape(n: 0) { .nothing & _: {}, .just & _ & true: {} } } "
                   "@assess construct Parcel {}","must be exhaustive",0);
    validate("macro assess(): Construct { let v: switch true { .true: { let x: 1 }, .false: 1 } } @assess construct Parcel {}",
             "neither yields a value nor diverges",0);
    validate("@builtin macro assess(): Construct @assess construct Parcel {}","no C primitive is implemented for builtin macro 'assess'",0);
    validateLanguage("macro assess(): Construct { let leaked: 7 " FIRST_VALUE
                     "switch m.value = 7 { .true: {}, .false: {} } } } } @assess construct Parcel { let payload: leaked }",
                     "unresolved compile-time local 'leaked'",0);
    // Reflection lists are Array values: count is its member, and first,
    // first(where:), filter(where:), and map(transform:) are the Range
    // functions @collection emits, run here with the closures a macro writes.
    // Any function Array declares runs the same way.
#define LIGHT "enum Light { case red case green(Int) case blue } " \
    "extension Array { function last(): Element? { switch count > 0 { .true: return read(at: count - 1), .false: {} } return .absent } } "
    validateLanguage(LIGHT "macro probe(): Enum { "
                     "switch #cases.count = 3 { .true: {}, .false: @diagnostic(\"count\") } "
                     "switch #cases.first() { .present(let c) & c.name = \"red\": {}, default: @diagnostic(\"first\") } "
                     "switch #cases.last() { .present(let c) & c.name = \"blue\": {}, default: @diagnostic(\"last\") } "
                     "switch #cases.first(where: { c in c.name = \"green\" }) { .present(let c): switch c.name = \"green\" { .true: {}, .false: @diagnostic(\"named\") }, "
                     ".absent: @diagnostic(\"missing green\") } "
                     "switch #cases.first(where: { c in c.name = \"purple\" }) { .absent: {}, .present: @diagnostic(\"purple\") } "
                     "switch #cases.filter(where: { c in c.name = \"blue\" }).count = 1 { .true: {}, .false: @diagnostic(\"filter\") } "
                     "switch #cases.map(transform: { c in c.name }).last() { .present(\"blue\"): {}, default: @diagnostic(\"map\") } } "
                     "@probe extension Light {}",NULL,2);
    validateLanguage(LIGHT "macro probe(): Enum { let none: #cases.second() } @probe extension Light {}",
                     "Array has no function 'second' with these labels",0);
    validateLanguage(LIGHT "macro probe(): Enum { let none: #cases.first.name } @probe extension Light {}",
                     "'Array.first' is a function; call it",0);
    // An optional is matched with switch; it has no isTarget, or any member.
    validateLanguage(LIGHT "macro probe(): Enum { let none: #cases.first().isTarget } @probe extension Light {}",
                     "this compile-time value has no member 'isTarget'",0);
    // Bodies are Block values, absent for a builtin; a block lists the
    // declarations written in it.
    validateLanguage("macro probe(): Function { switch #body { .present(let b): switch b.members.count = 2 { "
                     ".true: {}, .false: @diagnostic(\"members\") }, .absent: @diagnostic(\"no body\") } } "
                     "@probe function work(): Int { let a: 1 let b: 2 return a + b } "
                     "construct Holder { @probe @builtin function read(): Int }",
                     "no body",0);
    validateLanguage("macro probe(): Function { switch #body { .present(let b): switch b.members.count = 2 { "
                     ".true: {}, .false: @diagnostic(\"members\") }, .absent: {} } } "
                     "@probe function work(): Int { let a: 1 let b: 2 return a + b }",NULL,1);
    // C builds reflection lists through the collection's @insertion function,
    // found by that role: renamed, it still builds them, under its own label.
    languageEdits = (const char *const[]){"function append(let value: Element)","function add(let element: Element)",
                                          "result.append(value:","result.add(element:",
                                          "write(at: count, value: value)","write(at: count, value: element)",NULL};
    validateLanguage(LIGHT "macro probe(): Enum { "
                     "switch #cases.count = 3 { .true: {}, .false: @diagnostic(\"count\") } "
                     "switch #cases.first(where: { c in c.name = \"green\" }) { .present: {}, .absent: @diagnostic(\"missing green\") } } "
                     "@probe extension Light {}",NULL,2);
    // Without the role, C has no function to build them with.
    languageEdits = (const char *const[]){"@insertion\n","",NULL};
    validateLanguage(LIGHT "macro probe(): Enum { let none: #cases.first() } @probe extension Light {}",
                     "which declares no @insertion function to build it with",0);
    // A reflection list is also read: its collection declares @iteration too.
    languageEdits = (const char *const[]){"@iteration\n","",NULL};
    validateLanguage(LIGHT "macro probe(): Enum { let none: #cases.first() } @probe extension Light {}",
                     "which declares no @iteration function; a reflection list's collection declares both @iteration and @insertion",0);
    languageEdits = NULL;
    // Without the grammar, a reflection list has no Range type to be.
    validate("macro assess(): Construct { let none: #members.first() } @assess construct Parcel {}",
             "reflection field 'members' has no Range type",0);
    puts("macro validation: source policies, renamed declarations, diagnostics, scopes, control flow, limits=pass");
    return 0;
}
