---
name: neat-metadata-shapes-publisher
description: Use when changing Neat package publishing, metadata extraction, declaration metadata, visibility defaults, namespace locking, typed construction syntax, or docs around publisher-facing declaration shapes. Load the metadata shapes publisher note and use it to fix stale before/after examples or implementation drift.
---

# Neat Metadata Shapes Publisher

## Workflow

1. Read `docs/articles/metadata-shapes-publisher-note.md` when work touches publisher output, package model shape, declaration metadata, visibility, namespace behavior, or typed construction examples.
2. Verify the current parser, graph, backend, and tests before treating the note as current.
3. If examples are outdated, update the docs instead of copying stale syntax into code.
4. If implementation regressed from the intended shape, fix code/tests and keep docs aligned.
5. Keep optionality as `Optional<T>` unless current code and tests explicitly support another form.

## Current Shape Bias

- `let version: Version(0.1.8)` means typed construction metadata on the declaration.
- `Optional<Int>` remains a type shape, not a `#optional` declaration flag.
- `#namespace(.locked)` is publisher-facing namespace metadata.
- Public is the normal published shape; `private` marks the exception.

## Reference

Load `docs/articles/metadata-shapes-publisher-note.md` for the full before/after note. If it is stale, update that canonical doc.
