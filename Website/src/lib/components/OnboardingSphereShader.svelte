<script lang="ts">
  import type { ComponentProps } from "svelte";
  import SkyShader from "$lib/components/SkyShader.svelte";

  let {
    fullBleed = false,
    orbitDuration = 28,
    ...props
  }: ComponentProps<typeof SkyShader> = $props();
</script>

<SkyShader {fullBleed} {orbitDuration} {...props} />
