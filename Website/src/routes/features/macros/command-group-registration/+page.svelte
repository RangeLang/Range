<script lang="ts">
  import CodabilitySheet from "$lib/components/CodabilitySheet.svelte";
  import EssayPage from "$lib/components/EssayPage.svelte";
  import SphereLineShader from "$lib/components/SphereLineShader.svelte";
</script>

{#snippet heroShader()}
  <SphereLineShader palette={3} />
{/snippet}

<EssayPage
  title="Registration by Declaration"
  description="One small macro turns annotated member functions into a construct-owned command set."
  category="Macro breakdown"
  date="August 1, 2026"
  {heroShader}
  heroShaderFocusX={68}
>
  <CodabilitySheet variant="commandGroup" showIntro={false} />

  <article class="commandGroupNotes">
    <section>
      <h2>1. Mark the registrable members</h2>
      <p>
        <code>command</code> targets a <code>Function</code>. Its empty body is
        intentional: it supplies typed annotation identity, rather than a runtime
        registry or a wrapper around the function.
      </p>
    </section>

    <section>
      <h2>2. Discover the registrations</h2>
      <p>
        The group macro targets the enclosing <code>Construct</code>. Its
        <code>Declaration.members</code> query is local to that target, and
        <code>filter(all: @command)</code> retains only functions carrying the
        marker. The result is a typed, ordered collection of command declarations.
      </p>
    </section>

    <section>
      <h2>3. Validate the contract</h2>
      <p>
        A command group with no registrations is not meaningful. Before generating
        anything, the macro reports a targeted diagnostic: <code>@commandGroup
        requires at least one @command function.</code>
      </p>
    </section>

    <section>
      <h2>4. Generate the closed command set</h2>
      <p>
        <code>#environment</code> emits an extension on the target construct.
        Within it, <code>#commands.map</code> runs at macro time and splices one
        <code>case</code> per registered declaration into <code>Command</code>.
        Adding <code>@command function help()</code> therefore adds
        <code>case help</code>; no second list can drift out of sync.
      </p>
    </section>

    <section>
      <h2>5. Dispatch is the next boundary</h2>
      <p>
        The generated <code>runCommandLine()</code> deliberately returns
        <code>64</code> today. It proves that the macro can generate and attach a
        callable entry point, but it does not yet parse argv or invoke a registered
        function. That later dispatch work builds on this registration slice rather
        than changing what registration means.
      </p>
    </section>
  </article>
</EssayPage>

<style>
  .commandGroupNotes {
    width: min(820px, calc(100% - 48px));
    margin: 0 auto;
    padding: 72px 0 96px;
  }

  .commandGroupNotes section + section {
    margin-top: 64px;
  }

  .commandGroupNotes h2 {
    margin: 0 0 18px;
    font-size: clamp(27px, 4vw, 38px);
    font-weight: 520;
    letter-spacing: -0.045em;
    line-height: 1.08;
  }

  .commandGroupNotes p {
    margin: 0;
    color: oklch(0.31 0.018 255);
    font-size: 17px;
    line-height: 1.72;
  }

  @media (max-width: 760px) {
    .commandGroupNotes {
      width: min(100% - 28px, 600px);
      padding-top: 56px;
    }
  }
</style>
