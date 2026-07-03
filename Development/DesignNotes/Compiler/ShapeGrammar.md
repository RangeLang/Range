# Shape Grammar

## Vision: Substrate, Not Language

Range is a language substrate. The frozen reader supplies one universal
program shape; Range-authored Foundation declarations (Range) supply all
meaning. What users experience as "the Range language" is the substrate plus
the bundled Foundation. Swapping Foundation yields a different language on the
same machinery: a different keyword surface, different operators, different
semantics, all compiled through the same reader, rewriter, expander, and LLVM
emission path.

The `--range-root` seam already expresses this: the script runner (Bash) and
the `range` compiler host (Swift) treat Foundation as a parameter, not a
constant. This document defines the part that is *not* a parameter: the frozen
reader grammar and the boundary between reader knowledge and declared
knowledge.

## The Shape Thesis

Every program is, recursively:

```text
annotation* name (arguments)? { members* }
```

A block, possibly annotated, containing members. Members are themselves
shapes. Arguments are labeled values. That is the entire structural model.
Everything that looks like a keyword, a statement form, an operator, or a type
is a declared interpretation of this shape, not a grammar rule.

## The Boundary Rule

**The reader knows shape. Everything that carries meaning is declared.
No exceptions.**

- The reader layer is frozen, tiny, and declaration-free. It is never
  extended with keyword-like or meaning-like knowledge.
- The rewrite layer is driven entirely by loaded declarations: statement
  sugar, parameter capabilities, operator precedence, and semantics.

This rule exists to prevent creep. Any argument of the form "it would be
simpler to hardcode X in the parser for now" is an argument for leaking
meaning into the reader, and it is rejected uniformly. A keyword that leaks
into the reader is a keyword every future Foundation is stuck with.

Known current violation to migrate: parameter capability names
(`literal`, `name`, `generic`) are matched by hardcoded name in the Range
parser (Swift) rather than resolved from loaded Range-authored capability
macro declarations (Range).

## Frozen Reader Grammar

The reader consists of the Range lexer (Swift, later Range) and a
shape-agnostic parser. It knows only:

1. **Tokens**: identifiers, integer literals, float literals, string
   literals, bool literals, punctuation (`@ ( ) { } [ ] , : .`), operator
   characters, newlines.
2. **String literals**: quoting and escape rules are reader-owned. Escapes
   are fixed here and never declared.
3. **Annotations**: `@name` optionally followed by a balanced `(...)`
   argument clause, optionally followed by a `{...}` block.
4. **Argument clauses**: comma-separated `label: value` pairs. A value is a
   literal, an identifier, an annotation invocation, or a flat expression
   run.
5. **Blocks**: `{ ... }` containing members. Members are statements.
6. **Statement boundaries**: a statement ends at a newline unless the line
   is inside unbalanced `(`, `[`, or `{`. Line-scoped declarations remain
   the rule (one declaration begins on one physical line).
7. **Raw statements**: a statement that is not an explicit `@` invocation is
   kept as a raw, balanced token sequence. The reader does not interpret it.
8. **Flat expression runs**: sequences of operands and operator tokens are
   parsed flat, in source order, with no precedence applied. The reader
   never builds operator trees.

The reader does not know `let`, `if`, `while`, `main`, `int`, or any other
name. It does not know what `+` binds like. It produces token trees, raw
statements, and flat runs.

## Rewrite Layer

After Foundation declarations are loaded, the rewrite layer runs:

1. **Statement pattern matching**: each macro declaration may carry a
   surface pattern (the `@syntax` mechanism). Raw statements are matched
   against declared patterns and rewritten into canonical macro invocation
   form. Example: `let count: @int(5)` rewrites to
   `@let(name: count, value: @int(5))`.
2. **Expression folding**: flat operator runs are folded into trees using
   precedence declared on Foundation operator declarations.
3. **Expansion**: canonical macro invocations expand as they do today.

Canonical form is always valid input. Sugar is a projection over canonical
form, never a requirement. The self-hosted compiler may be written in pure
canonical form before the rewrite layer is ported.

Rewritten nodes must preserve original source spans so diagnostics point at
authored code, not desugared code.

### Splice Templates

Surface patterns are not a separate pattern mini-language. A `@syntax`
template is Range code with splices, evaluated in the compile-time runtime
with `self` bound to the declaration node:

```range
@syntax {
    function #(self.name)(@for param in self.parameters {
        #(param.name): #(param.type)
    } separator: ", "): #(self.result) #(self.body)
}
```

One template serves both directions:

- **Printing** (canonical -> sugar): evaluate the template forward. Any
  template can print.
- **Parsing** (sugar -> canonical): the template is statically compiled to a
  matcher. Literal text matches literally, member splices become captures,
  and `@for` over a member collection with a fixed separator becomes
  repetition (split on top-level separators; each match derives one member).

Parsing requires the **invertible subset**: literal text, direct member
splices, and `@for` over member collections with fixed separators. Splices
containing computation (string transforms, conditionals on derived values)
are lossy and therefore print-only. Because the compile-time runtime is
static and total, every template is classified invertible or print-only at
declaration-load time; using a print-only template where parsing is required
is a load-time error, not programmer discipline.

The invertible requirement applies only at the entry door: fresh authored
text has no provenance, so structure must be recoverable from the text
alone. Views rendered from already-committed nodes retain their mapping
edges, so even print-only templates support edit-propagation there.

Other matching rules:

- Captures are structural, never semantic. Matching never requires type
  information or macro evaluation.
- Two templates matching the same raw statement is a hard error at match
  time. There is no silent precedence between templates.

## Two Runtimes

Range has two execution contexts with different contracts:

1. **Compile-time runtime**: where macro bodies and syntax templates
   execute. It must be *static*: deterministic, terminating, closed over
   its declared inputs (source text plus pinned Foundation), and free of
   I/O. Determinism is what makes the stage1 == stage2 fixpoint test
   meaningful, and a small closed evaluator is what the Range-authored
   compiler (Range) can faithfully reimplement.
2. **Program runtime**: the compiled binary. All dynamic behavior (real
   memory, libc calls, file I/O) lives here.

Host concerns such as reading project files belong to the driver, which
passes contents *into* the compile-time runtime as inputs. Every capability
added to the compile-time runtime is a capability stage1 must reimplement,
so its surface is part of the freeze.

## Nothing Is Discarded

Every pipeline stage derives; no stage rewrites in place. Desugaring derives
canonical nodes with edges back to the authored form. Expansion derives
artifacts alongside the invocation. Authored text, canonical form, expanded
form, and emitted artifacts coexist in the graph, linked by provenance
edges.

This makes compilation itself fit the language's reactivity model: sources
are state, every downstream form is derived, and an edit invalidates along
retained edges. The self-hosted compiler should eventually be written using
Range's own reactivity primitives.

Stage0 does not build an incremental engine. It batch-recomputes everything
on every run, but it must preserve the invariants that make incrementality
possible later, because they are cheap now and unretrofittable:

- expansion and desugaring derive rather than mutate
- every derived node carries provenance edges to what it came from
- source spans survive every transformation
- every node retains the path facts (container chain, kind, name) needed to
  compute a stable identity later
- transient identity never influences emitted output; anything that reaches
  emitted text is deterministically generated

### Node Identity

Identity is two-phase, in the style of SwiftData object identity:

- **Committed**: a saved, settled node has a stable identity derived from
  its declaration path (container chain + kind + name), not from its
  content. Editing a node's body preserves its identity so downstream
  derivations invalidate instead of orphaning.
- **Limbo**: a node in an actively edited, unsaved buffer has a transient
  UUID. On commit, the limbo identity is promoted and all edges bound to it
  are rebound to the stable identity. A rename is a new stable identity plus
  a retained renamed-from provenance edge, not identity loss.

Granularity: declarations get fine-grained path-derived identity; statement
sequences inside bodies get coarse identity (a body edit invalidates the
body's derivations wholesale). Statement-level identity is a post-fixpoint
question.

Why stable identity exists at all: within one run, transient identity plus
consistent references is sufficient. Stable identity is needed to *match*
nodes across runs and edits, because incremental reuse is a join between
the old graph and the new one, and a join needs a key computable
independently from both sides. The path is that key; a fresh UUID cannot
be.

Stage0 batch-compiles, so neither limbo identity nor cross-run matching is
observable during bootstrap. Internally, transient identity is fine. What
stage0 must guarantee is only the two invariants above: path facts are
retained on every node, and transient identity never leaks into emitted
output (which would break the byte-identical fixpoint test). The stable
identity function itself can be introduced with the incremental engine.

## Operator Precedence

Precedence is declared on Foundation operator declarations, not stored in a
Swift-side table. The flat-parse/fold-later split makes this well-founded:
loading declarations never requires folded expression trees, so Foundation
parses before any precedence exists, and one fold pass runs after loading
completes.

### Derivation

The bundled Foundation's precedence values are not convention; they are
forced by treating expressions as layered algebras:

1. **Arithmetic algebra** operates on numbers. Product binds tighter than
   sum (PEMDAS): `*` `/` `%` above `+` `-`.
2. **Comparisons** are the bridge: they consume finished numbers and produce
   booleans, so they sit below all arithmetic.
3. **Boolean algebra** operates on booleans. The same product-over-sum law
   applies: `&&` (intersection) above `||` (union). Comparisons are the
   atoms of this layer, so they bind tighter than `&&`.

Resulting pinned table, tightest first:

| Level | Operators | Associativity |
| --- | --- | --- |
| 1 | member access `.`, call `()`, index `[]` | left |
| 2 | unary `-`, `!` | prefix |
| 3 | `*` `/` `%` | left |
| 4 | `+` `-` | left |
| 5 | `<` `<=` `>` `>=` | left |
| 6 | `==` `!=` | left |
| 7 | `&&` | left |
| 8 | `||` | left |

Additional pinned rules:

- Comparisons do not chain: `a < b < c` is a hard error.
- Unary minus binds above `*`: `-a * b` is `(-a) * b`.
- New operators declared post-fixpoint slot into existing levels; they do
  not define new levels. This keeps reading decidable without loading
  declarations.

## Declared Is Not Mutable During Bootstrap

The freeze applies to which Foundation ships, not to where knowledge lives.

- Stage0 (the Range compiler host, Swift) always loads the pinned Foundation
  from `RangeCompiler/Range/Foundation`.
- Sugar patterns, capabilities, and precedence are declared content inside
  that pinned Foundation. They are data, but they are frozen data.
- Project source cannot redefine sugar, capabilities, or precedence during
  bootstrap, simply because Foundation is pinned. No additional enforcement
  machinery is required.

## Stage Definitions

- **stage0**: Range compiler host (Swift) plus pinned Range-authored
  Foundation (Range). Frozen once stage1 compiles. Improvements after the
  freeze go into Range code, not the Swift host.
- **stage1**: Range-authored compiler (Range), compiled by stage0.
- **stage2**: the same compiler source, compiled by stage1.

Self-hosting is proven when stage1 and stage2 emit byte-identical LLVM IR
for the compiler's own source. That fixpoint is the permanent regression
gate.

## Explicitly Post-Fixpoint

These doors exist by design but are not opened during bootstrap:

1. **User Foundations**: pointing `--range-root` at a third-party Foundation
   to host a different language surface and semantics on the substrate.
2. **Replaceable reader**: per-Foundation reader replacement (the door to
   non-shape surface syntax, such as recreating C's exact notation). The
   substrate ships with exactly one fixed reader until after the fixpoint.
3. **Declared operator sugar**: user-defined operators slotting into the
   pinned precedence levels.
4. **Incremental compilation**: the reactive recompute engine over the
   retained derivation graph. Stage0 only preserves its invariants.
5. **Limbo identity**: transient editing identity and promotion-on-commit,
   needed once an editor/LSP holds unsaved buffers.
6. **Print-only templates**: declared formatting views over committed nodes
   that need not be parseable.

## Known Debt Against This Design

- The pipe-delimited macro payload strings (`value|construct=...`) have no
  escaping and cannot survive arbitrary source text as data. They must be
  replaced or escaped before a Range-authored lexer (Range) can process real
  Range source.
- Statement/expression source carried as escaped strings inside
  Range-authored Foundation macros (Range) (`@state(name: llvm, value:
  "\"...\" + name")`) should become real expression arguments.
- Parameter capability resolution is hardcoded in the Range parser (Swift)
  instead of read from loaded capability declarations.
- The compile-time evaluator (Swift) currently performs filesystem and
  project reads (`evaluateFileSystemCall`, `evaluateRangeProjectCall`)
  inside macro evaluation, violating the static compile-time runtime
  contract. These should become driver-provided inputs.
