# Macros

## Definition

Macros are compile-time transformations over compiler structures.

## Properties

- Use `#` as the macro marker at the use site

```neat
#lock {
    work()
}
```

- Run entirely at compile time

```neat
#literal("hello")
```

Macros rewrite compiler structures before code generation. They do not add runtime overhead.

- Are declared through ordinary Neat syntax

```neat
macro codable: Attached<Construct> { }
macro lock: Freestanding<Block> { }
```

- Are typed by macro kind

```neat
macro codable: Attached<Construct> { }
macro clamped: Attached<Property> { }
macro lock: Freestanding<Block> { }
macro literal: Freestanding<Expression> { }
```

- Support composition through the existing type system

```neat
macro observable: Attached<Property & Parameter> { }
```

- Split into freestanding and attached phases

```text
Lexer
Parser
Freestanding macros
Type checking / graph construction
Attached macros
Code generation
```

- Expose the compiler structure appropriate to their phase

```neat
macro lock: Freestanding<Block> { block in
    acquire()
    block()
    release()
}
```

```neat
macro codable: Attached<Construct> { construct in
    construct.values
    construct.states
}
```

- Are intended to absorb features other languages special-case separately

```text
@escaping
@autoclosure
variadics
result builders
property wrappers
```

Neat treats these as macro-system problems rather than separate baked-in language features.

## Notes

- Freestanding macros work over syntax-phase compiler structures.
- Attached macros work over resolved type and graph structures.
- The macro system is meant to replace one-off compiler markers with one unified transformation model.
