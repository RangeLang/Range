# Generics

## Definition

Generics let declarations abstract over types and compile-time values.

## Properties

- Type generics are declared inline

```gradient
protocol Container<Item>
```

- Gradient does not use a separate `associatedtype` keyword

```gradient
protocol Mapping<Input, Output>
```

- Constraints are written inline on the generic parameter

```gradient
protocol Sortable<Element: Comparable>
```

- `where` is used only for relational constraints between existing generic parameters

```gradient
where A.Item == B.Item
```

```gradient
where T: Comparable
```

The second form is not needed. That constraint should be written inline.

- Value generics declare compile-time values rather than types

```gradient
construct Int<let bits: RawInt>
```

- Type and value generics can be mixed

```gradient
construct Array<let capacity: RawInt, Element>
```

- Generic parameters can have default arguments

```gradient
construct Int<let bits: RawInt, let signedness: Signedness = .signed>
```

- Generic arguments can be partially supplied when defaults exist

```gradient
let x: Int<8>
let y: Int<8, .unsigned>
```

- Variadic generics are supported

```gradient
construct Group<each Child: View> {
    let children: (repeat each Child)
}
```

- Protocol composition can be used in generic constraints

```gradient
Property & Parameter
```

## Notes

- Value generics participate in compile-time type formation rather than ordinary runtime construction.
