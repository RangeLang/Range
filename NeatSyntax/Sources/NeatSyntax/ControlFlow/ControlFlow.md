# Control Flow

## Definition

Neat uses direct Swift-style control flow.

## Properties

- Supports `if` / `else if` / `else`

```neat
if score > 90 {
    print("A")
} else if score > 80 {
    print("B")
} else {
    print("C")
}
```

- Supports optional binding in `if let`

```neat
if let user = getUser() {
    print(user.name)
} else {
    print("missing")
}
```

- Supports exhaustive `switch` with no fallthrough by default

```neat
switch direction {
    case .north: print("north")
    case .south: print("south")
    case .east, .west: print("horizontal")
}
```

- Supports let binding in `switch`

```neat
switch result {
    case .success(let value): print(value)
    case .failure(let err): print(err)
}
```

- Supports `where` in `switch` cases

```neat
switch score {
    case let x where x > 90: print("A")
    case let x where x > 80: print("B")
    default: print("C")
}
```

- Supports `for`

```neat
for item in items {
    print(item)
}
```

```neat
for i in 0..<10 {
    print(i)
}
```

```neat
for (index, value) in items.enumerated() {
    print(index, value)
}
```

- Supports `while`

```neat
while condition {
    doSomething()
}
```

- Supports `repeat` / `while`

```neat
repeat {
    doSomething()
} while condition
```

- Supports `guard`

```neat
guard let user = getUser() else { return }
```

`guard` must transfer control in the `else` block.

- Supports optional binding in `guard let`

```neat
guard let user = getUser() else { return }
print(user.name)
```

- Supports `break` and `continue`

```neat
for item in items {
    if item == target { break }
    if item.isSkippable { continue }
    process(item)
}
```

- Supports labeled statements

```neat
outerLoop: for i in 0..<10 {
    for j in 0..<10 {
        if i == j { break outerLoop }
    }
}
```
