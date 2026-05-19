# Extension

## Definition

An extension adds declarations to an existing type definition.

## Role

`extension` separates a type’s original declaration from later additions.

## Mental Model

- the original type definition establishes the type
- an extension adds more surface to that existing type

## Properties

- Can extend an existing construct

```range
construct User {
    let name: String
}

extension User {
    function displayName() -> String {
        return name
    }
}
```

- Can extend an existing enum

```range
enum Direction {
    case north
    case south
}

extension Direction {
    function isVertical() -> Bool {
        return self == .north || self == .south
    }
}
```

- Can extend an existing protocol

```range
protocol Paginated {
    state page: Int
}

extension Paginated {
    function nextPage() {
        page += 1
    }
}
```

- Extends an existing type rather than declaring a new one

```range
extension User
```

## Notes

- `extension` is a type-definition-level feature, not a graph binding.
- Extensions add to an existing type surface rather than introducing a distinct type.
