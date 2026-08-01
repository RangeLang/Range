# Range Architecture

This document records durable language and compiler architecture. Actionable
implementation work remains in [TODO.md](TODO.md).

## Identity and uniqueness

`Identifier` is the language-facing identity of a graph value. It carries a
human name, a canonical stable ID, its direct parent identity, and an optional
source witness. Names are presentation; the stable ID and parent relationship
establish semantic identity.

Identity is structural before it is hashed. `@hashable` derives a stable hash
from the canonical identity representation so graph indexes can find values
quickly. A hash match must still confirm structural identity. Therefore:

- inserting the same identity with the same value is idempotent;
- inserting the same identity with a different value is a conflict;
- different identities may coexist even when their names are equal; and
- a hash collision never makes two identities equal.

Generated identities derive from the producer macro application, its target,
the emitted relationship role, the child ordinal, and the emitted nominal
type. They must not depend on allocation order or reconstructed source text.

## Flat syntax forms

Syntax is represented as one ordered form rather than separate prefix, infix,
postfix, invocation, trailing-closure, and delimiter-specific parser species.
A form contains two kinds of parts:

- an **anchor**, consisting of an introducer or literal and an `Identifier`;
- a **slot**, consisting of a role identity, an enclosure, and a nested syntax
  child.

For example:

```text
@foo(arguments) { body }
```

has the flat part sequence:

```text
anchor("@", foo), slot(arguments, parentheses), slot(body, braces)
```

Likewise, `#environment { ... }` is an anchor followed by one braced slot.
The nested child may initially be freeform `@syntax`; the macro or syntax
declaration attached to the anchor supplies the relationships that interpret
its contents.

Prefix, postfix, infix, and circumfix are projections of anchor position in
the ordered form, not independent syntax kinds:

```text
prefix:     anchor, slot
postfix:    slot, anchor
infix:      slot, anchor, slot
circumfix:  anchor, slot, anchor
```

`()`, `[]`, `{}`, and `<>` are interchangeable enclosure values on slots.
They do not choose the child's identity, cardinality, ordering, separator,
runtime representation, or collection type. Those are independent graph
relationship properties.

This collapses the syntax tree's apparent vertical axis into a flat ordered
graph. A tree remains a useful projection for editors and diagnostics, but it
is not the compiler's authoritative storage model.

## Graph facts and retained compiler products

The graph establishes identity, relationships, observed dependencies, and the
reverse invalidation closure. It does not replace the typed products computed
for a function or syntax value. A graph edge can say that one product depends
on another; it cannot reconstruct resolved bindings, CFG, ownership facts,
MIR, an ABI proof, or emitted LLVM without repeating those computations.

Each specialized function instance therefore owns one immutable, versioned
sequence of compiler products:

```text
syntax -> resolved body -> CFG -> ownership/effects -> MIR -> ABI proof -> LLVM
```

Every product records the exact graph identities and product fingerprints it
observed. A source or contributed-graph change invalidates the first product
whose observations changed and its reverse dependents. Unchanged products are
reused directly; later phases consume the retained predecessor rather than
reparsing source or asking the graph to recreate it.

The graph is consequently the authority for dependency and invalidation, while
typed phase products are the authority for compiled meaning. Graph structure
without a consumer is descriptive data. A retained product without graph-
checked observations is a stale cache. The compiler requires both and must not
conflate them.

Performance measurement follows the same boundary. Every phase reports elapsed
time, product count, cache hits and misses, and its natural units of work. A
cutover is not an optimization merely because data moved into the graph; it is
an optimization only when measured recomputation, memory, or elapsed time falls
without weakening the proof gates.

## Partial values, deltas, and resolution

Incomplete information and intended mutation are different graph values.
Range uses three lifecycle roles:

- `Partial<Value>` describes the fields and relationships currently known
  about a value. An absent relationship means unspecified, not `nil`.
- `Delta<Value>` describes ordered insert, replace, remove, and relationship
  changes against an identified value, together with the producer and the
  observations under which those changes were derived.
- `Resolved<Value>` is a complete, validated value produced by applying an
  accepted delta to its identified base and satisfying the value's required
  relationships.

Explicit `nil` is a present value. Removal is a delta operation. Neither is
represented by absence. This distinction lets defaults fill genuinely missing
information without reviving a removed relationship or overwriting an
explicitly nil value.

Resolution is an atomic compiler phase:

```text
partial base + ordered delta -> validate -> resolved value | typed error
```

The graph retains the partial base, delta provenance, observations, resolved
identity, and error when resolution fails. It does not expose a partially
committed resolved value. Consumers may query a delta before commit, but code
generation consumes only `Resolved` products.

The first compiler-backed adoption is generated macro members. Macro expansion
constructs a named `CompilerGeneratedMemberDelta`; validation resolves its
source spans, placement, target, and identities; commit materializes the
ordinary member only after the complete delta set passes collision and shape
checks. Dense integer storage remains an internal implementation detail during
this cutover, never the phase-facing schema.

## Errors are typed phase products

`@error` marks a construct as an error and requires exactly one member named
`message`; it may carry additional typed context. The first compiler-backed
slice is validation-only: it does not emit syntax, register a graph value,
throw, log, terminate, or render a diagnostic. The general concrete
`Error(message:)` obeys the same contract. Constraining the message to `String`
and exposing error capability constraints are subsequent typed-query work.

Those behaviors remain separate consumers of an error value. A future generic
boundary may constrain its failure value by the capability, while a phase may
retain a richer nominal error with structured fields beyond `message`.

A compiler failure is not a negative integer, a decimal digit packing scheme,
or a late-formatted String. It is a typed product of the phase that discovered
it. The minimum error identity records:

- a stable error ID and nominal kind;
- the phase and operation that failed;
- the syntax, function instance, graph value, or owned path that was the
  subject;
- a source witness when source syntax participated;
- structured expected and observed values;
- an optional causal error identity; and
- the exact dependency observations under which the failure was produced.

Each phase produces an explicit outcome equivalent to
`Result<ProductID, CompilerErrorID>`. Rendering a diagnostic is a projection of
the retained error after compilation stops; it is not the storage model. Error
causes form an ordered causal graph, but—as with successful products—the graph
does not infer or reconstruct the error.

Retained errors are checked by the same invalidation rules as successful phase
products. If none of an error's observed inputs changed, a later compile may
reuse the failure and its diagnostic without rerunning the phase. If an input
changed, the error and its reverse dependents are invalidated. This makes
failure deterministic and cheap while preserving fail-closed behavior.

Sentinel integers remain acceptable only inside a private, bounded algorithm
where the value cannot cross a phase or function-product boundary. Before a
failure leaves that boundary it must be converted into a typed error. Arithmetic
encodings such as `6000 + status`, `operation * 10000 + detail`, and overloaded
negative row IDs are migration targets because they erase domain identity and
make unrelated errors collide.

## Macro anchors

`@` attaches a macro application to existing syntax. `#` materializes a
compile-time value or syntax contribution into the graph. Both use the same
anchor-plus-slots representation; their different authority comes from the
introducer and the resolved macro capability, not from separate parsers.

`#environment { ... }` therefore describes and contributes typed constructs,
functions, relationships, or other graph values. A contributed
`RelationshipRegistration` is queried by type and identity like any other
graph value; it does not require a persistent macro-return side channel.

The compile-time evaluator may still use ordinary ephemeral function return
values while evaluating a macro. The architectural deletion target is only
the separately persisted macro-result channel once every durable result is a
typed graph contribution.
