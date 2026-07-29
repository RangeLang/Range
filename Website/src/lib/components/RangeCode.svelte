<script lang="ts">
  import { escapeHtml, highlightRange } from "$lib/benchmarks";

  let {
    source,
    syntax = "range",
    label,
  }: {
    source: string;
    syntax?: string;
    label?: string;
  } = $props();

  let renderedSource = $derived(
    syntax === "range"
      ? highlightRange(source.trimEnd())
      : escapeHtml(source.trimEnd()),
  );
</script>

<pre
  class={`rangeSource language-${syntax}`}
  aria-label={label}
><code>{@html renderedSource}</code></pre>

