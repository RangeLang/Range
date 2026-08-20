<script lang="ts">
  import { outlinePath, shapeOutline } from "$lib/design-knots";

  let {
    corners,
    toCorners = 0,
    progress = 0,
    size = 96,
    samples = 96,
  }: {
    corners: number;
    /** The shape this glyph collapses toward. Defaults to the circle. */
    toCorners?: number;
    progress?: number;
    size?: number;
    samples?: number;
  } = $props();

  const radius = 0.78;
  let from = $derived(shapeOutline(corners, samples, radius));
  let to = $derived(shapeOutline(toCorners, samples, radius));
  let path = $derived(outlinePath(from, to, progress, size / 2));
  let vertices = $derived(
    corners < 3
      ? []
      : Array.from({ length: corners }, (_, index) => {
          const sample = Math.round((index / corners) * samples) % samples;
          const start = from[sample];
          const end = to[sample];
          return {
            x: (start.x + (end.x - start.x) * progress) * (size / 2),
            y: (start.y + (end.y - start.y) * progress) * (size / 2),
          };
        }),
  );
</script>

<svg
  class="knotGlyph"
  width={size}
  height={size}
  viewBox={`${-size / 2} ${-size / 2} ${size} ${size}`}
  aria-hidden="true"
>
  <path class="knotOutline" d={path} />
  {#each vertices as vertex, index}
    <circle
      class="knotVertex"
      cx={vertex.x}
      cy={vertex.y}
      r={2.6}
      style={`--vertex-fade: ${index === 0 ? 1 : 1 - progress}`}
    />
  {/each}
  {#if corners < 3 || (toCorners < 3 && progress > 0.9)}
    <circle class="knotCore" cx="0" cy="0" r={2.2 + progress * 1.4} />
  {/if}
</svg>

<style>
  .knotGlyph {
    display: block;
    overflow: visible;
  }

  .knotOutline {
    fill: color-mix(in oklch, var(--range), transparent 94%);
    stroke: color-mix(in oklch, var(--range), transparent 42%);
    stroke-width: 1.25;
    stroke-linejoin: round;
  }

  .knotVertex {
    fill: var(--range);
    opacity: calc(0.25 + var(--vertex-fade, 1) * 0.75);
  }

  .knotCore {
    fill: var(--range);
  }
</style>
