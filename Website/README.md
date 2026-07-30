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

Editorial copy follows [`STYLEGUIDE.md`](STYLEGUIDE.md).

## Benchmark data

The repository benchmark runner at `../Benchmarks/Speed/run.py` writes the
versioned website input to `public/benchmarks.json`. The website test suite
validates that artifact against
`../Benchmarks/Speed/benchmark-results.schema.json`.

## Docker deployment

The production image uses Bun 1.3.14 for both the build and the runtime. It
runs as the unprivileged `bun` user and exposes the SvelteKit server on port
`3000`. Run Compose from this `Website/` directory inside the Range checkout:
the build context includes the website and its canonical
`RangeCompiler/Sources/Core/Macro/Codable.range` presentation source plus the
current `Benchmarks/Speed/results/latest.json` measurement artifact.

On the server:

```sh
cp .env.example .env
# Set SITE_ADDRESS in .env to the site's public HTTPS URL.
docker compose build --pull
docker compose up -d
docker compose ps
curl --fail https://your-domain.example/health
```

Caddy owns host ports `80` and `443`, obtains and renews the site's TLS
certificate, enables HTTP/3, and proxies to the website over the private
Compose network. Before starting the stack, point the domain's `A` record
(and `AAAA` record when used) at the server and allow inbound TCP `80`/`443`
and UDP `443`.

For a local HTTP check, leave `SITE_ADDRESS=http://localhost` and request
`http://localhost/health`.

To deploy a later revision:

```sh
git pull --ff-only
docker compose up -d --build
docker compose logs --tail=100 website caddy
```

`GET /health` is the container and external readiness endpoint. A healthy
response is `{"status":"ok"}`.
