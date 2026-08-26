<script lang="ts">
  import EssayPage from "$lib/components/EssayPage.svelte";
  import SphereLineShader from "$lib/components/SphereLineShader.svelte";
</script>

{#snippet heroShader()}
  <SphereLineShader palette={4} offsetX={0.3} />
{/snippet}

<EssayPage
  title="One Source, Two Lenses"
  description="In Range, written source and intended meaning share one typed graph."
  category="Observation"
  date="July 30, 2026"
  {heroShader}
  heroShaderFocusX={98}
>
  <section>
    <h2>No language is ever done</h2>
    <p>
      No programming language is ever finished. C is more than fifty years
      old, has reached
      <abbr
        class="standardTerm"
        title="C23 is the 2024 international standard for C, formally ISO/IEC 9899:2024."
      >C23</abbr> in 2024, and keeps going. Its longevity makes the point more
      clearly: even a foundational language does not close the field.
    </p>

    <p>
      Language design is not a sequence that ends in one correct language.
      Every new language begins with some pressure that existing languages did
      not make central. Its philosophies, theories, and experiments give that
      pressure a concrete form.
    </p>

    <p>
      A new language can therefore do more than answer a requirement. It can
      create one. Once an experiment makes a concept coherent, later languages
      are judged by an expectation that did not previously exist.
    </p>
  </section>

  <section>
    <h2>Requirements emerge</h2>
    <p>
      Requirements do not arrive fully formed. A concept appears, a language
      gives it rules, and programmers discover what becomes possible when
      those rules are taken seriously. The experiment solidifies into a
      requirement only after people can feel its absence elsewhere.
    </p>

    <p>
      But a language rarely answers a new requirement with a blank page. It
      appends. A keyword here, a modifier there, a special case to hold it
      together. C—a language praised for fitting in your head—went from
      thirty-two keywords to sixty. Swift is barely a decade old and is
      already somewhere past a hundred: <code>nonisolated</code>,
      <code>borrowing</code>, <code>consuming</code>, <code>rethrows</code>,
      <code>indirect</code>, <code>convenience</code>, and the count depends
      on who is counting, which is itself the tell. Nobody can say the exact
      number of words in the language they write every day.
    </p>

    <p>
      None of these was a mistake. But they all live in the same place: your
      head. Attention doesn’t get a version bump. And the real pain isn’t
      remembering the words—it’s that you know exactly what you want to
      declare, plainly, and the language makes you say it in its accumulated
      vocabulary instead. The intuitive spelling is never the legal one; the
      standard already spent it on something else.
    </p>

    <p>
      Range is, before anything else, a subtractive language. It began from
      that observation and has kept it through every host it has lived
      in—each implementation a different body, the same philosophy. What
      survives the moves is not syntax; it is the refusal to answer pressure
      by appending.
    </p>
  </section>

  <section>
    <h2>One source, two shapes</h2>
    <p>
      Subtraction is not only about keywords. Range proposes such a
      requirement: a program should not have to collapse its meaning into one
      representation too early.
    </p>

    <p>
      Earlier metaprogramming systems point toward this split. C preprocessor
      macros let us see written source as tokens that can become different
      instructions. Lisp macros let us see code as data and transform it in
      the language itself. Both ask us to look at one program through two
      lenses—what was written and what it is intended to become—but the
      connection is often messy. Expansion is not governed by one typed
      semantic model, so the two views are difficult to inspect together.
    </p>

    <p>
      Range asks whether those views can share one substrate. As with
      subtracting keywords, the fewer separate abstractions we must cross, the
      more a language behaves like a building material rather than a catalogue
      of special instructions. A program can be like a sheet of paper folded
      into many forms. The fold gives the paper a shape without replacing the
      paper; representation gives the program a concrete form without erasing
      its meaning.
    </p>

    <p>
      A Range program has a semantic shape and a concrete shape. The semantic
      shape is the program as known by the graph: identities, relationships,
      capabilities, state, bindings, and bodies. The concrete shape is the
      representation a particular consumer eventually needs.
    </p>
  </section>
</EssayPage>

<style>
  .standardTerm {
    color: var(--range);
    font-weight: 650;
    text-decoration: underline dotted;
    text-decoration-thickness: 1px;
    text-underline-offset: 0.16em;
    cursor: help;
  }
</style>
