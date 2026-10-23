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
    "let payload: #members.first(where: { m in m.name = \"payload\" }) " \
    "let ceiling: #generics.first(where: { g in g.name = \"ceiling\" }) " \
    "switch { payload.absent: @diagnostic(\"missing payload\"), " \
    "ceiling.absent: @diagnostic(\"missing ceiling\"), " \
    "payload.present & ceiling.present & !accepts(limit: ceiling.value, candidate: payload.value): " \
    "@diagnostic(\"source policy rejected\"), " \
    "payload.present & ceiling.present: {} } } " \
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
    validateLanguage("macro assess(): Construct { switch { #members.first().present(let m) & m.value < 0: @diagnostic(\"negative\"), default: {} } } "
                     "macro assess(): Function { let input: #parameters.first() switch { input.absent: @diagnostic(\"missing input\"), input.present: {} } } "
                     "@assess construct Parcel { let payload: 8 } @assess function start(let input: Any) {}",NULL,3);
    validate(EFFECT "macro diagnostic(): Construct {} macro assess(): Function { @diagnostic(\"selected effect\") } "
                    "@assess function start() {}","selected effect",0);
    // Whole rule bodies are executed. Reversing the source condition changes validity.
#define FIRST_VALUE "let first: #members.first() switch { first.absent: {}, first.present(let m): { "
    validateLanguage("macro assess(): Construct { " FIRST_VALUE "switch { m.value < 10: @diagnostic(\"too small\"), default: {} } } } } "
                     "@assess construct Parcel { let payload: 8 }","too small",0);
    validateLanguage("macro assess(): Construct { " FIRST_VALUE "switch { m.value > 10: @diagnostic(\"too large\"), default: {} } } } } "
                     "@assess construct Parcel { let payload: 8 }",NULL,2);
    // No concrete type, helper, or parameter spelling is an intrinsic;
    // builtin macros are selected by their own names.
    validate("@builtin macro diagnostic(let text: RenamedText) "
             "@builtin macro literal(let pattern: RenamedText): Macro "
             "@literal(\"[0-9]+\") macro decimalRule(): Construct { "
             "switch { !small(text: #name): @diagnostic(\"too big\"), default: {} } } "
             "function small(let text: RenamedText): RenamedTruth { return text = \"Quantity\" } "
             "@decimalRule construct Quantity { let storage: 3 }",NULL,1);
    validate(EFFECT "macro assess(): Construct { switch { false & absent: @diagnostic(\"bad\"), default: {} } "
                    "switch { true | absent: { let ok: true }, default: {} } } @assess construct Parcel {}",NULL,1);
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
    validate("macro assess(): Construct { let n: 1 switch { n.true: {}, default: {} } } @assess construct Parcel {}","field 'true' is not declared by @type integer",0);
    // switch runs at compile time: conditions joined by `|`, comparisons,
    // default, text, and switch expressions.
#define SIZES "macro assess(): Construct { " FIRST_VALUE "let n: m.value " \
    "switch { n = 1 | n = 2: @diagnostic(\"small\"), n < 0: @diagnostic(\"negative\"), " \
    "n > 100: @diagnostic(\"big \\(n)\"), n = 7: @diagnostic(\"seven\"), default: {} } } } } "
    validateLanguage(SIZES "@assess construct Parcel { let payload: 500 }","big 500",0);
    validateLanguage(SIZES "@assess construct Parcel { let payload: 2 }","small",0);
    validateLanguage(SIZES "@assess construct Parcel { let payload: -3 }","negative",0);
    validateLanguage(SIZES "@assess construct Parcel { let payload: 7 }","seven",0);
    validateLanguage(SIZES "@assess construct Parcel { let payload: 50 }",NULL,2);
    validateLanguage("macro assess(): Construct { let first: #members.first() let kind: switch { first.present: \"filled\", first.absent: \"empty\" } "
                     "@diagnostic(\"\\(#name) is \\(kind)\") } @assess construct Parcel {}","Parcel is empty",0);
    validateLanguage("macro assess(): Construct { let first: #members.first() let size: switch { first.present(let m): switch { m.value = 3: 30, default: 0 }, first.absent: 0 } "
                     "switch { size = 30: @diagnostic(\"thirty\"), default: {} } } @assess construct Parcel { let payload: 3 }","thirty",0);
    validate(EFFECT "macro assess(): Construct { switch { #name = \"Parcel\": @diagnostic(\"named\"), default: {} } } "
                    "@assess construct Parcel {}","named",0);
    validate("macro assess(): Construct { let b: true switch { b.true: {} } } @assess construct Parcel {}","'b.false' is not handled",0);
    validate("macro assess(): Construct { let n: 1 switch { n = 1: {} } } @assess construct Parcel {}","must be exhaustive; add a default",0);
    validate("macro assess(): Construct { let n: 1 switch { default: {}, n = 1: {} } } @assess construct Parcel {}","'default' must be the last arm",0);
    validate("macro assess(): Construct { let b: true switch { b.true: {}, b.false: {}, default: {} } } @assess construct Parcel {}","'default' is never reached",0);
    // Compile-time values include enum values with payloads. The optional is
    // the enum applying @optional, whatever it and its cases are named.
#define CASES "@builtin macro diagnostic(let text: RenamedText) @builtin macro optional(): Enum " \
    "@optional enum Maybe<Value> { case nothing case just(Value) } " \
    "enum Shape { case circle(radius: Size) case square(Size) case empty } " \
    "function half(let n: Size): Size? { switch { n < 0: return .nothing, default: {} } return n / 2 } " \
    "function shape(let n: Size): Shape { switch { n = 0: return .empty, n = 1: return Shape.circle(radius: 5), default: return .square(n) } } "
    validate(CASES "macro assess(): Construct { let h: half(n: 8) switch { h.nothing: @diagnostic(\"none\"), "
                   "h.just(let v) & v > 10: @diagnostic(\"big\"), h.just(4): @diagnostic(\"four\"), h.just: {} } } "
                   "@assess construct Parcel {}","four",0);
    validate(CASES "macro assess(): Construct { let h: half(n: -1) switch { h.nothing: @diagnostic(\"none\"), h.just: {} } } "
                   "@assess construct Parcel {}","none",0);
    validate(CASES "macro assess(): Construct { let s: shape(n: 9) let w: switch { s.square(let w) | s.circle(radius: let w): w, s.empty: 0 } "
                   "switch { w = 9: {}, default: @diagnostic(\"wrong payload\") } "
                   "switch { shape(n: 1) = Shape.circle(radius: 5): {}, default: @diagnostic(\"unequal\") } "
                   "switch { half(n: 6) = 3: {}, default: @diagnostic(\"not promoted\") } "
                   "switch { half(n: -2) = .nothing: {}, default: @diagnostic(\"not absent\") } "
                   "let held: Size?.just(5) switch { held.just(5): {}, default: @diagnostic(\"not held\") } } "
                   "@assess construct Parcel {}",NULL,2); /* @optional is an application too */
    validate(CASES "macro assess(): Construct { let h: half(n: 2) switch { h.nothing: {} } } @assess construct Parcel {}",
             "compile-time switch must be exhaustive: 'h.just' is not handled; add an arm for it or a default",0);
    validate(CASES "macro assess(): Construct { let s: shape(n: 2) switch { s.circle: {}, s.square: {}, s.empty: {}, default: {} } } "
                   "@assess construct Parcel {}","'default' is never reached",0);
    validate(CASES "macro assess(): Construct { let s: shape(n: 2) switch { s.square: {}, s.square(3): {}, default: {} } } "
                   "@assess construct Parcel {}","this condition is already handled by earlier arms",0);
    validate(CASES "macro assess(): Construct { let s: shape(n: 2) switch { s.round: {}, default: {} } } @assess construct Parcel {}",
             "Shape has no case 'round'",0);
    validate(CASES "macro assess(): Construct { let s: shape(n: 2) switch { s.empty(let x): {}, default: {} } } @assess construct Parcel {}",
             "case 'empty' has no payload to match",0);
    validate(CASES "macro assess(): Construct { let v: .empty } @assess construct Parcel {}","needs a context that names its enum",0);
    // Case tests on several subjects: bindings joined by `&`, alternatives
    // grouped in parentheses, and guards on one alternative or on the whole.
    validate(CASES "macro assess(): Construct { let h: half(n: 8) let s: shape(n: 2) switch { "
                   "h.just(let v) & s.square(let w) & v = w * 2: @diagnostic(\"rows \\(v) \\(w)\"), default: {} } } "
                   "@assess construct Parcel {}","rows 4 2",0);
    validate(CASES "macro assess(): Construct { let h: half(n: -1) let s: shape(n: 0) switch { "
                   "(h.nothing | h.just) & s.empty: @diagnostic(\"grouped\"), default: {} } } @assess construct Parcel {}","grouped",0);
    validate(CASES "macro assess(): Construct { let h: half(n: 8) let s: shape(n: 0) switch { "
                   "(h.just & s.empty | h.nothing & s.square) & false: @diagnostic(\"guarded\"), "
                   "h.nothing & s.empty | h.just & s.empty & true: @diagnostic(\"second row\"), default: {} } } "
                   "@assess construct Parcel {}","second row",0);
    validate(CASES "macro assess(): Construct { let h: half(n: 2) let s: shape(n: 0) switch { h.nothing: {}, h.just & s.empty: {} } } "
                   "@assess construct Parcel {}",
             "compile-time switch must be exhaustive: 'h.just & s.circle', 'h.just & s.square' are not handled; add arms for them or a default",0);
    validate(CASES "macro assess(): Construct { let h: half(n: 2) let s: shape(n: 0) switch { s.empty: {}, h.just & s.empty: {}, default: {} } } "
                   "@assess construct Parcel {}","this condition is already handled by earlier arms",0);
    validate(CASES "macro assess(): Construct { let h: half(n: 2) let s: shape(n: 0) switch { h.nothing: {}, h.just & true: {} } } "
                   "@assess construct Parcel {}","must be exhaustive",0);
    validate("macro assess(): Construct { let b: true let v: switch { b.true: { let x: 1 }, b.false: 1 } } @assess construct Parcel {}",
             "neither yields a value nor diverges",0);
    validate("@builtin macro assess(): Construct @assess construct Parcel {}","no C primitive is implemented for builtin macro 'assess'",0);
    validateLanguage("macro assess(): Construct { let leaked: 7 " FIRST_VALUE
                     "switch { m.value = 7: {}, default: {} } } } } @assess construct Parcel { let payload: leaked }",
                     "unresolved compile-time local 'leaked'",0);
    // Reflection lists are Array values: count is its member, and first,
    // first(where:), filter(where:), and map(transform:) are the Range
    // functions @collection emits, run here with the closures a macro writes.
    // Any function Array declares runs the same way.
#define LIGHT "enum Light { case red case green(Int) case blue } " \
    "extension Array { function last(): Element? { switch { count > 0: return read(at: count - 1), default: {} } return .absent } } "
    validateLanguage(LIGHT "macro probe(): Enum { "
                     "switch { #cases.count = 3: {}, default: @diagnostic(\"count\") } "
                     "switch { #cases.first().present(let c) & c.name = \"red\": {}, default: @diagnostic(\"first\") } "
                     "switch { #cases.last().present(let c) & c.name = \"blue\": {}, default: @diagnostic(\"last\") } "
                     "let green: #cases.first(where: { c in c.name = \"green\" }) "
                     "switch { green.present(let c): switch { c.name = \"green\": {}, default: @diagnostic(\"named\") }, "
                     "green.absent: @diagnostic(\"missing green\") } "
                     "switch { #cases.first(where: { c in c.name = \"purple\" }).absent: {}, default: @diagnostic(\"purple\") } "
                     "switch { #cases.filter(where: { c in c.name = \"blue\" }).count = 1: {}, default: @diagnostic(\"filter\") } "
                     "switch { #cases.map(transform: { c in c.name }).last().present(\"blue\"): {}, default: @diagnostic(\"map\") } } "
                     "@probe extension Light {}",NULL,2);
    validateLanguage(LIGHT "macro probe(): Enum { let none: #cases.second() } @probe extension Light {}",
                     "Array has no function 'second' with these labels",0);
    validateLanguage(LIGHT "macro probe(): Enum { let none: #cases.first.name } @probe extension Light {}",
                     "'Array.first' is a function; call it",0);
    // An optional is tested by its cases; it has no isTarget, or any member.
    validateLanguage(LIGHT "macro probe(): Enum { let none: #cases.first().isTarget } @probe extension Light {}",
                     "Optional has no case 'isTarget'",0);
    // Bodies are Block values, absent for a builtin; a block lists the
    // declarations written in it.
    validateLanguage("macro probe(): Function { let body: #body switch { body.present(let b): switch { b.members.count = 2: {}, "
                     "default: @diagnostic(\"members\") }, body.absent: @diagnostic(\"no body\") } } "
                     "@probe function work(): Int { let a: 1 let b: 2 return a + b } "
                     "construct Holder { @probe @builtin function read(): Int }",
                     "no body",0);
    validateLanguage("macro probe(): Function { let body: #body switch { body.present(let b): switch { b.members.count = 2: {}, "
                     "default: @diagnostic(\"members\") }, body.absent: {} } } "
                     "@probe function work(): Int { let a: 1 let b: 2 return a + b }",NULL,1);
    // C builds reflection lists through the collection's @insertion function,
    // found by that role: renamed, it still builds them, under its own label.
    languageEdits = (const char *const[]){"function append(let value: Element)","function add(let element: Element)",
                                          "result.append(value:","result.add(element:",
                                          "write(at: count, value: value)","write(at: count, value: element)",NULL};
    validateLanguage(LIGHT "macro probe(): Enum { "
                     "switch { #cases.count = 3: {}, default: @diagnostic(\"count\") } "
                     "switch { #cases.first(where: { c in c.name = \"green\" }).present: {}, default: @diagnostic(\"missing green\") } } "
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
