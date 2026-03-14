# Conditionals

```neat
if isPrimary {
    Logger.info("Primary")
} else if isSecondary {
    Logger.info("Secondary")
} else {
    Logger.info("Default")
}
```

This form works in statement blocks.

Current conditional rules:

- condition syntax is `if expression { ... }`
- `else if` chains are supported
- `else { ... }` is optional
- conditions support `==`, `!=`, `<`, `<=`, `>`, `>=`, `&&`, `||`, and unary `!`
- ternary expressions use `condition ? whenTrue : whenFalse`

```neat
value label = isPrimary ? "Primary" : "Secondary"
```
