# Range LLVM Lowering Handoff

Date: 2026-06-19

## Current Backend Reality

Normal Range execution still runs through the Range Swift-hosted emission pipeline (Swift):

```text
Range source
-> Range compiler pipeline (Swift)
-> generated Swift workspace
-> optional LLVM IR/object for supported scalar functions
-> Swift compiler
-> executable
```

Range LLVM emitter (Swift) is an internal native lowering path inside that generated Swift workspace. Swift remains the program driver today. LLVM is used for supported scalar compute islands.

## Work Completed In This Thread

### LLVM island direct lowering

Range Swift-hosted emission pipeline (Swift) no longer treats the Swift bridge as the source of truth for LLVM lowering.

Changed file:

- `RangeCompiler/Sources/RangeEmission/SwiftBackendEmitter.swift`

What changed:

- Added `llvmLoweredCallableNames`.
- `collectLLVMLoweredCallables` now first collects all lowerable callables.
- It then includes Swift-bridgeable roots plus their lowerable dependencies.
- Construct-typed helper functions can stay inside the LLVM island even when they cannot be bridged to Swift.
- Swift source omission is based on `llvmLoweredCallableNames`, not bridge presence.
- Added clearer rejection reason text for non-bridgeable LLVM-lowered helpers.

Added test:

- `Swift workspace emission keeps construct helpers inside LLVM island`
- File: `RangeCompiler/Tests/RangeEmissionTests/LLVMLoweringEmitterTests.swift`

### `map` macro surface tweak

Range bundled syntax macros (Range) changed `map` to take a typed collection.

Changed file:

- `RangeCompiler/Range/Foundation/Macros/Syntax.range`

Current shape:

```range
open macro map<T>(collection: Array<T>, @spliced syntax: @syntax): @syntax { target, diagnostics in
    return syntax
}
```

Validation that passed:

```sh
PATH="$HOME/.swiftly/bin:$PATH" swift test --package-path RangeCompiler --filter 'CompilerFixtureTests/syntaxDeclarationsAreSyntaxFacingThroughMetadata'
```

Note: this file was later not shown dirty in the final status before this handoff, so verify whether it was already committed or otherwise restored before relying on it.

### Reverted temporary `Let.range` experiment

RangeCore syntax declarations (Range) had a temporary experiment around:

```range
let value: @type<@value>
```

User asked to drop that for now and focus on `Int`.

Reverted file:

- `RangeCompiler/Range/Core/Syntax/Declarations/Property/Let.range`

Final check showed no diff for `Let.range`.

### Width and signedness aware `Int` lowering

Range LLVM emitter (Swift) now handles explicit integer width and signedness instead of assuming every Range `Int` is Swift `Int64` / LLVM `i64`.

Changed files:

- `RangeCompiler/Sources/RangeEmission/LLVMLowerability.swift`
- `RangeCompiler/Sources/RangeEmission/LLVMLoweringEmitter.swift`
- `RangeCompiler/Sources/RangeEmission/SwiftBackendEmitter.swift`
- `RangeCompiler/Tests/RangeEmissionTests/LLVMLoweringEmitterTests.swift`

Current model:

```swift
case int(bits: Int, signed: Bool)
static let defaultInt = ScalarType.int(bits: 64, signed: true)
```

Range type forms handled:

- `Int` -> signed 64-bit default
- `Int<8>`
- `Int<8, .signed>`
- `Int<8, .unsigned>`
- other positive widths, including non-Swift widths like `Int<13, .unsigned>`

LLVM behavior:

- `Int<bits, ...>` lowers to LLVM `i<bits>`.
- Signed division uses `sdiv`.
- Unsigned division uses `udiv`.
- Signed remainder uses `srem`.
- Unsigned remainder uses `urem`.
- Signed comparisons use signed predicates such as `slt`, `sle`, `sgt`, `sge`.
- Unsigned comparisons use unsigned predicates such as `ult`, `ule`, `ugt`, `uge`.
- Integer widening uses `sext` for signed values and `zext` for unsigned values.
- Integer narrowing uses `trunc`.
- `Int` literals default to signed `i64`, but binary lowering narrows literal constants to the explicit operand type when appropriate, so `Int<8, .unsigned> + 1` emits `add i8`.

Swift bridge behavior:

- Range Swift-hosted emission pipeline (Swift) only bridges integer widths Swift can represent directly:
  - `Int8`, `UInt8`
  - `Int16`, `UInt16`
  - `Int32`, `UInt32`
  - `Int64`, `UInt64`
- Nonstandard widths like `Int<13, .unsigned>` are still valid inside LLVM islands but are not Swift-bridgeable.

Added tests:

- `Explicit Int width lowers to matching LLVM integer type`
- `Unsigned Int comparison and division use unsigned LLVM operations`
- `Signed custom-width Int comparison uses signed LLVM predicate`

Validation that passed:

```sh
PATH="$HOME/.swiftly/bin:$PATH" swift test --package-path RangeCompiler --filter LLVMLoweringEmitterTests
```

Result:

- 57 LLVM lowering tests passed.
- `git diff --check` was clean.

## Design Decisions From The Discussion

### Direct lowering, not bridging

The desired direction is to directly lower supported Range constructs to LLVM rather than routing semantics through Swift.

Important wording:

- Swift remains the current program driver.
- LLVM should become the native lowering path for supported construct behavior inside that Swift-driven workspace.
- The bridge is only for calling into and out of LLVM islands, not for defining primitive semantics.

### `@llvm` belongs on constructs

The user clarified that `@llvm` should be attached to constructs, not functions.

Desired direction:

```range
@llvm {
    ...
}
construct Int<let bits: IntLiteral, let signedness: Signedness = .signed> {
    ...
}
```

Reasoning:

- Primitive behavior belongs to the construct/type.
- Operators/functions on that construct should be able to use construct-owned lowering metadata.
- This avoids scattering primitive lowering templates over individual functions.

### First `@llvm` step

The first implementation should be narrow:

- Add a Range-authored `llvm` macro declaration that accepts a raw foreign body.
- Preserve the raw LLVM template body on `ConstructDeclaration.macros`.
- Let Range LLVM emitter (Swift) inspect construct-level `@llvm` metadata.
- Keep current hardcoded integer instruction selection initially.
- Then replace the hardcoded table with construct-owned templates once the metadata path is proven.

Relevant existing support:

- `MacroApplication` already stores `rawBodyLanguage` and `rawBody`.
- `ConstructDeclaration` already stores attached `macros`.
- Parser support already allows macro raw bodies if macro metadata declares a foreign body language.

Likely macro declaration shape:

```range
open macro llvm(body: Foreign<LLVM>): Construct -> Void { target, diagnostics in
}
```

Likely new core text marker:

```range
construct LLVM { }
```

Existing similar pattern:

- `RangeCompiler/Range/Core/System/Text/Foreign.range`
- `RangeCompiler/Range/Core/Macro/WrittenSyntax.range`

Current `Foreign` declaration:

```range
construct Foreign<Language> { }
```

Existing raw body macro example:

```range
macro WrittenSyntax(text: Foreign<ASCII>): @syntax -> WrittenSyntax { target, diagnostics in
}
```

## Syntax And Macro Cleanup Discussion

This was design discussion only, not fully implemented in this thread.

Desired direction:

- Remove or shrink `WrittenSyntax`.
- Make `@syntax` the real syntax carrier.
- Avoid Swift hardcoding for rendering where Range-authored syntax macros can own it.
- Let syntax carry template data plus values so it can lower into LLVM or another native representation later.

Current blockers/places that still smell Swift-heavy:

- `RangeCompiler/Sources/RangeCompiler/Macros/MacroSyntaxRenderer.swift`
- `RangeCompiler/Sources/RangeCompiler/Macros/MacroExpander+Expansion.swift`
- `RangeCompiler/Sources/RangeCompiler/Macros/MacroTargetValueBuilder.swift`
- `RangeCompiler/Sources/RangeCompiler/Macros/CompileTimeValueEvaluator.swift`

Important direction:

- Do not duplicate construct JS-style syntax rendering logic.
- Prefer one Range-authored syntax value/rendering model.
- Compile-time values and normal values should move toward a unified value model where possible.

## Identity And Graph Design Discussion

This was design discussion only. The temporary `Let.range` experiment was reverted.

Ideas discussed:

- Merge `identity` and `identifier` concepts.
- Use one identity model.
- Possible model:

```range
@syntax($name)
construct Identifier {
    let name: String
    let identity: GraphIdentity
}
```

Possible graph identity shape discussed:

```range
construct GraphIdentity {
    let id: UUID
    let parents: Array<UUID>
    let children: Array<UUID>
}
```

Alternative relationship table shape discussed:

```range
construct GraphRelationship {
    let parent: UUID
    let child: UUID
}
```

User concern:

- A join-table-like in-memory relationship model feels old/heavy.

Possible direction:

- Add an `@identity` macro that marks a construct as an identity participant.
- Let identity define graph participation declaratively rather than embedding relationship storage everywhere.

No implementation was done here.

## UUID Lowering Discussion

No implementation was done in this thread.

Desired direction:

- Drop `UUIDStorage` eventually.
- Make `UUID` implement itself directly.
- Lower bytes directly.
- Add `UUID.new` that creates a new UUID.

Reference algorithm discussed:

```swift
let hex = Array("0123456789abcdef")
var b = (0..<16).map { _ in UInt8.random(in: .min ... .max) }
b[6] = (b[6] & 15) | 64
b[8] = (b[8] & 63) | 128

var s = String()
s.reserveCapacity(36)
for (i, x) in b.enumerated() {
    if i == 4 || i == 6 || i == 8 || i == 10 { s.append("-") }
    s.append(hex[Int(x >> 4)])
    s.append(hex[Int(x & 0xF)])
}
return s
```

Likely prerequisite:

- More direct primitive lowering for byte arrays, random bytes, string construction, and fixed-size data.

## Current Dirty Files At Handoff Creation

`git status --short` showed:

```text
 M RangeCompiler/Sources/RangeEmission/LLVMLowerability.swift
 M RangeCompiler/Sources/RangeEmission/LLVMLoweringEmitter.swift
 M RangeCompiler/Sources/RangeEmission/SwiftBackendEmitter.swift
 M RangeCompiler/Tests/RangeEmissionTests/LLVMLoweringEmitterTests.swift
```

No implementation edits for construct-level `@llvm` had been applied yet when this handoff was created.

## Recommended Next Steps

1. Add `construct LLVM { }`.
2. Add bundled `llvm` macro declaration that accepts `Foreign<LLVM>` and targets `Construct`.
3. Attach `@llvm { ... }` to `construct Int`.
4. Add a parser/compiler test proving the raw body is preserved on `ConstructDeclaration.macros`.
5. Add Range LLVM emitter (Swift) metadata plumbing from constructs into integer lowering.
6. Keep current hardcoded integer operation lowering as a fallback until template parsing is implemented.
7. Replace hardcoded integer operation lowering with construct-owned templates incrementally.

Suggested first validation commands:

```sh
PATH="$HOME/.swiftly/bin:$PATH" swift test --package-path RangeCompiler --filter LLVMLoweringEmitterTests
PATH="$HOME/.swiftly/bin:$PATH" swift test --package-path RangeCompiler --filter CompilerFixtureTests
git diff --check
```

Note: broad `CompilerFixtureTests` previously hung once and was killed manually. Prefer narrow filters first when iterating.
