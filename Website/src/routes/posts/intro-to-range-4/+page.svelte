<script lang="ts">
  import CodeBlock from "$lib/components/CodeBlock.svelte";
  import EssayPage from "$lib/components/EssayPage.svelte";
  import FibonacciSphereShader from "$lib/components/FibonacciSphereShader.svelte";

  const graphPattern = `construct GraphValue {
    let identity: Identity
    let relationships: RelationshipSet
    let value: Value
}

macro selectGraphValue(): GraphValue { environment in
    return environment.graph.values.filter { value in
        value.relationships.contains(role: @value)
    }
}`;
</script>

{#snippet heroShader()}
  <FibonacciSphereShader
    chalky
    sphereScale={0.5}
    starScale={10}
    skySpheres
  />
{/snippet}

<EssayPage
  title="Intro to Range: The Substrate"
  description="How one graph pattern can represent written syntax, databases, and anything else you need to express."
  category="Introduction"
  date="August 1, 2026"
  {heroShader}
  heroShaderFocusX={100}
  heroShaderFocusY={46}
  heroShaderOffsetX={20}
  heroShaderOpacity={1}
>
  <section>
    <h2>The graph scales</h2>

    <p>
      A graph pattern is useful precisely because it does not belong to one
      level of the system. The same shape can describe a written program, the
      declarations and relationships the compiler derives from it, or the
      rows and links that make up a database.
    </p>

    <p>
      Identities name the things that matter. Relationships say how they are
      connected. Values carry the information that gives those connections
      shape. Once those three pieces are available, the pattern can scale up
      or down without introducing a separate ontology for every new surface.
    </p>
  </section>

  <section>
    <h2>One pattern, many levels</h2>

    <CodeBlock
      source={graphPattern}
      syntax="range"
      label="A graph value at another level"
    />

    <p>
      The graph can represent source order, syntax ownership, compiler
      capabilities, database records, or a relationship between any other
      values a program needs to express. The surface changes, but the model
      stays inspectable: identities, relationships, and typed values.
    </p>

    <p>
      This is not a claim that every domain should be flattened into one
      undifferentiated table. It is a claim that the same small set of
      operations—name, relate, select, and preserve provenance—can be reused
      across domains without losing the distinctions that make each domain
      meaningful.
    </p>
  </section>

  <section>
    <h2>One substrate, several lenses</h2>

    <p>
      The graph gives the language a uniform substrate. Everything that needs
      to be expressed can be given an identity, related to other values, and
      inspected without first being translated into a special representation
      for its particular level.
    </p>

    <p>
      We navigate that substrate through lenses. Start with identity, then
      look at the value it carries. From there the language can view
      enumerations as alternatives, constructs as composed structure, and
      macros as graph-backed operations that author more structure:
      <code>identity → value → enumerations → constructs → macros</code>.
    </p>

    <p>
      These are not separate worlds stacked beside one another. They are
      different useful views of the same graph. A compiler phase can change
      its lens while keeping the underlying identity and relationships, which
      is what makes the progression uniform instead of a chain of one-off
      translations.
    </p>
  </section>

  <section>
    <h2>Macros can reach the result</h2>

    <p>
      When macros operate on a graph-backed compiler, they can modify the
      final result through the same values and relationships that describe the
      program. They do not need to invent a new intermediate representation
      just to express a transformation. The graph is already the intermediate
      representation: the macro queries it, adds the structure it needs, and
      leaves the compiler with a result whose provenance remains visible.
    </p>

    <p>
      Macros are the extension mechanism: the place where the language can
      author new graph-backed structure without asking the compiler to grow a
      bespoke concept for every new form. The substrate stays uniform while
      the macro supplies the domain-specific meaning.
    </p>

    <p>
      That is the larger promise of the pattern. A database, written syntax,
      a compiler graph, and generated structure can all remain different
      things while sharing one way to express identity, relationship, and
      value. Range gets leverage from that reuse: new forms add meaning to the
      graph instead of forcing the compiler to grow a new hidden world beside
      it.
    </p>
  </section>
</EssayPage>
