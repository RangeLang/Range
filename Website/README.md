# Range site

The Range website is rendered with Svelte 5 and SvelteKit. Bun owns dependency
installation, local scripts, tests, and the production server runtime.

## Routes

- `/`
- `/benchmarks`
- `/benchmarks/:benchmarkID`
- `/updates/:updateID`

## Commands

- `bun run dev` starts the local SvelteKit preview.
- `bun test` builds the site and verifies every route, the benchmark artifact,
  syntax highlighting, the Range scale, and the Svelte component boundary.
- `bun run build` creates the standalone server in `build/`.
- `bun run start` runs that production build with Bun.

SvelteKit performs the first render so direct links contain complete HTML.
Custom elements progressively enhance the Range scale, optical alignment guide,
and typed title transition in the browser. Drizzle is available through
`db/index.ts` when persistent data is needed; the benchmark pages use the
versioned JSON artifact directly.

## Benchmark data

The repository benchmark runner at `../Benchmarks/Speed/run.py` writes the
versioned website input to `public/benchmarks.json`. The website test suite
validates that artifact against
`../Benchmarks/Speed/benchmark-results.schema.json`.
