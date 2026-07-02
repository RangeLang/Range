# Range Handoff - Macro Context Cleanup

Date: 2026-06-22

## Goal

Move the old explicit macro evaluator bindings out of Range-authored macro
source:

```range
target, diagnostics in
target, diagnostics, graph in
```

The desired direction is that Range Foundation macros (Range) define their own
stringy records and projections, while the Range parser/type checker/macro
expander (Swift) only provides generic macro context boxes and macro execution
plumbing. Swift should not remain the source of truth for statement kinds,
macro target registries, construct/enum/function semantics, or graph roles.

## Current Baseline

The `@macro` seed in Range Foundation macros (Range) has already been reduced to
an implicit declaration context:

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

That is intentionally a bootstrap/pre-macro shape. Do not add helper projection
macros like `@macro.declaration.name`, do not add `target, diagnostics in`, and
do not make this seed depend on normal `@state`, `@let`, or other macro-defined
surface.

There is a focused test covering this shape:

```text
CompilerFixtureTests/macroEntrypointLowersMacroDeclarationsToStringyRecords
```

At handoff time, the Range parser/type checker/macro expander (Swift) still has
legacy support for explicit bindings, and many Range Foundation macros (Range)
still use those bindings.

## Why Not Delete The Bindings Globally First

Deleting all `target, diagnostics, graph` support up front will fail hard.

The Range parser/type checker/macro expander (Swift) still evaluates many
attached, syntax, graph, rewrite, and projection macros by injecting
`MacroBindings`. Existing Range Foundation macros (Range), RangeCore syntax
declarations (Range), and Swift test fixtures still reference:

- `target.declaration.*`
- `target.application.*`
- `target.declaration.expand`
- `target.declaration.replace`
- `diagnostics.error(...)`
- `graph.identities(...)`

The cleanup should migrate Range files and fixtures in small groups, then remove
the Swift parser/evaluator support only after no real Range source depends on
the old binding syntax.

## Inventory Commands

Use these before and after each cleanup phase:

```sh
rg -n "\{\s*target, diagnostics(, graph)? in|^\s*target, diagnostics(, graph)? in\s*$" RangeCompiler/Range -g'*.range'
rg -n "target, diagnostics|diagnostics, graph|target\.|graph\." RangeCompiler/Range RangeCompiler/Tests RangeCompiler/Sources -g'*.range' -g'*.swift'
```

Representative legacy hotspots:

- Range statement projection macros (Range): `RangeCompiler/Range/Core/Syntax/Statements/Statement.range`
- Range member/projection macros (Range): `RangeCompiler/Range/Foundation/Macros/Member.range`
- Range construct macro surface (Range): `RangeCompiler/Range/Foundation/Macros/Construct.range`
- Range enum/case macro surface (Range): `RangeCompiler/Range/Foundation/Macros/Enum.range`
- Range function macro surface (Range): `RangeCompiler/Range/Foundation/Macros/Function.range`
- Range graph macros (Range): `RangeCompiler/Range/Foundation/Macros/Graph.range`
- Range syntax/rewrite macros (Range): `RangeCompiler/Range/Foundation/Macros/Syntax.range`
- Range expansion macros (Range): `RangeCompiler/Range/Foundation/Macros/Expand.range`
- Range scalar and collection macros (Range): `Int.range`, `Float.range`, `Bool.range`, `String.range`, `Array.range`
- Range project/main/compiler macros (Range): `Project.range`, `Main.range`, `Compiler.range`

## Cleanup Strategy

### Phase 0 - Freeze The Baseline

Run this before editing shared parser/evaluator code:

```sh
cd RangeCompiler
swift build
swift test --filter 'CompilerFixtureTests/(macroPrefixDeclarationParses|macroEntrypointLowersMacroDeclarationsToStringyRecords)'
```

Keep the `@macro` seed test passing during every phase.

### Phase 1 - Projection Contexts

Replace explicit `target` references in simple projection macros with implicit
context names.

Examples of desired direction:

- statement macro context exposes statement/application data directly.
- member macro context exposes member/application data directly.
- construct application context exposes application body/projection data
  directly.

The Range parser/type checker/macro expander (Swift) can still build the context
box, but the Range-authored macro body should not spell `target, diagnostics in`.

This is generic plumbing, not a new Swift semantic registry.

### Phase 2 - Stringy Member And Block Macros

Port Range Foundation macros (Range) that already emit string records:

- `@construct`
- `@extension`
- `@function`
- `@enum`
- `@case`
- `@let`
- `@state`
- `@parameter`
- `@generic`
- `@value`
- `@return`
- `@if`
- `@while`

Prefer records like:

```text
construct|name=Counter|llvm=...
state|name=count|value=Int(27)|llvm=...
function|name=increment|result=Bool|body=count: count + 1|llvm=...
```

Do not add Swift special cases for individual macro names. If Swift has to pass
children, body text, or application arguments, expose them through a generic
context object that Range macros can read.

### Phase 3 - Syntax Capture And Raw Splicing

Port macros that depend on raw written syntax, capture, closure, or splicing.
These likely need an implicit `application` or `syntax` context rather than
direct `target.application.*` access.

Expect fallout around:

- `@syntax`
- `@capture`
- `@spliced`
- init forwarding/string literal syntax macros
- tests that inspect written syntax

### Phase 4 - Graph Context

Do not erase graph access. Convert it.

Range graph macros (Range) still need to query identities and attach or rewrite
graph roles. The new shape should be an implicit graph/context object, not a
comma binding:

```range
@graph(...)
```

should be implemented as Range-authored behavior over generic graph metadata
provided by the Range parser/type checker/macro expander (Swift).

Avoid hardcoding `block`, `statement`, `syntax`, `property`, or `macro` as the
source of truth in Swift. Those roles should come from Range-authored macro
records once the bootstrap path can read them.

### Phase 5 - Replace/Expand Migration

The riskiest remaining legacy operations are direct target rewrites:

- `target.declaration.expand { ... }`
- `target.declaration.replace { ... }`
- `target.application.replace`
- argument expression replace paths

Convert these into Range-authored string records or generic rewrite commands
that the Range parser/type checker/macro expander (Swift) executes after macro
evaluation.

Do this after projection and simple stringy macros are stable.

### Phase 6 - Remove Old Syntax

Only after inventory commands show no real Range source or active fixture needs
the old shape:

- remove parser support for macro bodies beginning with evaluator statements.
- remove default `MacroBindings(target: "target", diagnostics: "diagnostics", graph: ...)`.
- remove Swift-side macro target registries that encode Range-authored macro
  roles.
- update tests that deliberately parse legacy syntax, or move them to explicit
  rejection tests.

## Invariants

- `@macro` remains the seed entrypoint and uses implicit `declaration`.
- No new `target, diagnostics in` or `target, diagnostics, graph in` in Range
  source.
- No new Swift hardcoded list of Range macro names or statement kinds.
- Swift may provide generic context boxes, child/member traversal, string record
  execution, and diagnostics transport.
- Range-authored macros decide the stringy IR surface.
- Keep edits small enough that focused tests identify the broken layer.

## Focused Validation Matrix

Start with:

```sh
cd RangeCompiler
swift build
swift test --filter 'CompilerFixtureTests/(macroPrefixDeclarationParses|macroEntrypointLowersMacroDeclarationsToStringyRecords)'
```

After projection macro work:

```sh
swift test --filter 'CompilerFixtureTests/(statementBlockMacroExpandsThroughRangeAuthoredProjection|ifStatementBlockMacroExpandsThroughRangeAuthoredProjection|breakAndContinueStatementMacrosExpandThroughRangeAuthoredProjection|forAndSwitchStatementMacrosExpandThroughRangeAuthoredProjection|returnStatementMacroExpandsThroughRangeAuthoredProjection)'
```

After construct/member/function/enum stringy work:

```sh
swift test --filter 'CompilerFixtureTests/(constructMacroCollectsStringyMemberMacroRecords|enumMacroCollectsStringyCaseMemberRecords|functionMacroCollectsStatementBodyLLVMRecords)'
```

After syntax/rewrite/graph work, include relevant existing fixture tests such as:

- `clampedStateMacroRewritesInitializerAndAssignments`
- `identifierInitMacroStringifiesBareSyntax`
- `constructMacroExpandEmitsExtensionDeclarations`
- `extensionMacrosEvaluateAgainstExtensionTarget`
- `macroMetadataQueriesGraphThroughIdentities`
- `projectMacroRequiresSingleProjectDeclaration`

Run the full `swift test` only once the focused groups are clean, because parser
and macro evaluator changes have wide blast radius.

## Current Open Question

The cleanup needs one explicit design decision before the final Swift removal:
what is the exact generic context shape passed to Range-authored macro bodies?

The current `@macro` seed proves `declaration.name`,
`declaration.expansionTypeName`, and `declaration.body`. The same idea should be
extended consistently to application, statement, member, graph, and rewrite
contexts before removing legacy `MacroBindings`.
