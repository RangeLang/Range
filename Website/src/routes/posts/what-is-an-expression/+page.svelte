<script lang="ts">
  import CodeBlock from "$lib/components/CodeBlock.svelte";
  import EssayPage from "$lib/components/EssayPage.svelte";

  const composition = `let funded = balance > 0
let reachable = primary ?? fallback
let admitted = !blocked && (invited || funded)

// Each expression narrows, combines, or completes
// a space of possible values and execution states.`;

  const executionShape = `condition
├─ case accepted  → Execution.next
└─ case rejected  → Execution.next

// The graph contains both possibilities.
// Execution activates the successor selected by the value.`;

  const largerCase = `account.active && balance > 0 {
    .true {
        state result: Decision(.accepted)
    }
    .false {
        state result: Decision(.rejected)
    }
}

return result`;
</script>

<svelte:head>
  <meta name="robots" content="noindex, nofollow, noai" />
</svelte:head>

<EssayPage
  title="What Is an Expression?"
  description="In Range, an expression is a condition: a composable value that divides possible states of execution."
  category="Language design"
  date="August 28, 2026"
>
  <section>
    <h2>A split between possible states</h2>

    <p>
      An expression is usually introduced as a fragment of code that produces
      a value. That definition describes the result, but not the pressure the
      result places on execution. In Range, an expression is more useful to
      understand as a <em>condition</em>: a split between possible states of
      the program.
    </p>

    <p>
      The split does not have to be Boolean. A comparison divides an ordered
      space. An optional relationship divides occurrence from absence. An enum
      divides one closed identity into its cases. Even an ordinary value makes
      some future relationships possible and rules others out. The expression
      gives that distinction a value the graph can retain.
    </p>

    <blockquote>
      An expression is a condition. A condition is a value that makes a split
      in execution describable.
    </blockquote>
  </section>

  <section>
    <h2>A condition is a composable value</h2>

    <p>
      Once a condition is a value, it can be named, passed, stored, and
      combined. It does not have to disappear into a control-flow keyword.
      Operators become ways of composing spaces of possibility.
    </p>

    <CodeBlock
      source={composition}
      syntax="design-code"
      label="Design sketch — expressions compose possible states"
    />

    <p>
      <code>&gt;</code> draws a boundary through an ordered domain.
      <code>!</code> takes the complement of a condition. <code>||</code>
      accepts the union of two cases. <code>??</code> fills the absent side of
      a relationship with another possible value. They are not identical
      operations, but they share an algebraic character: each transforms a
      set of possible states into another value that can be composed again.
    </p>

    <p>
      This is why conditions should not be trapped inside <code>if</code>.
      The condition exists before any branch consumes it. A branch is only one
      possible relationship built from that value.
    </p>
  </section>

  <section>
    <h2>The graph keeps both possibilities</h2>

    <p>
      Range observes one semantic graph through two ordered views. The
      declaration compass records identities, values, relationships, and every
      possible successor. The execution compass activates the effects that
      follow from the value resolved at runtime.
    </p>

    <CodeBlock
      source={executionShape}
      syntax="design-code"
      label="Execution topology — conceptual, not current Range syntax"
    />

    <p>
      A condition therefore does not manufacture a special nested control-flow
      object. It contributes successor relationships. Zero successors means
      completion. One means continuation. Many represent a selection or fork.
      A merge is an execution identity with multiple incoming relationships;
      repetition is a cycle. The topology already contains the vocabulary
      usually distributed across separate statement forms.
    </p>

    <p>
      This is the design direction now being implemented in the native Range
      compiler. The graph identities and expression-first body model are in
      place, while general condition-valued application and successor
      materialization remain active compiler work. The model is the authority;
      the complete surface is not yet a finished language claim.
    </p>
  </section>

  <section>
    <h2>A statement describes a larger case</h2>

    <p>
      Complex cases still need room to be described. We can call that larger
      description a statement, but it does not need to be a second semantic
      species. A statement is a region in which values, effects, and
      relationships are authored together. Its operational order comes from
      the execution relationships between them.
    </p>

    <CodeBlock
      source={largerCase}
      syntax="design-code"
      label="Condition-valued application — design sketch"
    />

    <p>
      If one branch reaches another condition, the graph gains another split.
      If two branches continue into the same effect, they gain a shared
      successor. Nothing is recursively lowered because it happens to be
      written inside braces. Source ownership preserves provenance and branch
      membership; execution relationships preserve what can happen next.
    </p>

    <p>
      The familiar statement–expression divide then becomes an authoring
      distinction rather than an execution architecture. The statement gives
      a complex case a readable boundary. The expressions inside it remain
      conditions, and the conditions remain values.
    </p>
  </section>

  <section>
    <h2>One idea instead of a catalogue</h2>

    <p>
      Languages often accumulate a different compiler shape for each kind of
      split: Boolean guards, switches, short-circuit operators, optional
      fallback, early returns, loops. The surface differences are useful, but
      they do not require separate semantic foundations.
    </p>

    <p>
      Range can retain the surface that best describes each case while giving
      all of them the same substrate. Expressions produce composable
      conditions. Conditions select among already-described execution
      relationships. Statements gather larger descriptions without becoming a
      second execution language.
    </p>

    <p>
      What is an expression? It is the smallest value with which a program can
      say: from here, more than one state is possible.
    </p>
  </section>
</EssayPage>
