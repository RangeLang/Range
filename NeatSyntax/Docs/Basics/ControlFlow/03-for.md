# For Loops

## In View Bodies

```neat
for item in items {
    Text("Item: \\(item)")
}
```

This parses as a view loop.

## In Statement Blocks

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
