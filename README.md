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
- **Native output.** The supported compiler is authored in Range and emits
  LLVM for native execution.
- **A reproducible compiler authority.** A compiler checkpoint is accepted only
  when the accepted compiler builds a candidate and that candidate rebuilds
  the same source into byte-identical LLVM and a byte-identical executable.

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

function clamp(value: Int, min: Int, max: Int): Int {
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

## Written in Range

The supported compiler is authored in Range and emits native LLVM. Compiler
changes are proven with one two-build fixed-point check:

```text
accepted compiler + source -> candidate
candidate + same source -> reproduction
```

Candidate and reproduction LLVM and executables must match byte for byte.
There is one rolling compiler authority under `RangeCompiler/Bootstrap/`; Git
history preserves older checkpoints without turning them into competing
authorities.

## Project status

Range is early, self-hosting language infrastructure under active development.
The compiler parses and reasons about real Range programs, executes typed
macros, models ownership and graph relationships, and emits native code. The
supported language surface remains deliberately bounded: focused fixtures
prove individual capabilities rather than implying a complete language or
standard library.

Repository branches may represent different compiler generations. Run the
branch's command index to see its supported workflows:

```sh
scripts/range
```

Two shared compiler-maintenance proofs are:

```sh
scripts/range check-build-plan
scripts/range check-compiler-candidate
```

A passing focused proof establishes only its documented boundary. It is not a
claim that every later compiler gate or intended language feature is complete.

## Explore and contribute

- Read the [introduction to Range](https://rangelang.org/posts/intro-to-range).
- Inspect the reproducible [native benchmarks](https://rangelang.org/benchmarks).
- Explore the compiler, Core declarations, and focused fixtures in this
  repository.
- Use [GitHub Issues](https://github.com/RangeLang/Range/issues) for bugs,
  focused proposals, and questions about contributing.

Range welcomes careful experiments, bug reports, documentation improvements,
and focused compiler proofs. Because the language is evolving, verify a
capability against the live Range-authored implementation and its supported
fixtures before relying on design material or examples from another branch.

## License

Copyright 2026 Giorgi Tchelidze.

Range is licensed under the [Apache License, Version 2.0](LICENSE).

## Trademarks

The Range name and logo are trademarks of Giorgi Tchelidze. The Apache License
does not grant permission to use these marks except as required for reasonable
and customary use in describing the origin of the software.
