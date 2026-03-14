# Types

Neat keeps types visible without forcing users to pick between `struct` and `class`.

Examples:

```neat
var title: String
var count: Int
var isEnabled: Bool
var selectedID: Int?
var metadata: Dictionary
var numbers: [Int]

#Day {
    case today, tomorrow
}
```

Current direction:

- declarations always have identity
- types describe member and callable shapes
- case-bearing declarations replace a separate `enum` keyword
- optional types use suffix syntax like `Int?`
- `none` represents the empty value for optional expressions
- array types use bracket syntax like `[Int]`
- array literals exist in expressions like `[1, 2, 3]`
- richer collection behavior still needs to be added
