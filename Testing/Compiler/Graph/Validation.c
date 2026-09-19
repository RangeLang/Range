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
        // Validation must not mutate declarations or leak locals between applications.
        assert(validateMacroApplications(&arena,&unit,1,&checked,error,sizeof(error)));
        assert(checked == count);
    }
    rangeArenaDestroy(&arena);
}

#define EFFECT "@builtin(\"diagnostic\") macro complain(let message: TextValue) "
#define POLICY \
    EFFECT \
    "macro assess(): Construct { " \
    "let chosen: #target.members.filter(named: \"payload\").first " \
    "let rule: #target.generics.filter(named: \"ceiling\").first " \
    "if !chosen.isTarget { @complain(\"missing payload\") } " \
    "if !rule.isTarget { @complain(\"missing ceiling\") } " \
    "if chosen.isTarget && rule.isTarget { " \
    "if !accepts(limit: rule.value, candidate: chosen.value) { @complain(\"source policy rejected\") } } } " \
    "function accepts(let candidate: SomeNumber, let limit: SomeNumber): SomeTruth { " \
    "state remaining: candidate state consumed: 0 " \
    "while remaining > 0 { remaining: remaining - 1 consumed: consumed + 1 } " \
    "return consumed <= limit } "

int main(void)
{
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
    // Whole rule bodies are executed. Reversing the source condition changes validity.
    validate(EFFECT "macro assess(): Construct { if #target.members.first.value < 10 { @complain(\"too small\") } } "
                    "@assess construct Parcel { let payload: 8 }","too small",0);
    validate(EFFECT "macro assess(): Construct { if #target.members.first.value > 10 { @complain(\"too large\") } } "
                    "@assess construct Parcel { let payload: 8 }",NULL,1);
    // No concrete type, macro, helper, or parameter spelling is an intrinsic.
    validate("@builtin(\"diagnostic\") macro report(let text: RenamedText) "
             "@builtin(\"literal\") macro spelling(let pattern: RenamedText): Macro "
             "@spelling(\"[0-9]+\") macro decimalRule(): Construct { "
             "let stored: #target.members.first "
             "if !small(number: stored.value) { @report(\"too big\") } } "
             "function small(let number: RenamedNumber): RenamedTruth { return number < 4 } "
             "@decimalRule construct Quantity { let storage: 3 }",NULL,1);
    validate(EFFECT "macro assess(): Construct { if false && absent { @complain(\"bad\") } "
                    "if true || absent { let ok: true } } @assess construct Parcel {}",NULL,1);
    validate("macro assess(): Construct { let fixed: 0 fixed: 1 } @assess construct Parcel {}","state local",0);
    validate("macro assess(): Construct { let result: 1 / 0 } @assess construct Parcel {}","division by zero",0);
    validate("macro assess(): Construct { let result: 9223372036854775807 + 1 } @assess construct Parcel {}","numeric storage overflow",0);
    validate("macro assess(): Construct { while true {} } @assess construct Parcel {}","step limit",0);
    validate("function recurse(): Any { return recurse() } "
             "macro assess(): Construct { let result: recurse() } @assess construct Parcel {}","call depth",0);
    validate("macro assess(): Construct { #environment {} } @assess construct Parcel {}","unsupported compile-time expression",0);
    validate("macro assess(): Construct { @unknown(\"bad\") } @assess construct Parcel {}","unresolved compile-time declaration",0);
    validate("function f(let a: Any, let b: Any): Any { return a } "
             "macro assess(): Construct { let result: f(a: 1, a: 2) } @assess construct Parcel {}","duplicate compile-time local",0);
    validate("macro assess(): Construct { if 1 {} } @assess construct Parcel {}","boolean graph value",0);
    validate("@builtin(\"unknown\") macro assess(): Construct @assess construct Parcel {}","builtin construct effects",0);
    validate("macro assess(): Construct { let leaked: 7 let selected: #target.members.first "
             "if selected.value == 7 {} } @assess construct Parcel { let payload: leaked }",
             "unresolved compile-time local 'leaked'",0);
    puts("macro validation: source policies, renamed declarations, diagnostics, scopes, control flow, limits=pass");
    return 0;
}
