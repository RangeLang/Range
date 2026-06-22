# Range Handoff - Recent Macro Bootstrap Session

Date: 2026-06-22

This handoff records the recent conversation state and the files/ideas touched
while moving Range Foundation macros (Range) toward stringy self-hosting and
away from Swift-owned semantic special cases.

## Current Worktree Delta

At the time this handoff was written, the untracked repo files from the handoff
pass were:

- `Development/HANDOFF_MACRO_CONTEXT_CLEANUP.md`
- `Development/HANDOFF_RECENT_MACRO_BOOTSTRAP_SESSION.md`

The rest of the macro/bootstrap changes described below are already present in
the checkout baseline being inspected, not necessarily shown as current
uncommitted diffs.

## Main Direction From The Session

The current architectural direction is:

- Range Foundation macros (Range) define constructs, functions, enums, cases,
  members, control flow, returns, and lowering records in Range-authored stringy
  form.
- Range parser/type checker/macro expander (Swift) should become generic macro
  plumbing: parsing, generic context boxes, macro evaluation, diagnostics
  transport, rewrite execution, and child/member traversal.
- Swift should not keep adding semantic registries for Range concepts such as
  construct, enum, function, statement kind, property kind, graph role, or type
  lowering policy.
- Range LLVM emitter (Swift) is still an internal lowering path used by the
  current Swift-hosted emission pipeline. Do not describe it as a separate fully
  self-hosted backend yet.

## Important Decisions Captured

### Blocks, Statements, And Lines

Authored Range files are being treated as blocks and line spans first. A line is
a block-like statement surface, and a collection of lines is also a block. The
old idea that a block primarily owns typed Swift-parsed statements is being
lowered into compatibility machinery.

Control flow and terminal forms should move to Range-authored statement macros:

- `@if`
- `@while`
- `@return`
- future siblings like switch/break/continue/for

These should emit string records first, then later feed native lowering.

### Stringy Construct Surface

The preferred temporary Range surface is:

```range
@construct(name: "Counter") {
    @state(name: "count") {
        @value(type: "Int", current: "27")
    }
    @function(name: "increment", result: "Bool", body: "count: count + 1")
}
```

Not:

```range
construct Counter {
    state count: Int(27)
}
```

The old normal construct syntax may still parse today because Range parser/type
checker/macro expander (Swift) has legacy support. The desired cleanup is to
stop relying on that as the source of truth for new bootstrap declarations.

### Members And Values

Member metadata is intentionally stringly at this layer:

- `@let(name: "...")`
- `@state(name: "...")`
- `@parameter(name: "...")`
- `@generic(name: "...")`
- `@value(type: "...", current: "...")`

The session explicitly moved away from inferred type/value split for this layer.
For now, a value is a string representation. `UUID` is a type string;
`UUID()` is a value string/default expression.

### Macro Declaration Shape

The `@macro` seed is a bootstrap entrypoint. It should not depend on normal
macro-defined helpers.

Current Range Foundation macro (Range) shape in
`RangeCompiler/Range/Foundation/Macros/Macro.range`:

```range
@macro() -> String {
    @return(value: "macro"
        + "|name="
        + declaration.name
        + "|result="
        + declaration.expansionTypeName
        + "\n"
        + declaration.body
    )
}
```

Do not reintroduce:

- `target, diagnostics in`
- `@macro.declaration.name`
- `@macro.declaration.expansionTypeName`
- `@macro.declaration.body`

The implicit seed context is `declaration`. That is the only deliberate
bootstrap context currently used by this seed.

### `self`

Compile-time `self` should not be a magic implicit macro binding. The direction
is to reserve `@self` as a Range-authored construct/type metadata macro surface.

Runtime construct/member `self` is separate and should not be conflated with the
macro metadata surface.

### Graph And Replace

Macro replacement should happen before validation and later AST collection when
replacement changes declaration identity. The validator should see the replaced
Range AST, not the pre-rewrite shell.

For `@graph`, the current desired direction is not a Swift-side role registry.
Range-authored graph macros should own the record/projection shape, while Range
parser/type checker/macro expander (Swift) provides generic graph/context data
and executes rewrites.

## Files And Tests Touched Or Relevant

### Range Foundation Macros

Current relevant files:

- `RangeCompiler/Range/Foundation/Macros/Macro.range`
- `RangeCompiler/Range/Foundation/Macros/Construct.range`
- `RangeCompiler/Range/Foundation/Macros/Extension.range`
- `RangeCompiler/Range/Foundation/Macros/Function.range`
- `RangeCompiler/Range/Foundation/Macros/Enum.range`
- `RangeCompiler/Range/Foundation/Macros/Member.range`
- `RangeCompiler/Range/Foundation/Macros/Array.range`
- `RangeCompiler/Range/Foundation/Macros/Graph.range`
- `RangeCompiler/Range/Foundation/Macros/Syntax.range`
- `RangeCompiler/Range/Foundation/Macros/Main.range`

These are in mixed state. Some are already stringy; many still use legacy
`target, diagnostics` or `target, diagnostics, graph`.

### RangeCore Syntax Declarations

Current relevant areas:

- `RangeCompiler/Range/Core/Syntax/Statements/Statement.range`
- `RangeCompiler/Range/Core/Syntax/Expressions/Expression.range`
- declaration syntax under `RangeCompiler/Range/Core/Syntax/Declarations`

The intended rewrite is to express syntax declarations in macro form, for
example:

```range
@statement
@construct(name: "Expression") {
    @let(name: "type", value: "Optional<TypeReference>")
}
```

instead of a normal `construct Expression { ... }` declaration.

### Swift Tests

Recent relevant fixture tests in
`RangeCompiler/Tests/RangeCompilerTests/CompilerFixtureTests.swift` include:

- `constructApplicationGenericsExposeTypeLLVMMetadata`
- `constructMacroCollectsStringyMemberMacroRecords`
- `enumMacroCollectsStringyCaseMemberRecords`
- `statementBlockMacroParsesWithMembers`
- `statementBlockMacroExpandsThroughRangeAuthoredProjection`
- `functionMacroCollectsStatementBodyLLVMRecords`
- `macroPrefixDeclarationParses`
- `macroEntrypointLowersMacroDeclarationsToStringyRecords`
- `selfDottedConstructMetadataMacroParses`

The most important new seed test is:

```text
CompilerFixtureTests/macroEntrypointLowersMacroDeclarationsToStringyRecords
```

It manually parses:

```range
macro decorate -> String {
    @return(value: "ok")
}
```

then evaluates the `@macro` seed with `targetBinding` set to `declaration` and
expects:

```text
macro|name=decorate|result=String
@return(value: "ok")
```

## Validation Already Run During The Session

These passed after the `@macro` seed cleanup:

```sh
cd RangeCompiler
swift build
swift test --filter 'CompilerFixtureTests/(macroPrefixDeclarationParses|macroEntrypointLowersMacroDeclarationsToStringyRecords)'
```

Earlier focused tests that were passing during the same macro/bootstrap work:

```text
statementBlockMacroExpandsThroughRangeAuthoredProjection
ifStatementBlockMacroExpandsThroughRangeAuthoredProjection
breakAndContinueStatementMacrosExpandThroughRangeAuthoredProjection
forAndSwitchStatementMacrosExpandThroughRangeAuthoredProjection
returnStatementMacroExpandsThroughRangeAuthoredProjection
constructMacroCollectsStringyMemberMacroRecords
enumMacroCollectsStringyCaseMemberRecords
functionMacroCollectsStatementBodyLLVMRecords
```

Those earlier groups should be rerun after any further parser/evaluator cleanup.

## Known Legacy Surface Still Present

This command currently shows many remaining old bindings:

```sh
rg -n "target, diagnostics|diagnostics, graph|target\\.|graph\\." RangeCompiler/Range RangeCompiler/Tests RangeCompiler/Sources -g'*.range' -g'*.swift'
```

Representative remaining old forms include:

- `macro integer(): Construct -> String { target, diagnostics in`
- `macro llvm(body: String) -> String { target, diagnostics, graph in`
- `macro graph(role: GraphRole): Construct -> Identity { target, diagnostics in`
- `macro statement.* -> String { target, diagnostics in`
- `macro syntax(...): ... { target, diagnostics, graph in`
- `macro member.* -> String { target, diagnostics in`
- graph/project/main/compiler macros with `graph`

The next cleanup agent should not remove Swift support for these bindings until
the Range-authored files and tests are migrated.

## Separate Cleanup Handoff

The broader cleanup plan is in:

- `Development/HANDOFF_MACRO_CONTEXT_CLEANUP.md`

That document is the phased execution guide for removing explicit macro
bindings. This document is the recent-session memory of what was touched and why.

## Next Best Step

Start with the smallest migration that removes legacy binding use from a
projection macro already covered by tests:

1. Pick statement or member projection macros.
2. Replace explicit `target, diagnostics in` with an implicit context shape.
3. Keep Swift changes generic: context object in, evaluated string record out.
4. Run the matching focused fixture test group before touching graph/rewrite
   macros.

Do not start with `@graph`, `@syntax`, or `expand/replace`; those have wider
semantic blast radius.
