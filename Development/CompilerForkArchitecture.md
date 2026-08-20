# Compiler fork architecture

## Decision

Range compiler development has one accepted bootstrap authority and one
greenfield compiler under active development:

```text
Compiler A: accepted bootstrap and frozen reference implementation
Compiler B: minimal B-owned compiler grown through runnable slices
```

The committed LLVM, executable, and manifest under `RangeCompiler/Bootstrap/`
remain the repository's single accepted compiler authority. That accepted
Compiler A builds the current Compiler B executable. Compiler A does not
produce syntax, tables, arenas, or later compiler products for B to consume.

Compiler A source is frozen by default. Compiler B must not copy A's compiler
tree or migrate A's internals phase by phase. Git history and the live A source
remain available as references when B needs to understand proven behavior.

## Compiler B node

Compiler B is the current minimal project rooted at
`Projects/RangeCompilerB/`:

```text
CompilerB.Source
├── Project.range
├── CompilerCoreSources.txt
├── Sources/CompilerB/**
├── selected low-level Sources/Core/** dependencies
└── Runtime/**
```

It deliberately does not contain a copied `Sources/Compiler/` tree or a copied
Foundation. Add a source only when a runnable B slice requires it. Ignored
`.range/` and `.build/` directories are rebuildable materializations and never
contribute to the compiler-source value.

RangeView is outside the active Compiler B plan. It may become an independent
product proof later, but it does not drive the current lexer/parser slices.

## Development rule

Grow B one executable capability at a time:

```text
accepted Compiler A + current B sources
    -> runnable Compiler B slice

runnable Compiler B slice + focused input
    -> exact asserted product
```

Each slice has one bounded product and one focused check. A passing slice proves
only that product. It is not self-hosting, fixed-point, full-language, or
promotion evidence.

The active checkpoint is self-source lexical and syntax correctness:

1. Retain tokens with typed identity and source ranges.
2. Treat strings and comments as lexical regions so braces and declaration-like
   text inside them cannot become syntax.
3. Make the parser consume retained tokens rather than rescan raw source.
4. Parse B's own `Main.range` and `Lexer.range` and assert their exact expected
   top-level declaration and Block nodes.

The current coarse parser already prints function and Block rows for both files.
That observation is a baseline, not completion of this checkpoint, because the
lexer/parser is not yet string- or comment-aware and does not retain token
identity.

## Long horizon

Self-hosting remains a later acceptance milestone, not the current edit loop.
B must first acquire the required compiler products through runnable slices:

```text
source files
    -> retained tokens
    -> syntax identities and relationships
    -> resolution
    -> CFG and ownership
    -> MIR
    -> LLVM and linking
```

Only when B can compile the relevant language surface does the fixed-point rule
apply:

```text
accepted compiler + CompilerB.Source(R1) -> candidate
candidate + CompilerB.Source(R1)         -> reproduction
```

Candidate/reproduction LLVM and executables must compare byte for byte before a
B checkpoint can be described as self-hosting. Promotion remains separate and
requires explicit maintainer approval.

## Compiler A escape valve

An A change is allowed only when all of the following are true:

1. A focused fixture reproduces a concrete accepted-Compiler-A limitation that
   blocks the next B slice.
2. The required capability cannot be implemented inside B or behind B's
   primitive runtime boundary without violating the intended architecture.
3. The proposed A change is the smallest general capability that removes the
   blocker, not a B-specific name or fixture special case.
4. The maintainer explicitly approves the A change and its bootstrap promotion
   before B depends on it.

Without that evidence and approval, A stays frozen and work continues inside B.

## Current commands

```sh
# Focused runnable B proof: file routes and IO, lexer output, and syntax rows.
scripts/range check-compiler-b

# Run the accepted-A-built B executable against one file or directory route.
scripts/run-compiler-b-bootstrap <route>
```

Neither command currently proves A -> B -> B reproduction or a Compiler B
fixed point.
