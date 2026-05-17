---
name: neat-change-article
description: Create GitHub-ready technical design documents for Neat language design changes. Use when asked to turn Neat syntax, compiler, graph, editor, or product-design conversations into iterative explanatory Markdown docs, docs/articles drafts, release-note narratives, or GitHub design posts.
---

# Neat Change Article

## Workflow

1. Identify the language change and its motivation from the conversation, issue, PR, or local design notes.
2. Preserve the user's core framing when it is specific and strong. For typed construction metadata, read `references/typed-construction-metadata.md`.
3. Write to `docs/articles/<kebab-title>.md` unless the user names another destination.
4. Make the document concrete before abstract: introduce the smallest motivating example, then expand the model step by step.
5. Avoid calling a first-class language concept "sugar" unless the article is explicitly about surface syntax. Distinguish graph-level semantics from backend lowering.
6. Do not generate an `Open Questions`, `Questions`, `Unresolved`, or speculative ending section. When uncertainty matters, phrase the chosen direction as implementation sequencing or constraints.

## Design Document Shape

Use this structure by default:

```markdown
# Title

Short thesis paragraph that states the design decision.

## Motivation

Show the smallest example and why the old model misrepresents the language.

## Surface Form

Show the new syntax and the intended read.

## Semantic Model

Explain the graph-level meaning one layer at a time.

## Lowering

Describe how the model can lower to backend code without losing source intent.

## Implementation Sequence

Describe parser, AST, graph, diagnostics, codegen, and editor steps in order.

## Consequences

Explain effects on properties, tooling, diagnostics, codegen, docs, and cloud/package views.
```

Keep the document readable as a GitHub Markdown technical design document. Use fenced `neat` blocks for language examples and plain text blocks for graph sketches.

## Iterative Explanation

Build the design in passes:

1. Start with a single line of code.
2. State how a reader should understand it.
3. Show the graph shape.
4. Compare it to the old lowering only after the graph meaning is clear.
5. Expand from locals to properties and construct metadata.
6. End with concrete consequences, not questions.

## Voice

Use direct, design-forward prose. The document should sound like a language designer explaining the model iteratively, not like a changelog entry or brainstorming note.

Prefer phrases like:

- "the binding is born with construction data"
- "initialization is declaration metadata"
- "assignment is a later mutation operation"
- "the graph should preserve intent before lowering"

Avoid overclaiming implementation status. Say "proposed", "the intended model", or "the graph should" until the parser/compiler change exists.
