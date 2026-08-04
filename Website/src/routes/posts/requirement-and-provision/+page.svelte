<script lang="ts">
  import CodeBlock from "$lib/components/CodeBlock.svelte";
  import EssayPage from "$lib/components/EssayPage.svelte";

  const environmentSketch = `@shader
construct StarField {
    state cutoutRadius: Int(5)

    function body: Fragment {
        #environment {
            let count: Int(5)
        }
    }
}`;
</script>

<EssayPage
  title="Requirement and Provision: A Modern Split"
  description="One declaration in the environment can be both sides of the split."
  category="Language design"
  date="August 4, 2026"
  {heroShader}
>
  <section>
    <h2>Two words for one act</h2>
    <p>
      A protocol declares a requirement. A static member provides one. Two
      keywords, two mental models, two places in the language — for what is,
      on inspection, a single act: saying that some value must exist, or that
      it does.
    </p>

    <p>
      The split feels fundamental because it describes two different
      relationships: something asks, something answers. But a language does not
      have to embody the asking and the answering in separate machinery. It can
      hold both in one declaration, and let resolution decide which side you
      are looking at.
    </p>
  </section>

  <section>
    <h2>The declaration is the contract</h2>
    <p>
      Range already has the one mechanism that can carry both: a macro that
      emits into the environment. What a macro contributes is not a requirement
      or a provision in advance. It is a declaration. Whether it reads as a
      requirement or as a provision is a property of how the graph resolves it,
      not of how it was written.
    </p>

    <CodeBlock
      source={environmentSketch}
      syntax="range"
      label="A sketch: the macro emits, the graph resolves"
    />

    <p>
      A declaration with a provider is a provision: it resolves. A declaration
      without a provider is a requirement — and it survives only as a
      diagnostic, the error the graph raises when it cannot bind. The asking
      side is not a feature that needs syntax. It is the unresolved state of
      the same contribution.
    </p>
  </section>

  <section>
    <h2>What the split was protecting</h2>
    <p>
      The protocol/static distinction was protecting one useful idea: a
      contract should be visible before it is fulfilled. That visibility does
      not require a separate keyword. It requires that the graph can tell you
      which declarations are still asking, and a macro can check its own
      surface by filtering on the same kind of contribution.
    </p>

    <blockquote>
      Requirement and provision are two consumption states of one environment
      contribution.
    </blockquote>
  </section>
</EssayPage>
