# Bend, Bend2, HVM2, and HVM4 research for Range

## Decision

Range should study the Bend/HVM lineage as evidence that the representation of
computation can expose more useful parallelism than a conventional instruction
stream. We should not describe Bend as generally faster than C, adopt an HVM
runtime wholesale, or add a second evaluator beside Range's typed graph, CFG,
and MIR pipeline.

The transferable idea is narrower and stronger: begin with one requested
product, discover its reachable dependency graph, share repeated work by stable
identity, describe the remaining work as local interactions with explicit
effects, prove that independent interactions commute, and then schedule the
ready frontier over the available machine without changing program meaning.

LLVM remains a possible target backend. Range should own the semantic graph,
work discovery, ordering constraints, memory/lifetime facts, optimization
products, and parallel schedule before target lowering.

## Claim audit

The official sources reviewed on 2026-08-11 do not establish that Bend is
generally 2,000 times faster than C.

The strongest documented HVM2 throughput claim is scaling from approximately
400 million interactions per second on one Apple M3 Max thread, to 5.2 billion
on 16 M3 Max threads, to 74 billion on an NVIDIA RTX 4090. Those figures measure
HVM interactions, not equal end-to-end implementations of a general workload in
Bend and optimized C. They also cross different processors. The paper calls its
benchmarks and translations sections unfinished.

The Bend repository reports its immutable-tree bitonic sorter at 12.15 seconds
with the sequential Rust evaluator, 0.96 seconds with the parallel C evaluator,
and 0.21 seconds with the CUDA evaluator. This demonstrates scaling across Bend
runtimes and hardware; it is not a comparison against an equivalently tuned C or
CUDA implementation of the same algorithm.

The correct statement for Range is therefore:

> HVM2 reports near-linear interaction throughput scaling on sufficiently
> parallel graph workloads. Bend demonstrates that a high-level source language
> can expose that parallelism without explicit user-managed threads. Neither
> source establishes a universal speed advantage over optimized C.

Primary sources:

- [HVM2 paper](https://docs.rs/crate/hvm/latest/source/paper/PAPER.pdf)
- [HVM2 repository](https://github.com/HigherOrderCO/HVM2)
- [Bend repository and speedup example](https://github.com/HigherOrderCo/Bend)

## Bend2 and HVM4 update

Bend2 is a new implementation, not a version label for the public Bend/HVM2
codebase. As of 2026-08-11, its public
[repository](https://github.com/VictorTaelin/Bend2) is an empty WIP placeholder,
so its compiler, type/proof system, GPU backend, and performance claims cannot be
audited from public source. The public benchmark repository references a
`bend2-ts` repository which is also not publicly available. Bend2 results must
therefore not be inferred from Bend1 or HVM2 measurements.

The public and inspectable substrate associated with Bend2 is
[HVM4](https://github.com/HigherOrderCO/HVM4). Its README explicitly labels the
project pre-launch. Its current public implementation and documentation reveal a
material architectural change from the HVM2 paper:

- HVM2 reduces all available redexes ultra-eagerly. HVM4 returns to optimal lazy
  evaluation: duplication happens incrementally and only demanded layers are
  expanded.
- HVM4 uses duplications and superpositions as dual graph forms. Together they
  preserve sharing even when a lambda is duplicated, avoiding repeated work
  inside the lambda body.
- Static book terms and dynamic heap terms have distinct lifetimes. An `ALO`
  term bridges them by expanding only one demanded layer of a static definition
  into mutable dynamic storage.
- Every HVM4 term is represented as one 64-bit word with tag, metadata, and
  payload fields. This replaces the 32-bit-port limits described by the HVM2
  paper and gives native constructors, pattern matching, equality, lazy
  allocation, and substitution explicit representations.
- Variables remain affine and graph links resolve substitutions directly through
  heap cells. Demand, sharing, and lifetime are represented by the graph rather
  than recovered as unrelated optimizer analyses.

HVM4's current public README builds one C implementation with `clang -O2`. The
public tree does not yet document a released Bend2 compiler or a GPU backend
whose performance can be reproduced. The correct status is therefore
architecturally inspectable, performance-unproven for Bend2.

Additional primary sources:

- [HVM4 optimal lazy interaction calculus](https://github.com/HigherOrderCO/HVM4/blob/main/docs/theory/interaction_calculus.md)
- [HVM4 64-bit memory model](https://github.com/HigherOrderCO/HVM4/blob/main/docs/hvm/memory.md)
- [HVM/Bend benchmark inventory](https://github.com/HigherOrderCO/bench)

## Why it can be dramatically faster

### Computation is a graph rewrite, not an instruction stream

HVM2 lowers a program into an interaction net. An active pair, or redex, is a
small piece of graph that can be rewritten locally. Independent redexes do not
need a global program counter or a user-authored thread schedule.

Interaction combinators are strongly confluent: the order in which independent
redexes are reduced does not change the final result or total semantic work.
That property is the foundation of the parallel schedule. HVM2 is not discovering
parallelism after lowering sequential code; its execution representation already
contains the independent work.

### Synchronization is confined to graph linking

A worker owns the trees in its active pair. Allocation and most rewriting are
local to that worker. Outgoing wires are joined through a small atomic linking
operation. The runtime therefore avoids placing a lock or global transaction
around each high-level operation.

CPU workers keep local redex bags and steal older redexes from another worker
with a lightweight atomic exchange. GPU workers share work within blocks using
shared memory and warp operations, limiting expensive global synchronization.

### Representation is compact and uniform

The paper's current architecture uses a 32-bit tagged port and represents a
binary node as two ports in 64 bits. Nodes, substitutions, and active pairs live
in flat buffers. Names and definitions are indexes rather than repeated strings
or heap objects. Native numbers are unboxed into tagged ports.

This matters as much as parallelism: a local rewrite loads a tiny fixed shape,
creates a few tiny values, and links the result. HVM2 uses a linear bump allocator
for these uniformly small allocations.

### Linearity makes lifetime local

Interaction nets are linear. Eraser interactions consume unreachable subnets as
part of ordinary evaluation, so the model does not require a later global tracing
garbage-collection pass. Allocation, use, and erasure are graph behavior rather
than unrelated runtime bookkeeping.

### Locality is preserved before work is shared

The GPU evaluator attempts to keep reductions local and exposes unresolved
outgoing values as future-like links only when other blocks need them. The paper
reports one locality change increasing a stress-test result from roughly 13,000
to 54,000 million interactions per second. This is an example of an optimization
owned by the computation substrate, not recovered by a conventional backend.

### Source shape determines the available speedup

Bend does not make a sequential dependency parallel. Its documentation contrasts
a linear recursive sum with a divide-and-conquer sum whose two recursive halves
are independent. The language/runtime combination makes the latter parallel
without thread syntax, but the program must still contain independent work.

An expert can encode the same algorithm and schedule in C or CUDA. Bend's claim
is about making that execution model the natural consequence of source meaning,
not about producing instructions more fundamental than machine code.

## Important limitations

HVM2's own paper identifies material limitations:

- Single-core HVM2 is reported around five times slower than GHC at baseline,
  with much larger gaps possible for loops and mutable arrays.
- Ultra-eager reduction can allocate unused branches and cannot directly handle
  infinite structures; some recursion must be translated through lazy global
  references.
- The current single-duplicator model restricts some higher-order duplication.
  General bookkeeping is described as possible but approximately ten times
  slower in the cited design.
- Algebraic data types are lambda-encoded in the paper's implementation, with a
  reported two-to-five-times memory overhead because native constructors are
  absent.
- The 32-bit tagged representation limits address space and provides only
  24-bit integer and reduced-precision float payloads.
- The official Bend repository warns that current single-core performance may
  be lower and that its code generation remains immature.

These constraints are not footnotes. They explain why interaction throughput
cannot be treated as a universal application-performance result.

## What transfers into Range

### One graph, not a parallel evaluator beside the compiler

Range already treats declarations, applications, control flow, ownership, and
products as graph facts. The HVM lesson is to make executable work a query over
that same substrate. We should not parse Range into an unrelated interaction-net
interpreter and create another semantic authority.

The Bend2/HVM4 correction is that this query must be demand-driven. Range should
begin at the requested product identity and discover only its transitive
dependencies. A ready operation outside that closure is irrelevant and must not
run merely because it could run.

For each Range transformation, the graph should make these facts explicit:

- stable operation identity;
- required input identities;
- output identity or slot;
- read and write regions;
- ownership consumed, borrowed, produced, or erased;
- ordering edges that make two operations dependent; and
- a proof or validation rule for when two ready operations commute.

An operation is ready when every required input exists and no ordering edge
prevents its execution. The scheduler may execute ready, commuting operations in
any order. Deterministic artifacts remain a validation requirement even when the
physical schedule differs.

### Range-owned optimization

Range should optimize this graph before LLVM:

- eliminate duplicate derivations by output identity;
- avoid deriving products outside the requested output's dependency closure;
- retain completed products instead of reparsing source;
- fuse adjacent local transformations when their identity/effect proofs permit;
- keep work near the data and graph region that produced it;
- represent unresolved cross-region values as explicit dependencies rather than
  blocking a whole phase;
- allocate transient, uniformly shaped graph products in region or bump storage;
  and
- erase products at the lifetime boundary proven by ownership.

LLVM may then lower an already optimized schedule at `-O0`. An optional LLVM
optimization profile can measure backend contribution separately, but it must
not be credited as a Range architectural gain.

### Candidate Range workloads

The first experiments should use workloads whose relationships already exist:

1. Compiler function-product derivation: independently ready resolution, CFG,
   ownership, and MIR work across functions and closed specialization groups.
2. RangeView matrix layout: independent cells, layers, shape styling, and drawing
   products with explicit composition edges.
3. RangeView drawing: independent shape tessellation and layer preparation before
   ordered composition.

The compiler experiment should come first because it directly attacks the
current several-minute raw `-O0` compiler-production boundary.

## Required experiment before architectural adoption

Build a sequential, demand-driven Range-native reducer over the existing typed
graph. It must not introduce a second parser, IR authority, or evaluator. For one
bounded compiler product:

1. Start with one requested output identity and derive its reachable dependency
   closure from existing typed facts.
2. Materialize operation identities plus dependency and effect edges only for
   that closure.
3. Execute its ready frontier sequentially, sharing repeated derivations by
   output identity, and prove byte-identical output against the current product.
4. Record reachable and avoided operations, useful operations, duplicate
   attempts, node visits, bytes allocated, peak live bytes, wall time, and
   maximum RSS.
5. Add parallel frontier scheduling only after sequential product equality.
6. Measure one, two, four, eight, and available-core execution with LLVM `-O0`
   and a fixed runtime.
7. Report speedup and parallel efficiency alongside absolute time. Never report
   interaction throughput alone as an application speedup.

Success means the Range-owned graph representation reduces raw work or scales
the same semantic work while preserving deterministic products. It does not mean
reproducing an HVM marketing ratio.
