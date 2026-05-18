# Namespace Declaration Collection

Namespace attributes can give the graph one collection boundary for declarations and their applications.

The exact surface here is not finalized yet. The direction is that namespace-shaped declarations can carry shared behavior, while attributes mark the declarations and applications the graph should collect.

## Feature

A namespace can define shared behavior for a declaration family, then `@Namespace` can attach that behavior to both the declaration and the application sites.

## Example / Shape

```neat
#namespace
construct Declaration {
    function members(for declaration: Declaration.Type) -> [Declaration.Member]
    function applications(of declaration: Declaration.Type) -> [Declaration.Application]
}

@Declaration
@componentStorage
construct Vector<let dimensionality: IntLiteral, Scalar> {
}

@Declaration
let position: Vector<3, Float>
```

The graph gets both sides through the same namespace attribute:

```text
Declaration
  behavior:
    members(for:)
    applications(of:)

  declaration: Vector
    dimensionality
    Scalar
    componentStorage

  application: position
    Vector<3, Float>
```

## Reason

The declaration and its applications are related facts.

Namespace attributes give the graph a visible way to collect that relationship without making the parser or validator hardcode each domain.

The namespace owns the shared behavior. The attribute marks the places where that behavior applies.
