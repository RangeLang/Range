---
name: range-namespace-attributes
description: Use when changing namespace declarations, namespace-backed attributes, attribute validation, declaration graph collection, diagnostics for unknown attributes, or docs involving @Namespace behavior. Keeps namespace attribute facts graph-owned instead of validator-local.
---

# Range Namespace Attributes

## Workflow

1. Check the parser, declaration graph, validators, diagnostics, and fixtures before changing namespace-backed attribute behavior.
2. Treat this skill as design direction, not automatic truth.
3. Keep namespace validity as a declaration graph fact.
4. If validation walks source files to rediscover namespaces, inspect whether the graph should own that fact instead.
5. Keep diagnostics concrete: unknown namespace-backed attributes should say which namespace declaration is missing.

## Current Direction

- A namespace declaration can make `@Namespace` valid.
- Namespace attribute names and attachments should be collected into declaration data.
- Validators should query graph facts instead of rebuilding declaration meaning from raw syntax.
- Docs should avoid implying that namespace-backed attributes are loose parser markers.
