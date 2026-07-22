<script lang="ts">
  import { githubUrl } from "$lib/benchmarks";
  import GithubIcon from "./GithubIcon.svelte";
</script>

<range-site-footer>
  <footer>
    <a class="githubButton" href={githubUrl} target="_blank" rel="noreferrer" aria-label="Open the Range development branch on GitHub"><GithubIcon /><span>GitHub</span></a>
    <div class="footerMeta"><span>Range · native LLVM · O3</span><span>July 2026</span></div>
  </footer>
</range-site-footer>
