---
name: range-metadata-shapes-publisher
description: Use when changing Range package publishing, metadata extraction, declaration metadata, visibility defaults, namespace locking, typed construction syntax, or docs around publisher-facing declaration shapes. Keeps publisher examples aligned with current graph-backed package metadata.
---

# Range Metadata Shapes Publisher

## Workflow

1. Verify the current parser, graph, backend, and tests when work touches publisher output, package model shape, declaration metadata, visibility, namespace behavior, or typed construction examples.
2. Treat this skill as design direction, not automatic truth.
3. If examples are outdated, update the docs instead of copying stale syntax into code.
4. If implementation regressed from the intended shape, fix code/tests and keep docs aligned.
5. Keep optionality as `Optional<T>` unless current code and fixtures explicitly support another form.

## Current Direction

- `let version: Version(0.1.8)` means typed construction metadata on the declaration.
- `#package` marks the package manifest construct; do not use the old `@package { ... }` block shape.
- `Optional<Int>` remains a type shape, not a `#optional` declaration flag.
- `#namespace(.locked)` is publisher-facing namespace metadata.
- Public is the normal published shape; `private` marks the exception.
- Source examples should distinguish declaration metadata from later assignment or backend lowering.
