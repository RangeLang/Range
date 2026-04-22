# Macro Code Interpolation Handoff

This document captures the new macro direction after the construct/addition discussion.

The important shift is:

- stop centering high-level macros around hand-built syntax nodes
- stop centering the next pass around `replace(with:)`
- move toward code interpolation as the main authoring surface
- implement emitted code first
- leave replacement redesign for later

## Core Direction

Macros should move toward **code interpolation**.

Meaning:

- macro authors write normal Neat code
- macro bodies can splice compiler-known values into that code
- the emitted result is parsed/validated as ordinary Neat after expansion

This is different from:

- stringly generation
- building AST objects by hand
- exposing compiler structs as the only authoring surface

The design center should be:

1. quoted/emitted code
2. splice points
3. post-expansion checking

## Why This Direction Is Better

The previous construct-macro discussion kept running into AST/type-shape problems:

- should `Extension` carry `target`
- should `Extension` be generic
- should `Construct.Declaration` own `extensions`
- should the constraint be semantic or type-level

Those questions matter internally, but they are not what macro authors actually want to write.

What macro authors want is:

- write ordinary-looking Neat
- interpolate a few compiler-provided values
- let the compiler validate the expanded result normally

That is exactly what code interpolation gives us.

## Guiding Principle

Macros are fundamentally AST/code substitution.

So the correct flow is:

1. parse/check the macro body enough to understand the macro program
2. perform expansion/interpolation
3. parse/validate the expanded result as ordinary Neat
4. continue the normal compiler pipeline

This means high-level macros should primarily produce syntax/code, not semantic graph objects.

## New Term

Use this term going forward:

- **code interpolation**

Good supporting terms:

- quoted code
- splicing
- emitted code
- post-expansion checking

## What To Prioritize First

Do **not** redesign `replace(with:)` first.

`replace` already has a working bootstrap path.

The highest-value new capability is:

- declaration-level emission
- especially construct/extension emission

That is where the macro system becomes materially more powerful.

So the next pass should focus on:

- `@expand`
- emitted code
- splice support
- ordinary post-expansion validation

## Proposed User-Facing Shape

The likely first surface is an attribute-bearing compiler block:

```neat
macro addGreeting(): Construct { target, diagnostics in
    @expand {
        extension #(target.declaration.self) {
            function greet() -> String {
                return "Hello"
            }
        }
    }
}
```

Important properties of this model:

- the author writes normal Neat code inside `@expand`
- `#(...)` is a splice/interpolation escape hatch
- after interpolation, the resulting code is checked as normal Neat

The exact sigil may still change, but the model should stay the same.

## Constraint Model

A useful realization from the discussion:

- nothing prevents nonsense output in the old system either
- the real question is where nonsense is rejected

For interpolation-based expansion, constraints come from three places:

1. macro target/context
   - a `Construct` macro can emit construct-valid surfaces

2. syntax category at the interpolation site
   - after `extension`, expect `NominalTypeReference`
   - in a function body, expect statements/expressions
   - in a declaration body, expect declarations/members

3. ordinary post-expansion validation
   - the final emitted result must parse/type-check/validate normally

So the compiler does not need a giant hardcoded “allowed interpolation forms” list.
It needs to know the expected syntax category at each hole.

## Important Scope Decision

For the first pass, support **emission**, not generalized arbitrary structural mutation.

That means:

- yes: emit declarations/extensions/members through `@expand`
- no: redesign all rewrite operations at the same time
- no: solve every AST self-description problem first

This is a bootstrap feature.
The compiler can own more of the implementation at first.

## Concrete First Target

The best proving example is construct macro emission of an extension.

Example shape:

```neat
macro addGreeting(): Construct { target, diagnostics in
    @expand {
        extension #(target.declaration.self) {
            function greet() -> String {
                return "Hello"
            }
        }
    }
}
```

This proves:

- declaration-level emitted syntax
- interpolation of a typed syntax value into a declaration head
- ordinary graph/semantic validation afterward

## Compiler Implementation Plan

### Stage 1: Introduce `@expand` As A Macro-Body Statement Form

Add a new macro-only statement/block surface representing emitted code.

Requirements:

- valid only inside macro bodies
- parsed distinctly from ordinary statements
- stores the quoted emitted body plus splice markers

This does **not** need full self-description in `NeatCore` first.
It can be bootstrapped directly in the compiler.

### Stage 2: Parse Interpolation Holes Inside `@expand`

Add one splice form first:

```neat
#(...)
```

Inside `@expand`, splice holes should preserve the embedded macro expression as an expression node until interpolation time.

First-pass supported splice categories:

- nominal type reference
- expression
- statement
- declaration/member

Start with the smallest set needed for construct/extension emission.

### Stage 3: Define Expected Syntax Categories By Position

When parsing or lowering the emitted block, determine what category each slot expects.

Examples:

- extension target -> `NominalTypeReference`
- function body position -> statements
- return value position -> expression
- declaration body position -> declarations/members

Interpolation succeeds only if the splice result matches the expected category.

This is the key rule that makes “splice anything” safe:

- you may splice anything that inhabits the expected syntax category

### Stage 4: Lower `@expand` Into Ordinary AST Declarations

For the first pass, lower emitted construct-macro code into ordinary AST declarations/extensions.

The important target is:

- construct macro emits `ExtensionDeclaration` siblings

This avoids needing fully generalized mutable declaration-surface collections first.

The output of expansion should feed the existing declaration graph/validation pipeline as normal source-like AST.

### Stage 5: Revalidate Expanded Output Normally

After interpolation/lowering:

- parse/normalize the emitted result if needed
- include it in the expanded file/module output
- rebuild declaration graph and run ordinary validation

This is non-negotiable.

The breakthrough here is not just interpolation.
It is interpolation plus ordinary post-expansion checking.

### Stage 6: Add A Real Fixture

Add one real compiler fixture proving construct-level emission.

The first fixture should:

- attach a `Construct` macro
- emit an extension for the attached construct
- use interpolation in the extension target
- compile successfully through the ordinary pipeline

Do **not** start by broadening the surface to many macro targets.
Prove the construct case first.

## What To Defer

Do not try to solve these in the same pass:

- replacement redesign through `@expand`
- full quote/splice support for every syntax category
- making syntax self-describe every grammar rule in `NeatCore`
- final generic/type-theoretic model for `Extension<Target>`
- generalized arbitrary mutation of syntax collections

Those are follow-up problems.
The current pass should prove emitted code interpolation concretely.

## Internal Representation Notes

It is acceptable for the compiler to bootstrap this before `NeatCore` fully models it.

That means:

- the compiler may hardcode `@expand` first
- the compiler may hardcode interpolation category rules first
- the compiler may lower emitted code into existing AST models first

This is consistent with the existing `@core` bootstrap approach.

The self-hosting/self-describing version can come later.

## Recommended Next Pass

Implement this order:

1. add `@expand` as a macro-body emission block
2. add `#(...)` interpolation inside emitted code
3. support extension emission from `Construct` macros
4. thread emitted extensions into expanded file/module output
5. validate the expanded result through the normal compiler pipeline
6. add one proving fixture

That is the highest-value next move for the macro system.
