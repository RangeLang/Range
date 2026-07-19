# Range site

The Range website is rendered with standards-based Web Components and a small
Cloudflare Worker. It has no React, Next, or Vinext runtime.

## Routes

- `/`
- `/benchmarks`
- `/benchmarks/:benchmarkID`
- `/updates/:updateID`

## Commands

- `npm run dev` starts the local Worker preview.
- `npm test` builds the site and verifies every route, the benchmark artifact,
  syntax highlighting, the Range scale, and the framework-free component
  boundary.
- `npm run build` creates the Sites deployment output.

The Worker performs the first render so direct links contain complete HTML.
Custom elements own the site surfaces and progressively enhance the Range
scale, optical alignment guide, and typed title transition in the browser.
