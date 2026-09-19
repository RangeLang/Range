<div align="center">

<a href="https://rangelang.org">
  <img src="https://rangelang.org/og-homepage.png" alt="Range — a love letter to electrons, logic and abstraction" width="100%">
</a>

# Range

### An applied programming language

[Website](https://rangelang.org) · [Introduction](https://rangelang.org/posts/intro-to-range) · [Benchmarks](https://rangelang.org/benchmarks)

</div>

Range is a native programming language for describing software as a typed
graph. Identity, value, access, ownership, and transformation remain connected
in one program model instead of being recovered from syntax and scattered
across unrelated compiler representations.

Range is about the architecture of a program as much as its execution: what a
value is, which identity it belongs to, how it may be reached, and what is
allowed to transform it.

## Why Range

- **One connected program model.** The same typed graph carries declarations,
  values, relationships, ownership, and execution.
- **Typed metaprogramming.** Macros query program identities and relationships,
  receive only the environment they are allowed to observe, and return graph
  transformations rather than rewriting an untyped token stream.
- **Native output.** The C compiler is being built to lower the Range program
  graph directly to ARM64 machine code and Mach-O artifacts.
- **Core-defined semantics.** Core constructs and macros describe the graph
  facts consumed by lowering instead of relying on compiler name checks.

## Identity : Value

Range begins with one base concept: **Identity : Value**. Lowering may represent
identity and value separately, but the language does not confuse a value with
the question of *which* value it is.

That distinction lets Range describe mutation, sharing, ownership, and
specialization as relationships in the graph rather than conventions layered
on top of it.

## A small concrete language

The concrete substrate is intentionally compact:

- `construct` describes composed values.
- `enum` describes alternatives.
- `function` describes behavior between them.

Properties state their storage and access relationship directly. `let` is
immutable storage, `state` is mutable storage, `binding` is projected access,
and `derived` is computed access.

```range
construct Counter {
    let seed: Int
    state count: Int

    derived total: Int {
        seed + count
    }
}

function clamp(let value: Int, let min: Int, let max: Int): Int {
    if value < min { return min }
    if value > max { return max }
    return value
}
```

Richer ideas are composed from these few explicit forms instead of requiring a
new language construct for every programming pattern.

## The language can see itself

A Range macro receives typed program structure, queries the environment it has
authority to observe, and returns a transformed execution graph. Macros work
with declarations, members, identities, and relationships—not a separate
untyped representation hidden from the rest of the language.

The long-term aim is for frameworks, the compiler, editor intelligence, and
program transformations to speak about the same graph as ordinary Range code.

## Core in Range, compiler in C

Range's language model lives in `Language/Grammar`, `Language/Macros`, and
`Language/Types` as Range constructs and macros.
Structural syntax is defined directly in C; grammar constructs and `@literal`
patterns remain in Range. The compiler is implemented in C under `Language/Compiler`. It parses Core,
builds the queryable program graph, resolves supported Core macro queries, and will encode target
artifacts directly as bytes. LLVM and the former generated bootstrap chain are
not part of the current architecture.

## Project status

Range is early language infrastructure under active development. The current C
compiler has a lexer, parser, and Core-backed graph resolver. Parsing and graph
shapes live in C; runtime-loaded compiler templates and the old interpreter are
retired. Native machine-code emission remains the next milestone. No seed or
self-compilation verification is required for normal iteration.

Build it with:

```sh
Language/Compiler/Tools/build-range-compiler /tmp/range-compiler
/tmp/range-compiler Language/Grammar Language/Macros Language/Types
```

The focused compiler checks are:

```sh
Testing/Tools/check-compiler-parser
Testing/Tools/check-compiler-graph
Testing/Tools/check-compiler-literal
```

Editor navigation can be checked with `Testing/Tools/check-range-editor-navigation`.
The build discovers C sources directly from `Language/Compiler/Source`, and the
compiler discovers every Range source under each supplied directory.

Earlier Core definitions are preserved in `Development/DeferredCore`. Old
project declarations, compiler tests, runtime support, and benchmark programs
are in `Development/DeferredCompiler`. Saved benchmark data remains available
to the website and describes the former compiler.

A passing focused proof establishes only its documented boundary. It is not a
claim that every later compiler gate or intended language feature is complete.

## Explore and contribute

- Read the [introduction to Range](https://rangelang.org/posts/intro-to-range).
- Inspect the reproducible [native benchmarks](https://rangelang.org/benchmarks).
- Explore the C compiler, Core declarations, and focused fixtures in this
  repository.
- Use [GitHub Issues](https://github.com/RangeLang/Range/issues) for bugs,
  focused proposals, and questions about contributing.

Range welcomes careful experiments, bug reports, documentation improvements,
and focused compiler proofs. Because the language is evolving, verify a
capability against the live implementation and its supported
fixtures before relying on design material or examples from another branch.

## License

Copyright 2026 Giorgi Tchelidze.

Range is licensed under the [Apache License, Version 2.0](LICENSE).

## Trademarks

The Range name and logo are trademarks of Giorgi Tchelidze. The Apache License
does not grant permission to use these marks except as required for reasonable
and customary use in describing the origin of the software.
