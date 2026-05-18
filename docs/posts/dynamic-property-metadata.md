# Value Generics & Macros

Value generics give macros enough declaration shape to add members to an otherwise empty construct.

The exact surface here is not finalized yet. The important direction is that value-generic facts are visible to macros and the graph.

## Feature

A construct can declare only the fact that matters, then a macro can use that fact to project the storage, accessors, and related behavior.

## Example / Shape

```neat
@componentStorage
construct Vector<let dimensionality: IntLiteral, Scalar> {
}
```

`Vector` does not need to repeat the same component surface by hand.

```neat
macro componentStorage(): Construct { target, diagnostics in
    target.declaration.expand {
        extension #(target.declaration.self) {
            let storage: ComponentStorage<Scalar>

            function count() -> Int {
                return dimensionality
            }

            function component(index: Int) -> Scalar {
                return storage.component(index: index)
            }

            function map<Output>(_ transform: (Scalar) -> Output) -> #(target.declaration.self)<dimensionality, Output> {
                return #(target.declaration.self)<dimensionality, Output>(
                    storage: storage.map(transform)
                )
            }
        }
    }
}
```

The value generic ties the generated surface together:

```neat
let position: Vector<3, Float>
let color: Vector<4, Float>

let next: Vector<3, Float> = position.map { value in value + 1.0 }
```

The graph can see both the declaration fact and the generated members:

```text
Vector
  value generic: dimensionality
  type generic: Scalar
  macro: componentStorage

Vector<3, Float>
  dimensionality: 3
  Scalar: Float
  generated storage: ComponentStorage<Float>
  generated map -> Vector<3, Output>
```

## Reason

The empty construct is not missing information. It is saying that the meaningful information is in the declaration header.

`Vector<3, Float>` already carries dimensionality and scalar type. `Int<8, .unsigned>` already carries width and signedness.

Macros can use those facts to add members without making the author repeat the shape.
