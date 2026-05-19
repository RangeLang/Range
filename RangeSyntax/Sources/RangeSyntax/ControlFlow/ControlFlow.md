# Control Flow

## Definition

Range uses direct Swift-style control flow.

## Properties

- Supports `if` / `else if` / `else`

```range
if score > 90 {
    print("A")
} else if score > 80 {
    print("B")
} else {
    print("C")
}
```

- Supports optional binding in `if let`

```range
if let user = getUser() {
    print(user.name)
} else {
    print("missing")
}
```

- Supports exhaustive `switch` with no fallthrough by default

```range
switch direction {
    case .north: print("north")
    case .south: print("south")
    case .east, .west: print("horizontal")
}
```

- Supports let binding in `switch`

```range
switch result {
    case .success(let value): print(value)
    case .failure(let err): print(err)
}
```

- Supports `where` in `switch` cases

```range
switch score {
    case let x where x > 90: print("A")
    case let x where x > 80: print("B")
    default: print("C")
}
```

- Supports `for`

```range
for item in items {
    print(item)
}
```

```range
for i in 0..<10 {
    print(i)
}
```

```range
for (index, value) in items.enumerated() {
    print(index, value)
}
```

- Supports `while`

```range
while condition {
    doSomething()
}
```

- Supports `repeat` / `while`

```range
repeat {
    doSomething()
} while condition
```

- Supports `guard`

```range
guard let user = getUser() else { return }
```

`guard` must transfer control in the `else` block.

- Supports optional binding in `guard let`

```range
guard let user = getUser() else { return }
print(user.name)
```

- Supports `break` and `continue`

```range
for item in items {
    if item == target { break }
    if item.isSkippable { continue }
    process(item)
}
```

- Supports labeled statements

```range
outerLoop: for i in 0..<10 {
    for j in 0..<10 {
        if i == j { break outerLoop }
    }
}
```
