---
name: neat-embedded-swift-direction
description: Use when changing Neat Swift implementation, Package.swift settings, compiler targets, CLI code, Swift backend output, runtime assumptions, reflection, dynamic dispatch, generated Swift, or build settings that may affect Embedded Swift compatibility. Load the historical Embedded Swift direction note and use it to catch outdated docs or implementation drift.
---

# Neat Embedded Swift Direction

## Workflow

1. Read `references/embedded-swift-direction.md` before making or reviewing Swift implementation changes that touch runtime behavior, generated Swift, compiler package settings, or backend design.
2. Check the current code before applying the note. The reference is design history, not automatic truth.
3. If code contradicts the reference, decide whether the code is a regression or the doc is stale.
4. Fix the implementation when it violates the intended direction. Clean the docs when the implementation has intentionally moved on.
5. Preserve the core bias: explicit structure, predictable lowering, graph metadata over runtime discovery, and small generated output.

## Watch For

- Reflection or runtime discovery replacing graph facts.
- Dynamic Swift behavior becoming part of generated output without a clear reason.
- Package settings drifting away from Embedded Swift diagnostics.
- Backend lowering that hides structure the graph already knows.

## Reference

Load `references/embedded-swift-direction.md` for the full historical note.
