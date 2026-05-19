---
name: gradient-typed-construction-metadata
description: Use when changing typed construction syntax such as `let version: Version(0.1.8)`, binding/property initialization, graph initializer shape, assignment vs declaration metadata, parser diagnostics, backend lowering, or docs about construction metadata. Use the embedded direction in this skill to catch stale syntax or model drift.
---

# Gradient Typed Construction Metadata

## Workflow

1. Check current code and tests before changing typed construction parsing, graph storage, diagnostics, lowering, or docs.
2. Treat this skill as design intent, but clean up examples if implementation changed.
3. Preserve the core model unless the user explicitly changes direction: initialization is declaration metadata; assignment is later mutation.
4. Keep source intent separate from backend lowering.
5. If `Type(args)` appears after `:`, treat it as typed construction metadata, not sugar for `= Type(args)`.

## Shape Bias

```gradient
let version: Version(0.1.8)
```

Read this as:

```text
binding version
  type: Version
  construction data: 0.1.8
```

Do not model it first as slot assignment.
