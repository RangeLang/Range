# Range site

The Range website is rendered with Svelte 5 and SvelteKit. Bun owns dependency
installation, local scripts, tests, and the production server runtime.

## Routes

- `/`
- `/benchmarks`
- `/benchmarks/:benchmarkID`
- `/posts/:postID`

## Commands

- `bun run dev` starts the local SvelteKit preview.
- `bun run sync:sources` refreshes the Website-owned Range source snapshots and
  records their source commit and SHA-256 hashes.
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

## Versioned content

`public/benchmarks.json` is the Website-owned benchmark artifact used by the
production build. Range source excerpts are complete snapshots under
`src/lib/content/source-snapshots/`; their source commit and SHA-256 hashes are
recorded in that directory's `manifest.json`. Run `bun run sync:sources` from a
clean Range development commit whenever those snapshots are deliberately
refreshed, then review and commit the generated files with the Website.

Production image builds therefore need only the `Website/` directory and the
pinned Sveltely submodule. They do not read sibling compiler, fixture, or
benchmark paths.

## Docker deployment

The production image uses Bun 1.3.14 for both the build and the runtime. It
runs as the unprivileged `bun` user and exposes the SvelteKit server on port
`3000`. Run Compose from the `Website/` directory after initializing the pinned
Sveltely submodule.

On the server:

```sh
cp .env.example .env
# Set SITE_ADDRESS=https://rangelang.org and
# SITE_ALIAS_ADDRESS=https://www.rangelang.org in .env.
git submodule update --init Website/src/lib/frameworks/sveltely
RANGE_WEBSITE_TAG="$(git rev-parse HEAD)" docker compose build --pull
docker compose up -d
docker compose ps
curl --fail https://rangelang.org/health
```

Caddy owns host ports `80` and `443`, obtains and renews the site's TLS
certificate, enables HTTP/3, and proxies to the website over the private
Compose network. Before starting the stack, point the domain's `A` record
(and `AAAA` record when used) at the server and allow inbound TCP `80`/`443`
and UDP `443`.

For a local HTTP check, leave `SITE_ADDRESS=http://localhost` and request
`http://localhost/health`.

To deploy a later revision, retain the prior tagged image for rollback and tag
the replacement with its production release commit:

```sh
git pull --ff-only
git submodule update --init Website/src/lib/frameworks/sveltely
RANGE_WEBSITE_TAG="$(git rev-parse HEAD)" docker compose build
RANGE_WEBSITE_TAG="$(git rev-parse HEAD)" docker compose up -d
docker compose logs --tail=100 website caddy
```

`GET /health` is the container and external readiness endpoint. A healthy
response is `{"status":"ok"}`.
