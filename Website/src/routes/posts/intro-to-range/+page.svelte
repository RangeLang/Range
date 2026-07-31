<script lang="ts">
  import CodeBlock from "$lib/components/CodeBlock.svelte";
  import EssayPage from "$lib/components/EssayPage.svelte";
  import ThreeFourRhythm from "$lib/components/ThreeFourRhythm.svelte";

  const bindingIntents = `construct Counter {
    let seed: Int           // immutable  · owned storage
    state count: Int        // mutable    · owned storage
    binding source: Int     // read/write · projected access

    derived total: Int {    // read-only  · computed access
        self.seed + self.count
    }
}`;

  const abstractionForms = `macro component(): Construct -> Void {}

@component
construct Point {
    let x: Int
    let y: Int
}

enum Axis {
    case horizontal
    case vertical
}`;
</script>

<EssayPage
  title="Intro to Range"
  description="The smallest pieces of Range: identity and value, binding intents, and the three abstraction forms."
  category="Introduction"
  date="July 30, 2026"
>
  <section>
    <ThreeFourRhythm>
      {#snippet identityIntro()}
        <p>
          In Range, <span class="accentTerm">identity</span> and
          <span class="accentTerm">value</span> form the smallest semantic unit
          tracked independently through the program graph.
        </p>
      {/snippet}

      {#snippet identityDetail()}
        <p>
          A value can contain smaller structure, but Range does not detach that
          structure into separately tracked meaning below this pair. Lowering
          may change its representation; identity and value move through those
          changes together.
        </p>
      {/snippet}

      {#snippet bindingIntro()}
        <p>
          Range names each storage and access relationship directly. Before we
          read a body, the declaration tells us whether a value is immutable,
          mutable, computed, or projected:
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

      {#snippet abstractionIntro()}
        <p>
          From that foundation, Range keeps its abstraction vocabulary small.
          Constructs describe composed values, enums describe alternatives,
          and macros describe transformations. Together they cover the
          fundamental ways a program introduces shape without adding a new
          category for every higher-level idea. The fewer kinds of abstraction
          we must cross, the more each one behaves like a building block.
        </p>
      {/snippet}

      {#snippet abstractionCode()}
        <CodeBlock
          source={abstractionForms}
          syntax="range"
          label="Three abstraction forms"
        />
      {/snippet}
    </ThreeFourRhythm>
  </section>
</EssayPage>

<style>
  .accentTerm {
    color: var(--range);
  }
</style>
