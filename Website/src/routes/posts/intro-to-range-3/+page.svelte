<script lang="ts">
  import CodeBlock from "$lib/components/CodeBlock.svelte";
  import EssayPage from "$lib/components/EssayPage.svelte";
  import FibonacciSphereShader from "$lib/components/FibonacciSphereShader.svelte";

  const macroShape = `macro value(): Member -> RelationshipRegistration { environment in
    return scalarValueRelationship()
}

@value
macro codable(): Construct { environment in
    #environment {
        extension #environment.target.Declaration.identifier {
            function encode() { ... }
        }
    }
}`;
</script>

{#snippet heroShader()}
  <FibonacciSphereShader chalky />
{/snippet}

<EssayPage
  title="Intro to Range: The Meta"
  description="How Range macros operate on the identity-bearing graph to make reusable program structure."
  category="Introduction"
  date="August 1, 2026"
  {heroShader}
  heroShaderOpacity={1}
>
  <section>
    <h2>The macros</h2>

    <p>
      A macro is not a second language standing beside the program. It is a
      value in the same graph, with an identity, relationships, and a body
      that can be inspected before the program is lowered.
    </p>

    <p>
      The macro reads the relationships that matter, selects the values it
      needs, and describes the structure that should exist next. Its output is
      not magic text emitted from outside the language; it is a graph-backed
      result with the same provenance as the source it extends.
    </p>
  </section>

  <section>
    <h2>Code can describe code</h2>

    <CodeBlock source={macroShape} syntax="range" label="A macro as a value" />

    <p>
      Because macro operations use the same identity-bearing graph, a macro
      can remain close to the program it transforms without duplicating the
      compiler’s model of that program. It can query declarations, follow
      relationships, and expand a concrete body while preserving the facts
      that explain where each generated value came from.
    </p>

    <p>
      This is the next step after identity, value, and relationship: a value
      can now participate in the act of making more structure. The compiler
      does not need a private representation for every kind of synthesis. The
      macro uses the graph that the language already has.
    </p>
  </section>
</EssayPage>
