# Neat Macros

Macros are compiler-time Neat code that reads syntax surfaces and expands them into ordinary Neat shape.

## Feature

A macro declares the syntax it applies to. The compiler gives it a typed target and a diagnostics channel, then the macro expands through explicit declaration or application surfaces.

## Example / Shape

```neat
#codable(.snakeCase)
construct User {
    let userId: Int
    let displayName: String
}
```

```neat
macro codable(_ strategy: CodingKeyStrategy = .identity): Construct { target, diagnostics in
    target.declaration.expand {
        extension #(target.declaration.self): Codable {
            function encode(to encoder: Encoder) -> Result<Void, EncodingError> {
                let container: KeyedEncodingContainer = encoder.keyedContainer()
                #encodeBody(
                    container: container,
                    properties: target.declaration.lets,
                    strategy: strategy
                )
                return .success(result: Void())
            }
        }
    }
}
```

## Reason

Macros keep repeated compiler-shaped code out of declarations.

The source says the design fact once. The compiler expands it into the boring shape it already knows how to check and lower.
