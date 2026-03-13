# Types

Neat keeps types visible without forcing users to pick between `struct` and `class`.

Examples:

```neat
var title: String
var count: Int
var isEnabled: Bool
var metadata: Dictionary
var colors: [Color]

@Day {
    case today, tomorrow
}
```

Current direction:

- declarations always have identity
- types describe member and function shapes
- case-bearing declarations replace a separate `enum` keyword
- array types use bracket syntax like `[Color]`
- array literals and richer collection behavior still need to be added
