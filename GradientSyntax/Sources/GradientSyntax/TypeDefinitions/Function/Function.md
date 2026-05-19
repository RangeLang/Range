# Function

## Definition

A function declares callable behavior.

## Properties

- Uses an explicit parameter clause

```gradient
function greet(name: String)
```

- Supports Swift-style external and internal labels

```gradient
function greet(person name: String)
```

- Can declare a return type

```gradient
function greet(name: String) -> String
```

- Can omit the return type when it can be inferred from the body

```gradient
function greet(name: String) {
    return "Hello " + name
}
```

- Can appear at the top level

```gradient
function add(left: Int, right: Int) -> Int {
    return left + right
}
```

- May be marked `#language` at the top level and omit a body when the operation is supplied by compiler, runtime, or backend behavior

```gradient
#language
function +(lhs: Int, rhs: Int) -> Int
```

- Can appear inside a construct

```gradient
construct User {
    let name: String

    function displayName() -> String {
        return name
    }
}
```

- Can appear inside a protocol as a requirement

```gradient
protocol Named {
    function displayName() -> String
}
```

- Can appear inside an extension as an implementation

```gradient
extension Named {
    function displayName() -> String {
        return name
    }
}
```

- Requires a body in constructs

```gradient
construct User {
    let name: String

    function displayName() -> String {
        return name
    }
}
```

- May omit a body inside `#language construct` declarations when the operation is supplied by compiler, runtime, or backend behavior

```gradient
#language
construct ArrayStorage<Element> {
    function append(element: Element)
    function element(index: Int) -> Element
}
```

- May omit a body in protocol declarations

```gradient
protocol Named {
    function displayName() -> String
}
```

- Requires a body in extensions

```gradient
extension Named {
    function displayName() -> String {
        return name
    }
}
```

- Uses static dispatch by default

```gradient
function greet(name: String) -> String {
    return "Hello " + name
}
```

Calls are resolved through the graph at compile time unless the language explicitly opts out.

- Can mutate `state`

```gradient
construct Counter {
    state count: Int = 0

    function increment() {
        count += 1
    }
}
```

- Can write through `binding`

```gradient
construct NameEditor {
    binding name: String

    function rename(to newName: String) {
        name = newName
    }
}
```

- Cannot assign to `let`

```gradient
construct User {
    let name: String

    function rename(to newName: String) {
        name = newName
    }
}
```

Assigning to `let` is a compile error.
