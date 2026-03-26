# Binding

## Definition

A binding is a borrowed reference to existing storage.

## Role

`binding` is how Neat expresses shared access explicitly instead of making aliasing implicit through ordinary assignment.

## Mental Model

`binding` is pointer-like in role, but compiler-tracked and ownership-aware.

It does not introduce new owned storage. It gives access to storage owned elsewhere.

## Properties

- Declares a borrowed binding rather than owned storage

```neat
binding name: String
```

- Can be plain

```neat
binding name: String
```

- Can be derived through explicit get and set behavior

```neat
binding displayName: String {
    get {
        return name
    }

    set {
        name = newValue
    }
}
```

- Is not the source of truth

```neat
binding name: String
```

`name` points to state owned elsewhere rather than owning the data itself.

- Can be passed from owned state through binding projection syntax

```neat
construct Person {
    binding name: String
}

state name: String = "George"

Person(name: $name)
```

Here `Person.name` is bound to the surrounding `state name`. The construct does not own that storage; it points at the existing state through the binding.

- Shared mutation flows through the binding in both directions

```neat
construct Person {
    value name: String
    state age: Int
}

state a: Person = Person(name: "George", age: 26)
binding b: Person = $a

b.age = 28
```

`a.age` and `b.age` refer to the same mutable storage path. Mutating through either side updates the same owned state.

## Notes

- `binding` is the Neat mechanism closest to class-like shared access, but it is explicit rather than implicit.
- Ordinary assignment copies semantically. `binding` is the tool for shared live connection.
