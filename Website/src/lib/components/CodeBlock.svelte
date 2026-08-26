<script lang="ts">
  import RangeCode from "./RangeCode.svelte";

  let { source, syntax, label }: { source: string; syntax: string; label: string } = $props();
</script>

<range-code-block>
  <section class="codeBlock" aria-label={label}>
    <header>{label}</header>
    <div class="codeBlockBody">
      <RangeCode {source} {syntax} />
    </div>
  </section>
</range-code-block>

<style>
  range-code-block {
    display: block;
  }

  .codeBlock {
    min-width: 0;
    overflow: hidden;
    border: 1px solid var(--line);
    border-radius: 10px;
    background: oklch(0.97 0.006 255);
  }

  .codeBlock > header {
    padding: 8px 11px;
    border-bottom: 1px solid var(--line);
    color: var(--muted);
    font-family: var(--font-geist-mono), monospace;
    font-size: 10px;
  }

  .codeBlockBody {
    max-height: 430px;
    overflow: auto;
  }

  .codeBlockBody :global(.rangeSource) {
    padding: 18px 20px 20px;
    font-size: 13px;
    line-height: 1.68;
    tab-size: 4;
  }
</style>
