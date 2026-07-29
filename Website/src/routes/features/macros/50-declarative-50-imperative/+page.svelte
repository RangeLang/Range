<script lang="ts">
  import CodeBlock from "$lib/components/CodeBlock.svelte";
  import EssayPage from "$lib/components/EssayPage.svelte";

  const projectMacro = `macro project(): Construct { environment in
    #environment {
        construct ProjectDefaults {
            #environment.system.defaults.map { default in
                let #default.identifier: #default.value
            }
        }
    }
}`;
</script>

<EssayPage
  title="50% Declarative, 50% Imperative"
  description="Describe the environment you want, then use ordinary macro code when getting there needs computation."
  category="Language design"
  date="July 29, 2026"
>
  <section>
    <h2>Describe the world</h2>
    <p>
      Declarative code is wonderful when the shape is the point. You say what
      should exist and leave the machinery of making it exist to the language.
      Imperative code is wonderful when the path matters: inspect something,
      branch on it, transform it, reject it, or make a slightly strange decision.
    </p>
    <p>Range wants both, with a visible border between them.</p>

    <CodeBlock source={projectMacro} syntax="range" label="Core/Macro/Project.range" />
  </section>

  <section>
    <h2>The declarative half</h2>
    <p>
      Inside <code>#environment</code>, the macro describes a piece of the
      program’s environment. It says that a <code>ProjectDefaults</code>
      construct exists and shows the members that belong inside it. There is no
      builder to push into, no syntax tree to assemble, and no sequence of
      mutation calls pretending to be a language.
    </p>
    <p>
      The block reads like Range because it is Range. It is the desired program
      shape, written directly.
    </p>
  </section>

  <section>
    <h2>The imperative half</h2>
    <p>
      The contents do not have to be static. A macro can query the system,
      iterate over its defaults, and project each result into the declaration.
      The <code>map</code> is compile-time execution: ordinary control and data
      flow used to produce declarative code.
    </p>
    <ul>
      <li>Query the graph and the current system.</li>
      <li>Filter, map, branch, and validate with ordinary Range.</li>
      <li>Emit declarations in the same syntax programmers use everywhere else.</li>
    </ul>
  </section>

  <blockquote>
    Outside the boundary, decide what should happen. Inside it, describe what
    should exist.
  </blockquote>

  <section>
    <h2>The useful middle</h2>
    <p>
      “Declarative or imperative” is a false choice. A fully declarative system
      becomes awkward the moment its vocabulary runs out. A fully imperative
      metaprogramming system makes simple shapes noisy and hides intent behind
      construction APIs.
    </p>
    <p>
      The interesting place is fifty-fifty: declarations for the stable shape,
      a real programming language for the funky parts, and one explicit boundary
      where values become code. That is the direction of Range’s project macro.
      The compiler is being brought up to meet the spelling.
    </p>
  </section>
</EssayPage>
