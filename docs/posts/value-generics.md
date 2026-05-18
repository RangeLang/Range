# Value Generics

Value generics let a type carry compile-time values directly on its declaration shape.

## Addition

```neat
@componentStorage
construct Vector<let dimensionality: IntLiteral, Scalar> {
    let storage: ComponentStorage<Scalar>
}

let position: Vector<3, Float>
let velocity: Vector<3, Float>
let color: Vector<4, Float>
```

```neat
construct Int<let bits: IntLiteral, let signedness: Signedness = .signed>: ExpressibleByIntLiteral {
    let storage: IntStorage
}

let nibble: Int<4>
let byte: Int<8>
let unsignedByte: Int<8, .unsigned>
```

## Reason

Some type facts are not types.

Vector dimensionality is a number. Integer width is a number. Signedness is a value.

Putting those facts on the construct keeps the source honest: `Vector<3, Float>` says this is a three-component vector, not just a vector with a runtime field that might happen to contain three items.

That gives macros a stronger shape too. `@componentStorage` can generate component APIs while preserving `dimensionality`, and a backend can still choose a packed SIMD representation, an array-backed representation, or something else later.
