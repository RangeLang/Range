---
name: range-update-post
description: Create very short Range update, addition, or feature posts with a concept title, compact example shape, and short design-oriented reason. Use when asked to turn Range syntax, compiler, graph, editor, tooling, docs, or product-design changes into compact Markdown update notes instead of long articles.
---

# Range Update Post

## Workflow

1. Identify the post kind: `Update post`, `Addition post`, or `Feature post`.
2. Choose a concept title, not an action title.
3. Keep the post short. Prefer one title, one sentence of context, one compact example section, and a compact reason.
4. Write to a user-named destination; if none is given, return the Markdown draft in the response.
5. Use the user's first-person Range developer voice only when needed, but avoid filler like "to me because".
6. Explain what repetition, awkwardness, or unclear shape was removed, and what the new shape makes easier to see.
7. Avoid speculative sections such as `Open Questions`, `Questions`, or `Unresolved`.

## Post Shapes

Use `Update post` when an existing shape changed:

````markdown
# Title

Short intro sentence.

## Before

```range
old shape
```

## After

```range
new shape
```

## Reason

One to three short sentences.
````

Use `Addition post` when a new syntax shape, compiler behavior, tool, or docs convention was added without replacing an old one:

````markdown
# Title

Short intro sentence.

## Addition

```range
new shape
```

## Reason

One to three short sentences.
````

Use `Feature post` when introducing a larger user-facing capability:

````markdown
# Title

Short intro sentence.

## Feature

Short description of the capability.

## Example

```range
example shape
```

## Reason

One to three short sentences.
````

Section names may change only when the user asks for a different format. Keep the order for the chosen post kind.

## Voice

Write like a concise update note from the Range developer:

- short paragraphs
- direct technical claims
- design-oriented wording
- concept titles, not action titles
- concrete examples over abstract framing
- no detached changelog boilerplate
- no long academic argument
- no "to me because" filler
- highlight repetition, awkwardness, or improved shape
- keep `Reason` short
- use a quote block when the reason is a quote

Good explanation lines sound like:

- "The old form worked, but it hid the intent."
- "The new form keeps the construction fact on the declaration."
- "Lowering can still happen later."
- "The graph now has the shape the editor needs."
- "This removes one repeated edge from every declaration."
- "The source now matches the thing the graph already knew."

## Constraints

- Keep most posts under 500 words unless the user asks for more.
- Use fenced `range` blocks for Range code.
- Use plain text blocks for graph sketches.
- Use Markdown quote blocks for quoted reasons.
- Do not call a first-class language concept "sugar" unless the update is specifically about surface syntax.
- Distinguish source intent, graph meaning, and backend lowering when that distinction matters.
