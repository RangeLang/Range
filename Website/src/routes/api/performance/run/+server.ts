import { execFile } from "node:child_process";
import { access } from "node:fs/promises";
import { resolve } from "node:path";
import { promisify } from "node:util";
import { error } from "@sveltejs/kit";
import type { RequestHandler } from "./$types";
import {
  parseCompilerProfileSummary,
  parseProcessRows,
  sampleProcesses,
  type MonitorEvent,
} from "$lib/performance-monitor";

const executeFile = promisify(execFile);
const encoder = new TextEncoder();
const sampleIntervalMilliseconds = 250;
const maximumRunMilliseconds = 15 * 60 * 1000;
let activeRun = false;
let stopActiveRun: (() => void) | null = null;

function isLoopback(hostname: string): boolean {
  return hostname === "localhost" || hostname === "127.0.0.1" || hostname === "[::1]" || hostname === "::1";
}

function repositoryRoot(): string {
  return process.env.RANGE_REPOSITORY_ROOT ?? resolve(process.cwd(), "..");
}

function encodeEvent(event: MonitorEvent): Uint8Array {
  return encoder.encode(`${JSON.stringify(event)}\n`);
}

export const POST: RequestHandler = async ({ request, url }) => {
  if (!isLoopback(url.hostname)) error(404, "The performance monitor is available only on localhost.");
  if (activeRun) error(409, "A Range compiler profile is already running.");

  const body = await request.json().catch(() => ({}));
  if (body?.preset !== "compiler") error(400, "Unknown performance preset.");

  const root = repositoryRoot();
  const profiler = resolve(root, "scripts/profile-range-compiler");
  await access(profiler).catch(() => error(503, "Range compiler profiler was not found."));
  activeRun = true;

  let child: ReturnType<typeof Bun.spawn> | undefined;
  let stopped = false;
  let sampleTimer: ReturnType<typeof setInterval> | undefined;
  let runTimer: ReturnType<typeof setTimeout> | undefined;

  const stopChild = () => {
    if (stopped) return;
    stopped = true;
    if (sampleTimer) clearInterval(sampleTimer);
    if (runTimer) clearTimeout(runTimer);
    if (child?.pid) {
      try {
        process.kill(-child.pid, "SIGTERM");
      } catch {
        child.kill("SIGTERM");
      }
    }
  };
  stopActiveRun = stopChild;
  runTimer = setTimeout(stopChild, maximumRunMilliseconds);

  const stream = new ReadableStream<Uint8Array>({
    async start(controller) {
      const started = performance.now();
      let sampling = false;
      let stdout = "";
      try {
        child = Bun.spawn([profiler], {
          cwd: root,
          env: process.env,
          stdout: "pipe",
          stderr: "pipe",
          detached: true,
        });
        controller.enqueue(encodeEvent({
          type: "started",
          startedAt: new Date().toISOString(),
          sampleIntervalMilliseconds,
        }));

        const collectSample = async () => {
          if (!child?.pid || sampling || stopped) return;
          sampling = true;
          try {
            const { stdout: processOutput } = await executeFile("ps", [
              "-axo",
              "pid=,ppid=,%cpu=,rss=,comm=",
            ]);
            controller.enqueue(encodeEvent({
              type: "sample",
              ...sampleProcesses(
                parseProcessRows(processOutput),
                child.pid,
                performance.now() - started,
              ),
            }));
          } catch {
            // A missed sample should not invalidate the compiler profile.
          } finally {
            sampling = false;
          }
        };

        await collectSample();
        sampleTimer = setInterval(collectSample, sampleIntervalMilliseconds);
        const stdoutPromise = new Response(child.stdout as ReadableStream<Uint8Array>).text();
        const stderrPromise = new Response(child.stderr as ReadableStream<Uint8Array>).text();
        const exitCode = await child.exited;
        stdout = await stdoutPromise;
        const stderr = await stderrPromise;
        if (sampleTimer) clearInterval(sampleTimer);
        await collectSample();

        const summary = parseCompilerProfileSummary(stdout);
        controller.enqueue(encodeEvent({
          type: "finished",
          durationMilliseconds: performance.now() - started,
          ...summary,
          status: summary.status ?? exitCode,
        }));
        if (exitCode !== 0 && summary.status === null) {
          controller.enqueue(encodeEvent({
            type: "error",
            message: stderr.trim().split("\n").at(-1) || "The compiler profile failed.",
          }));
        }
        controller.close();
      } catch (cause) {
        controller.enqueue(encodeEvent({
          type: "error",
          message: cause instanceof Error ? cause.message : "The compiler profile could not start.",
        }));
        controller.close();
      } finally {
        if (sampleTimer) clearInterval(sampleTimer);
        if (runTimer) clearTimeout(runTimer);
        activeRun = false;
        stopActiveRun = null;
      }
    },
    cancel() {
      stopChild();
      activeRun = false;
    },
  });

  request.signal.addEventListener("abort", stopChild, { once: true });
  return new Response(stream, {
    headers: {
      "cache-control": "no-store",
      "content-type": "application/x-ndjson; charset=utf-8",
      "x-content-type-options": "nosniff",
    },
  });
};

export const DELETE: RequestHandler = ({ url }) => {
  if (!isLoopback(url.hostname)) error(404, "The performance monitor is available only on localhost.");
  if (!stopActiveRun) return new Response(null, { status: 204 });
  stopActiveRun();
  return new Response(null, { status: 202 });
};
