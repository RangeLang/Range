# syntax=docker/dockerfile:1

FROM oven/bun:1.3.14-alpine AS dependencies

WORKDIR /app

COPY Website/package.json Website/bun.lock ./
RUN bun install --frozen-lockfile

FROM oven/bun:1.3.14-alpine AS build

WORKDIR /app

COPY --from=dependencies /app/node_modules ./node_modules
COPY Website/ .
COPY RangeCompiler/Sources/Core/Macro/Codable.range /RangeCompiler/Sources/Core/Macro/Codable.range
COPY RangeCompiler/Sources/Core/Macro/CommandGroup.range /RangeCompiler/Sources/Core/Macro/CommandGroup.range
COPY Benchmarks/Speed/results/latest.json /Benchmarks/Speed/results/latest.json

RUN bun run build

FROM oven/bun:1.3.14-alpine AS runtime

WORKDIR /app

ENV HOST=0.0.0.0 \
    NODE_ENV=production \
    PORT=3000

COPY --chown=bun:bun --from=build /app/build ./build
COPY --chown=bun:bun --from=dependencies /app/node_modules ./node_modules

USER bun

EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD ["bun", "-e", "const port=process.env.PORT??'3000';const response=await fetch(`http://127.0.0.1:${port}/health`);if(!response.ok)process.exit(1)"]

CMD ["bun", "build/index.js"]
