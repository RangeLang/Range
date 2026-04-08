# Core Attribute

## Definition

`@core` marks foundational declarations whose implementation boundary is supplied by the compiler, runtime, or backend.

## Role

`@core` keeps `construct` available as the single concrete declaration form while still giving the standard library and compiler a way to declare non-identity-bearing types such as `Int`, `Closure`, and `Block`.

`@core` may also mark top-level functions whose bodies are primitive operations supplied outside ordinary Neat source, such as scalar operator functions.

`@core` may also mark protocols that are reserved compiler-recognized semantic categories, such as future macro syntax categories.

## Mental Model

`construct` remains identity-bearing by default.

`@core construct` is the exception for compiler-recognized non-identity constructs:

- plain value semantics
- no memory-graph identity
- eligible for special lowering
- still allowed to define behavior in Neat itself

`@core` is not a general replacement for declaration kinds, and it does not apply to `enum`.

## Properties

- `@core` may be applied only to `construct`, top-level `function`, and `protocol`.
- `@core construct` declarations are non-identity-bearing.
- `@core construct` declarations compose as plain value data.
- `@core construct` declarations may still declare fields, conformances, generics, and behavior.
- Members inside an `@core construct` may omit bodies when the operation is supplied by the compiler, runtime, or backend.
- Top-level `@core function` declarations may omit bodies when the operation is supplied by the compiler, runtime, or backend.
- `@core protocol` declarations are compiler-recognized semantic categories; `@core` does not cascade through protocol conformance.
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

```neat
@core
protocol Syntax {}
```

## Notes

- `@core` does not imply that every operation is compiler-implemented.
- `@core` must be written on each declaration that is itself core; conforming to an `@core protocol` does not make a declaration core.
- Body omission in an `@core construct` member or top-level `@core function` is an explicit declaration that the implementation is provided outside normal Neat source for now.
- `@core construct` means the compiler treats the declaration as a plain value type with privileged lowering semantics.
- `@core protocol` means the compiler may recognize the protocol as a reserved semantic category; it does not provide protocol requirement bodies.
- Syntax-tree nodes exposed to macros may also be modeled as `@core construct` when they are compiler-recognized structural values.
