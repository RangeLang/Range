<script lang="ts">
  import CodeBlock from "$lib/components/CodeBlock.svelte";
  import CompilationTree from "$lib/components/CompilationTree.svelte";
  import EssayPage from "$lib/components/EssayPage.svelte";
  import FibonacciSphereShader from "$lib/components/FibonacciSphereShader.svelte";

  const relationshipRegistration = `construct RelationshipRegistration {
    let multiplicity: RelationshipMultiplicity
    let ordering: RelationshipOrdering
    let separator: RelationshipSeparator
    let enclosure: RelationshipEnclosure
}

macro value(): Member -> RelationshipRegistration {
    return scalarValueRelationship()
}`;

  const graphRelationship = `construct RangeGraphRelationship {
    let origin: Identifier
    let role: Identifier
    let destination: Identifier
    let registration: RelationshipRegistration
}`;

  const occurrenceMetadata = `construct RelationshipMultiplicity {
    let minimum: Int
    let maximum: RelationshipBound
}

enum RelationshipSeparator {
    case none
    case syntax(identifier: Identifier)
}

enum RelationshipEnclosure {
    case none
    case delimited(pair: DelimiterPair)
}`;
</script>

{#snippet heroShader()}
  <FibonacciSphereShader />
{/snippet}

<EssayPage
  title="Intro to Range: The Concrete"
  description="How the Range compiler uses typed relationship values to describe multiplicity, order, separators, and enclosure."
  category="Introduction"
  date="August 1, 2026"
  {heroShader}
  heroShaderOpacity={1}
>
  <section>
    <h2>The next smallest thing</h2>

    <p>
      Core is the smallest logical unit inside Range compilation. It contains
      the commands, macro definitions, and fundamental values needed to
      describe the language without making the native bootstrap the language's
      permanent architecture.
    </p>

    <p>
      The compiler is itself a project implemented in Range. Core provides the
      authority that compiles that compiler project; the resulting compiler is
      then what compiles your project. The same path can branch into any number
      of programs without introducing another compiler model.
    </p>

    <CompilationTree />

    <p>
      The first introduction began with Range’s smallest unit of meaning:
      identity and value. That immediately gives the compiler a harder
      question. If an identity can have no value, one value, or many values,
      where does that knowledge live?
    </p>

    <p>
      It lives in a value. In compiler space, the value produced by
      <code>@value</code> carries the metadata for the relationship it
      declares. The macro is not an empty marker that waits for a private
      compiler switch to interpret it later. Its result is typed Range data:
    </p>

    <CodeBlock
      source={relationshipRegistration}
      syntax="range"
      label="A value relationship registration"
    />

    <p>
      The scalar registration says exactly one value, unordered, with no
      separator and no enclosure. That is only the default. The same shape can
      describe absence, optionality, or a sequence without inventing a second
      compiler model for each case.
    </p>
  </section>

  <section>
    <h2>Three identities, one fact</h2>

    <p>
      The three dots above are the identities in a graph relationship: origin,
      role, and destination. The origin identifies where the fact begins. The
      role identifies what the fact means—such as <code>appliesTo</code> or
      <code>resolvedBy</code>. The destination identifies the syntax or
      declaration at the other end.
    </p>

    <CodeBlock
      source={graphRelationship}
      syntax="range"
      label="The plotted relationship"
    />

    <p>
      The fourth field does not add a fourth identity. Registration is the
      typed value carried by their relationship. Because the graph preserves
      both the identities and that value, later compiler phases can inspect
      the fact without rediscovering it from a name, an array position, or
      nearby source text.
    </p>
  </section>

  <section>
    <h2>Multiplicity is not a container</h2>

    <p>
      An array makes “many” look like a type. An optional makes “maybe” look
      like another type. In the compiler, both are more fundamental as bounds
      on a relationship. A minimum of zero and maximum of one describes an
      optional occurrence. A minimum of zero and an unbounded maximum
      describes many. One through one is the ordinary scalar case.
    </p>

    <CodeBlock
      source={occurrenceMetadata}
      syntax="range"
      label="Occurrence and written shape"
    />

    <p>
      Multiplicity answers how many values can occur. Ordering answers whether
      position matters. Separator records what appears between occurrences.
      Enclosure records the paired shape around them—<code>()</code>,
      <code>[]</code>, <code>&#123;&#125;</code>, or <code>&lt;&gt;</code>. These are
      independent facts. A comma does not imply brackets; brackets do not make
      the collection its primary semantic type. The elements remain primary,
      and their relationship describes how they gather.
    </p>

    <p>
      This stays hidden from ordinary source. A programmer still writes
      <code>String?</code>. The postfix spelling becomes the written shape of a
      zero-or-one relationship; it does not require every user to construct a
      compiler registration by hand.
    </p>
  </section>

  <section>
    <h2>The important split</h2>

    <p>
      The compiler can keep these concerns separate because they are already
      represented by different values and relationships:
    </p>

    <div class="compilerSplitTableWrap">
      <table class="compilerSplitTable">
        <thead>
          <tr>
            <th scope="col">Concern</th>
            <th scope="col">Lives in</th>
          </tr>
        </thead>
        <tbody>
          <tr>
            <td>“These are three members, in this source order”</td>
            <td>graph relationships</td>
          </tr>
          <tr>
            <td>
              “They are separated by commas or lines and enclosed by
              <code>[]</code>, <code>&#123;&#125;</code>, or <code>()</code>”
            </td>
            <td>relationship shape metadata</td>
          </tr>
          <tr>
            <td>“This is zero, one, or many”</td>
            <td>occurrence / cardinality</td>
          </tr>
          <tr>
            <td>“This is an <code>Array&lt;Int&gt;</code> at runtime”</td>
            <td>ordinary nominal type semantics</td>
          </tr>
          <tr>
            <td>“Select members carrying <code>@value</code>”</td>
            <td>Range macro query</td>
          </tr>
        </tbody>
      </table>
    </div>

    <p>
      <code>many</code> is a compiler execution form, not a synonym for
      <code>Array</code>. A source selection, literal, macro argument list, or
      block body can all be many, while <code>Array</code> remains one
      particular runtime value type.
    </p>
  </section>

  <section>
    <h2>Plot once, select later</h2>

    <p>
      Macro applications now enter the compiler graph through relationship
      roles such as <code>appliesTo</code>, <code>resolvedBy</code>, and
      <code>references</code>. The compiler can plot those facts once, then
      select declarations and applications by role, type, or metatype instead
      of maintaining a parallel path for every feature.
    </p>

    <p>
      Selection preserves why a value matched. When the compiler selects a
      member through <code>@value</code>, the returned compiler value carries
      the exact relationship-row identity alongside the member’s syntax
      identity. Later phases can follow that row back to its registration
      instead of reconstructing provenance from the selected member.
    </p>

    <p>
      The cutover is deliberately incremental. The relationship model and the
      macro links are in place; legacy Array and Optional lowering still acts
      as an adapter while occurrence selection moves onto the graph. That
      boundary matters. It lets the new model become the source of truth
      before the old representations are removed.
    </p>

    <p>
      LLVM then receives a concrete representation after Range has already
      decided what the program means. It becomes a lowering target rather than
      the architecture of the language. The compiler gets smaller for the same
      reason the model gets clearer: no value, one value, and many values are
      registrations of one relationship—not three unrelated compiler paths.
    </p>
  </section>

  <section>
    <h2>Identity gives the compiler a universe</h2>

    <p>
      Once every value has an identity, the compiler no longer has to treat
      each kind of value as an isolated island. A declaration, a member, a
      macro application, and the relationship that connects them can all be
      named, collected, compared, and selected in the same graph.
    </p>

    <p>
      That makes set-theoretic operations a natural way to describe compiler
      work. A query can form the union of several candidate groups, intersect
      them with a capability or role, remove values that have already been
      consumed, and test membership without inventing a separate traversal
      mechanism for every feature.
    </p>

    <p>
      It is cheap because the compiler is not manufacturing a new world for
      each operation. Identity already names the value, and the relationship
      row already records why it is present. Union, intersection, difference,
      and membership can reuse those identities and rows rather than copying
      values, rebuilding provenance, or translating through an intermediate
      representation.
    </p>

    <p>
      The values are not all literally sets. The point is that they inhabit a
      common identity-bearing universe, so sets of values and relations among
      those values can be manipulated with the same small vocabulary. That is
      what macro selection is already doing: collecting graph values,
      narrowing them by typed facts, and preserving the identity of the row
      that justified each result.
    </p>

    <p>
      Meaning therefore survives the operation. Union does not flatten the
      values into anonymous members. Intersection does not erase provenance.
      Difference does not require a second representation of the program.
      Each result is still a value with an identity and relationships that the
      next compiler phase can inspect.
    </p>
  </section>
</EssayPage>

<style>
  .compilerSplitTableWrap {
    overflow-x: auto;
    margin: 28px 0 30px;
    border: 1px solid color-mix(in oklch, var(--line), var(--ink) 12%);
    border-radius: 7px;
  }

  .compilerSplitTable {
    width: 100%;
    min-width: 600px;
    border-collapse: collapse;
    color: var(--ink);
    font-size: 0.92em;
  }

  .compilerSplitTable th,
  .compilerSplitTable td {
    padding: 12px 14px;
    border-bottom: 1px solid var(--line);
    text-align: left;
    vertical-align: top;
  }

  .compilerSplitTable thead th {
    background: color-mix(in oklch, var(--line), var(--paper) 55%);
    font-weight: 650;
  }

  .compilerSplitTable tbody tr:last-child td {
    border-bottom: 0;
  }

  .compilerSplitTable td + td,
  .compilerSplitTable th + th {
    border-left: 1px solid var(--line);
  }

  .compilerSplitTable code {
    white-space: nowrap;
  }
</style>
