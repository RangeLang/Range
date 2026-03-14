# Types

Neat keeps types visible without forcing users to pick between `struct` and `class`.

Examples:

```neat
value title: String
value count: Int
value isEnabled: Bool
value selectedID: Int?
value metadata: Dictionary
value numbers: [Int]

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
