# Handoff: Macro Syntax Value Splicing

## Goal

Unlock real Neat macro code by treating NeatCore syntax values as first-class macro-time values that can be spliced into `expand` output.

The desired authoring model is:

```neat
macro codable(): Construct { target, diagnostics in
    let cases = target.declaration.lets.map { property in
        Enum.Case(name: property.name, associatedValues: [])
    }

    let codingKeys: Enum = Enum(
        declaration: Enum.Declaration(
            self: NamedTypeReference(name: "CodingKeys"),
            cases: cases
        )
    )

    target.declaration.expand {
        extension #(target.declaration.self) {
            #(codingKeys)
        }
    }
}
```

This keeps `expand` simple:

- raw emitted syntax stays raw emitted syntax
- `#(value)` splices a macro-time syntax value
- iteration/filtering/string transformation happen in normal macro code before `expand`
- no template `#for`, `#if`, `emit`, or second control-flow language is needed

## Current State

The first bridge slice exists and passes tests:

- `#(localBinding)` inside `expand` can resolve a preceding macro-body `let`.
- A narrow `Enum(...)` syntax value can render into emitted source.
- `NamedTypeReference(name: "...")` can render as a nominal name for this path.
- `Enum.Case(name: "...", associatedValues: [])` can render as `case ...`.
- Extensions now parse nested enums/protocols so `CodingKeys` can live inside the generated extension instead of as a peer declaration.
- Fixture: `NeatCompilerFixtures/CompilePass/Macros/SyntaxValueSpliceCodingKeys.neat`.

Important limitation: this is still bridge code, not a general macro-time evaluator. It supports explicit local syntax values, not real computed arrays yet.

## Why This Direction

`target.declaration.self` is already a syntax value (`NominalTypeReference`) that gets realized by splicing:

```neat
extension #(target.declaration.self) {
}
```

`codingKeys` should work the same way. It is just a larger syntax value (`Enum`) that gets realized by:

```neat
#(codingKeys)
```

This aligns with self-hosting: NeatCore describes syntax, macro code constructs syntax, and `expand` realizes syntax.

## Next Implementation Slice

Add a generic macro-time value bridge instead of adding codable-specific logic.

Suggested model:

```swift
enum MacroValue {
    case string(String)
    case array([MacroValue])
    case syntax(type: String, fields: [String: MacroValue])
    case expression(Expression)
    case typeReference(TypeReference)
}
```

Then add a small evaluator/bridge:

- Evaluate macro-body `let` statements into `MacroValue`.
- Resolve target paths like `target.declaration.lets` into arrays of NeatCore-shaped syntax values.
- Evaluate array literals.
- Evaluate NeatCore constructor calls by field labels:
  - `Enum(...)`
  - `Enum.Declaration(...)`
  - `Enum.Case(...)`
  - `NamedTypeReference(...)`
- Evaluate member access on syntax values:
  - `property.name`
  - `property.type`
- Evaluate `Array.map` generically over `.array` by applying the closure to each value.
- Render `MacroValue` according to the expected splice position.

This should make the codable-style macro possible without special-casing `map`.

## Bridge Rendering To Add

Start with the syntax needed by lightweight coding-key generation:

- `Enum`
- `Enum.Declaration`
- `Enum.Case`
- `NamedTypeReference`
- arrays of syntax values

Then broaden as needed:

- `Extension`
- `Construct`
- `Protocol`
- `Function.Declaration`
- property declarations

Keep this isolated in a bridge layer rather than spreading syntax-specific rendering through `MacroExpander+Models.swift`.

Potential names:

- `MacroValue`
- `MacroValueEvaluator`
- `MacroSyntaxRenderer`
- `NeatCoreSyntaxBridge`

## Design Rules

- Do not add a template control-flow language unless syntax-value construction proves insufficient.
- Keep computation before `expand` in normal macro code.
- Keep `expand` as emitted syntax plus splices.
- Treat `#(...)` as "realize this macro-time syntax value here."
- Placement validation remains the job of normal Neat parsing/validation after realization.

## Validation Fixture To Aim For

Replace the hardcoded fixture with a computed one:

```neat
macro codingKeysSyntaxValue(): Construct { target, diagnostics in
    let cases = target.declaration.lets.map { property in
        Enum.Case(name: property.name, associatedValues: [])
    }

    let codingKeys: Enum = Enum(
        declaration: Enum.Declaration(
            self: NamedTypeReference(name: "CodingKeys"),
            cases: cases
        )
    )

    target.declaration.expand {
        extension #(target.declaration.self) {
            #(codingKeys)
        }
    }
}
```

This is the smallest real proof that macro code can inspect a target declaration, build syntax values, and splice those values into generated code.
