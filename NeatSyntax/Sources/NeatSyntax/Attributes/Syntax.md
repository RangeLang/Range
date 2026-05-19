# Syntax Attribute

## Definition

`@syntax` marks declarations that model compiler-visible syntax surfaces.

## Role

`@syntax` is the category marker for syntax-tree values exposed to macros and compiler graph views.

It keeps syntax membership on the declaration as an attribute instead of requiring every syntax-facing declaration to conform to a broad `Syntax` protocol.

## Example

```neat
@syntax
protocol Expression: Statement, SyntaxReplaceable<Expression> {
    let type: TypeReference?
}
```

```neat
@syntax
construct Construct {
    let declaration: Declaration
    let application: Application

    @syntax
    construct Application: SyntaxReplaceable<Expression> {
        let type: TypeReference
        let arguments: [Parameter.Application]
    }
}
```

## Notes

- `@syntax` may be applied only inside NeatCore.
- `@syntax` declarations are compiler-recognized syntax surfaces.
- Capability protocols such as `SyntaxReplaceable`, `SyntaxExpandable`, and `SyntaxEmittable` still describe what a syntax surface can do.
- `#language` remains for foundational language/runtime boundaries such as scalar storage and primitive operations.
