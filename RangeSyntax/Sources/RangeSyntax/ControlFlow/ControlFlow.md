# Control Flow

## Definition

Gradient uses direct Swift-style control flow.

## Properties

- Supports `if` / `else if` / `else`

```gradient
if score > 90 {
    print("A")
} else if score > 80 {
    print("B")
} else {
    print("C")
}
```

- Supports optional binding in `if let`

```gradient
if let user = getUser() {
    print(user.name)
} else {
    print("missing")
}
```

- Supports exhaustive `switch` with no fallthrough by default

```gradient
switch direction {
    case .north: print("north")
    case .south: print("south")
    case .east, .west: print("horizontal")
}
```

- Supports let binding in `switch`

```gradient
switch result {
    case .success(let value): print(value)
    case .failure(let err): print(err)
}
```

- Supports `where` in `switch` cases

```gradient
switch score {
    case let x where x > 90: print("A")
    case let x where x > 80: print("B")
    default: print("C")
}
```

- Supports `for`

```gradient
for item in items {
    print(item)
}
```

```gradient
for i in 0..<10 {
    print(i)
}
```

```gradient
for (index, value) in items.enumerated() {
    print(index, value)
}
```

- Supports `while`

```gradient
while condition {
    doSomething()
}
```

- Supports `repeat` / `while`

```gradient
repeat {
    doSomething()
} while condition
```

- Supports `guard`

```gradient
guard let user = getUser() else { return }
```

`guard` must transfer control in the `else` block.

- Supports optional binding in `guard let`

```gradient
guard let user = getUser() else { return }
print(user.name)
```

- Supports `break` and `continue`

```gradient
for item in items {
    if item == target { break }
    if item.isSkippable { continue }
    process(item)
}
```

- Supports labeled statements

```gradient
outerLoop: for i in 0..<10 {
    for j in 0..<10 {
        if i == j { break outerLoop }
    }
}
```
