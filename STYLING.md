# Neat Styling MANIFEST

This document describes the **styling system** used by Neat at a high level. It focuses on how we structure CSS and what kinds of classes we introduce; concrete details live in the CSS files themselves.

## 1. CSS Structure

Global styles live under `Sources/Neat/Resources/Styles`:

- `preflight.css` — Reset / preflight and base element defaults.
- `root.css` — Global tokens (e.g. `--space-unit`).
- `layout.css` — Small layout utilities (e.g. stack, padding/margin, size helpers).
- `style.css` — Visual utilities (background/text color, corner radius, typography).

Primitive styles live alongside their primitives under `Sources/Neat/Resources/Primitives/<Primitive>/`.

For the exact selectors and properties, refer directly to these files.

---

## 2. Utility-First Philosophy

Neat is **utility-first**:

- We prefer many small, orthogonal utilities over large, specialized classes.
- Utilities do one thing (e.g. padding/margin behavior, stack layout, background/text color, typography).
- Utilities are **design-system agnostic**; actual values are provided via CSS variables or higher-level APIs, not baked into class names.

Visual styling uses **variable-driven utilities plus style buckets**:

- Utilities in `layout.css`/`style.css` define behavior in terms of custom properties (e.g. padding, margin, background, text color, typography).
- Components and modifiers generate hashed style-bucket classes that only assign those variables.
- Elements combine:
  - Utility classes for behavior.
  - One or more hashed bucket classes for concrete values.

This keeps the utility vocabulary small and stable, while variation lives in CSS variables that Neat can generate and dedupe per component.

Common bucket class prefixes:

- `stack-` — Stack layout variables (`--stack-*`).
- `padding-` — Padding variables (`--pt/--pr/--pb/--pl`).
- `margin-` — Margin variables (`--mt/--mr/--mb/--ml`).
- `radius-` — Corner radius variables (`--cr-*`).
- `text-color-` — Text color variable (`--c`).
- `bg-color-` — Background color variable (`--bg`).
- `border-color-` — Border color variable (`--bc`).
- `border-` — Border width/style variables (`--bw`, `--bs`).
- `style-` — Everything else not captured by a more specific bucket.

Layout-aware primitives (e.g. `HStack`, `VStack`, `Spacer`) may interpret their children and choose between different utility combinations (such as stack display mode or size helpers) to provide higher-level layout behavior, but they must still emit compositions of small utilities and style buckets rather than introducing new semantic layout classes.

---

## 3. What We Avoid

We explicitly avoid:

- Aggregated / special-purpose classes that combine multiple behaviors into one (e.g. `.vstack`, `.hstack`, `.card`, `.hero`) where a single class implies both structure and role.
- Old helper classes like `.flex`, `.row`, `.column`, etc.; layout should be expressed via stack utilities plus variables, not generic flex helpers.
- Hard-coded scale utilities in class names (e.g. `.gap-1`, `.gap-2`, `.gap-5`); numeric decisions belong in variables/tokens, not class identifiers.

Primitives and components should compose existing utilities and style buckets instead of inventing new semantic layout or design classes.

---

## 4. Scope of This Document

This MANIFEST defines:

- The roles of the global style files in `Sources/Neat/Resources/Styles`.
- The utility-first, compositional philosophy for classes.
- The commitment to avoid aggregated, highly specific CSS classes in favor of small, reusable utilities and variable-driven style buckets.

For concrete usage and exact selectors, look at the corresponding CSS files and the style-related Swift modifiers and primitives.
