<script lang="ts">
  import CodeBlock from "$lib/components/CodeBlock.svelte";
  import EssayPage from "$lib/components/EssayPage.svelte";

  const environmentBoundary = `macro project(): Construct { environment in
    #environment {
        construct ProjectDefaults {
            // declarations projected into this environment
        }
    }
}`;
</script>

<EssayPage
  title="Somewhere, Sometime, Some-here"
  description="A macro environment is not a bag of helpers. It is a coordinate in the program: a place, a phase, and a deliberately local here."
  category="Metaprogramming"
  date="July 29, 2026"
>
  <section>
    <h2>Environment is a coordinate</h2>
    <p>
      “Environment” can sound like a miscellaneous object passed to a callback:
      a place to collect services, flags, and helper methods. That is useful, but
      it is not the idea here.
    </p>
    <p>
      In Range, a macro environment answers three questions at once. Where in
      the program are we? When is this code running? What does “here” have the
      authority to observe and change?
    </p>

    <CodeBlock source={environmentBoundary} syntax="range" label="A contextual expansion boundary" />
  </section>

  <section>
    <h2>Somewhere</h2>
    <p>
      A macro is attached somewhere: to a project, a construct, a member, or an
      application. Its environment carries that location. Queries such as the
      target, source, ancestors, system defaults, and graph relationships are
      not global reflection. They are views from a particular coordinate.
    </p>
  </section>

  <section>
    <h2>Sometime</h2>
    <p>
      Macro code runs at a different time from the code it produces. It can
      inspect compile-time values, make decisions, and project syntax that will
      participate in later compilation and execution.
    </p>
    <p>
      The <code>#</code> makes that crossing visible. A value known now becomes
      part of code that exists next.
    </p>
  </section>

  <section>
    <h2>Some-here</h2>
    <p>
      “Here” should be smaller than “everywhere.” The environment gives a macro
      local authority and makes its observations explicit. That lets the graph
      remember what the macro depended on, reject capabilities it does not have,
      and reconsider the expansion when its particular world changes.
    </p>
  </section>

  <blockquote>
    Somewhere gives the macro a place. Sometime gives it a phase. Some place gives it a boundary.
  </blockquote>

  <section>
    <h2>Not expand. Environment.</h2>
    <p>
      That is why <code>#environment &#123; ... &#125;</code> feels closer to the idea
      than asking an object to <code>expand</code>. The block is not merely a
      method call that returns syntax. It names the contextual surface through
      which declarations enter the program.
    </p>
    <p>
      The spelling is small, but the model is large: metaprogramming grounded
      in where, when, and here.
    </p>
  </section>
</EssayPage>
