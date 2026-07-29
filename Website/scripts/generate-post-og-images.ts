import { mkdtemp, mkdir, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { posts } from "../src/lib/posts";

const websiteRoot = resolve(import.meta.dir, "..");
const outputRoot = resolve(websiteRoot, "public/og/posts");
const port = 44_000 + (process.pid % 1_000);
const origin = `http://127.0.0.1:${port}`;

const chromeCandidates = [
  process.env.RANGE_OG_CHROME,
  "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
  "/usr/bin/google-chrome",
  "/usr/bin/chromium",
  "/usr/bin/chromium-browser",
].filter((candidate): candidate is string => Boolean(candidate));

async function resolveChrome() {
  for (const candidate of chromeCandidates) {
    if (await Bun.file(candidate).exists()) return candidate;
  }
  throw new Error(
    "Chrome was not found. Set RANGE_OG_CHROME to a Chrome or Chromium executable.",
  );
}

async function waitForServer() {
  for (let attempt = 0; attempt < 80; attempt += 1) {
    try {
      const response = await fetch(origin);
      if (response.ok) return;
    } catch {
      // The server is still starting.
    }
    await Bun.sleep(50);
  }
  throw new Error("The built Website server did not start in time.");
}

async function assertPng(path: string) {
  const bytes = await readFile(path);
  const signature = bytes.subarray(0, 8).toString("hex");
  const width = bytes.readUInt32BE(16);
  const height = bytes.readUInt32BE(20);
  if (signature !== "89504e470d0a1a0a" || width !== 1200 || height !== 630) {
    throw new Error(`${path} is not a 1200x630 PNG.`);
  }
}

async function waitForCapture(path: string) {
  for (let attempt = 0; attempt < 200; attempt += 1) {
    try {
      await assertPng(path);
      return;
    } catch {
      await Bun.sleep(50);
    }
  }
  throw new Error(`Chrome did not write a valid capture to ${path}.`);
}

const chrome = await resolveChrome();
const profile = await mkdtemp(join(tmpdir(), "range-og-chrome-"));
await mkdir(outputRoot, { recursive: true });

const server = Bun.spawn([process.execPath, "build/index.js"], {
  cwd: websiteRoot,
  env: {
    ...process.env,
    HOST: "127.0.0.1",
    PORT: String(port),
    ORIGIN: origin,
  },
  stdout: "ignore",
  stderr: "inherit",
});

try {
  await waitForServer();

  for (const post of posts) {
    const output = resolve(outputRoot, `${post.slug}.png`);
    await rm(output, { force: true });
    const capture = Bun.spawn(
      [
        chrome,
        "--headless=new",
        "--hide-scrollbars",
        "--window-size=1200,630",
        "--force-device-scale-factor=1",
        "--run-all-compositor-stages-before-draw",
        "--virtual-time-budget=1500",
        `--user-data-dir=${profile}`,
        `--screenshot=${output}`,
        `${origin}/og-card/posts/${post.slug}`,
      ],
      {
        cwd: websiteRoot,
        stdout: "ignore",
        stderr: "ignore",
      },
    );

    try {
      await waitForCapture(output);
    } finally {
      if (capture.exitCode === null) capture.kill();
      await capture.exited;
    }
    console.log(`Generated public/og/posts/${post.slug}.png`);
  }
} finally {
  server.kill();
  await server.exited;
  await rm(profile, { recursive: true, force: true });
}
