# Codable, Markers, And Syntax-Producing Macro Handoff

This note captures the current state after the marker / Codable / syntax-producing macro work.

## Current Direction

The design moved away from Swift-shaped `CodingKeys` synthesis.

The current model is:

- `Result` remains ordinary data for encoding and decoding failure.
- `Codable` is only `Encodable & Decodable`.
- keyed encoding and decoding use `String` keys directly.
- field customization is marker metadata on stored properties.
- `#codable` is an expansion macro that reads `Let` metadata and emits real encode/decode bodies.
- small reusable generated syntax pieces are written as freestanding syntax-producing macros.

## Codable Surface

The core protocol shape is now non-generic:

```range
protocol Encoder {
    function keyedContainer() -> KeyedEncodingContainer
    function unkeyedContainer() -> UnkeyedEncodingContainer
    function singleValueContainer() -> SingleValueEncodingContainer
}

protocol Decoder {
    function keyedContainer() -> KeyedDecodingContainer
    function unkeyedContainer() -> UnkeyedDecodingContainer
    function singleValueContainer() -> SingleValueDecodingContainer
}

protocol Encodable {
    function encode(to encoder: Encoder) -> Result<Void, EncodingError>
}

protocol Decodable {
    init(from decoder: Decoder) -> Result<Self, DecodingError>
}

protocol Codable: Encodable, Decodable {
}
```

Keyed containers use string keys:

```range
protocol KeyedEncodingContainer {
    function encode<T: Encodable>(_ value: T, forKey key: String) -> Result<Void, EncodingError>
}

protocol KeyedDecodingContainer {
    function decode<T: Decodable>(_ type: T.Type, forKey key: String) -> Result<T, DecodingError>
}
```

There is no remaining runtime/protocol dependency on `CodingKey`, `CodingKeys`, `container(keyedBy:)`, or `.id` key cases. The only remaining `CodingKey` name is `CodingKeyStrategy`, which is a key naming strategy enum, not Swift-style key machinery.

## Marker Support

Markers are now a first-class declaration kind:

```range
marker codingKey<T>(_ value: String): Let<T> -> String {
    return value
}
```

The important shape is:

```range
construct Marker: Syntax {
    construct Declaration: Syntax {
        let identifier: Identifier
        let parameters: [Parameter.Declaration]
        let target: TypeReference
        let valueType: TypeReference
    }

    construct Application<Value>: Syntax {
        let identifier: Identifier
        let value: Value
    }
}
```

Marker applications are exposed generically through syntax target values. For stored lets:

```range
construct Let<T>: Property, SyntaxEmittable {
    let macros: [Macro.Application]
    let markers: [Marker.Application]
    let identifier: Identifier
    let type: TypeReference
    let value: Expression?
}
```

That means parent macros inspect metadata in a normal collection-oriented way:

```range
let codingKeyMarkers: [Marker.Application] = property.markers.filter { application in
    application.identifier.name == "codingKey"
}

let codingKeyValues: [String] = codingKeyMarkers.map { application in
    application.value
}
```

This is intentionally not hardcoded to a special `property.codingKey` field. `codingKey` is just one marker application among many.

Marker values are evaluated at compile time and checked against the marker return type. Current primitive checked value types include `String`, `Int`, `Float`, and `Bool`. A mismatch produces a real diagnostic, for example:

```text
Marker #badKey evaluated value does not match String.
```

## Identifier Syntax Values

Property names moved from raw `String` use toward explicit syntax values:

```range
construct Identifier: SyntaxEmittable {
    let name: String
}
```

Stored properties now expose `property.identifier`, and macros use:

```range
property.identifier
property.identifier.name
```

This distinguishes a name-as-syntax from a string value. It also lets syntax-producing macros splice identifiers directly.

## Codable Macro

The current Codable implementation is in:

```text
RangeCore/Macros/Implementations/Codable.range
```

The user-facing shape is:

```range
#codable(.snakeCase)
construct User {
    let userId: Int
    let displayName: String
}
```

or:

```range
#codable(.snakeCase)
construct User {
    #codingKey("id")
    let userId: Int
}
```

`#codable` currently accepts an unlabeled strategy parameter:

```range
macro codable(_ strategy: CodingKeyStrategy = .identity): Construct { target, diagnostics in
    ...
}
```

Supported strategy enum:

```range
enum CodingKeyStrategy {
    case identity
    case snakeCase
}
```

Resolution order for a field key:

1. first `#codingKey("...")` marker value if present
2. `property.identifier.name.snakeCase()` when `#codable(.snakeCase)` is used
3. `property.identifier.name` for identity

The macro emits an extension with `encode(to:)` and `init(from:)`, using sequential `switch` statements over `Result`. On encode, success breaks and failure returns. On decode, success assigns `self.<property>` and failure returns.

## Syntax-Producing Macros

Freestanding macros can now produce syntax values directly:

```range
macro encodeProperty(container: KeyedEncodingContainer, value: Identifier, key: String) -> Switch {
    switch container.encode(#(value), forKey: key) {
    case .success:
        break
    case .failure(let error):
        return .failure(cause: error)
    }
}
```

And are invoked from another macro expansion:

```range
#(target.declaration.lets.map { property in
    #encodeProperty(
        container: container,
        value: property.identifier,
        key: codingKeyValues.first(default: property.identifier.name)
    )
})
```

This is the current answer to the repeated-statement problem. Instead of hand-building `Switch(...)` trees everywhere, a macro can write normal Range switch syntax and return `Switch`.

Important behavior:

- `macro name(...) -> SyntaxType { ... }` without a target is a freestanding syntax-producing macro.
- The body can be a syntax template, or a value-returning compile-time body.
- `#(...)` inside the syntax template splices compile-time values.
- `#otherSyntaxMacro(...)` can invoke another syntax-producing macro.
- The returned source is parsed back as the declared syntax type.

## Template Validation And Warnings

Syntax-producing macros validate that identifiers in the template come from:

- macro parameters
- local bindings inside the template
- explicit splices

This intentionally catches cases like:

```range
macro invalidEncodeSwitch(value: Identifier, key: String) -> Switch {
    switch container.encode(#(value), forKey: #(key)) {
    ...
    }
}
```

because `container` is not a parameter or local binding. The accepted shape is:

```range
macro encodeProperty(container: KeyedEncodingContainer, value: Identifier, key: String) -> Switch {
    switch container.encode(#(value), forKey: key) {
    ...
    }
}
```

Identifier splices used as member-access bases are allowed, but the expander emits a compiler warning because that chain cannot be fully proven until after expansion:

```text
Spliced Identifier is used as a member-access base. This chain is checked after macro expansion.
```

This warning is emitted by the compiler diagnostics channel, not by user macro `diagnostics.warning`.

## Macro Diagnostics

Macro diagnostics now mirror language diagnostic severities:

```range
construct MacroDiagnostics {
    function error(_ message: String)
    function warning(_ message: String)
    function information(_ message: String)
    function hint(_ message: String)
}
```

These are for user-authored macro diagnostics. Compiler/system warnings, such as risky identifier-member splices, are emitted through the compiler diagnostic engine.

## Syntax Omission

`SyntaxOmittable` was added as the planned surface for macros that remove syntax:

```range
protocol SyntaxOmittable {
    function omit()
}
```

This is present as core surface, but the larger conditional-compilation / `#if` style design is not completed.

## Diagnostics Infrastructure

The compiler now has structured diagnostic severity:

```swift
public enum RangeDiagnosticSeverity: Sendable {
    case error
    case warning
    case information
    case hint
}
```

The goal is for compiler diagnostics, macro diagnostics, LSP diagnostics, and fixture assertions to use the same severity vocabulary.

## Fixtures To Know

Important pass fixtures:

- `RangeCompilerFixtures/CompilePass/Macros/CodableMacroSynthesis.range`
- `RangeCompilerFixtures/CompilePass/Macros/SyntaxProducingMacroSwitch.range`
- `RangeCompilerFixtures/CompilePass/Macros/SyntaxProducingMacroIdentifierMemberAccess.range`
- `RangeCompilerFixtures/CompilePass/Macros/LetMacroApplicationsSurface.range`
- `RangeCompilerFixtures/CompilePass/Macros/MacroDiagnosticsWarning.range`

Important fail fixtures:

- `RangeCompilerFixtures/CompileFail/Macros/MarkerValueTypeMismatch.range`
- `RangeCompilerFixtures/CompileFail/Macros/SyntaxProducingMacroUnknownTemplateIdentifier.range`
- `RangeCompilerFixtures/CompileFail/Macros/MacroRequiresArgumentLabel.range`
- `RangeCompilerFixtures/CompileFail/Macros/CaptureRequiresSyntaxType.range`
- `RangeCompilerFixtures/CompileFail/Macros/SyntaxParameterRequiresCapture.range`

There is also an absence assertion in the compiler fixture tests to ensure `#codable` no longer emits `CodingKeys`.

## Remaining Rough Edges

- `Marker.Application` is generic in the Range surface, but the macro target builder currently stores marker application values in a compile-time object. Parent macros usually filter by `application.identifier.name` and then assume the expected value type.
- Marker value checking is primitive-type based today. Rich marker values can be designed later.
- Syntax-producing macro rendering is still a renderer/parser loop, not a fully uniform structural syntax builder for every declaration/statement/expression kind.
- `#(...)` splicing is supported, but the more ambitious `# { ... }` syntax block shape has not been implemented.
- String operations such as `snakeCase()` are still bootstrapped through storage forwarding, not a full Character/String library model.
- `SyntaxOmittable` exists, but conditional syntax redaction / region macros / compiler-macro style `#if` remains design work.

## Suggested Next Steps

1. Keep hardening generic marker access.
   Make marker arrays ergonomic without introducing one-off fields such as `property.codingKey`.

2. Expand syntax-producing macro coverage.
   The most useful next pieces are more complete rendering/parsing support for function bodies, initializer bodies, blocks, switches, assignments, and declaration lists.

3. Decide the syntax block story.
   The current system supports syntax-producing macros and `#(...)` splices. The future `# { ... }` block shape could make repeated generated code prettier, but it should not be added until the phase boundary is crisp.

4. Keep Codable macro generation boring.
   It should keep using sequential `switch` over `Result` for now. Do not reintroduce hidden throwing control flow to reduce generated-code noise.

5. Unify diagnostics through the structured diagnostic engine.
   Macro-authored diagnostics should feed the same severity/channel shape as compiler and LSP diagnostics.

