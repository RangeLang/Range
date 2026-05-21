# Zero Zero Days

Range's security story is not that a language can promise zero unknown vulnerabilities. It is that many zero-days begin as behavior the language did not make explicit enough for the compiler, tools, or reviewer to see.

## Feature

Range turns security-relevant intent into graph structure.

The goal is to reduce the number of places where dangerous behavior can hide behind ordinary-looking code.

## Example

```range
construct Editor {
    state document: Document
    binding selection: Selection

    derived title: String {
        return document.title
    }

    function rename(title: String) {
        document.title = title
    }
}
```

Those facts are not comments, framework conventions, or runtime guesses. They are the semantic shape of the source.

## Reason

Zero-days usually begin in a gap between what the code appears to mean and what the system actually allows.

Memory safety is one version of that gap. A value looks fixed, but can still be mutated through another path. A reference looks local, but escapes. Work looks sequential, but shared state moves across a concurrent boundary.

The same shape appears outside memory: trust boundaries, host behavior, generated code, and permissions can all become security risks when they live in convention instead of the program model.

Range tries to make those boundaries visible early enough for the compiler to check them, not late enough for a bug report to explain them.

Fewer hidden edges means fewer places for a zero-day to begin.
