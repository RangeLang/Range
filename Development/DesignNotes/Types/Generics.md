# Generics

## Definition

Generics let declarations abstract over types and compile-time values.

## Properties

- Type generics are declared inline

```range
protocol Container<Item>
```

- Range does not use a separate `associatedtype` keyword

```range
protocol Mapping<Input, Output>
```

- Constraints are written inline on the generic parameter

```range
protocol Sortable<Element: Comparable>
```

- `where` is used only for relational constraints between existing generic parameters

```range
where A.Item == B.Item
```

```range
where T: Comparable
```

The second form is not needed. That constraint should be written inline.

- Value generics declare compile-time values rather than types

```range
construct Int<let bits: RawInt>
```

- Type and value generics can be mixed

```range
construct Array<let capacity: RawInt, Element>
```

- Generic parameters can have default arguments

```range
construct Int<let bits: RawInt, let signedness: Signedness = .signed>
```

- Generic arguments can be partially supplied when defaults exist

```range
let x: Int<8>
let y: Int<8, .unsigned>
```

- Variadic generics are supported

```range
construct Group<each Child: View> {
    let children: (repeat each Child)
}
```

- Protocol composition can be used in generic constraints

```range
View & Identifiable
```

## Notes

- Value generics participate in compile-time type formation rather than ordinary runtime construction.
