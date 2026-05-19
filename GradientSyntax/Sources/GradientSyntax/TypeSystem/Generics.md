# Generics

## Definition

Generics let declarations abstract over types and compile-time values.

## Properties

- Type generics are declared inline

```neat
protocol Container<Item>
```

- Neat does not use a separate `associatedtype` keyword

```neat
protocol Mapping<Input, Output>
```

- Constraints are written inline on the generic parameter

```neat
protocol Sortable<Element: Comparable>
```

- `where` is used only for relational constraints between existing generic parameters

```neat
where A.Item == B.Item
```

```neat
where T: Comparable
```

The second form is not needed. That constraint should be written inline.

- Value generics declare compile-time values rather than types

```neat
construct Int<let bits: RawInt>
```

- Type and value generics can be mixed

```neat
construct Array<let capacity: RawInt, Element>
```

- Generic parameters can have default arguments

```neat
construct Int<let bits: RawInt, let signedness: Signedness = .signed>
```

- Generic arguments can be partially supplied when defaults exist

```neat
let x: Int<8>
let y: Int<8, .unsigned>
```

- Variadic generics are supported

```neat
construct Group<each Child: View> {
    let children: (repeat each Child)
}
```

- Protocol composition can be used in generic constraints

```neat
Property & Parameter
```

## Notes

- Value generics participate in compile-time type formation rather than ordinary runtime construction.
