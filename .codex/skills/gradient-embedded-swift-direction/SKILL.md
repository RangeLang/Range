---
name: gradient-embedded-swift-direction
description: Use when changing Gradient Swift implementation, Package.swift settings, compiler targets, CLI code, Swift backend output, runtime assumptions, reflection, dynamic dispatch, generated Swift, or build settings that may affect Embedded Swift compatibility. Use the embedded direction in this skill to catch implementation drift.
---

# Gradient Embedded Swift Direction

## Workflow

1. Check current code and tests before making or reviewing Swift implementation changes that touch runtime behavior, generated Swift, compiler package settings, or backend design.
2. Treat this skill as design history, not automatic truth.
3. If code contradicts the direction here, decide whether the code is a regression or the direction has intentionally moved on.
4. Fix the implementation when it violates the intended direction.
5. Preserve the core bias: explicit structure, predictable lowering, graph metadata over runtime discovery, and small generated output.

## Watch For

- Reflection or runtime discovery replacing graph facts.
- Dynamic Swift behavior becoming part of generated output without a clear reason.
- Package settings drifting away from Embedded Swift diagnostics.
- Backend lowering that hides structure the graph already knows.
