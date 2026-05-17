---
name: neat-update-post
description: Create very short Neat update posts that show a before example, an after example, and a brief explanation of what changed. Use when asked to turn Neat syntax, compiler, graph, editor, tooling, docs, or product-design changes into compact Markdown update notes instead of long articles.
---

# Neat Update Post

## Workflow

1. Identify the smallest visible change. Treat the old shape as `Before` and the new shape as `After`.
2. Keep the post short. Prefer one title, one sentence of context, before/after examples, and a compact explanation.
3. Write to `docs/posts/<kebab-title>.md` unless the user names another destination.
4. Use the user's first-person Neat developer voice when a design opinion matters, but avoid long narrative setup.
5. Explain what the before form made unclear, what the after form makes explicit, and what compiler/tooling behavior follows.
6. Avoid speculative sections such as `Open Questions`, `Questions`, or `Unresolved`.

## Default Shape

Use this structure by default:

````markdown
# Title

One short sentence saying what changed.

## Before

```neat
old code or model
```

## After

```neat
new code or model
```

## Why

Two to six short sentences explaining the update.
````

Section names may change, but the post must still show before, after, and explanation in that order.

## Voice

Write like a concise update note from the Neat developer:

- short paragraphs
- direct technical claims
- concrete examples over abstract framing
- no detached changelog boilerplate
- no long academic argument

Good explanation lines sound like:

- "The old form worked, but it hid the intent."
- "The new form keeps the construction fact on the declaration."
- "Lowering can still happen later."
- "The graph now has the shape the editor needs."

## Constraints

- Keep most posts under 500 words unless the user asks for more.
- Use fenced `neat` blocks for Neat code.
- Use plain text blocks for graph sketches.
- Do not call a first-class language concept "sugar" unless the update is specifically about surface syntax.
- Distinguish source intent, graph meaning, and backend lowering when that distinction matters.
