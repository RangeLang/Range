<script lang="ts">
  import { escapeHtml, highlightRange } from "$lib/benchmarks";

  let { source, syntax, label }: { source: string; syntax: string; label: string } = $props();
  let code = $derived(syntax === "range" ? highlightRange(source.trimEnd()) : escapeHtml(source.trimEnd()));
</script>

<range-code-block>
  <section class="codeBlock" aria-label={label}>
    <header>{label}</header>
    <div class="codeBlockBody">
      <pre class={`language-${syntax}`}><code>{@html code}</code></pre>
    </div>
  </section>
</range-code-block>
