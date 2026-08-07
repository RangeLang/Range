<script lang="ts">
  import CodeBlock from "$lib/components/CodeBlock.svelte";
  import EssayPage from "$lib/components/EssayPage.svelte";

  const macroSketch = `macro myMacro(): Construct { environment in
    let addFunctions: Array<Function>(
        environment.target.Declaration.members.filter(all: Function)
            .filter { member in member.identity.name == "add" }
    )
    if addFunctions.count == 0 {
        #environment {
            extension #environment.target.Declaration.identity {
                function add(left: Int, right: Int): Int {
                    return left + right
                }
            }
        }
    }
    #environment {
        let count: Int(5)
    }
}

@myMacro
construct MyConstruct {
    // myMacro checks for "add", emits default if missing
    // then emits count into the environment
}`;
</script>

<EssayPage
  title="Requirement and Provision: A Modern Split"
  description="One declaration in the environment can be both sides of the split."
  category="Language design"
  date="August 4, 2026"
>
  <section>
    <h2>Why I removed protocols</h2>
    <p>
      I removed protocols because a macro can do everything a protocol did
      — and one thing it couldn't: provide defaults. A protocol says "you
      must have this member." A macro says "I need this member. If it's
      missing, I'll emit one myself."
    </p>

    <p>
      Look at <code>myMacro</code>. It filters the target construct's
      <code>Function</code> members for one named <code>add</code>. If none
      is found, it emits a default via <code>#environment</code> using
      <code>extension</code>. This is the requirement side — the macro
      <em>requires</em> <code>add</code> to be meaningful. But instead of
      forcing the user to write it, it supplies one. The macro also
      unconditionally emits <code>count</code> into the environment. That
      is the provision side.
    </p>

    <p>
      Protocols encoded one relationship (you must write X). Macros encode
      two: you must have X, and if you don't, here is one. That is strictly
      more useful. A keyword for the weaker relationship stopped making sense.
    </p>
  </section>

  <section>
    <h2>Why I removed static properties</h2>
    <p>
      A static property on a construct was a provision — a value attached
      to the type itself. But <code>#environment</code> inside a function
      body does the same thing. A macro emits into the environment,
      a function's body emits into the environment. There is no need for
      a separate static declaration site.
    </p>

    <p>
      Static properties existed because we needed somewhere to put values
      that belonged to the construct, not to an instance. That place was a
      second keyword. But <code>#environment</code> is already the place for
      ambient values. Whether they come from a macro or a function body is
      an implementation detail. The keyword <code>static</code> was a
      distinction without a difference.
    </p>
  </section>

  <section>
    <h2>The macro is both sides</h2>

    <CodeBlock
      source={macroSketch}
      syntax="range"
      label="One macro, two jobs"
    />

    <p>
      This is the complete replacement. A macro queries
      <code>environment.target.Declaration.members</code> to inspect what
      a construct provides, then conditionally emits what it needs via
      <code>#environment</code>. The "requirement" half is the filter check.
      The "provision" half is the emit. Both live in the same declaration,
      not split across protocols and statics.
    </p>

    <p>
      The graph resolves contributions regardless of origin. It does not care
      whether a declaration came from a macro, a function body, or a construct
      member. It only cares whether it has a provider. If it does, it binds.
      If it does not, it reports an error. The split between requirement and
      provision was a property of the resolution, not of the declaration.
      I made it explicit by removing the keywords that pretended otherwise.
    </p>
  </section>
</EssayPage>
