# Compiler Pipeline

## Purpose

`GradientSyntax` should own Gradient's compiler pipeline. `GradientCLI` should supply files, load `GradientCore`, choose commands and backends, and report results, but it should not assemble semantic compiler stages ad hoc.

## Pipeline

The intended pipeline is:

1. `Lexer`
2. `Parser`
3. `AST`
4. `DeclarationGraph`
5. `SemanticProgram`
6. `MemoryGraph`
7. `ReactivityGraph`
8. `BackendLowering`
9. `Emission`

## Stage Roles

- `Lexer`
  tokenizes source text

- `Parser`
  builds source-file AST nodes

- `AST`
  records what was written, not the final semantic truth

- `DeclarationGraph`
  is the first dependency-graph layer
  resolves declaration relationships such as conformances, requirement satisfaction, declaration-targeted macro carry, and literal bridge realization

- `SemanticProgram`
  is the semantically settled compiler artifact derived from the declaration graph
  should carry the graph-backed program view that backends consume

- `MemoryGraph`
  derives storage, ownership, mutation, and aliasing structure from already-settled semantics

- `ReactivityGraph`
  derives invalidation and recomputation dependencies from the earlier semantic and memory layers

- `BackendLowering`
  adapts settled Gradient meaning to a target such as Swift, C, or a future native backend

- `Emission`
  prints or writes target output

## Boundary Between GradientSyntax And GradientCLI

The split should be:

- `GradientSyntax`
  owns lexing, parsing, AST construction, declaration-graph construction, semantic resolution, and later graph derivation

- `GradientCLI`
  discovers project files, loads `GradientCore`, chooses commands, invokes backends, reports diagnostics, and writes output

That means `GradientCLI` should request a semantic artifact from `GradientSyntax` rather than manually rebuilding semantic pipeline steps from raw parsed files.

## Minimal First SemanticProgram

The first version does not need to solve every later graph. It only needs enough structure to stop the CLI from stitching semantic stages together manually.

A minimal shape is:

```swift
public struct SemanticProgram {
    public let parsedFiles: [ParsedSourceFile]
    public let expandedFiles: [ParsedSourceFile]
    public let declarationGraph: DeclarationGraph
}
```

This is enough to:

- centralize parsing and macro expansion in `GradientSyntax`
- centralize declaration-graph construction in `GradientSyntax`
- let backends consume one semantic entry point instead of raw file collection

## Backend Rule

Backends should sit after `SemanticProgram`.

They may still need AST structure for bodies and source layout, but they should take declaration-graph-derived semantic facts as the source of truth rather than re-deriving semantics from raw AST scans.
