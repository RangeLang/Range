---
name: range-direct-construct-application
description: Use when changing construct calls, initializer inference, direct construct application, constructor diagnostics, fixture cleanup, generated Swift initializers, or docs about constructs carrying data shape without explicit init declarations. Keeps construction modeled as direct application of construct data shape.
---

# Range Direct Construct Application

## Workflow

1. Check current compiler behavior and tests before changing construct application, initializer inference, constructor fixtures, or docs around `init`.
2. Treat this skill as historical design direction, not automatic truth.
3. Preserve the design direction where possible: construct calls apply the construct data shape directly.
4. Avoid reintroducing explicit `init` boilerplate as the language model unless the user explicitly changes direction.
5. If generated Swift still needs an initializer, keep that as lowering detail rather than source-level language truth.

## Current Direction

```range
construct User {
    let id: Int
    let name: String
}

let user: User(id: 1, name: "George")
```

The application should link arguments to construct members directly.

## Guardrails

- Project source should not need explicit `init` declarations for ordinary data-shaped constructs.
- Diagnostics should talk about construct members and arguments, not hidden Swift initializer machinery.
- Backend-generated initializers are allowed only as lowering detail.
