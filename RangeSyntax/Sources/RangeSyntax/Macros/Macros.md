# Macros

## Definition

Macros are compile-time transformations over compiler structures.
They declare the syntax target they apply to directly, for example `: Expression`,
`: Block`, `: Parameter`, or `: Init`.

## Properties

- Use `#` for call-style macro use sites

```range
#lock {
    work()
}
```

- Run entirely at compile time

```range
#stringify("hello")
```

Macros rewrite compiler structures before code generation. They do not add runtime overhead.

- Are declared through ordinary Range syntax

```range
macro codable(): Construct { }
macro lock(): Block { }
```

- Are typed by direct target syntax kinds

```range
macro codable(): Construct { }
macro clamped(min: Int, max: Int): State { }
macro lock(): Block { }
macro literal<T>(): Function { }
macro stringify(@capture<Expression> _ value: Expression): Expression -> String { }
```

- Support composition through the existing type system

```range
macro observable(): Property { }
```

- Run as syntax rewrites before semantic validation trusts their result

```text
Lexer
Parser
Macro expansion
Type checking / graph construction
Code generation
```

- Expose the compiler structure appropriate to their phase

```range
macro lock(): Block { target, diagnostics in
    target.rewrite({
        acquire()
        target()
        release()
    })
}
```

```range
macro codable(): Construct { target, diagnostics in
    target.values
    target.states
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

Range treats these as macro-system problems rather than separate baked-in language features.

## Notes

- Expression-targeted and block-targeted macros are invoked at explicit `#macro`
  use sites.
- Declaration-targeted macros such as `: Parameter`, `: Construct`, and `: Init`
  rewrite the declaration surface they are attached to.
- For `: Init`, direct attachment to a concrete initializer is the base model.
  Protocol requirements may carry the same macro onto satisfying initializers.
- The macro system is meant to replace one-off compiler hooks with one unified transformation model.
