# Repository Guidance

## TODO Tracking

- Record repository work in the root `TODO.md` instead of creating scattered
  TODO files or leaving TODO lists in handoffs.
- Write actionable work as Markdown checkboxes: `- [ ]` for pending work and
  `- [x]` for completed work.
- Use nested checkboxes when an item has independently verifiable steps.
- Add a short nested description, decision note, or verification condition
  when the checkbox title alone does not provide enough context.
- Keep historical proof and completed checkpoint details in the relevant
  documentation; `TODO.md` should describe current or deliberately deferred
  work.

## Compiler Self-Hosting

- Keep exactly one accepted compiler authority: the committed bootstrap LLVM,
  executable, and manifest under `RangeCompiler/Bootstrap/`.
- Use one two-build proof for a compiler-source checkpoint:

  ```text
  accepted compiler + source -> candidate
  candidate + same source -> reproduction
  ```

- Compare both candidate/reproduction LLVM and linked executables byte for
  byte. If both pairs match, another build from the same deterministic inputs
  is redundant. The candidate may replace the accepted compiler.
- If either pair differs, do not promote either output. An additional
  generation may diagnose convergence, but it is not part of the promotion
  proof and does not turn a failed comparison into an accepted checkpoint.
- Do not retain older compilers as active authorities. Promotion replaces the
  accepted artifacts; Git history preserves prior checkpoints.
- Do not promote after every compiler edit. Develop against the accepted
  compiler, run focused gates, and roll the bootstrap only at a deliberate
  stable checkpoint with explicit maintainer approval.
- The canonical proof is `scripts/range check-compiler-candidate`. Promote an
  approved fixed point with `scripts/range compiler promote --approve`; that
  command runs the proof, replaces the accepted artifacts, and finishes with
  `scripts/range check-compiler-integrity` without compiling a third generation.
- `scripts/range check-compiler` remains available only as an optional
  independent reproduction audit. It is not part of the promotion path.

## Testing Structure

- `Testing/` is the repository's single active test-fixture root.
- Group fixtures by the language or compiler feature they protect, then by
  expected outcome: `Testing/<Feature>/Pass/` or
  `Testing/<Feature>/Fail/`. Do not create competing top-level `Tests`,
  `Native`, `SelfHosting`, or global `Pass`/`Fail` trees.
- `Pass` means the fixture must reach its expected successful result. `Fail`
  means rejection or a runtime trap is expected; the proof script that owns
  the fixture must check the exact failure boundary.
- Name fixtures after the behavior they prove. Add one only for behavior
  implemented by the Range-authored compiler and wire it into a supported
  proof command.
- Treat these fixtures as focused compiler proofs, not as evidence that the
  complete language or Foundation surface works.
- Run the supported validation ladder from the narrowest relevant gate toward
  the broadest required gate:
  - `scripts/range check-build-plan`
  - `scripts/range check-value-ownership` (add `--controls` for its full positive
    and rejection set)
  - `scripts/range check-compiler-smoke`
  - `scripts/range check-compiler-candidate`
  - `scripts/range check-compiler-integrity`
- `scripts/range compiler next` and `scripts/range compiler progression` are
  maintainer diagnostics for inspecting candidate production and cached
  convergence. They are not additional required generations after the
  candidate/reproduction comparison passes.
- A passing gate proves only that gate and its prerequisites. Do not report it
  as proof that later gates ran or passed.

## Collection Iteration

- Range has no `for` statement. Do not introduce one or reserve `for` as a
  control-flow keyword.
- Collection traversal should state its intent through operations such as
  `map`, `filter`, `each`, and `reduce`, as each operation is implemented and
  proven.
- `while` remains the explicit control-flow form for condition-driven
  iteration, mutation, and irregular short-circuiting.
- Do not infer runtime collection support from the compile-time macro
  collection transforms; each surface needs its own focused fixture and
  supported proof command.

## RangeView

- Treat RangeView as the idealized version of Range. Its source and examples
  may express the intended language and framework design ahead of what the
  current compiler can compile.
- Put every RangeView macro under
  `Projects/RangeView/Macros/`, grouped by concern.
  `Macros/Core.range` owns the foundational `@app`, `@component`, and `@page`
  macros; do not duplicate macro declarations in `RangeView.range`.
- Do not treat a RangeView compilation failure as evidence that its design is
  invalid. Distinguish idealized RangeView code from compiler-backed language
  support, and require a focused fixture and supported proof command before
  claiming that a RangeView capability currently compiles.

## Deferred Unified Generic Parameters Review

Do not change generic syntax or semantics as part of the current Buffer work.
Use the generic system exactly as it exists unless it becomes a concrete
blocker.

A later design review should consider one unified model in which every generic
argument is an immutable compile-time value and a type is one possible value,
rather than maintaining fundamentally separate type-generic and value-generic
systems. Questions for that review include:

- whether a bare parameter such as `Element` should accept an unconstrained
  compile-time value rather than implicitly mean `Type`;
- whether an annotation such as `size: Int` should constrain the value without
  requiring the redundant `let` spelling;
- whether generic parameters should follow the same independent local-name and
  external-argument-label rules as ordinary function parameters;
- how specialization bindings should be exposed as type-level properties
  without adding fields to every runtime instance; and
- how parameter usage should contribute capability requirements such as
  `Element.layout` through the graph.

Revisit this only after the current generic system blocks a permanent Buffer
layout implementation, or after that implementation is complete. Do not make
the Buffer slice depend on resolving these questions first.
