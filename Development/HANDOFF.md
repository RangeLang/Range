# Range Handoff — Latest State

Date: 2026-06-10

## High-level direction

Current work is focused on making graph participation explicit and identity-backed, while moving member/property metadata away from the old `field` vocabulary.

The intended model is:

- `@graph` means a declaration participates in the graph.
- `@graph(.declaration)` and `@graph(.application)` still provide explicit roles.
- Bare `@graph` is valid and means graph participation without a specific role.
- Graph participants emit/return an `Identity`.
- `Identity` is backed by UUID storage under the shell/runtime.
- Property-like syntax declarations are graph `@member`s, not `@field`s.
- Construct declaration graph collections should expose `members`, not `fields`.

## Graph / identity changes

### `@graph`

File:

- `RangeCompiler/Foundation/Macros/Graph.range`

Current shape:

```range
macro graph(_ role: GraphRole?): Construct -> Identity { target, diagnostics in
    return Identity(uuid: UUID(storage: UUIDStorage()))
}
```

Notes:

- Role is optional: `GraphRole?`.
- Bare `@graph` is expected to work.
- The macro currently returns an `Identity` directly.
- UUID creation uses the existing backend-supported `UUIDStorage()` path.

### `Identity`

File:

- `RangeCompiler/Core/System/Identity/Identity.range`

Current shape:

```range
construct Identity {
    let uuid: UUID
}

macro identity(): Construct -> Identity { target, diagnostics in
    return Identity(uuid: UUID(storage: UUIDStorage()))
}
```

Notes:

- `Identity` now has a `uuid` field.
- `@identity` now returns `Identity`, not the string `"identity"`.

## Field → member rename

Property syntax declarations now use `@member` instead of `@field`, plus `@graph`.

Touched files:

- `RangeCompiler/Core/Syntax/Declarations/Property/Let.range`
- `RangeCompiler/Core/Syntax/Declarations/Property/Binding.range`
- `RangeCompiler/Core/Syntax/Declarations/Property/Derived.range`
- `RangeCompiler/Core/Syntax/Declarations/Property/State.range`

Current pattern:

```range
@syntax
@property
@member
@graph
construct Let<T> {
    ...
}
```

A new macro file was added:

- `RangeCompiler/Foundation/Macros/Member.range`

```range
open macro member(): Construct -> Void { target, diagnostics in
}
```

`Construct.Declaration` now exposes `members` instead of `fields`:

- `RangeCompiler/Core/Syntax/Declarations/Type/Construct.range`

```range
let members: [GraphIdentity]
```

The Swift macro target value builder/test expectations were updated toward `members` as well:

- `RangeSyntax/Sources/RangeSyntax/Macros/MacroTargetValueBuilder.swift`
- `RangeSyntax/Tests/RangeSyntaxTests/CompilerFixtureTests.swift`

## Hashing state

Existing Range hashing before the latest SHA-256 work:

- `RangeCompiler/Core/DataSystem/Hashing/Hasher.range`
- `RangeCompiler/Core/DataSystem/Hashing/HasherStorage.range`
- `RangeCompiler/Foundation/Macros/Hashable.range`

Current non-crypto hash model is still `Hasher` / `HasherStorage` / `hash(into:)`.

Important caveat:

- No concrete Swift backend implementation for `HasherStorage` was found.
- Existing `Hasher` appears to be semantic/user-facing and not yet fully wired to runtime storage.

## `@hash` macro idea

A new direct `hash` macro was started in:

- `RangeCompiler/Foundation/Macros/Hashable.range`

Current added shape:

```range
macro hash(): Construct { target, diagnostics, graph in
    target.declaration.expand {
        extension #(target.declaration.self) {
            function hash(into hasher: Hasher) {
                @hashableBody(
                    hasher: hasher,
                    properties: target.declaration.lets
                )
            }
        }
    }
}
```

Notes:

- It takes construct properties via `target.declaration.lets`.
- `@hashable` remains present for compatibility.
- The existing `Hashable macro synthesizes field combines` test failed after running, but the failure appears related to the macro not emitting the expected `Hashable` conformance in the extension:

Expected by test:

```range
extension Type: Hashable { ... }
```

Current macro emits:

```range
extension Type { ... }
```

Next step if continuing this path:

- Update both `@hash` and `@hashable` to emit `extension #(target.declaration.self): Hashable { ... }` if that is the intended conformance model.

## SHA-256 work started

A SHA-256 language surface was added:

- `RangeCompiler/Core/DataSystem/Hashing/SHA256.range`

```range
@language
construct SHA256 {
    function digest(data: Data): Data

    function digest(string: String): Data
}
```

Backend changes started in:

- `RangeBackendSwift/Sources/SwiftBackendEmitter.swift`

Added known-call mapping:

```swift
"SHA256.digest": "Range_SHA256.digest"
```

Added runtime support enum:

```swift
enum Range_SHA256 {
    static func digest(string: String) -> Data
    static func digest(data: Data) -> Data
}
```

Implementation is a pure Swift SHA-256 implementation returning `Data` bytes. It does not depend on `CryptoKit`.

Caveats:

- The edit tool introduced broad Swift formatting churn in `SwiftBackendEmitter.swift` around existing code. Review diff carefully before committing.
- Runtime support compiled as part of the backend package build, but full backend tests had an unrelated/fixture parser failure noted below.
- No dedicated SHA-256 fixture/test has been added yet.

Suggested next validation:

1. Add a backend emission test that checks:
   - runtime contains `enum Range_SHA256`
   - calls to `SHA256.digest(string:)` lower to `Range_SHA256.digest(string:)`
2. Add a compile/run fixture hashing `"abc"` and compare bytes to the known SHA-256 digest:

```text
ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad
```

## Validation already run

Passed:

```sh
swift test --package-path RangeSyntax --filter CompilerFixtureTests/macroMetadataQueriesGraphThroughIdentities
```

Passed:

```sh
swift test --package-path RangeSyntax --filter CompilerFixtureTests/syntaxGraphProjectionContainsDeclarationAndApplicationSurfaces
```

Backend package build completed, but test suite failed in an existing fixture parse path:

```sh
swift test --package-path RangeBackendSwift
```

Failure observed:

```text
Initializer forwarding emits nested construction
Caught error: Expected '(' after #.
```

This failure did not point at SHA-256 directly; it came from parsing test fixture macro syntax around `#initForwarded`.

Hashable macro targeted test failed:

```sh
swift test --package-path RangeSyntax --filter CompilerFixtureTests/hashableMacroSynthesizesFieldCombines
```

Failure summary:

- Expected `Hashable` conformance on generated extension.
- Expected combines `id`, `name`, `active`.
- Current generated extension did not include those in the inspected result.

Likely next action:

- Make `@hash` / `@hashable` emit an extension conforming to `Hashable` and verify expansion.

## Workspace state warning

The workspace contains many pre-existing modified files beyond this handoff’s direct changes. Do not blindly reset or checkout files.

Observed modified/deleted/renamed files included:

- `Development/DesignNotes/Types/MetatypesAndSetTheory.md`
- `RangeCompiler/Core/Syntax/Declarations/Type/Function.range`
- `RangeCompiler/Foundation/Macros/CodableField.range`
- deleted `RangeCompiler/Foundation/Macros/Field.range`
- `RangeSyntax/Sources/RangeSyntax/Core/DeclarationGraph+MacroViewModels.swift`
- `RangeSyntax/Sources/RangeSyntax/Macros/AST+Macro.swift`
- renamed testing fixture `FieldAndConstructMacroSurface.range -> PropertyMacroSurface.range`

Some of these were already present before the latest edits. Preserve user work.

## Recommended next steps

1. Review `SwiftBackendEmitter.swift` diff and reduce formatting-only churn if desired.
2. Finish `@hash` / `@hashable` conformance emission:
   - likely `extension #(target.declaration.self): Hashable { ... }`
3. Add SHA-256 backend tests:
   - runtime support presence
   - known-call lowering
   - digest correctness for `"abc"`
4. Decide whether `SHA256.digest(string:)` should return raw `Data` only, or also expose hex encoding.
5. Decide whether identity UUIDs should be deterministic graph identities or fresh runtime UUIDs. Current implementation produces runtime UUID-backed identity values through `UUIDStorage()`.
