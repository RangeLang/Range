# Compiler fork architecture

## Decision

Range compiler development now has one frozen bootstrap authority and one
actively evolving, complete compiler fork:

```text
Compiler A: RangeCompiler/Bootstrap + frozen RangeCompiler source
Compiler B: Projects/RangeCompilerB/Project.range + complete copied source/runtime
```

The duplication is a deliberate bootstrap boundary, not two implementations
that must evolve together. Compiler A exists only to produce the first Compiler
B executable. All subsequent compiler changes belong to B.

Do not copy `RangeCompiler/Bootstrap/` into B. Git history preserves prior A
source checkpoints, while the committed LLVM, executable, and manifest under
`RangeCompiler/Bootstrap/` remain the repository's single accepted authority.

## Compiler B node

Compiler B is one identified compiler-source node whose value includes its
project declaration, Core inventory, Core/Foundation declarations, compiler
implementation, and native runtime:

```text
CompilerB.Source
├── Projects/RangeCompilerB/Project.range
├── Projects/RangeCompilerB/CompilerCoreSources.txt
├── Projects/RangeCompilerB/Sources/Core/**
├── Projects/RangeCompilerB/Sources/Foundation/**
├── Projects/RangeCompilerB/Sources/Compiler/**
└── Projects/RangeCompilerB/Runtime/**
```

Ignored `.range/` and `.build/` directories are rebuildable materializations
and never contribute to this node. RangeView is an independent product node,
not part of Compiler B's source value.

## Primary proof

Self-compilation is B's first acceptance boundary:

```text
accepted Compiler A + CompilerB.Source(R1)
    -> Compiler B candidate

Compiler B candidate + CompilerB.Source(R1)
    -> Compiler B reproduction

candidate LLVM == reproduction LLVM
candidate executable == reproduction executable
```

This is the repository's existing two-build fixed-point rule applied to the B
project. Tiny fixtures remain debugging probes, but they do not replace the
self-hosting proof.

After the fixed point, the exact reproduced B artifact compiles RangeView:

```text
Compiler B reproduction + RangeView source(V1)
    -> RangeView product(P1)
```

That second application tests B against an independent product. It is not the
first proof that B is complete.

## Complete compiler ownership

Compiler B owns the entire compilation request:

```text
project path
    -> file and source gathering
    -> Core/Foundation/framework/product inventory
    -> lexical syntax
    -> declaration/application graph
    -> macro expansion and resolution
    -> CFG and ownership
    -> MIR
    -> LLVM emission
    -> linking
    -> executable product
```

Shell scripts may select A or B and invoke the process, but they must not become
a second semantic compiler. File gathering and source roles move into B's Range
driver rather than remaining a permanent shell-produced source bundle.

## Migration rule

B initially duplicates the complete working compiler, including inherited
tables, body arenas, and lowering code. Those are a runnable baseline rather
than the target design. Replace one vertical phase at a time inside B while A
stays frozen:

1. Move project and file gathering into B.
2. Make typed Source, File, Declaration, Application, Block, and relationship
   values the sole source graph authority.
3. Derive resolution and CFG from those stable identities without reparsing.
4. Derive ownership and MIR as typed products.
5. Emit and link entirely through B.
6. Delete displaced tables, arenas, serialized records, and compatibility
   adapters as each B-owned replacement proves itself through self-compilation.

Buffers or matrices may remain physical storage where useful. Anonymous table
columns must not remain the semantic authority when the graph already provides
typed identity and relationships.

## Commands

```sh
# Complete A -> B -> B fixed-point proof.
scripts/range compiler b
scripts/range check-compiler-b

# Earlier single-file lexical/source-graph component probe only.
scripts/range check-compiler-b-source-graph
```

Promotion remains deliberate and separate. A passing B fixed point does not
automatically replace `RangeCompiler/Bootstrap/`.
