# Conditionals

```neat
if isPrimary {
    print("Primary")
} else if isSecondary {
    print("Secondary")
} else {
    print("Default")
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
let label = isPrimary ? "Primary" : "Secondary"
```
