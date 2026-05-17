---
name: neat-typed-construction-metadata
description: Use when changing typed construction syntax such as `let version: Version(0.1.8)`, binding/property initialization, graph initializer shape, assignment vs declaration metadata, parser diagnostics, backend lowering, or docs about construction metadata. Load the historical typed construction metadata article and use it to catch stale syntax or model drift.
---

# Neat Typed Construction Metadata

## Workflow

1. Read `references/typed-construction-metadata.md` before changing typed construction parsing, graph storage, diagnostics, lowering, or docs.
2. Compare the reference against current code and tests. The note defines design intent, but examples may need cleanup if implementation changed.
3. Preserve the core model unless the user explicitly changes direction: initialization is declaration metadata; assignment is later mutation.
4. Keep source intent separate from backend lowering.
5. If `Type(args)` appears after `:`, treat it as typed construction metadata, not sugar for `= Type(args)`.

## Shape Bias

```neat
let version: Version(0.1.8)
```

Read this as:

```text
binding version
  type: Version
  construction data: 0.1.8
```

Do not model it first as slot assignment.

## Reference

Load `references/typed-construction-metadata.md` for the full article.
