# Switch

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
