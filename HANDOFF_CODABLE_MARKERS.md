# Codable, Encoding, Decoding, And Marker Macro Handoff

This note captures the recent implementation work and the design direction that came out of the Codable / CodingKeys / marker macro discussion.

## Implemented In The Recent Pass

### Result-Centered Encoding And Decoding

The current direction is explicit `Result`, not hidden throwing control flow.

Encoding and decoding APIs now use ordinary result values:

```neat
Result<Void, EncodingError>
Result<Self, DecodingError>
```

This keeps failure visible in the type graph and avoids deepening Swift-style `throws`, `try`, `throw`, and `do/catch` as core language features.

### Codable Protocol Shape

`Codable` now sits on top of the two real protocols:

```neat
protocol Codable: Encodable, Decodable {
}
```

This means `Codable` is just the combined requirement surface. Synthesis belongs to the macro, not the protocol.

### Encodable / Encoder Surface

Encoding support exists for scalar and collection-oriented values through the container strategy:

- single value container
- keyed container
- unkeyed container

The generic encoder shape is currently:

```neat
protocol Encoder<Output> {
    function container<Key: CodingKey>(
        keyedBy keyType: Key.Type
    ) -> KeyedEncodingContainer<Key>

    function unkeyedContainer() -> UnkeyedEncodingContainer
    function singleValueContainer() -> SingleValueEncodingContainer
}
```

Scalar conformances such as `Int`, `String`, `Bool`, and `Float` encode through `singleValueContainer()`.

Collection conformances were extended so arrays, dictionaries, and sets can participate in encoding. Some collection bodies still depend on the current compiler/runtime support level, but the intended model is ordinary Neat traversal plus container calls.

### Decodable / Decoder Surface

Decoding mirrors encoding.

The accepted initializer shape is:

```neat
init(from decoder: Decoder<JSONValue>) -> Result<Self, DecodingError>
```

This is intentionally a failable initializer expressed as `Result<Self, Failure>`, not a hidden throw channel.

Swift lowering currently maps this to a throwable Swift initializer where needed so fixtures can run against the Swift backend.

### Initializer Return Support

Initializers can now express a result-producing decode shape:

```neat
init(from decoder: Decoder<JSONValue>) -> Result<Self, DecodingError>
```

Language-level issues encountered and addressed:

- initializer parameters are now available to local binding inference inside initializer bodies
- result-returning initializers lower through Swift backend support
- generic failable initializer calls work through protocol constraints for the decoding path

### Graph-Derived Inference Improvements

Recent inference fixes were made graph-first rather than special-case first.

Important improvements:

- member call inference now asks declaration/application graph knowledge before falling back to native collection shortcuts
- recursive member base inference supports chains such as `self.values.count` and `self.values.element(index:)`
- construct calls inside local bindings infer correctly across `let`, `state`, and related storage forms
- enum static case construction supports graph-derived type validation

### Exhaustive Switch Return Analysis

Return validation now understands exhaustive enum switches semantically.

This should validate:

```neat
function decodeInt(_ value: JSONValue) -> Result<Int, DecodingError> {
    switch value {
    case .int(let value):
        return .success(result: value)
    case .string:
        return .failure(cause: .failed)
    case .bool:
        return .failure(cause: .failed)
    case .float:
        return .failure(cause: .failed)
    case .null:
        return .failure(cause: .failed)
    case .array:
        return .failure(cause: .failed)
    case .object:
        return .failure(cause: .failed)
    }
}
```

No trailing fallback should be required when the switch covers every enum case and every branch returns.

This is graph-derived from enum declarations, not text matching.

### Multiple Patterns Per Case

The parser already supports multiple bare patterns per case by expanding them internally:

```neat
case .bool, .float, .string:
    return .failure(cause: .failed)
```

Patterns with bindings remain more constrained.

### Fixtures

Fixtures were added or adjusted around:

- manual Codable conformance
- JSON encoding
- JSON decoding
- nested decode paths
- exhaustive switch return validation
- non-exhaustive switch failure validation
- member-chain inference

The manual Codable fixture demonstrates the currently working shape: a user type manually implements `encode` and `init(from:)`, then round-trips through JSON decoding.

## Current Codable Macro State

`NeatCore/Macros/Implementations/Codable.neat` currently only synthesizes a nested enum:

```neat
macro codable(): Construct { target, diagnostics in
    let codingKeys: Enum.Declaration = Enum.Declaration(
        self: NamedTypeReference(name: "CodingKeys"),
        cases: target.declaration.lets.map { property in
            Enum.Case(name: property.name, associatedValues: [])
        }
    )

    target.declaration.expand {
        extension #(target.declaration.self): Codable {
            #(codingKeys)
        }
    }
}
```

That proves syntax-value splicing for enum declarations, but it is not yet full Codable synthesis.

The old compile-pass fixture that expected `#codable` to be enough was moved to compile-fail because `Codable` now requires actual `Encodable` and `Decodable` implementations.

## CodingKeys Discussion

### Swift Shape

Swift usually synthesizes:

```swift
enum CodingKeys: String, CodingKey {
    case id
    case name
}
```

and then generated methods use:

```swift
container.encode(id, forKey: .id)
```

Swift's `CodingKey` requires string/int key access, and `String` raw-value enums provide the bridge.

### Neat Concern

Copying Swift's `CodingKeys` directly may be too Swift-shaped.

In Neat, the `#codable` macro already sees the stored property names:

```neat
let id: Int
let name: String
```

So for synthesized code, the macro can directly emit:

```neat
container.encode(id, forKey: "id")
container.encode(name, forKey: "name")
```

This means `CodingKeys` may not be necessary for the first Neat-native design.

### Possible Simplified Container Shape

A cleaner future container API may be string-keyed:

```neat
protocol Encoder<Output> {
    function keyedContainer() -> KeyedEncodingContainer
}

protocol KeyedEncodingContainer {
    function encode<T: Encodable>(
        _ value: T,
        forKey key: String
    ) -> Result<Void, EncodingError>
}
```

Decoding would mirror it:

```neat
protocol Decoder<Input> {
    function keyedContainer() -> KeyedDecodingContainer
}

protocol KeyedDecodingContainer {
    function decode<T: Decodable>(
        _ type: T.Type,
        forKey key: String
    ) -> Result<T, DecodingError>
}
```

This removes:

- `CodingKey`
- `CodingKeys.self`
- `container(keyedBy:)`
- one-off key wrapper constructs

The tradeoff is losing typed manual key checking. That may be acceptable because the primary synthesis path is macro-generated from the declaration graph.

## Raw-Value Enum Discussion

Raw-value enums were considered as a way to model:

```neat
enum CodingKeys {
    case id = "user_id"
}
```

But this may be too large a feature just for Codable.

Raw-value enums raise broader questions:

- are raw values limited to literals?
- can duplicate raw values exist?
- is reverse lookup supported?
- are raw values runtime values or compile-time metadata?
- does this pull Neat toward Swift semantics?

The preferred direction is to avoid raw-value enums for Codable and instead attach key metadata directly to properties.

## Marker Macro Direction

The discussion moved from `CodingKeys` to a more general need:

> One macro should be able to attach typed metadata to a declaration, and a parent macro should be able to read that metadata from child declarations.

Example desired user code:

```neat
#codable
construct User {
    #codingKey("user_id")
    let id: Int

    let name: String
}
```

Here:

- `#codingKey` should not emit code
- it should attach metadata to the `let`
- `#codable` should inspect that metadata when generating encode/decode bodies

### Raw Macro Applications

Declarations should expose attached macro syntax by default:

```neat
construct Let.Declaration {
    let macros: [MacroApplication]
    let name: String
    let type: TypeReference
}
```

And similarly for constructs, functions, enum cases, etc.

This is syntax truth: if a declaration can be annotated with `#something`, the macro target model should expose that annotation.

### Typed Markers

Raw `property.macros` is useful, but stringly.

The better long-term model is typed marker output:

```neat
construct CodingKeyMarker {
    let value: String
}

marker codingKey(_ value: String): Let.Declaration -> CodingKeyMarker {
    return CodingKeyMarker(value: value)
}
```

Then a parent macro can ask for typed marker metadata:

```neat
let marker = property.marker(CodingKeyMarker.self)
let key = marker.value ?? property.name
```

This avoids no-op expansion macros whose only purpose is to carry information.

### Macro Versus Marker

The conceptual split:

```neat
macro
```

expands or rewrites syntax.

```neat
marker
```

attaches typed compile-time metadata to a syntax node.

`#codable` remains an expansion macro.

`#codingKey("user_id")` becomes a marker macro.

### Generic Marker Form

A generic form was also discussed:

```neat
Marker<Let.Declaration>
Marker<Enum.Case>
Marker<Construct.Declaration>
```

But the cleaner user-facing declaration syntax appears to be:

```neat
marker codingKey(_ value: String): Let.Declaration -> CodingKeyMarker {
    return CodingKeyMarker(value: value)
}
```

This reads as:

- attach to `Let.Declaration`
- produce `CodingKeyMarker`

## Ideal Future Codable Macro Shape

Ignoring current renderer limitations, the desired macro behavior is:

```neat
#codable
construct User {
    #codingKey("user_id")
    let id: Int

    let name: String
}
```

expands conceptually into:

```neat
extension User: Codable {
    function encode<Output>(to encoder: Encoder<Output>) -> Result<Void, EncodingError> {
        state container = encoder.keyedContainer()

        switch container.encode(id, forKey: "user_id") {
        case .success:
            return container.encode(name, forKey: "name")
        case .failure(let error):
            return .failure(cause: error)
        }
    }

    init(from decoder: Decoder<JSONValue>) -> Result<Self, DecodingError> {
        let container = decoder.keyedContainer()

        switch container.decode(Int.self, forKey: "user_id") {
        case .success(let id):
            self.id = id
        case .failure(let error):
            return .failure(cause: error)
        }

        switch container.decode(String.self, forKey: "name") {
        case .success(let name):
            self.name = name
        case .failure(let error):
            return .failure(cause: error)
        }

        return .success(result: self)
    }
}
```

The generated code may still use the current `container(keyedBy:)` / `CodingKey` API until the container surface is simplified.

## Current Macro System Constraints

The current macro renderer can splice some typed syntax values, especially:

- `Enum.Declaration`
- type references
- strings

It does not yet render full:

- `Function.Declaration`
- `Init.Declaration`
- arbitrary `[Statement]`
- `Block`

However, full declaration-value rendering may not be necessary for the first Codable macro.

The macro can emit ordinary written syntax in an expansion block and only splice smaller generated pieces where needed.

The hard missing capability is ergonomic generation of repeated statement bodies, such as one encode/decode switch per property.

## Suggested Next Steps

### 1. Expose Attached Macro Applications In Target Models

Add `macros` to syntax target values for:

- construct declarations
- stored properties / lets
- enum cases
- functions / initializers where relevant

This is useful immediately and does not require typed marker semantics yet.

### 2. Add Marker Macro Design Separately

Do not overload normal expansion macros to act like empty annotations.

Design a first-class marker declaration:

```neat
marker codingKey(_ value: String): Let.Declaration -> CodingKeyMarker
```

Then add typed marker resolution later.

### 3. Decide Whether To Remove CodingKey From Core Encoding

Before making `#codable` depend deeply on `CodingKeys`, decide whether keyed containers should just use `String`.

The string-keyed design is simpler and probably more native to Neat's macro-first synthesis approach.

### 4. Implement Minimal Codable Macro Generation

Once marker/raw macro access is available, implement:

- default field key = property name
- optional field key override from marker
- encode body generation
- decode initializer generation

Use explicit `switch` over `Result` for each field until a Result-control-flow macro exists.

### 5. Keep Result Control-Flow Sugar Separate

Do not solve repeated encoding switch nesting by reintroducing `throws`.

If repetition becomes too noisy, solve it with explicit `Result` helpers or future macro sugar.

## Current Design Preference

The strongest current direction is:

- `Result` remains ordinary data
- encoding/decoding are library/core protocols, not native language magic
- `#codable` provides synthesis
- `CodingKeys` should not be copied from Swift unless it earns its place
- field customization should live as property metadata
- marker macros are the right abstraction for metadata-only annotations
- declaration graph/application graph should provide semantic truth wherever possible

