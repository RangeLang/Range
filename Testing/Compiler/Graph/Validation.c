#define main rangeCompilerMain
#include "../../../Language/Compiler/Source/compiler.c"
#undef main
#include <assert.h>

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

#define EFFECT "@builtin macro diagnostic(let message: TextValue) "
#define POLICY \
    EFFECT \
    "macro assess(): Construct { " \
    "let chosen: #members.filter(named: \"payload\").first " \
    "let rule: #generics.filter(named: \"ceiling\").first " \
    "switch chosen.isTarget { .false: @diagnostic(\"missing payload\"), .true: {} } " \
    "switch rule.isTarget { .false: @diagnostic(\"missing ceiling\"), .true: {} } " \
    "switch chosen.isTarget && rule.isTarget { " \
    ".true: switch accepts(limit: rule.value, candidate: chosen.value) { .false: @diagnostic(\"source policy rejected\"), .true: {} }, " \
    ".false: {} } } " \
    "function accepts(let candidate: SomeNumber, let limit: SomeNumber): SomeTruth { " \
    "state remaining: candidate state consumed: 0 " \
    "while remaining > 0 { remaining: remaining - 1 consumed: consumed + 1 } " \
    "return consumed <= limit } "

static void validateInteger(const char *source, int accepted)
{
    RangeArena arena; rangeArenaInit(&arena); rangeGraphInitTypes(&arena);
    const char *paths[] = {"Language/Macros/Integer.range", "Language/Macros/Literal.range",
        "Language/Macros/Diagnostic.range", "Language/Types/Int.range"};
    RangeNode *units[5]; char error[512];
    for (size_t i = 0; i < 4; ++i) {
        size_t length; char *text = readFile(paths[i],&length);
        assert(text);
        units[i] = rangeParseUnit(&arena,paths[i],text,length,error,sizeof(error));
        free(text); assert(units[i]);
    }
    units[4] = rangeParseUnit(&arena,"Project.range",source,strlen(source),error,sizeof(error));
    assert(units[4]);
    assert(resolveGraphApplications(&arena,units,5,error,sizeof(error)));
    size_t checked;
    int ok = validateMacroApplications(&arena,units,5,&checked,error,sizeof(error));
    assert(ok == accepted);
    if (accepted) assert(checked == 2);
    else assert(strstr(error,"Integer value does not fit the declared bits and signedness"));
    rangeArenaDestroy(&arena);
}

int main(void)
{
    // Exercise the actual Range rule independently of unfinished compilation.
    validateInteger("@integer construct Wide<let bits: 128, let signed: true> { let value: 0 }",1);
    validateInteger("@integer construct Narrow<let bits: 8, let signed: true> { let value: 128 }",0);
    validateInteger("@integer construct Negative<let bits: 8, let signed: true> { let value: -128 }",1);
    validateInteger("@integer construct Unsigned<let bits: 8, let signed: false> { let value: -1 }",0);
    validate(POLICY "@assess construct Parcel<let ceiling: 7> { let payload: 7 }",NULL,1);
    validate(POLICY "@assess construct Parcel<let ceiling: 7> { let payload: 8 }","source policy rejected",0);
    validate(POLICY "@assess construct Parcel<let ceiling: 8> { let payload: 8 }",NULL,1);
    validate(POLICY "@assess construct Parcel<let ceiling: 7> { let payload: 3 + 4 }",NULL,1);
    validate(POLICY "@assess construct Parcel<let ceiling: 7> {}","missing payload",0);
    validate(POLICY "@assess construct Parcel { let payload: 1 }","missing ceiling",0);
    validate(POLICY "@assess construct First<let ceiling: 7> { let payload: 7 } "
                    "@assess construct Second<let ceiling: 2> { let payload: 2 }",NULL,2);
    validate(POLICY "@assess construct First<let ceiling: 7> { let payload: 7 } "
                    "@assess construct Second<let ceiling: 2> { let payload: 3 }","source policy rejected",0);
    validate(EFFECT "macro assess(): Construct { switch #members.first.value < 0 { .true: @diagnostic(\"negative\"), .false: {} } } "
                    "macro assess(): Function { switch #parameters.first.isTarget { .false: @diagnostic(\"missing input\"), .true: {} } } "
                    "@assess construct Parcel { let payload: 8 } @assess function start(let input: Any) {}",NULL,2);
    validate(EFFECT "macro diagnostic(): Construct {} macro assess(): Function { @diagnostic(\"selected effect\") } "
                    "@assess function start() {}","selected effect",0);
    // Whole rule bodies are executed. Reversing the source condition changes validity.
    validate(EFFECT "macro assess(): Construct { switch #members.first.value < 10 { .true: @diagnostic(\"too small\"), .false: {} } } "
                    "@assess construct Parcel { let payload: 8 }","too small",0);
    validate(EFFECT "macro assess(): Construct { switch #members.first.value > 10 { .true: @diagnostic(\"too large\"), .false: {} } } "
                    "@assess construct Parcel { let payload: 8 }",NULL,1);
    // No concrete type, helper, or parameter spelling is an intrinsic;
    // builtin macros are selected by their own names.
    validate("@builtin macro diagnostic(let text: RenamedText) "
             "@builtin macro literal(let pattern: RenamedText): Macro "
             "@literal(\"[0-9]+\") macro decimalRule(): Construct { "
             "let stored: #members.first "
             "switch small(number: stored.value) { .false: @diagnostic(\"too big\"), .true: {} } } "
             "function small(let number: RenamedNumber): RenamedTruth { return number < 4 } "
             "@decimalRule construct Quantity { let storage: 3 }",NULL,1);
    validate(EFFECT "macro assess(): Construct { switch false && absent { .true: @diagnostic(\"bad\"), .false: {} } "
                    "switch true || absent { .true: { let ok: true }, .false: {} } } @assess construct Parcel {}",NULL,1);
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
    validate("macro assess(): Construct { switch 1 { .true: {}, .false: {} } } @assess construct Parcel {}","boolean graph value",0);
    // switch runs at compile time: literal, relational, and `|` labels, a
    // binding with a where guard, default, text, and switch expressions.
#define SIZES EFFECT "macro assess(): Construct { let n: #members.first.value " \
    "switch n { 1 | 2: @diagnostic(\"small\"), < 0: @diagnostic(\"negative\"), " \
    "let big where big > 100: @diagnostic(\"big \\(big)\"), = 7: @diagnostic(\"seven\"), default: {} } } "
    validate(SIZES "@assess construct Parcel { let payload: 500 }","big 500",0);
    validate(SIZES "@assess construct Parcel { let payload: 2 }","small",0);
    validate(SIZES "@assess construct Parcel { let payload: -3 }","negative",0);
    validate(SIZES "@assess construct Parcel { let payload: 7 }","seven",0);
    validate(SIZES "@assess construct Parcel { let payload: 50 }",NULL,1);
    validate(EFFECT "macro assess(): Construct { let kind: switch #members.first.isTarget { .true: \"filled\", .false: \"empty\" } "
                    "@diagnostic(\"\\(#name) is \\(kind)\") } @assess construct Parcel {}","Parcel is empty",0);
    validate(EFFECT "macro assess(): Construct { let size: switch #members.first.value { 3: 30, default: 0 } "
                    "switch size = 30 { .true: @diagnostic(\"thirty\"), .false: {} } } @assess construct Parcel { let payload: 3 }","thirty",0);
    validate(EFFECT "macro assess(): Construct { switch #name { \"Parcel\": @diagnostic(\"named\"), default: {} } } "
                    "@assess construct Parcel {}","named",0);
    validate("macro assess(): Construct { switch true { .true: {} } } @assess construct Parcel {}","must be exhaustive: handle .true and .false",0);
    validate("macro assess(): Construct { switch 1 { 1: {} } } @assess construct Parcel {}","must be exhaustive; add a default",0);
    validate("macro assess(): Construct { switch 1 { default: {}, 1: {} } } @assess construct Parcel {}","'default' must be the last arm",0);
    validate("macro assess(): Construct { switch true { .true: {}, .false: {}, default: {} } } @assess construct Parcel {}","'default' is never reached",0);
    validate("macro assess(): Construct { switch 1 { .value(let n): {}, default: {} } } @assess construct Parcel {}","boolean graph value",0);
    validate("macro assess(): Construct { let v: switch true { .true: { let x: 1 }, .false: 1 } } @assess construct Parcel {}",
             "neither yields a value nor diverges",0);
    validate("@builtin macro assess(): Construct @assess construct Parcel {}","no C primitive is implemented for builtin macro 'assess'",0);
    validate("macro assess(): Construct { let leaked: 7 let selected: #members.first "
             "switch selected.value = 7 { .true: {}, .false: {} } } @assess construct Parcel { let payload: leaked }",
             "unresolved compile-time local 'leaked'",0);
    puts("macro validation: source policies, renamed declarations, diagnostics, scopes, control flow, limits=pass");
    return 0;
}
