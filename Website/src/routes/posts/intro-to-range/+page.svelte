<script lang="ts">
  import CodeBlock from "$lib/components/CodeBlock.svelte";
  import EssayPage from "$lib/components/EssayPage.svelte";
  import SkyShader from "$lib/components/SkyShader.svelte";
  import MacroWordCloud from "$lib/components/MacroWordCloud.svelte";
  import ThreeFourRhythm from "$lib/components/ThreeFourRhythm.svelte";

  const bindingIntents = `construct Counter {
    let seed: Int           // immutable  · owned storage
    state count: Int        // mutable    · owned storage
    binding source: Int     // read/write · projected access

    derived total: Int {    // read-only  · computed access
        self.seed + self.count
    }
}`;

  const substrateForms = `construct Point {
    let x: Int
    let y: Int
}

enum Direction {
    case north
    case east
    case south
    case west
}

function clamp(value: Int, min: Int, max: Int): Int {
    if value < min { return min }
    if value > max { return max }
    return value
}`;
</script>

{#snippet heroShader()}
  <SkyShader />
{/snippet}

<EssayPage
  title="Intro to Range"
  description="The basic building blocks of the graph"
  category="Introduction"
  date="July 30, 2026"
  {heroShader}
  heroShaderOpacity={1}
  heroShaderFade={false}
  heroAlignment="center"
  heroTone="inverse"
  heroVariant="saturated-p3"
>
  <section>
    <ThreeFourRhythm>
      {#snippet identityIntro()}
        <p>
          Range begins with one base concept:
          <span class="accentTerm">Identity : Value</span>. It is the smallest
          unit of meaning in the graph. Nothing smaller is tracked.
        </p>
      {/snippet}

      {#snippet identityDetail()}
        <p>
          Lowering can represent the two sides of
          <span class="accentTerm">Identity : Value</span> separately, and that
          separation is where full control over the architecture comes from.
          But the meaning never splits.
        </p>
        <blockquote class="identityQuote">
          Without identity there is only
          <span class="accentTerm">value</span> |
          <span class="accentTerm">no value</span> |
          <span class="accentTerm">many values</span><span class="accentTerm">—</span>never
          <em>this</em> value.
        </blockquote>
      {/snippet}

      {#snippet bindingIntro()}
        <p>
          Range names each storage and access relationship directly. Before we
          read a body, the declaration tells us whether a value is immutable,
          mutable, projected, or computed:
        </p>
      {/snippet}

      {#snippet bindingCode()}
        <CodeBlock
          source={bindingIntents}
          syntax="range"
          label="Binding access"
        />
      {/snippet}

      {#snippet bindingDetail()}
        <p>
          Many languages make a coarse type-level choice—class or
          struct—before individual properties are considered. Range moves that
          choice onto each property’s storage and access relationship, making
          the resulting representation more composable.
        </p>
      {/snippet}

      {#snippet functionIntro()}
        <p>
          Range keeps its concrete substrate small.
          <span class="accentTerm">Construct</span> describes composed values,
          <span class="accentTerm">Enum</span> describes alternatives, and
          <span class="accentTerm">Function</span> describes the logic between
          them. Together they account for shape, choice, and behavior without
          introducing a new kind for every pattern.
        </p>
      {/snippet}

      {#snippet functionCode()}
        <CodeBlock
          source={substrateForms}
          syntax="range"
          label="Three concrete substrate forms"
        />
      {/snippet}
    </ThreeFourRhythm>

    <div class="macroPrelude">
      <p>
        Those forms describe the source itself: its shape, alternatives, and
        behavior. This is where the concrete vocabulary ends.
        <span class="accentTerm">Macros</span> begin one layer above, receiving
        source structure as input and returning a transformed execution graph.
      </p>
    </div>
    <MacroWordCloud />
  </section>
</EssayPage>

<style>
  .accentTerm {
    color: var(--range);
  }

  .macroPrelude {
    margin: 56px 0 32px;
  }

  .identityQuote {
    margin: 24px 0;
    padding-left: 18px;
    border-left: 2px solid var(--range);
    color: color-mix(in oklch, var(--ink), transparent 14%);
  }
</style>
