<script lang="ts">
  import CodeBlock from "$lib/components/CodeBlock.svelte";
  import EssayPage from "$lib/components/EssayPage.svelte";

  const optionality = `enum Optional<Value, None = Nil> {
    case exists(value: Value)
    case none(value: None)
}

let selected: Int?(.exists(value: 7))`;

  const relationship = `construct RelationshipMultiplicity {
    let minimum: Int
    let maximum: RelationshipBound
}

// one through one: the ordinary value
// zero through one: an optional occurrence
// zero through many: a collection relationship`;

  const existentialShape = `// The question is not “is there a value?”
// It is “which concrete type is carrying this value?”

// An existential package would need to preserve:
//   a hidden type identity
//   the value carrying that type
//   the operations permitted by its boundary`;

  const swiftVocabulary = `enum Optional<Wrapped> {
    case some(Wrapped)
    case none
}

func makeShape() -> some Shape { ... }
let shapes: [any Shape] = [triangle, square]
let mixed: [Any] = ["Range", 7, true]`;

  const rangeViewState = `@component
construct Stack {
    state axis: Axis

    derived view: [@component] {
        // the trailing component body is the view field
    }
}`;
</script>

<svelte:head>
  <meta name="robots" content="noindex, nofollow, noai" />
</svelte:head>

<EssayPage
  title="Optionality v. Existentiality"
  description="Range separates the question of whether a value occurs from the question of which type a value is."
  category="Language design"
  date="August 10, 2026"
>
  <section>
    <h2>Two kinds of unknown</h2>

    <p>
      “Maybe” and “some type” often arrive together in a language discussion.
      They should not. Optionality asks whether a relationship has an
      occurrence. Existentiality asks whether an occurrence has a concrete
      type that the current context is not allowed to name.
    </p>

    <p>
      Those are different unknowns. The first is about presence. The second is
      about identity and the boundary of knowledge. If we put both into one
      wrapper, the wrapper starts carrying decisions that belong to different
      parts of the language.
    </p>

    <blockquote>
      Optionality is a question about a relationship. Existentiality is a
      question about the type identity behind a relationship.
    </blockquote>
  </section>

  <section>
    <h2>Optionality is not a mystery type</h2>

    <p>
      Range’s current <code>Optional</code> is deliberately ordinary. It is an
      enum with an existing value and a none value. The none case can even
      carry its own information: <code>None</code> defaults to <code>Nil</code>,
      but a caller can provide a meaningful absence value such as a missing
      reason.
    </p>

    <CodeBlock
      source={optionality}
      syntax="range"
      label="The current Optional model"
    />

    <p>
      The surface question-mark is only a compact type reference. It does not
      make absence a second kind of value, and it does not erase the value
      inside the existing case. The program still switches over a typed enum;
      the compiler has a concrete thing to inspect.
    </p>
  </section>

  <section>
    <h2>Look one level lower</h2>

    <p>
      The deeper Range model says that optionality is even more fundamental as
      a relationship bound. The compiler’s relationship registration records
      multiplicity, ordering, separators, and enclosure as separate typed
      values. “Maybe” is the multiplicity from zero through one, not a reason
      to make a container the primary meaning.
    </p>

    <CodeBlock
      source={relationship}
      syntax="range"
      label="Multiplicity is a relationship fact"
    />

    <p>
      This is the same move Range makes elsewhere: keep identity, value, and
      relationship distinct so later phases can use each fact directly. An
      optional member can be absent without becoming an untyped hole in the
      graph. Its identity remains available; its relationship simply has no
      occurrence at that moment.
    </p>
  </section>

  <section>
    <h2>Existentiality changes the question</h2>

    <p>
      An existential value is not “no value.” It is a value whose concrete type
      is hidden behind a boundary. The consumer may know that the value
      satisfies some permitted shape, while being unable—or unwilling—to name
      the exact type that produced it.
    </p>

    <CodeBlock
      source={existentialShape}
      syntax="design-code"
      label="Design sketch — not current Range syntax"
    />

    <p>
      That is why existentiality belongs near type identity, capabilities, and
      representation. It needs a way to preserve the hidden type’s identity,
      carry its value, and limit the operations that can cross the boundary.
      Optionality needs none of those things. It needs a cardinality rule.
    </p>

    <p>
      Range’s current <code>@opaque</code> surface is useful evidence of the
      boundary, but not a general existential system. It describes nominal
      borrowed foreign handles and their ABI representation. A nullable opaque
      pointer is still a foreign pointer that may be null; it is not an
      existential package whose hidden Range type can be opened and used.
    </p>
  </section>

  <section>
    <h2>Swift names the neighborhood</h2>

    <p>
      Swift is a useful comparison because it gives these nearby ideas
      different spellings. Its optional is an enum with <code>some</code> and
      <code>none</code>. That <code>some</code> is a case constructor: it means
      that a wrapped value is present. It is not the opaque-type keyword.
    </p>

    <CodeBlock
      source={swiftVocabulary}
      syntax="design-code"
      label="Swift vocabulary — comparison, not Range syntax"
    />

    <p>
      Swift’s <code>some Shape</code> is an opaque type. The implementation
      chooses one concrete type that conforms to <code>Shape</code>, and the
      caller can use the promised interface without learning that concrete
      type. The identity of that hidden type is still preserved for the
      compiler.
    </p>

    <p>
      Swift’s <code>any Shape</code> is an existential, or boxed protocol type.
      It can hold different conforming types at different times, so the
      concrete type is erased behind a runtime box. <code>Any</code> goes even
      wider: it can hold a value of any type, but useful operations generally
      require a cast back to something known. “Some,” “any,” and “Any” are
      therefore not three spellings for optionality. They mark three different
      relationships with type identity: hidden-but-stable, hidden-and-variable,
      and broadly dynamic.
    </p>

    <p>
      The Swift distinction sharpens the Range question. <code>none</code>
      describes absence; <code>some</code> as an opaque type describes a
      producer-owned hidden type; <code>any</code> describes a consumer-facing
      existential boundary. A language can place all three beside a question
      mark and still keep them semantically separate.
    </p>
  </section>

  <section>
    <h2>The component question dissolves</h2>

    <p>
      This has a practical consequence for RangeView. Consider a component
      whose state carries an axis and derives its view from its component body:
    </p>

    <CodeBlock
      source={rangeViewState}
      syntax="design-code"
      label="RangeView design sketch — not current compiler proof"
    />

    <p>
      A <code>Stack</code> is not merely a convenient layout helper. It is a
      way to quantize a field. The field begins as open possibility: values may
      arrive, relate, and occupy space without a chosen sequence. The stack
      gives that field an axis, an order, and a set of component occurrences.
      It turns continuous possibility into inspectable relationships without
      requiring each possible component to become a new nominal type.
    </p>

    <p>
      Someone may ask: which component is <code>view</code>? But that is already
      answered by its boundary. It is not some one named component. It is a
      relationship containing component values. The stack, the slot, and the
      eventual leaf values can all participate through the same semantic
      relationship.
    </p>

    <p>
      The type of the state does not need to predict every concrete actor that
      may occupy it. <code>@component</code> says what may appear through the
      boundary. The existential is not an exotic box placed beside the state;
      it is the state’s ordinary value relationship, viewed through the
      capability the consumer needs. A later renderer can lower that value to
      a <code>Fragment</code>, but the fragment is the product, not the
      semantic boundary.
    </p>

    <p>
      This may be why states are the more fundamental actors in RangeView.
      Different things can be states—spacing, routes, fragments, native
      handles, or a selected component—while “component” is the role that
      describes what a value can do at a rendering boundary. We see values
      first. The framework names an actor only when it needs a stable identity,
      a capability, or a relationship around that value.
    </p>

    <p>
      RangeView’s current source already points in this direction: component
      bodies and fragment children are expressed as <code>[@component]</code>
      relationships. The design sketch extends that idea; it does not claim
      that the complete state/view surface is already compiler-backed.
    </p>
  </section>

  <section>
    <h2>The unresolved knot</h2>

    <p>
      The temptation is to solve both problems with a universal spelling:
      <code>Optional&lt;Any&gt;</code>, an interface box, or a special “some” type
      that also handles absence. That feels economical because both surfaces
      contain something unknown. Semantically, it is expensive. It mixes a
      missing relationship with a present relationship whose type is hidden.
    </p>

    <p>
      But there is a darker temptation on the other side: if <code>some</code>
      and <code>any</code> are useful, why stop there? Why not add
      <code>different</code> for values whose types must differ, <code>many</code>
      for a family of types, or another qualifier for values that share a
      hidden identity? Each word can sound like a precise answer to one more
      real question.
    </p>

    <p>
      This is where the curse of dimensionality enters the reasoning field.
      Presence, multiplicity, type visibility, type identity, and permitted
      operations are separate axes. Once each axis receives its own syntactic
      marker, programmers must reason about their combinations as well as the
      original values. The language has not merely gained a few words; it has
      gained a grid of possible states.
    </p>

    <CodeBlock
      source={`// Conceptual axes — not current Range syntax
presence:    none | one | many
type view:   concrete | some | any
identity:    same | different | unknown

// The combinations are the real surface area.`}
      syntax="design-code"
      label="The combinatorial pressure — design sketch"
    />

    <p>
      A language can keep adding qualifiers until every distinction is named,
      but naming every distinction does not make the model smaller. It can
      make the programmer carry the product of all the distinctions in their
      head. The syntax becomes locally expressive while the reasoning field
      becomes globally expensive.
    </p>

    <p>
      The escape hatch is the beautiful part: we get value generics for free.
      Not by adding a <code>many</code> keyword, then a <code>different</code>
      keyword, then another keyword for the next axis, but by treating those
      dimensions as compile-time values. A relationship can carry a
      multiplicity value. A type boundary can carry a visibility value. An
      identity rule can carry a sameness value. One generic shape can be
      specialized with those values instead of growing a new syntactic branch
      for every combination.
    </p>

    <p>
      This is the larger Range promise: once meaning is already represented as
      typed identity, value, and relationship, the language can parameterize
      the meaning rather than naming every variation. The programmer sees the
      stable concept; the compiler sees the chosen values. That turns the
      combinatorial field into data that can be inspected, constrained, and
      composed.
    </p>

    <p>
      Which points to the deeper claim: a language at its core needs to be
      fully generic. Genericity should not be a side facility reserved for
      containers and type names, bolted onto a mostly concrete core. The core
      should be able to abstract over every compile-time value that carries
      meaning—types, bounds, identities, capabilities, representation choices,
      and relationships alike. A type is one important value in that field, not
      the border of it.
    </p>

    <p>
      Because there is nothing concrete about semantics. Semantics is not a
      privileged collection of type-shaped objects waiting to be annotated
      with exceptions. It is the structure of relationships: what a value is,
      where it belongs, what it may connect to, how often it may occur, and
      which operations are permitted. A concrete representation comes later,
      when some consumer needs storage, instructions, or an ABI.
    </p>

    <p>
      Then <code>some</code>, <code>any</code>, <code>many</code>, and
      <code>different</code> stop looking like an expanding vocabulary of
      special cases. They become possible values in a shared generic model.
      The language can add a distinction by describing its semantics, not by
      reserving another word and another grammar branch for it.
    </p>

    <p>
      The unified value-generic model is a design direction, not a claim that
      today’s compiler has finished every part of it. The important insight is
      architectural: value parameters let the language absorb new dimensions
      without turning each one into another permanent word.
    </p>

    <p>
      Range’s philosophy points toward a smaller split. Let multiplicity say
      whether a relationship occurs. Let identity and typed relationships say
      what is present and how it can be used. If existentiality becomes part of
      Range, it should arrive as another inspectable relationship and capability
      boundary—not as optionality wearing a more mysterious name.
    </p>

    <p>
      The design is not finished. That is the useful conclusion. Optionality is
      a current, concrete model. Existentiality is a neighboring question that
      the graph-first philosophy makes easier to ask precisely, while refusing
      to pretend it has already been answered.
    </p>
  </section>
</EssayPage>
