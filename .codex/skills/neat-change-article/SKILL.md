---
name: neat-change-article
description: Create GitHub-ready first-person technical design notes with a clear story for Neat language design changes. Use when asked to turn Neat syntax, compiler, graph, editor, or product-design conversations into developer-authored Markdown docs, docs/articles drafts, release-note narratives, or GitHub design posts.
---

# Neat Change Article

## Workflow

1. Identify the language change and its motivation from the conversation, issue, PR, or local design notes.
2. Preserve the user's core framing when it is specific and strong. For typed construction metadata, read `references/typed-construction-metadata.md`.
3. Write to `docs/articles/<kebab-title>.md` unless the user names another destination.
4. Make the document concrete before abstract: introduce the smallest motivating example, then expand the model step by step as a first-person story of the idea becoming clearer.
5. Avoid calling a first-class language concept "sugar" unless the article is explicitly about surface syntax. Distinguish graph-level semantics from backend lowering.
6. Do not generate an `Open Questions`, `Questions`, `Unresolved`, or speculative ending section. When uncertainty matters, phrase the chosen direction as implementation sequencing or constraints.

## Story Shape

Use this structure by default:

```markdown
# Title

Short first-person thesis paragraph that states the design direction and the shift in mental model.

## The Starting Point

Start with the ordinary code shape, what feels wrong about it, and the assumption it carries.

## The Turn

Introduce the smaller syntax as the change the developer wants to make and explain what it reveals.

## The Model

Explain the graph-level meaning one layer at a time, letting each layer follow from the previous one.

## The Boundary

Separate source intent from backend lowering.

## The Path

Describe parser, AST, graph, diagnostics, codegen, and editor steps in order.

## The Result

Explain effects on properties, tooling, diagnostics, codegen, docs, and cloud/package views.
```

Keep the document readable as a GitHub Markdown technical design document. Use fenced `neat` blocks for language examples and plain text blocks for graph sketches.

The section titles may change, but the story arc should remain: old assumption, pressure point, new form, deeper model, implementation path, resulting system behavior.

## Narrative Rules

Give the document a first-person technical story without making it casual fiction:

1. Write as a developer explaining the change they want to make: use "I want", "I think", "I do not want", and "the compiler should" where natural.
2. Start from a real line of Neat code that feels slightly wrong or too repetitive.
3. Explain the hidden assumption in that line.
4. Introduce the proposed form as the moment the model becomes visible.
5. Follow the consequence into the graph, then into properties, then into lowering.
6. End by showing the system after the change, not by listing uncertainties.

Use transitions that carry the reader forward: "That works, but it teaches the wrong model", "The smaller form changes what the declaration is saying", "Once the graph keeps that fact, properties become data-shaped", "Lowering can still be ordinary Swift, but it happens later."

## Iterative Explanation

Build the design in passes:

1. Start with a single line of code.
2. State how a reader should understand it.
3. Show the graph shape.
4. Compare it to the old lowering only after the graph meaning is clear.
5. Expand from locals to properties and construct metadata.
6. End with concrete consequences, not questions.

## Voice

Use direct, design-forward prose in first person. The document should sound like a developer explaining why they want the change and walking the reader through the idea as it becomes inevitable, not like a changelog entry, brainstorming note, or detached spec dump.

Prefer phrases like:

- "the binding is born with construction data"
- "initialization is declaration metadata"
- "assignment is a later mutation operation"
- "the graph should preserve intent before lowering"

Avoid overclaiming implementation status. Say "proposed", "the intended model", or "the graph should" until the parser/compiler change exists.
