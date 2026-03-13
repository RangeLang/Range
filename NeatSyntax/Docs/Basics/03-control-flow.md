# Control Flow

Neat currently supports `for` and `switch` in the parser.

## Loops In View Bodies

```neat
for item in items {
    Text("Item: \\(item)")
}
```

This parses as a view loop.

## Loops In Statement Blocks

```neat
for item in items {
    print("Item: \\(item)")
}
```

This parses as a statement loop.

Current loop rules:

- loop syntax is `for name in expression { ... }`
- one loop binding only
- no index binding yet
- no `where` clause yet

## Switch Statements

```neat
switch mode {
case .light: {
    print("light")
}
case .dark: {
    print("dark")
}
default: {
    print("unknown")
}
}
```

Current switch rules:

- `case` values are expressions
- dotted case references like `.light` and `Theme.light` work
- no exhaustiveness checking yet
- no associated-value pattern matching yet
