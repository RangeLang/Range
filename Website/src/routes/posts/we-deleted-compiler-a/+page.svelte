<script lang="ts">
  import CodeBlock from "$lib/components/CodeBlock.svelte";
  import EssayPage from "$lib/components/EssayPage.svelte";

  const oldShape = `RangeCompiler/          // Compiler A
Projects/RangeCompilerB/ // Compiler B

// Two source trees.
// Two test forests.
// Two stories about which compiler was real.`;

  const pipeline = `Range graph
  → semantic execution graph
  → Apple arm64 instruction graph
  → deterministic textual assembly
  → clang assembly and linking`;

  const execution = `construct Execution {
    binding effect: @syntax?

    @many
    state next: Execution
}`;

  const boundary = `range compiler self-host audit: pass sources=49 llvm=0 compilerA=0
range compiler self-host boundary:
execution compass continuation effect is not materialized`;
</script>

<svelte:head>
  <meta name="robots" content="noindex, nofollow, noai" />
</svelte:head>

<EssayPage
  title="We Deleted Compiler A"
  description="Why Range retired its old compiler before reaching the native self-hosted fixed point."
  category="Compiler design"
  date="August 28, 2026"
>
  <section>
    <h2>Two compilers is one too many</h2>

    <p>
      Range had two compilers. Compiler A was the old accepted authority: a
      large self-hosted pipeline whose final product was LLVM. Compiler B was
      the smaller graph-native replacement growing beside it. A built B. B
      proved one native behavior at a time. Every serious change therefore had
      to answer an increasingly awkward question: which compiler was Range?
    </p>

    <CodeBlock
      source={oldShape}
      syntax="design-code"
      label="The former repository shape"
    />

    <p>
      The arrangement was useful while B was an experiment. It became harmful
      once B owned the language direction. A still controlled bootstrap paths,
      custom entry builds, generated LLVM, and a historical fixture forest.
      Whenever B reached a new boundary, there was a temptation to repair A so
      it could carry B one step farther. The bridge was starting to decide the
      destination.
    </p>

    <p>
      So we removed it. Compiler B moved into <code>RangeCompiler/</code> and
      became simply the Range Compiler. The duplicate project, Compiler A
      source, generated LLVM bootstrap, custom-entry lifecycle, and obsolete
      fixture forest left the active checkout together.
    </p>
  </section>

  <section>
    <h2>Deleting A is not self-hosting</h2>

    <p>
      This is the funny part: the remaining compiler cannot yet reproduce
      itself. Removing the predecessor did not close the bootstrap loop. It
      made the open loop impossible to disguise.
    </p>

    <blockquote>
      One compiler remains. It is canonical, native, and still pre-self-hosting.
    </blockquote>

    <p>
      The repository now checks in one hash-pinned macOS arm64 seed. That seed
      is generation zero: a verified executable produced before the cleanup.
      It reads the canonical 49-source manifest and drives the native pipeline,
      but source edits do not magically change the executable already on disk.
      A new compiler exists only when that seed emits a candidate capable of
      emitting an identical reproduction.
    </p>

    <p>
      Until candidate and reproduction assembly, objects, executables, and
      focused output are byte-identical, there is no fixed point. The seed is
      a bridge across that gap, not a hidden second implementation.
    </p>
  </section>

  <section>
    <h2>One native path</h2>

    <p>
      The remaining architecture is deliberately narrow. Range source becomes
      one semantic graph. The execution compass activates effects through that
      graph. Apple instructions are another graph product. A renderer writes
      deterministic assembly without inspecting Range declaration names.
    </p>

    <CodeBlock
      source={pipeline}
      syntax="design-code"
      label="The canonical compiler pipeline"
    />

    <p>
      Clang still assembles and links. It is a target tool, not a semantic
      compiler. The temporary C host and RawBuffer runtime remain for dynamic
      storage and system boundaries that have not yet moved into ordinary
      Range-authored effects. Those dependencies are explicit removal gates,
      not alternative language authorities.
    </p>

    <CodeBlock
      source={execution}
      syntax="range"
      label="Continuation is an ordinary graph relationship"
    />

    <p>
      <code>Execution.next</code> is the center of the native model. No
      successor means completion. One means continuation. Many represent a
      selection or fork. Multiple incoming relationships form a merge; a cycle
      represents repetition. The renderer consumes the resulting instruction
      facts rather than reconstructing an <code>if</code>, switch, or loop from
      source-shaped special cases.
    </p>
  </section>

  <section>
    <h2>The audit passes, the boundary remains</h2>

    <p>
      The cleanup has a compact acceptance gate. It verifies the 49-source
      manifest, the exact seed hash, self-describing syntax, Vector
      construction, homogeneous collections, locals and mutable state,
      execution-compass outcomes, graph-native output, and deterministic
      assembly. A separate audit rejects active LLVM and Compiler A surfaces.
    </p>

    <CodeBlock
      source={boundary}
      syntax="design-code"
      label="Current verified boundary"
    />

    <p>
      Both lines matter. The first proves that the architecture was actually
      consolidated. The second prevents consolidation from being narrated as
      completion. The untouched seed reaches the continuation after the
      compiler entry’s first compound conditional and stops because the next
      effect has not been materialized.
    </p>

    <p>
      A narrow rescue probe can advance farther by loading a stored return
      value, but it reaches the same class of boundary at a selected body with
      state replacement. That is evidence about the missing general topology,
      not permission to add one more shape-specific branch to the old seed.
    </p>
  </section>

  <section>
    <h2>Now the compiler has nowhere to hide</h2>

    <p>
      The next step is not to resurrect A. It is to produce the first bridge
      candidate with generic brace-form Application retention and safe syntax
      matching, then materialize condition values as exhaustive
      <code>Execution.next</code> relationships. Bool guards, enum selection,
      short-circuiting, and repetition should all become the same graph
      topology.
    </p>

    <p>
      After that come dynamic String and command-line values, file and process
      effects, diagnostics, collection growth, ownership, and cleanup on every
      exit. Only then can the seed emit a candidate, the candidate emit its
      reproduction, and both agree byte for byte.
    </p>

    <p>
      Deleting Compiler A did not finish the Range Compiler. It did something
      more useful: it made unfinished work belong to exactly one compiler.
      There is no fallback implementation to flatter the new architecture and
      no second source tree to keep alive out of habit. There is one path
      forward. Now it has to compile itself.
    </p>
  </section>
</EssayPage>
