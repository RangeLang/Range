# Property Macro Handoff

This document is a focused handoff for the next implementation pass.

It captures:
- the current compiler/graph state
- what was just finished
- the current property-macro design direction
- what is still unresolved
- the safest next steps

## Current Compiler State

The graph and validation architecture is now in a much cleaner place:

- `ProgramGraph` is the root graph storage.
- `DeclarationGraph` is the primary semantic declaration layer.
- `ApplicationGraph` is the downstream use/access layer.
- `CompiledProgram` is the pipeline/container artifact.

Validation is split into passes:

- `ProgramGraphValidator`
- `DeclarationGraphValidator`
- `ApplicationGraphValidator`
- `CompiledProgramValidator` as orchestration only

Macro architecture is also cleaner than before:

- macro context is graph-backed
- rewrite validation is declaration-backed
- rewrite-site decoding is now descriptor-driven instead of a hardcoded path table

Important: the macro system is still primarily rewrite/addition-oriented. That is exactly the pressure point this handoff is about.

## Recently Finished

These are already done and green:

- `State`/`Binding`/`Value`/`Derived` were flattened on the Neat side
  - no nested `Declaration` wrapper anymore
- NeatCore declaration files were reorganized:
  - `NeatCore/Macros/Declarations/Property/`
  - `NeatCore/Macros/Declarations/Type/`
- protocol requirement validation was implemented for declaration conformance
- synthesized core protocol false positives were suppressed for:
  - `Equatable`
  - `Comparable`
  - `Hashable`
  - `SupportsExtension`
- `Closure` was updated to explicitly satisfy `Expression` by adding:
  - `value type: TypeReference?`

Current test state:

- `cd NeatSyntax && swift test` passes
- `cd NeatCLI && swift package clean && swift test` passes

## Key Realization About Property Macros

The core design pressure point is this:

Current Neat macros are good at:

- AST/surface rewrite
- declaration addition / sibling emission

But property-style transforms like `clamped` want something else too:

- behavioral transformation
- especially around initialization and writes

That means the current macro model is too narrow if it remains only:

- rewrite-based
- append-based

The likely long-term model is:

- macro = function-first semantic transformer
- rewrite is one capability
- extension/addition is another capability
- behavioral attachment or transform is a third capability

This has not been implemented yet. It is the main open design topic.

## Important Conclusions Reached

### 1. Do not force Swift-style property wrappers directly into Neat

Swift property wrappers are basically compiler-owned behavioral lowering over properties.

They are informative, but the right takeaway is:

- properties may need attachable behavior

not:

- copy wrapper syntax literally

### 2. `clamped` is not “just” an AST rewrite problem

There are two separate concerns:

- initializer transformation
- subsequent write transformation

Initializer transformation can be expressed as expression wrapping.

Example:

```neat
state age: Int = input()
```

can become:

```neat
min(max(input(), min), max)
```

That part is straightforward.

The deeper issue is future writes to the property, which points toward setter-like behavior.

### 3. `Expression` should stay the gateway into macro power

We explicitly discussed whether `State` should store only a resolved constant value instead of an `Expression`.

Conclusion:

- no, not only resolved value
- `Expression` should remain the gateway

Reason:

- `state age: Int = 1 + 1500`
- `state age: Int = input()`

Both should still participate in macro semantics.

So the useful model is:

- `State.type` provides expected type context
- `State.value` or `State.initializer` remains an `Expression?`
- expression becomes richer over time

This may later include:

- resolved type
- compile-time constant value when known
- semantic graph handle / identity

### 4. `State` is a core type and can have compiler-known special surfaces

This matters a lot.

We do not need to solve property behavior as a purely general user-facing feature first.

Because `State` is a core semantic type, it can grow compiler-owned surfaces that macros can target.

That is already consistent with the rest of the compiler, where core surfaces have compiler-owned semantics.

### 5. For property-family things, `Declaration`/`Application` may be the wrong split

For `State`, `Binding`, `Value`, `Derived`, the `Declaration`/`Application` split felt too coarse and too abstract.

We narrowed toward a more concrete model:

- the property declaration itself is concrete
- future access semantics are about initialization / getting / setting

This is probably a better fit than trying to invent `Property.Application`.

## The Current Best Candidate Shape

This is the best concrete shape discussed for `State` so far:

```neat
@core
construct State: Property {
    value name: String
    value type: TypeReference
    value value: Expression?

    value initializer: ((Expression) -> T)?
    value getter: ((T) -> T)?
    value setter: ((Expression) -> T)?
}
```

This is still conceptual, not implemented.

Important caveats:

- `T` here is conceptual, not yet grounded in the actual current core model
- we explicitly do **not** want to make the core `State` declaration itself generic in a naive way
- target typing/generic matching may instead belong in macro matching rather than in the core declaration node itself

So the real takeaway is not the exact syntax above.

The real takeaway is:

- `State` likely wants:
  - `name`
  - `type`
  - `value` / initializer expression
  - initializer transform
  - getter transform
  - setter transform

And those transform surfaces are likely function-shaped.

## Most Important Open Question

This is the current crux:

Should property-like macro surfaces be modeled as:

1. rewrite/addition-only effects on declaration nodes
2. function-like transform surfaces on core property types
3. a broader macro result/effect system that can attach behavior

The strongest current direction is:

- macro is fundamentally function-first
- rewrite is just one capability
- `State` can expose function-like initializer/getter/setter transform surfaces

That is the closest thing to a coherent property macro model reached so far.

## Concrete Example We Narrowed To

The user strongly resonated with this shape:

```neat
macro clamped(min: Int, max: Int): State { target, diagnostics in
    target.initializer { value in
        min(max(value, min), max)
    }

    target.setter { value in
        min(max(value, min), max)
    }
}
```

What this means conceptually:

- the initial incoming value gets clamped
- future assigned values get clamped
- getter remains unchanged

The syntax is not implemented.

But this is the most useful design anchor reached in the discussion.

## Explicitly Rejected / Deprioritized Directions

These were discussed and should not be rederived from scratch unless there is a strong reason:

### Rejected for now: treating `clamped` as a normal rewrite-only macro

Reason:

- it naturally wants behavior over writes
- not only declaration or expression replacement

### Rejected for now: modeling Swift property wrappers directly

Reason:

- too special
- copies syntax instead of extracting the real semantic need

### Rejected for now: replacing `State.value` with only resolved constant values

Reason:

- loses non-constant initializers like `input()`
- weakens `Expression` as the semantic gateway

### Rejected for now: forcing `Property.Application`

Reason:

- property “application” is too vague
- read/write semantics are more concrete than a generic application facet

## What The Next Pass Should Do

The safest next pass is design-first, not implementation-first.

Recommended order:

1. Decide the exact `State` surface.
   - Is the field called `value` or `initializer`?
   - Are `initializer`/`getter`/`setter` function-valued fields?
   - Are they optional?

2. Decide whether macro target matching syntax can express typed targets without making `State` itself naively generic.
   - Example desired user-level feel:
     - `macro clamped(min: Int, max: Int): State<Int>`
   - But the underlying core `State` declaration should likely stay concrete.

3. Decide whether the current macro system should gain:
   - one new property-transform surface for `State`
   - or a broader “macro effects” redesign

4. Only after that, implement the smallest viable property transform.
   - likely initializer transform first
   - then setter transform

## What Should Not Be Done Blindly

Avoid doing these without rechecking the model first:

- making `State` literally generic in a way that pollutes the core declaration model
- shoving property behavior into the existing rewrite-only macro pipeline without a clean surface
- introducing `Property.Application` just to mirror earlier declaration/application patterns
- replacing `Expression` with only constant values

## Repo Files Most Relevant To This Topic

Neat side:

- [NeatCore/Macros/Declarations/Property/Property.neat](/Users/george/Documents/Neat/NeatCore/Macros/Declarations/Property/Property.neat)
- [NeatCore/Macros/Declarations/Property/State.neat](/Users/george/Documents/Neat/NeatCore/Macros/Declarations/Property/State.neat)
- [NeatCore/Macros/Declarations/Property/Binding.neat](/Users/george/Documents/Neat/NeatCore/Macros/Declarations/Property/Binding.neat)
- [NeatCore/Macros/Declarations/Property/Value.neat](/Users/george/Documents/Neat/NeatCore/Macros/Declarations/Property/Value.neat)
- [NeatCore/Macros/Declarations/Property/Derived.neat](/Users/george/Documents/Neat/NeatCore/Macros/Declarations/Property/Derived.neat)
- [NeatCore/Macros/Expressions/Expression.neat](/Users/george/Documents/Neat/NeatCore/Macros/Expressions/Expression.neat)
- [NeatCore/Macros/Expressions/Closure.neat](/Users/george/Documents/Neat/NeatCore/Macros/Expressions/Closure.neat)

Compiler side:

- [NeatSyntax/Sources/NeatSyntax/Macros/MacroExpander+Expansion.swift](/Users/george/Documents/Neat/NeatSyntax/Sources/NeatSyntax/Macros/MacroExpander+Expansion.swift)
- [NeatSyntax/Sources/NeatSyntax/Macros/MacroExpander+Rewrite.swift](/Users/george/Documents/Neat/NeatSyntax/Sources/NeatSyntax/Macros/MacroExpander+Rewrite.swift)
- [NeatSyntax/Sources/NeatSyntax/Macros/MacroExpander+Models.swift](/Users/george/Documents/Neat/NeatSyntax/Sources/NeatSyntax/Macros/MacroExpander+Models.swift)
- [NeatSyntax/Sources/NeatSyntax/Core/DeclarationGraph+MacroViewModels.swift](/Users/george/Documents/Neat/NeatSyntax/Sources/NeatSyntax/Core/DeclarationGraph+MacroViewModels.swift)
- [NeatSyntax/Sources/NeatSyntax/GraphBindings/State/AST+State.swift](/Users/george/Documents/Neat/NeatSyntax/Sources/NeatSyntax/GraphBindings/State/AST+State.swift)
- [NeatSyntax/Sources/NeatSyntax/GraphBindings/State/Parser+State.swift](/Users/george/Documents/Neat/NeatSyntax/Sources/NeatSyntax/GraphBindings/State/Parser+State.swift)

## Final Recommendation To Next Pass

Do not start by coding `#clamped`.

Start by locking the `State` surface:

- concrete declaration fields
- function-like transform hooks
- target matching story

Then implement only the smallest slice that proves the design.

The discussion was narrowing toward something good, but it is not settled enough to safely code the full behavior system yet.
