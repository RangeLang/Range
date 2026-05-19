# Function

## Definition

A function declares callable behavior.

## Properties

- Uses an explicit parameter clause

```range
function greet(name: String)
```

- Supports Swift-style external and internal labels

```range
function greet(person name: String)
```

- Can declare a return type

```range
function greet(name: String) -> String
```

- Can omit the return type when it can be inferred from the body

```range
function greet(name: String) {
    return "Hello " + name
}
```

- Can appear at the top level

```range
function add(left: Int, right: Int) -> Int {
    return left + right
}
```

- May be marked `#language` at the top level and omit a body when the operation is supplied by compiler, runtime, or backend behavior

```range
#language
function +(lhs: Int, rhs: Int) -> Int
```

- Can appear inside a construct

```range
construct User {
    let name: String

    function displayName() -> String {
        return name
    }
}
```

- Can appear inside a protocol as a requirement

```range
protocol Named {
    function displayName() -> String
}
```

- Can appear inside an extension as an implementation

```range
extension Named {
    function displayName() -> String {
        return name
    }
}
```

- Requires a body in constructs

```range
construct User {
    let name: String

    function displayName() -> String {
        return name
    }
}
```

- May omit a body inside `#language construct` declarations when the operation is supplied by compiler, runtime, or backend behavior

```range
#language
construct ArrayStorage<Element> {
    function append(element: Element)
    function element(index: Int) -> Element
}
```

- May omit a body in protocol declarations

```range
protocol Named {
    function displayName() -> String
}
```

- Requires a body in extensions

```range
extension Named {
    function displayName() -> String {
        return name
    }
}
```

- Uses static dispatch by default

```range
function greet(name: String) -> String {
    return "Hello " + name
}
```

Calls are resolved through the graph at compile time unless the language explicitly opts out.

- Can mutate `state`

```range
construct Counter {
    state count: Int = 0

    function increment() {
        count += 1
    }
}
```

- Can write through `binding`

```range
construct NameEditor {
    binding name: String

    function rename(to newName: String) {
        name = newName
    }
}
```

- Cannot assign to `let`

```range
construct User {
    let name: String

    function rename(to newName: String) {
        name = newName
    }
}
```

Assigning to `let` is a compile error.
