# Function

## Definition

A function declares callable behavior.

## Properties

- Uses an explicit parameter clause

```neat
function greet(name: String)
```

- Supports Swift-style external and internal labels

```neat
function greet(person name: String)
```

- Can declare a return type

```neat
function greet(name: String) -> String
```

- Can omit the return type when it can be inferred from the body

```neat
function greet(name: String) {
    return "Hello " + name
}
```

- Can appear at the top level

```neat
function add(left: Int, right: Int) -> Int {
    return left + right
}
```

- Can appear inside a construct

```neat
construct User {
    value name: String

    function displayName() -> String {
        return name
    }
}
```

- Can appear inside a protocol as a requirement

```neat
protocol Named {
    function displayName() -> String
}
```

- Can appear inside an extension as an implementation

```neat
extension Named {
    function displayName() -> String {
        return name
    }
}
```

- Requires a body in constructs

```neat
construct User {
    value name: String

    function displayName() -> String {
        return name
    }
}
```

- May omit a body in protocol declarations

```neat
protocol Named {
    function displayName() -> String
}
```

- Requires a body in extensions

```neat
extension Named {
    function displayName() -> String {
        return name
    }
}
```

- Uses static dispatch by default

```neat
function greet(name: String) -> String {
    return "Hello " + name
}
```

Calls are resolved through the graph at compile time unless the language explicitly opts out.

- Can mutate `state`

```neat
construct Counter {
    state count: Int = 0

    function increment() {
        count += 1
    }
}
```

- Can write through `binding`

```neat
construct NameEditor {
    binding name: String

    function rename(to newName: String) {
        name = newName
    }
}
```

- Cannot assign to `value`

```neat
construct User {
    value name: String

    function rename(to newName: String) {
        name = newName
    }
}
```

Assigning to `value` is a compile error.
