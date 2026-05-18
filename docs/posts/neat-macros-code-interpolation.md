# Neat Macros: Code Interpolation

The Codable macro body is mostly ordinary Neat code with syntax values interpolated into it.

## Feature

`#(...)` inside a macro template is code interpolation.

String interpolation takes a value and places its textual form inside a string. Code interpolation takes a compile-time value and places its syntax form inside generated code.

## Example / Shape

```neat
macro encodeProperty(container: KeyedEncodingContainer, value: Identifier, key: String) -> Switch {
    switch container.encode(#(value), forKey: key) {
    case .success:
        break
    case .failure(let error):
        return .failure(cause: error)
    }
}
```

`value` is not printed as the word `value`.

It is an `Identifier`, so `#(value)` splices the identifier into the call site:

```neat
switch container.encode(userId, forKey: "user_id") {
case .success:
    break
case .failure(let error):
    return .failure(cause: error)
}
```

The parent Codable macro uses the same shape at a larger scale:

```neat
macro codable(_ strategy: CodingKeyStrategy = .identity): Construct { target, diagnostics in
    target.declaration.expand {
        extension #(target.declaration.self): Codable {
            function encode(to encoder: Encoder) -> Result<Void, EncodingError> {
                let container: KeyedEncodingContainer = encoder.keyedContainer()
                @encodeBody(
                    container: container,
                    properties: target.declaration.lets,
                    strategy: strategy
                )
                return .success(result: Void())
            }

            function decode(from decoder: Decoder) -> Result<Self, DecodingError> {
                let container: KeyedDecodingContainer = decoder.keyedContainer()
                @decodeBody(
                    container: container,
                    properties: target.declaration.lets,
                    strategy: strategy
                )
                return .success(result: self)
            }
        }
    }
}
```

Here `#(target.declaration.self)` splices the construct type into the generated extension. `@encodeBody` and `@decodeBody` splice arrays of generated `Switch` statements into the function bodies.

The body macros are where repetition is deconstructed:

```neat
macro encodeBody(container: KeyedEncodingContainer, properties: [Let], strategy: CodingKeyStrategy) -> [Switch] {
    #(properties.map { property in
        let codingKeyMarkers: [Marker.Application] = property.markers.filter { application in
            application.identifier.name == "codingKey"
        }
        let codingKeyValues: [String] = codingKeyMarkers.map { application in
            application.value
        }
        let key = codingKeyValues.first(default: strategy == .snakeCase ? property.identifier.name.snakeCase() : property.identifier.name)

        @encodeProperty(
            container: container,
            value: property.identifier,
            key: key
        )
    })
}
```

The loop is compile-time work. The result is source-shaped: one switch per stored property.

## Reason

The important distinction is that interpolation is not string building.

The macro author writes the generated code in the shape it should have, then splices the variable parts where they belong. Identifiers stay identifiers, types stay types, statements stay statements, and the expanded result is parsed and checked as normal Neat code.
