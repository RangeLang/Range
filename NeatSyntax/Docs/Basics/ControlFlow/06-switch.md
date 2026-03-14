# Switch

```neat
switch mode {
case .light: {
    Logger.info("light")
}
case .dark: {
    Logger.info("dark")
}
default: {
    Logger.info("unknown")
}
}
```

Current switch rules:

- `case` values are expressions
- dotted case references like `.light` and `Theme.light` work
- no exhaustiveness checking yet
- no associated-value pattern matching yet
