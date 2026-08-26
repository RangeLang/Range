<script lang="ts">
  import { githubUrl } from "$lib/benchmarks";
  import GithubIcon from "./GithubIcon.svelte";
</script>

<range-site-footer>
  <footer>
    <a class="githubButton" href={githubUrl} target="_blank" rel="noreferrer" aria-label="Open the Range repository on GitHub"><GithubIcon /><span>GitHub</span></a>
    <a class="footerMeta" href="/" aria-label="Range homepage">
      <span>Range</span>
      <range-scale
        class="footerScale"
        standalone
        orientation="horizontal"
        rest-position="0.5"
        endpoint-gap="0"
        endpoint-gap-end="0"
        division-base="3"
        division-levels="2"
        mark-length="9"
        mark-thickness="0.45"
        aria-label="Interactive Range scale separator"
      ></range-scale>
      <span>An applied programming language</span>
    </a>
  </footer>
</range-site-footer>

<style>
  .footerMeta {
    display: inline-flex;
    align-items: center;
    gap: 8px;
    line-height: 1;
    color: inherit;
    text-decoration: none;
  }

  .footerMeta > span {
    display: inline-flex;
    height: 20px;
    align-items: center;
  }

  .footerScale {
    width: 72px;
    height: 20px;
    flex: 0 0 72px;
    align-self: center;
    color: currentColor;
    --ink: currentColor;
  }
</style>
