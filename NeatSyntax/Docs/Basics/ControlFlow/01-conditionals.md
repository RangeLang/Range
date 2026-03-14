# Conditionals

```neat
if isPrimary {
    Text("Primary")
} else if isSecondary {
    Text("Secondary")
} else {
    Text("Default")
}
```

This form works in both view bodies and statement blocks.

Current conditional rules:

- condition syntax is `if expression { ... }`
- `else if` chains are supported
- `else { ... }` is optional
- conditions support `==`, `!=`, `<`, `<=`, `>`, `>=`, `&&`, `||`, and unary `!`
- ternary expressions use `condition ? whenTrue : whenFalse`

```neat
let label = isPrimary ? "Primary" : "Secondary"
```
