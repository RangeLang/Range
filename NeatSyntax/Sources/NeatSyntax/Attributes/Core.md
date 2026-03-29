# Core Attribute

## Definition

`@core` marks a `construct` as a compiler-recognized non-identity type rather than a memory-graph identity type.

## Role

`@core` keeps `construct` available as the single concrete declaration form while still giving the standard library and compiler a way to declare non-identity-bearing types such as `Int`, `Closure`, and `Block`.

## Mental Model

`construct` remains identity-bearing by default.

`@core construct` is the exception for compiler-recognized non-identity constructs:

- plain value semantics
- no memory-graph identity
- eligible for special lowering
- still allowed to define behavior in Neat itself

`@core` is not a general replacement for declaration kinds, and it does not apply to `enum` or `protocol`.

## Properties

- `@core` may be applied only to `construct`.
- `@core construct` declarations are non-identity-bearing.
- `@core construct` declarations compose as plain value data.
- `@core construct` declarations may still declare fields, conformances, generics, and behavior.
- `@core` exists for foundational language types and compiler-exposed structural constructs, not ordinary domain modeling.
- `@core construct` does not inherit from other constructs.

## Examples

```neat
@core
construct Int<value bits: IntLiteral, value signedness: Signedness = .signed>: ExpressableByIntLiteral {
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

## Notes

- `@core` does not imply that every operation is compiler-implemented.
- `@core` means the compiler treats the declaration as a plain value type with privileged lowering semantics.
- Syntax-tree nodes exposed to macros may also be modeled as `@core construct` when they are compiler-recognized structural values.
