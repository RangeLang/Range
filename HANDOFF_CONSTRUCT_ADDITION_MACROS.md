# Construct / Addition Macro Handoff

This document is a focused handoff for the next implementation pass.

It captures:
- the current macro/compiler state after the property-macro pass
- what replacement is still good for
- where rewrite-centric thinking should stop
- why construct/addition/emission is the next pressure point
- the safest next steps

## Current Compiler State

The macro system is now in a much better place than the earlier rewrite-only model.

Important current facts:

- property macros are real and working
  - `State<T>` supports `initializer`, `getter`, `setter`
  - `Let<T>` supports `initializer`, `getter`
  - `Binding<T>` supports `getter`, `setter`
  - `Derived<T>` supports `getter`
- `State<T>` generic matching is now real
  - bare `State` means “any state”
  - `State<T>` constrains against the declaration graph
- parameter label parsing is now Swift-style everywhere
  - first name = external
  - second name = internal
  - internal `_` is rejected
- namespace support exists
- `extension Math { ... }` style reopening exists
- `@defer { ... }` now exists as a real statement/block surface
  - front-end and CLI semantics are in
  - Swift backend lowering now preserves the delayed-exit semantics instead of emitting plain Swift `defer`

Current test state:

- `cd NeatSyntax && swift test` passes
- `cd NeatCLI && swift test` passes

## Macro Direction That Landed

The important realization from the last pass is this:

- replacement is valid
- behavioral attachment is valid
- but plain rewrite is not the center of the macro system anymore

This especially matters because several bad macro ideas were cut:

- `unwrap` was removed
  - `??` already exists as a language primitive
- `trace` was removed
  - should be a normal function
- `lock` was removed
  - wanted cleanup/control-flow guarantees, not a plain macro wrapper
- block macros were removed entirely
  - they were mostly function duplication with AST replacement

That cleanup was correct.

## Replacement Is Still Important

Replacement should stay, but for the right class of problems.

We renamed the old rewrite surface to:

```neat
protocol SyntaxReplaceable<T> {
    function replace(with replacement: T) -> T
}
```

This is the right shape because the important remaining macros are doing literal replacement, not callback registration.

Examples where replacement is clearly justified:

- `autoclosure`
  - declaration-side parameter type replacement
  - application-side expression replacement
- `literal`
  - init/application-side literal bridge realization
- `variadic`
  - declaration-side parameter type replacement
- `stringify`
  - expression replacement with a generated string literal expression

These are not weak wrapper macros.
They alter language surface or semantic lowering.

## The Key Realization About Construct Macros

The next real pressure point is not “what else can be replaceable.”

It is:

- addition
- extension
- emission
- lowering

That is where construct-targeted macros start to matter.

The reason is simple:

- property macros were valuable because they attached behavior to compiler-known surfaces
- init/parameter macros are valuable because they reshape declaration/application meaning
- construct macros will only be valuable if they can add semantic surface, not just inspect or pretend to rewrite a construct node

So the next pass should stop orbiting `replace(with:)` as the default macro power.

`replace` is one primitive.
It is not the whole system.

## What Already Exists On The Construct Side

Current construct-side signals in the repo:

- `Construct` exists as a core syntax declaration surface
- `Construct` conforms to `SupportsExtension`
  - see [Construct.neat](/Users/george/Documents/Neat/NeatCore/Syntax/Declarations/Type/Construct.neat:1)
- `SupportsExtension` currently exposes:

```neat
protocol SupportsExtension {
    function addExtension(_ extension: Self)
}
```

- there is already a fixture proving the call shape:
  - [ConstructAddExtensionSurface.neat](/Users/george/Documents/Neat/NeatCompilerFixtures/CompilePass/Macros/ConstructAddExtensionSurface.neat:1)
- there is also a minimal attachment fixture:
  - [ConstructMacroAttachment.neat](/Users/george/Documents/Neat/NeatCompilerFixtures/CompilePass/Macros/ConstructMacroAttachment.neat:1)

This means the repo already points toward construct macros being about extension/addition surfaces.

That is the correct direction.

## What Feels Wrong Right Now

There are still a few things that are conceptually stale or underpowered.

### 1. Old docs still think in rewrite terms

Some docs and README text still refer to:

- `SupportsRewrite<T>`
- `target.rewrite(...)`
- `Block`-targeted macros

Those are out of date after the cleanup.

The implementation moved on faster than the docs.

### 2. `SupportsExtension` is still too underspecified

Current shape:

```neat
protocol SupportsExtension {
    function addExtension(_ extension: Self)
}
```

This is only enough to prove that “some construct-like thing can receive an added sibling/extension surface.”

But it does not yet answer:

- what exact thing is being added
- whether the addition is declaration-side only
- whether it is semantic-only or real syntax emission
- whether the added surface is nested, sibling, or reopening-based

So this protocol is directionally correct, but still vague.

### 3. Construct macros are not yet the real story

Right now they are more hinted than fully modeled.

The real open question is not:

- “can a construct macro exist?”

It is:

- “what concrete addition/emission surfaces should a construct macro own?”

That is the actual design pressure point now.

## Important Conclusion About Literal / Init Macros

One point that came up and should not be lost:

- the suspicious part is not that literals lower
- the suspicious part would be if that lowering were backend magic or ad hoc constructor guessing

Current intended model is:

- literal carrier type is recognized
- declaration graph realizes the bridge
- semantic result is something like `String(literal: "Hello")`
- backend consumes that settled result

This is another reason the next pass should focus on lowering/emission semantics rather than just more replaceability.

## The Right Mental Split Going Forward

The macro system now wants at least these buckets:

1. direct replacement
   - `replace(with:)`
   - syntax substitution at graph-backed sites

2. behavioral attachment
   - property hooks like `initializer/getter/setter`

3. addition / extension
   - adding construct-level semantic surface
   - protocol/construct extension-style contribution

4. lowering / emission
   - changing how accepted language surface settles into semantic form

The next meaningful work is bucket 3 and 4.

## Strong Current Examples

These are the examples that actually justify the current macro system:

- `clamped`
  - because it attaches behavior to a property surface
- `autoclosure`
  - because it replaces both declaration-side and application-side syntax surfaces
- `literal`
  - because it participates in declaration-graph literal bridge realization
- `variadic`
  - because it changes how a parameter’s declaration/application shape is interpreted
- `stringify`
  - because it turns captured syntax into generated syntax

These are the examples that should **not** pull design:

- `trace`
- `lock`
- `unwrap`
- any old block wrapper

## Most Important Open Question

The current crux is:

What exactly should construct-targeted macro power mean?

The candidate directions are:

1. sibling/declaration addition only
2. extension/reopening-style contribution
3. emission/lowering participation for construct-owned generated surfaces
4. some combination of the above

The strongest current direction is:

- construct macros should primarily be about addition/extension
- replacement should remain available for nested syntax surfaces when needed
- but construct macros should not be designed as “just another rewrite target”

## Safest Next Step

Do not start by adding random `Construct` demo macros.

Start by locking the exact construct addition surface.

Recommended order:

1. Decide what `addExtension(...)` actually means.
   - Does it add a whole extension declaration?
   - Does it add members?
   - Does it reopen the construct semantically?
   - Is it syntax-owned, graph-owned, or both?

2. Decide whether construct addition is:
   - sibling emission
   - nested member addition
   - reopening/extension semantics
   - or a graph-level “realized surface” separate from raw syntax

3. Decide what the compiler should validate.
   - what kinds may be added
   - whether duplicates are allowed
   - whether added members participate in the declaration graph identically to source members

4. Only then add one real construct macro that proves the model.
   - not a toy wrapper
   - something that clearly benefits from addition/extension semantics

## What Should Not Be Done Blindly

Avoid these unless the model is explicitly locked first:

- making construct macros just another `replace(with:)` target story
- reviving block macros in disguise
- adding demo construct macros that only inspect but do not justify a surface
- letting backend lowering invent semantic structure that should have been settled in the declaration/application graph

## Files Most Relevant To The Next Pass

Neat side:

- [Construct.neat](/Users/george/Documents/Neat/NeatCore/Syntax/Declarations/Type/Construct.neat)
- [SupportsExtension.neat](/Users/george/Documents/Neat/NeatCore/Macros/CoreMacro/SupportsExtension.neat)
- [Autoclosure.neat](/Users/george/Documents/Neat/NeatCore/Macros/Implementations/Autoclosure.neat)
- [Literal.neat](/Users/george/Documents/Neat/NeatCore/Macros/Implementations/Literal.neat)
- [Variadic.neat](/Users/george/Documents/Neat/NeatCore/Macros/Implementations/Variadic.neat)
- [Stringify.neat](/Users/george/Documents/Neat/NeatCore/Macros/Implementations/Stringify.neat)

Fixtures:

- [ConstructMacroAttachment.neat](/Users/george/Documents/Neat/NeatCompilerFixtures/CompilePass/Macros/ConstructMacroAttachment.neat)
- [ConstructAddExtensionSurface.neat](/Users/george/Documents/Neat/NeatCompilerFixtures/CompilePass/Macros/ConstructAddExtensionSurface.neat)
- [AutoclosureParameter.neat](/Users/george/Documents/Neat/NeatCompilerFixtures/CompilePass/Macros/AutoclosureParameter.neat)
- [LiteralBridge.neat](/Users/george/Documents/Neat/NeatCompilerFixtures/CompilePass/Macros/LiteralBridge.neat)
- [VariadicParameterReturn.neat](/Users/george/Documents/Neat/NeatCompilerFixtures/CompilePass/Macros/VariadicParameterReturn.neat)

Compiler side:

- [DeclarationGraph+MacroViewModels.swift](/Users/george/Documents/Neat/NeatSyntax/Sources/NeatSyntax/Core/DeclarationGraph+MacroViewModels.swift)
- [MacroExpander+Rewrite.swift](/Users/george/Documents/Neat/NeatSyntax/Sources/NeatSyntax/Macros/MacroExpander+Rewrite.swift)
- [MacroExpander+Expansion.swift](/Users/george/Documents/Neat/NeatSyntax/Sources/NeatSyntax/Macros/MacroExpander+Expansion.swift)
- [DeclarationGraph.swift](/Users/george/Documents/Neat/NeatSyntax/Sources/NeatSyntax/Core/DeclarationGraph.swift)
- [BootstrapExpressionSemantics.swift](/Users/george/Documents/Neat/NeatSyntax/Sources/NeatSyntax/Core/BootstrapExpressionSemantics.swift)

## Final Recommendation To Next Pass

Do not keep pushing on “what else can be replaced.”

That is no longer the bottleneck.

The next pass should lock:

- construct addition semantics
- extension/addition surface meaning
- lowering/emission responsibilities versus graph responsibilities

Then implement one real construct-level macro that proves that model.

That is the highest-value next step.
