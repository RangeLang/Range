<script lang="ts">
  import CodeBlock from "$lib/components/CodeBlock.svelte";
  import EssayPage from "$lib/components/EssayPage.svelte";

  const constructExample = `construct Counter {
    state value: Int

    derived doubled: Int {
        value + value
    }

    function update(newValue: Int): Int {
        value: newValue
        return value
    }
}`;
</script>

<EssayPage
  title="Class v. Struct"
  description="The old argument is tired, but it keeps walking back into the room."
  category="Observation"
  date="May 18, 2026"
>
  <section>
    <h2>Observation</h2>
    <p>
      The usual question bundles several independent decisions into one
      binary: copy or share, stack or heap, immutable or mutable, value or
      identity. The language asks us to choose a container before we have
      described the relationships inside it.
    </p>

    <ol class="comparison">
      <li>
        <strong>Structs:</strong> great for isolated values, predictable
        copying, local ownership, and making change easier to reason about.
      </li>
      <li>
        <strong>Classes:</strong> useful when identity and sharing matter—until
        five systems hold the same mutable object and everyone prays nobody
        mutates it during production hours.
      </li>
    </ol>

    <p>
      Both are useful. The problem is the size of the choice. A single type can
      contain an immutable identifier, mutable state, projected access, and a
      computed view. Making the entire declaration “a value” or “a reference”
      forces those different relationships to inherit one story.
    </p>
  </section>

  <section>
    <h2>Verdict</h2>
    <p>
      <em>The split is trying to protect two useful ideas:</em> values should be
      understandable in isolation, and some things should keep a stable
      identity as they move through a system.
    </p>

    <p>
      But identity and value are not opposites. In Range, they form the smallest
      unit of meaning: <span class="accentTerm">Identity : Value</span>. The
      identity says which thing a relationship belongs to. The value says what
      that relationship carries. Sharing, copying, storage, and mutation can be
      decided from those facts without changing what the thing means.
    </p>
  </section>

  <section>
    <h2>Construct</h2>
    <p>
      The compiler already knows what a "thing" is after parsing it. It already
      has identity, connections, and relationships inside the compiler graph.
      Range exposes that existing idea instead of asking the declaration to
      disguise itself as either a class or a struct.
    </p>

    <p>
      A <span class="accentTerm">Construct</span> describes a composed value.
      Its members state their own storage and access intent. Here,
      <code>value</code> is mutable state, while <code>doubled</code> is derived
      from it and owns no separate storage:
    </p>

    <CodeBlock
      source={constructExample}
      syntax="range"
      label="One construct, member-level intent"
    />

    <p>
      The declaration remains one thing, but its relationships do not have to
      pretend they are the same kind of thing. An immutable member can remain
      fixed. State can change. A binding can project access elsewhere. A
      derived member can be recomputed. The compiler can lower each one
      independently while preserving the construct’s identity and meaning.
    </p>
  </section>

  <section>
    <h2>The question moves</h2>
    <p>
      “Class or struct?” stops being the first architectural decision. The
      useful questions become smaller: what has identity, what carries value,
      which relationships own storage, and which only expose or derive it?
    </p>

    <blockquote>
      The declaration describes the thing. Its relationships describe how the
      thing is carried.
    </blockquote>
  </section>
</EssayPage>

<style>
  .comparison {
    display: grid;
    gap: 18px;
    margin: 28px 0;
    padding-left: 24px;
    color: oklch(0.31 0.018 255);
    font-size: 17px;
    line-height: 1.72;
  }

  .comparison strong {
    color: var(--range);
    font-weight: 650;
  }

  .accentTerm {
    color: var(--range);
  }
</style>
