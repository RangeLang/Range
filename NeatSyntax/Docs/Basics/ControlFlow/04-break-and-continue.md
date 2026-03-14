# Break And Continue

Neat currently supports `break` and `continue` inside statement blocks.

```neat
while isRunning {
    if shouldSkip {
        continue
    }

    if shouldStop {
        break
    }
}
```
