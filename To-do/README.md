# Neat Unified Checklist

This is the high-level working checklist for active Neat cleanup.

The older notes remain useful as context, but this file should be the place to
look first when deciding what to do next.

## Core Bootstrap Cleanup

- [ ] Keep Swift-side type knowledge named and treated as bootstrap machinery,
      not true language builtins.
- [ ] Push more literal compatibility through declaration graph facts and
      NeatCore literal bridge protocols.
- [ ] Reduce places where `BootstrapLiteralType` directly carries language
      meaning.
- [ ] Keep Swift bootstrap logic only for parsing, lowering, runtime hooks, and
      source sugar that cannot yet live in Neat.
- [ ] Decide whether a normal `construct` can store a `@language construct`
      member as plain inline value data.
- [ ] Replace parser-owned operator precedence defaults with explicit Neat
      operator and precedence declarations.
- [ ] Shrink Swift-side operator typing rules so operator meaning can migrate
      toward Neat declarations.

## Declaration Graph Cleanup

- [ ] Add first-class `DeclarationGraph` registries or query views for enums,
      macros, and extensions.
- [ ] Add uniform declaration query surfaces for states, environments,
      bindings, deriveds, values, initializers, and parameters.
- [ ] Model declaration relations explicitly:
      `facetOf`, `satisfiesRequirement`, and `carriesMacro`.
- [ ] Strengthen declaration metadata so every declaration category can answer:
      kind, core/project role, container, declared type, and signature shape.
- [ ] Rebuild declaration-side resolvers/views on top of stronger graph facts
      instead of ad hoc declaration-struct traversal.
- [ ] Keep namespace-backed attribute facts graph-owned, not validator-local.
- [ ] Keep declaration/application facets such as `Init.Declaration`,
      `Init.Application`, `Function.Declaration`, and `Function.Application`
      visible as graph facts.

## Application Graph Cleanup

- [ ] Keep `ApplicationGraph` downstream from `DeclarationGraph`.
- [ ] Keep body traversal, use-site resolution, call-site flow, alias flow, and
      mutation behavior out of declaration storage.
- [ ] Build application/use-site facts from expanded files plus declaration
      graph facts.
- [ ] Use declaration graph queries for all “what exists?” checks before
      application validation decides “is this use valid here?”.
- [ ] Keep application-local transient state out of stable declaration views.

## Memory And Reactivity Boundary

- [ ] Decide the first concrete `MemoryGraph` inputs from declaration facts and
      application facts.
- [ ] Define stable memory-domain relations before adding a new storage model.
- [ ] Keep `MemoryGraph` derived from declaration + application meaning, not
      raw parser structures.
- [ ] Derive future reactivity facts from memory facts.
- [ ] Avoid coupling reactivity directly to AST-shaped or parser-shaped data.

## Macro And Metadata Cleanup

- [ ] Harden generic marker access without introducing one-off fields like
      `property.codingKey`.
- [ ] Expand syntax-producing macro coverage for function bodies, initializer
      bodies, blocks, switches, assignments, and declaration lists.
- [ ] Decide the syntax block story around future `# { ... }` blocks.
- [ ] Keep `#codable` generation boring: sequential `switch` over `Result`,
      no hidden throwing control flow.
- [ ] Keep macro-authored diagnostics and compiler diagnostics flowing through
      the same severity/channel model.
- [ ] Move marker value handling beyond primitive-only checks when rich marker
      values are needed.
- [ ] Replace renderer/parser-loop syntax production with more uniform
      structural syntax builders where that becomes worth the complexity.
- [ ] Complete the `SyntaxOmittable` story for conditional redaction,
      region-style macros, or compiler-macro style conditional syntax.

## NeatCore Surface Cleanup

- [ ] Add `Sequence` and `Collection` protocols before expanding collection-like
      APIs across storage types.
- [ ] Revisit `ComponentStorage` and `Vector<let dimensionality, Scalar>` after
      value-generic application support is less transitional.
- [ ] Keep namespace-shaped domain surfaces as `#namespace construct ...` when
      they carry namespace behavior or configuration.
- [ ] Keep representation/storage constructs as ordinary constructs unless they
      are actually namespace-shaped.
- [ ] Continue moving foundational language-visible surfaces into NeatCore
      instead of Swift-only mirrors.

## Tooling And Editor Cleanup

- [ ] Add semantic origin modifiers for project vs core/external symbols.
- [ ] Map origin-aware semantic token rules such as `type.neat.project` and
      `type.neat.other`.
- [ ] Split constants from mutable variables where declaration graph facts know
      immutability.
- [ ] Split globals, locals, and properties where symbol scope is known.
- [ ] Add semantic attribute classification instead of relying only on fallback
      syntax highlighting.
- [ ] Add documentation comment and documentation markup token categories once
      doc comments are formalized.

## Product And Publishing

- [ ] Decide whether NeatCloud is a real product direction for packages,
      articles, examples, and language-design notes.
- [ ] Keep X publishing scripts separate from docs source generation.
- [ ] Keep credentials in `.env` only.

## Immediate Next Slice

1. Add enum/macro/extension query surfaces to `DeclarationGraph`.
2. Use that pattern to add query surfaces for values, states, parameters, and
   initializers.
3. Push one literal compatibility path through declaration graph facts instead
   of direct `BootstrapLiteralType` checks.
4. Add `Sequence` and `Collection` core protocols before growing vector and
   component APIs further.
5. Decide the first memory-domain relations from existing declaration and
   application graph facts.
