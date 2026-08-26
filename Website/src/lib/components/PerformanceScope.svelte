<script lang="ts">
  import { onMount } from "svelte";
  import type { PerformanceSample } from "$lib/performance-monitor";

  let {
    samples,
    metric,
  }: {
    samples: PerformanceSample[];
    metric: "memory" | "cpu";
  } = $props();

  let canvas: HTMLCanvasElement;
  let scaleLabel = $state("");
  let visibleWindowMilliseconds = 30_000;
  let lastSampleCount = 0;
  let lastSampleArrival = 0;

  const memoryValue = (sample: PerformanceSample) => sample.rangeResidentBytes;
  const peerMemoryValue = (sample: PerformanceSample) => sample.peers[0]?.residentBytes ?? 0;
  const cpuValue = (sample: PerformanceSample) => sample.rangeCpuPercent;
  const peerCpuValue = (sample: PerformanceSample) => sample.peers[0]?.cpuPercent ?? 0;

  function draw(context: CanvasRenderingContext2D, width: number, height: number, now: number) {
    context.clearRect(0, 0, width, height);
    const padding = { top: 24, right: 18, bottom: 24, left: 18 };
    const plotWidth = width - padding.left - padding.right;
    const plotHeight = height - padding.top - padding.bottom;
    if (samples.length !== lastSampleCount) {
      lastSampleCount = samples.length;
      lastSampleArrival = now;
    }
    const latestElapsed = samples.at(-1)?.elapsedMilliseconds ?? 0;
    const displayElapsed = latestElapsed + Math.min(250, now - lastSampleArrival);
    const earliest = Math.max(0, displayElapsed - visibleWindowMilliseconds);
    const visible = samples.filter((sample) => sample.elapsedMilliseconds >= earliest);
    const rangeValue = metric === "memory" ? memoryValue : cpuValue;
    const peerValue = metric === "memory" ? peerMemoryValue : peerCpuValue;
    const floor = metric === "memory" ? 64 * 1024 * 1024 : 100;
    const maximum = Math.max(floor, ...visible.flatMap((sample) => [rangeValue(sample), peerValue(sample)])) * 1.12;
    scaleLabel = metric === "memory"
      ? `${Math.ceil(maximum / (1024 * 1024))} MB`
      : `${Math.ceil(maximum)}%`;

    context.lineWidth = 1;
    context.strokeStyle = "oklch(0.34 0.02 255 / 0.55)";
    for (let index = 0; index <= 6; index += 1) {
      const x = padding.left + (plotWidth * index) / 6;
      context.beginPath();
      context.moveTo(x, padding.top);
      context.lineTo(x, height - padding.bottom);
      context.stroke();
    }
    for (let index = 0; index <= 4; index += 1) {
      const y = padding.top + (plotHeight * index) / 4;
      context.beginPath();
      context.moveTo(padding.left, y);
      context.lineTo(width - padding.right, y);
      context.stroke();
    }

    const plot = (color: string, value: (sample: PerformanceSample) => number) => {
      if (visible.length < 2) return;
      context.beginPath();
      visible.forEach((sample, index) => {
        const x = padding.left + ((sample.elapsedMilliseconds - earliest) / visibleWindowMilliseconds) * plotWidth;
        const y = height - padding.bottom - (value(sample) / maximum) * plotHeight;
        if (index === 0) context.moveTo(x, y);
        else context.lineTo(x, y);
      });
      context.strokeStyle = color;
      context.lineWidth = 2;
      context.lineJoin = "round";
      context.shadowColor = color;
      context.shadowBlur = 9;
      context.stroke();
      context.shadowBlur = 0;
    };

    plot("oklch(0.78 0.2 286)", rangeValue);
    plot("oklch(0.78 0.17 72)", peerValue);
  }

  onMount(() => {
    const context = canvas.getContext("2d");
    if (!context) return;
    let frame = 0;
    const resize = () => {
      const density = Math.min(window.devicePixelRatio || 1, 2);
      const bounds = canvas.getBoundingClientRect();
      canvas.width = Math.max(1, Math.round(bounds.width * density));
      canvas.height = Math.max(1, Math.round(bounds.height * density));
      context.setTransform(density, 0, 0, density, 0, 0);
    };
    const render = (now: number) => {
      draw(context, canvas.clientWidth, canvas.clientHeight, now);
      frame = requestAnimationFrame(render);
    };
    const observer = new ResizeObserver(resize);
    observer.observe(canvas);
    resize();
    frame = requestAnimationFrame(render);
    return () => {
      cancelAnimationFrame(frame);
      observer.disconnect();
    };
  });
</script>

<div class="scopeFrame">
  <canvas bind:this={canvas} aria-label={`Live Range compiler ${metric} trace`}></canvas>
  <span class="scaleTop">{scaleLabel}</span>
  <span class="scaleBottom">0</span>
</div>

<style>
  .scopeFrame {
    position: relative;
    min-height: 380px;
    overflow: hidden;
    border: 1px solid oklch(0.34 0.025 255);
    border-radius: 14px;
    background:
      radial-gradient(circle at 50% 60%, oklch(0.2 0.045 286 / 0.45), transparent 62%),
      oklch(0.135 0.018 255);
    box-shadow: inset 0 0 60px oklch(0.06 0.02 255 / 0.7);
  }

  canvas {
    width: 100%;
    height: 380px;
    display: block;
  }

  .scaleTop,
  .scaleBottom {
    position: absolute;
    right: 18px;
    color: oklch(0.7 0.02 255);
    font: 10px var(--font-geist-mono), monospace;
    pointer-events: none;
  }

  .scaleTop { top: 8px; }
  .scaleBottom { bottom: 8px; }

  @media (max-width: 620px) {
    .scopeFrame { min-height: 300px; }
    canvas { height: 300px; }
  }
</style>
