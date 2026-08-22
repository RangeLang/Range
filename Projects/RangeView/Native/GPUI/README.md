# RangeView GPUI boundary

Compiler B lowers the RangeView source graph directly to LLVM. The emitted
module calls one stable foreign symbol, `rangeGPUIRun`, from the precompiled
`librange_view_gpui.a` archive.

This crate does not parse Range, select graph nodes, or generate an
intermediate Rust program. It exists only because GPUI exposes a Rust API
rather than a stable C ABI. The Range-authored backend owns the semantic
lowering and artifact pipeline in
`Projects/RangeCompilerB/Sources/CompilerB/Backend/RangeViewGPUI.range`.

The current ABI receives the app title plus an ordered array of view records.
Compiler B derives those records from one ordinary `derived body: @view`
Process and its resolved Construct Applications. This crate does not recognize
`Rectangle` or `Text` source names. RangeView's `@view` relationship establishes
drawability; `@shape` contributes that relationship and lowers its one ordered
`@many` member to a closed point path. The adapter-owned `@gpui(kind:)`
relationship remains the native encoding selector for non-shape leaves such as
Text. GPUI receives point records and paints them; it does not infer shape
semantics from source declarations.

Build the archive with:

```sh
cargo build --release
```

Run the focused graph-to-LLVM-to-native proof from the repository root:

```sh
scripts/check-range-compiler-b-rangeview-gpui
```
