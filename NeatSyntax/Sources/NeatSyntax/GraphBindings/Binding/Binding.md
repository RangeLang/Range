# Binding

## Definition

A binding is a borrowed graph binding.

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
