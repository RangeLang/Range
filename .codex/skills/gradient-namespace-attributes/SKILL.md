---
name: neat-namespace-attributes
description: Use when changing namespace declarations, namespace-backed attributes, attribute validation, declaration graph collection, diagnostics for unknown attributes, or docs involving @Namespace behavior. Use the embedded direction in this skill to avoid validator side tables and stale attribute docs.
---

# Neat Namespace Attributes

## Workflow

1. Check current parser, declaration graph, validator, diagnostics, and tests before changing namespace-backed attribute behavior.
2. Treat this skill as design direction, not automatic truth.
3. Prefer declaration graph facts over validator-local rediscovery.
4. If the validator walks source files to rediscover namespaces, treat that as suspicious and inspect whether the graph should own the fact.
5. Keep diagnostics user-facing and concrete: unknown namespace-backed attributes should tell the user which namespace declaration is missing.

## Shape Bias

- A namespace declaration can make `@Namespace` valid.
- That fact should live in collected declaration data.
- Validators should ask the graph instead of reconstructing declaration meaning from raw source.
