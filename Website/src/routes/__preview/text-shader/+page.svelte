<script lang="ts">
  type ShadowSettings = {
    label: string;
    color: string;
    angle: number;
    distance: number;
    blur: number;
    spread: number;
    opacity: number;
  };

  let sample = $state("Range");
  let baseColor = $state("#aaacb0");
  let outer90 = $state<ShadowSettings>({
    label: "Outer · 90°",
    color: "#111318",
    angle: 90,
    distance: 40,
    blur: 0,
    spread: 0,
    opacity: 70,
  });
  let outer270 = $state<ShadowSettings>({
    label: "Outer · 270°",
    color: "#17191e",
    angle: 270,
    distance: 40,
    blur: 0,
    spread: 0,
    opacity: 50,
  });
  let inner90 = $state<ShadowSettings>({
    label: "Inner · 90°",
    color: "#ffffff",
    angle: 90,
    distance: 40,
    blur: 0,
    spread: 0,
    opacity: 85,
  });
  let inner270 = $state<ShadowSettings>({
    label: "Inner · 270°",
    color: "#ffffff",
    angle: 270,
    distance: 40,
    blur: 0,
    spread: 0,
    opacity: 85,
  });

  const displayText = $derived(sample.trim() || "Range");

  function offset(angle: number, distance: number, inner = false) {
    const radians = (angle * Math.PI) / 180;
    const direction = inner ? -1 : 1;
    return {
      x: Math.cos(radians) * distance * direction,
      y: Math.sin(radians) * distance * direction,
    };
  }
</script>

<svelte:head>
  <title>Text shader — Range preview</title>
  <meta
    name="description"
    content="An interactive embossed text material study for Range."
  />
  <meta name="robots" content="noindex, nofollow" />
</svelte:head>

<main class="shaderPage">
  <div class="grain" aria-hidden="true"></div>

  <header>
    <span class="eyebrow">Range material study</span>
    <span class="directions" aria-label="Light directions: 90 and 270 degrees">
      90° <i></i> 270°
    </span>
  </header>

  <section class="stage" aria-live="polite">
    <svg class="shader" viewBox="0 0 1400 560" role="img" aria-label={displayText}>
      <defs>
        <filter
          id="range-text-material"
          x="-18%"
          y="-30%"
          width="136%"
          height="160%"
          color-interpolation-filters="sRGB"
        >
          <feMorphology in="SourceAlpha" operator="dilate" radius={outer90.spread} result="outer-90-spread" />
          <feGaussianBlur in="outer-90-spread" stdDeviation={outer90.blur} result="outer-90-soft" />
          <feOffset
            in="outer-90-soft"
            dx={offset(outer90.angle, outer90.distance).x}
            dy={offset(outer90.angle, outer90.distance).y}
            result="outer-90-offset"
          />
          <feFlood flood-color={outer90.color} flood-opacity={outer90.opacity / 100} result="outer-90-color" />
          <feComposite
            in="outer-90-color"
            in2="outer-90-offset"
            operator="in"
            result="outer-90-shadow"
          />

          <feMorphology in="SourceAlpha" operator="dilate" radius={outer270.spread} result="outer-270-spread" />
          <feGaussianBlur in="outer-270-spread" stdDeviation={outer270.blur} result="outer-270-soft" />
          <feOffset
            in="outer-270-soft"
            dx={offset(outer270.angle, outer270.distance).x}
            dy={offset(outer270.angle, outer270.distance).y}
            result="outer-270-offset"
          />
          <feFlood flood-color={outer270.color} flood-opacity={outer270.opacity / 100} result="outer-270-color" />
          <feComposite
            in="outer-270-color"
            in2="outer-270-offset"
            operator="in"
            result="outer-270-shadow"
          />

          <feMorphology in="SourceAlpha" operator="erode" radius={inner90.spread} result="inner-90-spread" />
          <feGaussianBlur in="inner-90-spread" stdDeviation={inner90.blur} result="inner-90-soft" />
          <feOffset
            in="inner-90-soft"
            dx={offset(inner90.angle, inner90.distance, true).x}
            dy={offset(inner90.angle, inner90.distance, true).y}
            result="inner-90-offset"
          />
          <feComposite
            in="SourceAlpha"
            in2="inner-90-offset"
            operator="out"
            result="inner-90-mask"
          />
          <feFlood flood-color={inner90.color} flood-opacity={inner90.opacity / 100} result="inner-90-color" />
          <feComposite
            in="inner-90-color"
            in2="inner-90-mask"
            operator="in"
            result="inner-90-shadow"
          />

          <feMorphology in="SourceAlpha" operator="erode" radius={inner270.spread} result="inner-270-spread" />
          <feGaussianBlur in="inner-270-spread" stdDeviation={inner270.blur} result="inner-270-soft" />
          <feOffset
            in="inner-270-soft"
            dx={offset(inner270.angle, inner270.distance, true).x}
            dy={offset(inner270.angle, inner270.distance, true).y}
            result="inner-270-offset"
          />
          <feComposite
            in="SourceAlpha"
            in2="inner-270-offset"
            operator="out"
            result="inner-270-mask"
          />
          <feFlood flood-color={inner270.color} flood-opacity={inner270.opacity / 100} result="inner-270-color" />
          <feComposite
            in="inner-270-color"
            in2="inner-270-mask"
            operator="in"
            result="inner-270-shadow"
          />

          <feMerge>
            <feMergeNode in="outer-270-shadow" />
            <feMergeNode in="outer-90-shadow" />
            <feMergeNode in="SourceGraphic" />
            <feMergeNode in="inner-270-shadow" />
            <feMergeNode in="inner-90-shadow" />
          </feMerge>
        </filter>
      </defs>

      <text
        class="shaderText"
        x="700"
        y="306"
        text-anchor="middle"
        dominant-baseline="middle"
        fill={baseColor}
        textLength={Math.min(1120, Math.max(420, displayText.length * 178))}
        lengthAdjust="spacingAndGlyphs"
      >{displayText}</text>
    </svg>
  </section>

  <form onsubmit={(event) => event.preventDefault()}>
    <div class="textControl">
      <label class="controlLabel" for="shader-copy">Text</label>
      <div class="field">
      <input
        class="textInput"
        id="shader-copy"
        bind:value={sample}
        maxlength="12"
        autocomplete="off"
        spellcheck="false"
        aria-describedby="character-count"
      />
      <span id="character-count">{sample.length}/12</span>
      </div>
    </div>

    <div class="materialHeader">
      <span>Material controls</span>
      <label class="baseControl">
        <input type="color" bind:value={baseColor} aria-label="Base glyph color" />
        <span>Base</span>
        <code>{baseColor}</code>
      </label>
    </div>

    <div class="shadowControls">
      {#each [inner90, outer90, inner270, outer270] as shadow}
        <fieldset class="shadowControl">
          <legend>
            <input type="color" bind:value={shadow.color} aria-label={`${shadow.label} color`} />
            <span>{shadow.label}</span>
            <code>{shadow.color}</code>
          </legend>

          <label class="rangeControl">
            <span>Rotation</span>
            <output>{shadow.angle}°</output>
            <input type="range" min="0" max="360" step="1" bind:value={shadow.angle} />
          </label>
          <label class="rangeControl">
            <span>Distance</span>
            <output>{shadow.distance}px</output>
            <input type="range" min="0" max="40" step="1" bind:value={shadow.distance} />
          </label>
          <label class="rangeControl">
            <span>Blur</span>
            <output>{shadow.blur}px</output>
            <input type="range" min="0" max="36" step="0.5" bind:value={shadow.blur} />
          </label>
          <label class="rangeControl">
            <span>Spread</span>
            <output>{shadow.spread}px</output>
            <input type="range" min="0" max="12" step="0.5" bind:value={shadow.spread} />
          </label>
          <label class="rangeControl">
            <span>Intensity</span>
            <output>{shadow.opacity}%</output>
            <input type="range" min="0" max="100" step="1" bind:value={shadow.opacity} />
          </label>
        </fieldset>
      {/each}
    </div>
  </form>
</main>

<style>
  :global(html) {
    background: #ffffff;
  }

  :global(body) {
    overflow: hidden;
    background: #ffffff;
  }

  .shaderPage {
    position: relative;
    isolation: isolate;
    width: 100%;
    min-height: 100svh;
    margin: 0;
    padding: clamp(22px, 3vw, 42px);
    display: grid;
    grid-template-rows: auto 1fr auto;
    overflow: hidden;
    color: #292b30;
    background: #ffffff;
  }

  .shaderPage::before {
    position: absolute;
    z-index: -1;
    inset: 0;
    box-shadow: inset 0 0 14vw rgba(34, 36, 42, 0.025);
    content: "";
    pointer-events: none;
  }

  .grain {
    position: absolute;
    z-index: -1;
    inset: 0;
    opacity: 0.19;
    pointer-events: none;
    background-image: url("data:image/svg+xml,%3Csvg viewBox='0 0 180 180' xmlns='http://www.w3.org/2000/svg'%3E%3Cfilter id='n'%3E%3CfeTurbulence type='fractalNoise' baseFrequency='.82' numOctaves='3' stitchTiles='stitch'/%3E%3C/filter%3E%3Crect width='100%25' height='100%25' filter='url(%23n)' opacity='.18'/%3E%3C/svg%3E");
    mix-blend-mode: soft-light;
  }

  header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 24px;
    font-family: var(--font-geist-mono), monospace;
    font-size: 10px;
    letter-spacing: 0.12em;
    line-height: 1;
    text-transform: uppercase;
  }

  .eyebrow {
    color: rgba(30, 32, 37, 0.62);
  }

  .directions {
    display: flex;
    align-items: center;
    gap: 10px;
    color: rgba(30, 32, 37, 0.44);
  }

  .directions i {
    width: 28px;
    height: 1px;
    display: block;
    background: currentColor;
  }

  .stage {
    min-height: 0;
    display: grid;
    place-items: center;
  }

  .shader {
    width: min(94vw, 1220px);
    max-height: 44vh;
    overflow: visible;
  }

  .shaderText {
    filter: url(#range-text-material);
    font-family: var(--font-range-sans), sans-serif;
    font-size: 256px;
    font-weight: 680;
    letter-spacing: -0.075em;
  }

  form {
    width: min(1120px, 100%);
    margin: 0 auto;
    display: grid;
    gap: 12px;
  }

  .controlLabel,
  .materialHeader > span {
    display: block;
    margin: 0 0 9px 2px;
    color: rgba(30, 32, 37, 0.52);
    font-family: var(--font-geist-mono), monospace;
    font-size: 10px;
    letter-spacing: 0.11em;
    line-height: 1;
    text-transform: uppercase;
  }

  fieldset {
    min-width: 0;
    margin: 0;
    padding: 0;
    border: 0;
  }

  .textControl {
    width: min(460px, 100%);
  }

  .field {
    height: 52px;
    display: flex;
    align-items: center;
    gap: 12px;
    padding: 0 16px;
    border: 1px solid rgba(255, 255, 255, 0.66);
    border-radius: 14px;
    background: rgba(220, 221, 223, 0.7);
    box-shadow:
      0 8px 28px rgba(37, 39, 44, 0.07),
      inset 0 1px 1px rgba(255, 255, 255, 0.82),
      inset 0 -1px 1px rgba(37, 39, 44, 0.1);
    backdrop-filter: blur(16px);
  }

  .textInput {
    min-width: 0;
    flex: 1;
    padding: 0;
    border: 0;
    outline: 0;
    color: #292b30;
    background: transparent;
    font: 500 16px/1 var(--font-range-sans), sans-serif;
    letter-spacing: -0.02em;
  }

  .materialHeader {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 20px;
  }

  .materialHeader > span {
    margin: 0 0 0 2px;
  }

  .baseControl {
    display: flex;
    align-items: center;
    gap: 7px;
    color: rgba(30, 32, 37, 0.6);
    font-size: 10px;
    cursor: pointer;
  }

  .baseControl code,
  .shadowControl code {
    color: rgba(30, 32, 37, 0.38);
    font-family: var(--font-geist-mono), monospace;
    font-size: 9px;
    text-transform: uppercase;
  }

  input[type="color"] {
    width: 24px;
    height: 24px;
    flex: 0 0 24px;
    padding: 0;
    border: 0;
    border-radius: 7px;
    outline: 0;
    overflow: hidden;
    background: transparent;
    cursor: pointer;
  }

  input[type="color"]::-webkit-color-swatch-wrapper {
    padding: 0;
  }

  input[type="color"]::-webkit-color-swatch {
    border: 1px solid rgba(30, 32, 37, 0.13);
    border-radius: 6px;
  }

  .shadowControls {
    display: grid;
    grid-template-columns: repeat(4, minmax(0, 1fr));
    gap: 8px;
  }

  .shadowControl {
    padding: 12px;
    border: 1px solid rgba(30, 32, 37, 0.08);
    border-radius: 14px;
    background: rgba(238, 238, 239, 0.78);
    box-shadow:
      0 8px 24px rgba(37, 39, 44, 0.035),
      inset 0 1px 1px rgba(255, 255, 255, 0.9);
  }

  .shadowControl legend {
    width: 100%;
    margin: 0 0 9px;
    padding: 0;
    display: flex;
    align-items: center;
    gap: 7px;
    color: rgba(30, 32, 37, 0.7);
    font-size: 10px;
    font-weight: 570;
  }

  .shadowControl legend span {
    min-width: 0;
    flex: 1;
  }

  .rangeControl {
    display: grid;
    grid-template-columns: 1fr auto;
    align-items: center;
    gap: 3px 8px;
    padding: 3px 0;
    color: rgba(30, 32, 37, 0.55);
    font-family: var(--font-geist-mono), monospace;
    font-size: 9px;
    line-height: 1;
  }

  .rangeControl output {
    min-width: 34px;
    color: rgba(30, 32, 37, 0.72);
    text-align: right;
  }

  .rangeControl input[type="range"] {
    width: 100%;
    height: 14px;
    grid-column: 1 / -1;
    margin: 0;
    accent-color: #34363b;
    cursor: ew-resize;
  }

  .field:focus-within {
    border-color: rgba(255, 255, 255, 0.94);
    box-shadow:
      0 10px 34px rgba(37, 39, 44, 0.09),
      0 0 0 3px rgba(255, 255, 255, 0.22),
      inset 0 1px 1px white,
      inset 0 -1px 1px rgba(37, 39, 44, 0.11);
  }

  #character-count {
    color: rgba(30, 32, 37, 0.36);
    font-family: var(--font-geist-mono), monospace;
    font-size: 10px;
  }

  @media (max-width: 640px) {
    :global(body) {
      overflow: auto;
    }

    .shaderPage {
      padding: 20px 16px 24px;
      overflow: visible;
    }

    .shader {
      width: 108vw;
      max-width: none;
    }

    .shaderText {
      font-size: 224px;
    }

    .shadowControls {
      grid-template-columns: repeat(2, minmax(0, 1fr));
    }
  }

  @media (max-width: 420px) {
    .shadowControls {
      grid-template-columns: 1fr;
    }
  }

  @media (prefers-reduced-motion: no-preference) {
    .shaderText {
      animation: settle 900ms cubic-bezier(0.16, 1, 0.3, 1) both;
    }

    @keyframes settle {
      from {
        opacity: 0;
        transform: translateY(10px);
      }
    }
  }
</style>
