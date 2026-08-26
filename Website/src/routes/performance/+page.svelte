<script lang="ts">
  import { onDestroy } from "svelte";
  import PerformanceScope from "$lib/components/PerformanceScope.svelte";
  import type {
    CompilerProfileSummary,
    MonitorEvent,
    PerformanceSample,
  } from "$lib/performance-monitor";

  let samples = $state<PerformanceSample[]>([]);
  let metric = $state<"memory" | "cpu">("memory");
  let runState = $state<"idle" | "running" | "finished" | "failed">("idle");
  let message = $state("Ready to profile the current compiler source graph.");
  let summary = $state<CompilerProfileSummary | null>(null);
  let abortController: AbortController | null = null;

  let latest = $derived(samples.at(-1));
  let peakMemory = $derived(samples.reduce((peak, sample) => Math.max(peak, sample.rangeResidentBytes), 0));
  let peakCpu = $derived(samples.reduce((peak, sample) => Math.max(peak, sample.rangeCpuPercent), 0));
  let topPeer = $derived(latest?.peers[0]);

  const memory = (bytes: number | null | undefined) => {
    if (!bytes) return "0 MB";
    return `${(bytes / (1024 * 1024)).toFixed(bytes >= 1024 * 1024 * 1024 ? 0 : 1)} MB`;
  };

  const seconds = (milliseconds: number | null | undefined) =>
    `${((milliseconds ?? 0) / 1000).toFixed(1)} s`;

  function receive(event: MonitorEvent) {
    if (event.type === "started") {
      message = "Building the instrumented compiler…";
      return;
    }
    if (event.type === "sample") {
      samples = [...samples.slice(-239), event];
      message = event.rangeCpuPercent > 0
        ? "Compiler activity detected"
        : "Preparing the next compiler phase…";
      return;
    }
    if (event.type === "finished") {
      summary = event;
      runState = event.status === 0 ? "finished" : "failed";
      message = event.status === 0
        ? "Profile complete"
        : `Compiler profile exited with status ${event.status ?? "unknown"}`;
      return;
    }
    runState = "failed";
    message = event.message;
  }

  async function runProfile() {
    if (runState === "running") return;
    samples = [];
    summary = null;
    runState = "running";
    message = "Starting profiler…";
    abortController = new AbortController();
    try {
      const response = await fetch("/api/performance/run", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ preset: "compiler" }),
        signal: abortController.signal,
      });
      if (!response.ok || !response.body) {
        throw new Error((await response.text()) || `Profiler returned ${response.status}`);
      }

      const reader = response.body.getReader();
      const decoder = new TextDecoder();
      let buffer = "";
      while (true) {
        const { value, done } = await reader.read();
        buffer += decoder.decode(value, { stream: !done });
        const lines = buffer.split("\n");
        buffer = lines.pop() ?? "";
        for (const line of lines) {
          if (line) receive(JSON.parse(line) as MonitorEvent);
        }
        if (done) break;
      }
      if (buffer) receive(JSON.parse(buffer) as MonitorEvent);
    } catch (cause) {
      if (cause instanceof DOMException && cause.name === "AbortError") {
        runState = "idle";
        message = "Profile stopped";
      } else {
        runState = "failed";
        message = cause instanceof Error ? cause.message : "The profiler failed.";
      }
    } finally {
      abortController = null;
    }
  }

  async function stopProfile() {
    const controller = abortController;
    try {
      await fetch("/api/performance/run", { method: "DELETE", keepalive: true });
    } finally {
      controller?.abort();
    }
  }

  onDestroy(() => {
    if (runState === "running") {
      void fetch("/api/performance/run", { method: "DELETE", keepalive: true });
    }
    abortController?.abort();
  });
</script>

<svelte:head>
  <title>Compiler Scope · Range</title>
  <meta name="description" content="A local live performance monitor for the Range compiler." />
  <meta name="robots" content="noindex,nofollow" />
</svelte:head>

<range-performance-monitor>
  <main>
    <header class="monitorHeader">
      <div>
        <p class="eyebrow">LOCAL INSTRUMENT</p>
        <h1>Compiler Scope</h1>
        <p class="introduction">A moving trace of the real Range compiler process and the other work sharing your Mac.</p>
      </div>
      <div class="runControls">
        {#if runState === "running"}
          <button class="stopButton" onclick={stopProfile}>Stop</button>
        {:else}
          <button class="runButton" onclick={runProfile}>Run compiler profile</button>
        {/if}
        <span class:live={runState === "running"} class="status"><i></i>{message}</span>
      </div>
    </header>

    <section class="instrument" aria-labelledby="trace-title">
      <div class="instrumentBar">
        <div>
          <h2 id="trace-title">Live trace</h2>
          <span class="legend rangeLegend">Range process tree</span>
          <span class="legend peerLegend">Heaviest neighboring task</span>
        </div>
        <div class="metricPicker" aria-label="Trace metric">
          <button class:active={metric === "memory"} onclick={() => metric = "memory"}>Memory</button>
          <button class:active={metric === "cpu"} onclick={() => metric = "cpu"}>CPU</button>
        </div>
      </div>
      <PerformanceScope {samples} {metric} />
      <div class="readouts">
        <article><span>Range now</span><strong>{metric === "memory" ? memory(latest?.rangeResidentBytes) : `${(latest?.rangeCpuPercent ?? 0).toFixed(1)}%`}</strong></article>
        <article><span>Range peak</span><strong>{metric === "memory" ? memory(peakMemory) : `${peakCpu.toFixed(1)}%`}</strong></article>
        <article><span>Elapsed</span><strong>{seconds(latest?.elapsedMilliseconds)}</strong></article>
        <article><span>Neighbor</span><strong>{topPeer?.name ?? "—"}</strong><small>{topPeer ? `${memory(topPeer.residentBytes)} · ${topPeer.cpuPercent.toFixed(1)}%` : "Waiting for sample"}</small></article>
      </div>
    </section>

    <section class="result" aria-labelledby="result-title">
      <div><p class="eyebrow">LAST RESULT</p><h2 id="result-title">Compiler output</h2></div>
      <dl>
        <div><dt>Status</dt><dd>{summary ? (summary.status === 0 ? "Passed" : `Exit ${summary.status}`) : "—"}</dd></div>
        <div><dt>Functions</dt><dd>{summary?.functionCount?.toLocaleString() ?? "—"}</dd></div>
        <div><dt>LLVM emitted</dt><dd>{summary?.llvmBytes ? memory(summary.llvmBytes) : "—"}</dd></div>
        <div><dt>Peak footprint</dt><dd>{summary?.peakFootprintBytes ? memory(summary.peakFootprintBytes) : memory(peakMemory) || "—"}</dd></div>
      </dl>
      <p class="provenance">Runs <code>scripts/profile-range-compiler</code> against the checkout you opened. Measurements stay on this machine.</p>
    </section>
  </main>
</range-performance-monitor>

<style>
  :global(range-performance-monitor) {
    min-height: 100vh;
    display: block;
    background: oklch(0.105 0.014 255);
    color: oklch(0.94 0.01 255);
  }

  :global(range-performance-monitor range-spline-nav a),
  :global(range-performance-monitor .landingWordmark) { color: oklch(0.76 0.02 255); }
  :global(range-performance-monitor range-spline-nav a:hover),
  :global(range-performance-monitor .landingWordmark:hover) { color: oklch(0.98 0.01 255); }

  main {
    width: min(1320px, calc(100% - 48px));
    padding-bottom: 72px;
  }

  .monitorHeader {
    display: grid;
    grid-template-columns: minmax(0, 1fr) auto;
    align-items: end;
    gap: 32px;
    padding: 36px 0 42px;
  }

  .eyebrow {
    margin: 0 0 12px;
    color: oklch(0.67 0.12 286);
    font: 10px/1 var(--font-geist-mono), monospace;
    letter-spacing: 0.18em;
  }

  h1, h2 { margin: 0; font-weight: 500; letter-spacing: -0.04em; }
  h1 { font-size: clamp(44px, 7vw, 86px); line-height: 0.9; }
  h2 { font-size: 18px; }

  .introduction {
    max-width: 590px;
    margin: 22px 0 0;
    color: oklch(0.7 0.02 255);
    font-size: 15px;
    line-height: 1.55;
  }

  .runControls { min-width: min(100%, 280px); display: grid; gap: 13px; justify-items: stretch; }
  button { font: inherit; cursor: pointer; }
  .runButton, .stopButton {
    min-height: 46px;
    padding: 0 18px;
    border: 1px solid transparent;
    border-radius: 8px;
    font-weight: 600;
  }
  .runButton { background: oklch(0.74 0.2 286); color: oklch(0.13 0.03 286); }
  .runButton:hover { background: oklch(0.8 0.2 286); }
  .stopButton { border-color: oklch(0.55 0.16 28); background: oklch(0.22 0.06 28); color: oklch(0.86 0.1 28); }

  .status {
    display: flex;
    align-items: center;
    gap: 8px;
    color: oklch(0.64 0.02 255);
    font: 11px var(--font-geist-mono), monospace;
  }
  .status i { width: 7px; height: 7px; border-radius: 50%; background: oklch(0.45 0.02 255); }
  .status.live i { background: oklch(0.76 0.2 145); box-shadow: 0 0 10px oklch(0.76 0.2 145); animation: pulse 1.4s ease-in-out infinite; }

  .instrument, .result {
    border: 1px solid oklch(0.27 0.02 255);
    border-radius: 18px;
    background: oklch(0.15 0.016 255);
  }
  .instrument { padding: 18px; }
  .instrumentBar { display: flex; align-items: center; justify-content: space-between; gap: 20px; padding: 2px 2px 18px; }
  .instrumentBar > div:first-child { display: flex; flex-wrap: wrap; align-items: center; gap: 12px 20px; }
  .legend { color: oklch(0.66 0.02 255); font: 10px var(--font-geist-mono), monospace; }
  .legend::before { width: 14px; height: 2px; display: inline-block; margin: 0 7px 3px 0; content: ""; }
  .rangeLegend::before { background: oklch(0.78 0.2 286); box-shadow: 0 0 7px oklch(0.78 0.2 286); }
  .peerLegend::before { background: oklch(0.78 0.17 72); box-shadow: 0 0 7px oklch(0.78 0.17 72); }
  .metricPicker { display: flex; padding: 3px; border: 1px solid oklch(0.28 0.02 255); border-radius: 8px; background: oklch(0.12 0.01 255); }
  .metricPicker button { padding: 6px 10px; border: 0; border-radius: 5px; background: transparent; color: oklch(0.6 0.02 255); font: 11px var(--font-geist-mono), monospace; }
  .metricPicker button.active { background: oklch(0.25 0.035 286); color: oklch(0.88 0.08 286); }

  .readouts { display: grid; grid-template-columns: repeat(4, minmax(0, 1fr)); border-top: 1px solid oklch(0.27 0.02 255); margin-top: 18px; }
  .readouts article { min-width: 0; padding: 18px 16px 2px; border-right: 1px solid oklch(0.27 0.02 255); }
  .readouts article:last-child { border-right: 0; }
  .readouts span, .readouts small { display: block; color: oklch(0.58 0.02 255); font: 10px var(--font-geist-mono), monospace; }
  .readouts strong { display: block; overflow: hidden; margin-top: 8px; color: oklch(0.94 0.01 255); font: 500 clamp(18px, 2.5vw, 28px)/1 var(--font-geist-mono), monospace; text-overflow: ellipsis; white-space: nowrap; }
  .readouts small { margin-top: 7px; }

  .result { display: grid; grid-template-columns: 0.8fr 2fr; gap: 36px; margin-top: 18px; padding: 28px 20px; }
  .result dl { display: grid; grid-template-columns: repeat(4, minmax(0, 1fr)); gap: 20px; margin: 0; }
  .result dl div { min-width: 0; }
  dt { color: oklch(0.58 0.02 255); font: 10px var(--font-geist-mono), monospace; }
  dd { overflow: hidden; margin: 9px 0 0; font: 16px var(--font-geist-mono), monospace; text-overflow: ellipsis; }
  .provenance { grid-column: 2; margin: 0; color: oklch(0.55 0.02 255); font-size: 11px; }
  code { color: oklch(0.72 0.1 286); font-family: var(--font-geist-mono), monospace; }

  @keyframes pulse { 50% { opacity: 0.45; } }

  @media (max-width: 800px) {
    .monitorHeader { grid-template-columns: 1fr; }
    .runControls { justify-items: stretch; }
    .readouts { grid-template-columns: repeat(2, minmax(0, 1fr)); }
    .readouts article:nth-child(2) { border-right: 0; }
    .readouts article:nth-child(-n + 2) { border-bottom: 1px solid oklch(0.27 0.02 255); }
    .result { grid-template-columns: 1fr; }
    .result dl { grid-template-columns: repeat(2, minmax(0, 1fr)); }
    .provenance { grid-column: 1; }
  }

  @media (max-width: 520px) {
    main { width: min(100% - 28px, 1320px); padding-top: 26px; }
    .instrumentBar { align-items: flex-start; flex-direction: column; }
    .readouts strong { font-size: 18px; }
  }

  @media (prefers-reduced-motion: reduce) {
    .status.live i { animation: none; }
  }
</style>
