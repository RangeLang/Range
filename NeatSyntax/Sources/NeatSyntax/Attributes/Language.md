# Language Attribute

## Definition

`#language` marks foundational declarations whose implementation boundary is supplied by the compiler, runtime, or backend.

## Role

`#language` keeps `construct` available as the single concrete declaration form while still giving the standard library and compiler a way to declare non-identity-bearing types such as `Int` and storage boundary values.

`#language` may also mark top-level functions whose bodies are primitive operations supplied outside ordinary Neat source, such as scalar operator functions.

`@syntax` marks compiler-visible syntax surfaces. Use it for syntax-tree nodes exposed to macros instead of overloading `#language`.

## Mental Model

`construct` remains identity-bearing by default.

`#language construct` is the exception for compiler-recognized non-identity constructs:

- plain value semantics
- no memory-graph identity
- eligible for special lowering
- still allowed to define behavior in Neat itself

`#language` is not a general replacement for declaration kinds, and it does not apply to `enum`.

## Properties

- `#language` may be applied only to `construct`, top-level `function`, and `protocol`.
- `#language construct` declarations are non-identity-bearing.
- `#language construct` declarations compose as plain value data.
- `#language construct` declarations may still declare fields, conformances, generics, and behavior.
- Members inside an `#language construct` may omit bodies when the operation is supplied by the compiler, runtime, or backend.
- Top-level `#language function` declarations may omit bodies when the operation is supplied by the compiler, runtime, or backend.
- `#language protocol` declarations are compiler-recognized semantic categories; `#language` does not cascade through protocol conformance.
- `#language` exists for foundational language types, not ordinary domain modeling.
- `#language construct` does not inherit from other constructs.

## Examples

```neat
#language
construct Int<let bits: IntLiteral, let signedness: Signedness = .signed>: ExpressibleByIntLiteral {
    let storage: IntStorage
}
```

```neat
#language
construct IntLiteral { }
```

```neat
#language
construct ArrayStorage<Element> {
    init()
    derived count: Int
    derived isEmpty: Bool
    function append(element: Element)
    function element(index: Int) -> Element
}
```

```neat
#language
function +(lhs: Int, rhs: Int) -> Int
```

## Notes

- `#language` does not imply that every operation is compiler-implemented.
- `#language` must be written on each declaration that is itself language-level; conforming to an `#language protocol` does not make a declaration language-level.
- Body omission in an `#language construct` member or top-level `#language function` is an explicit declaration that the implementation is provided outside normal Neat source for now.
- `#language construct` means the compiler treats the declaration as a plain value type with privileged lowering semantics.
- `#language protocol` means the compiler may recognize the protocol as a reserved semantic category; it does not provide protocol requirement bodies.
