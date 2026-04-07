# Core Attribute

## Definition

`@core` marks foundational declarations whose implementation boundary is supplied by the compiler, runtime, or backend.

## Role

`@core` keeps `construct` available as the single concrete declaration form while still giving the standard library and compiler a way to declare non-identity-bearing types such as `Int`, `Closure`, and `Block`.

`@core` may also mark top-level functions whose bodies are primitive operations supplied outside ordinary Neat source, such as scalar operator functions.

## Mental Model

`construct` remains identity-bearing by default.

`@core construct` is the exception for compiler-recognized non-identity constructs:

- plain value semantics
- no memory-graph identity
- eligible for special lowering
- still allowed to define behavior in Neat itself

`@core` is not a general replacement for declaration kinds, and it does not apply to `enum` or `protocol`.

## Properties

- `@core` may be applied only to `construct` and top-level `function`.
- `@core construct` declarations are non-identity-bearing.
- `@core construct` declarations compose as plain value data.
- `@core construct` declarations may still declare fields, conformances, generics, and behavior.
- Members inside an `@core construct` may omit bodies when the operation is supplied by the compiler, runtime, or backend.
- Top-level `@core function` declarations may omit bodies when the operation is supplied by the compiler, runtime, or backend.
- `@core` exists for foundational language types and compiler-exposed structural constructs, not ordinary domain modeling.
- `@core construct` does not inherit from other constructs.

## Examples

```neat
@core
construct Int<value bits: IntLiteral, value signedness: Signedness = .signed>: ExpressibleByIntLiteral {
    value storage: IntStorage
}
```

```neat
@core
construct IntLiteral { }
```

```neat
@core
construct Closure {
    value body: Block
}
```

```neat
@core
construct ArrayStorage<Element> {
    init()
    derived count: Int
    derived isEmpty: Bool
    function append(element: Element)
    function element(index: Int) -> Element
}
```

```neat
@core
function +(lhs: Int, rhs: Int) -> Int
```

## Notes

- `@core` does not imply that every operation is compiler-implemented.
- Body omission in an `@core construct` member or top-level `@core function` is an explicit declaration that the implementation is provided outside normal Neat source for now.
- `@core` means the compiler treats the declaration as a plain value type with privileged lowering semantics.
- Syntax-tree nodes exposed to macros may also be modeled as `@core construct` when they are compiler-recognized structural values.
