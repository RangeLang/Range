---
name: neat-change-article
description: Create GitHub-ready first-person technical design notes written as the Neat developer/user, from previous/current Neat language changes, with point-A to point-B transition narrative, annoyed developer story, academic question-answer flow, raw thought cadence, and super short information bursts. Use when asked to turn Neat syntax, compiler, graph, editor, or product-design diffs into user-authored Markdown docs, docs/articles drafts, release-note narratives, or GitHub design posts.
---

# Neat Change Article

## Workflow

1. Read both versions of the change first: the previous code/model and the current code/model. Treat them as point A and point B. If the user gives only one side, infer the missing side from context and state it inside the draft through examples.
2. Extract the transition: what point A made the compiler/user think, what point B now makes clear, and what had to move between them.
3. Turn the delta into the story of the user as the annoyed Neat developer. The irritation should be specific: repetition, wrong abstraction, compiler learning the wrong shape, graph losing source intent, editor/tooling forced to reverse-engineer meaning.
4. Preserve the user's core framing when it is specific and strong. For typed construction metadata, read `references/typed-construction-metadata.md`.
5. Write to `docs/articles/<kebab-title>.md` unless the user names another destination.
6. Make the document concrete before abstract: show point A, show point B, then explain the path from A to B as the user's first-person story of the annoyance becoming a design.
7. Frame the document as an answer to one design question. State that question early, then answer it by moving through evidence, model, consequences, and implementation.
8. Avoid calling a first-class language concept "sugar" unless the article is explicitly about surface syntax. Distinguish graph-level semantics from backend lowering.
9. Do not generate an `Open Questions`, `Questions`, `Unresolved`, or speculative ending section. When uncertainty matters, phrase the chosen direction as implementation sequencing or constraints.

## Diff Reading

Before writing, create a small internal transition map:

```text
point A / previous:
  code/model shape
  what it makes the compiler think
  what annoys the developer

point B / current:
  code/model shape
  what it lets the compiler know
  what becomes simpler or more truthful

transition:
  tokens removed or added
  graph fact preserved
  backend boundary clarified
  mental model moved from X to Y
```

Do not include this checklist verbatim unless it helps the article. Use it to find the story.

## Story Shape

Use this structure by default:

```markdown
# Title

Short first-person thesis paragraph in the user's voice that states the design direction and the shift in mental model.

## The Question

State the design question the article answers.

## Point A

Start with the previous code/model shape, what felt wrong about it, and the assumption it carried.

## Point B

Introduce the current code/model shape as the changed state and explain what it reveals.

## The Move

Explain the transition from point A to point B: what changed in syntax, graph meaning, and compiler responsibility.

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

The section titles may change, but the story arc should remain: previous assumption, pressure point, current form, transition, deeper model, implementation path, resulting system behavior.

## Academic Flow

Make the document feel like it is answering a design question:

1. Pose one central question, such as "Should initialization be modeled as assignment, or as declaration metadata?"
2. Give a short answer before the evidence.
3. Use previous/current examples as evidence.
4. Define the terms that matter: assignment, initialization, construction metadata, source graph, lowering.
5. Argue from model clarity, not preference alone.
6. State consequences as conclusions from the model.

The academic flow should organize the thought. It should not erase the user's annoyed developer voice.

## Narrative Rules

Give the document a first-person technical story from the point-A to point-B transition without making it casual fiction:

1. Write as the user/Neat developer explaining the change they want to make. Do not write as the AI or agent. Use "I want", "I think", "I do not want", and "the compiler should" where natural.
2. Start from point A and name the annoyance plainly.
3. Show point B as the current state the change is moving toward, not as decoration.
4. Explain the hidden assumption in point A.
5. Introduce the proposed form as the moment the model becomes visible.
6. Explain the move from A to B before going deeper into graph, properties, and lowering.
7. End by showing the system at point B still moving, not by listing uncertainties.

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

Use direct, design-forward prose in the user's first person. The document should sound like the Neat developer explaining why they want the change and walking the reader through the idea as it becomes inevitable, not like an AI assistant, changelog entry, brainstorming note, or detached spec dump.

Use a lower-level thought cadence. Keep sentences short. Let some lines feel blunt and almost primitive:

- "This works."
- "But it lies a little."
- "This is the annoying part."
- "The slot is not the thing."
- "The binding is being born."
- "Assignment is later."
- "The graph needs the birth shape."

Do not make the prose sloppy. The cadence can be raw, but the technical model must stay precise.

Use super short information bursts. Most paragraphs should be one to three short sentences. Keep each burst meaningful: one claim, one example, or one consequence. Do not make it decorative poetry. Use rhythm to make technical thought feel alive without making the article vague:

- short image-like statements where they help
- repeated motifs
- clean white space
- compact chunks that build one idea at a time
- fast movement from point A to point B
- final lines that leave the model still moving forward

The document must still be a technical design note. Code blocks, graph sketches, and implementation steps remain concrete.

Prefer phrases like:

- "the binding is born with construction data"
- "initialization is declaration metadata"
- "assignment is a later mutation operation"
- "the graph should preserve intent before lowering"

Avoid overclaiming implementation status. Say "proposed", "the intended model", or "the graph should" until the parser/compiler change exists.
