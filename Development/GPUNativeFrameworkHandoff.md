# Range Native GPU and RangeView Handoff

## Purpose

This document records the current native graphics checkpoint, the compiler and
tooling work that enabled it, what was actually executed, what remains
unverified, and the shortest path from a wgpu instance to a Range-authored GPU
render pass.

The intended product is a native, GPU-rendered RangeView framework authored in
Range. The browser/WebGPU example remains useful as a shader-generation proof,
but it is not the target backend.

## Executive Status

The repository now contains source implementations for:

- macro-authored external C functions through `@extern`;
- macro-authored native link requirements through `@link`;
- nominal borrowed native pointer handles through `@opaque`;
- direct C ABI lowering for signed `Int`, `Int<.unsigned, 8>`, opaque `ptr`, and
  `Void`;
- contextual `nil` for an opaque external parameter, lowered as LLVM
  `ptr null`;
- inferred call bindings using the required spelling
  `let value: function(label: argument)`;
- SDL2 discovery and native linkage;
- `WGPU_NATIVE_DIR` discovery and native linkage; and
- a small RangeView native window surface.

Two native checkpoints have executed successfully with disposable compilers:

1. An SDL2 accelerated window cleared a background, drew three triangle edges,
   presented them, released its renderer and window, shut SDL down, and exited
   `42`.
2. A pinned wgpu-native dylib created a real wgpu instance through
   `wgpuCreateInstance(NULL)`, released it, reported a positive wgpu version,
   and exited `42`.

The second checkpoint generated the essential LLVM directly from Range:

```llvm
%r0 = call ptr @wgpuCreateInstance(ptr null)
call void @wgpuInstanceRelease(ptr %r0)
```

This is real native wgpu initialization on macOS. It is not yet adapter, device,
surface, shader, pipeline, or render-pass initialization.

## Critical State Distinction

There are two different states that must not be conflated.

### Proven With a Disposable Compiler

- `@extern`, `@link`, and `@opaque` registration and lowering.
- Opaque pointer parameters and returns.
- Unsigned-byte SDL color parameters.
- `Void` external calls.
- SDL2 native triangle-window execution and cleanup.
- Contextual opaque `nil` producing `ptr null`.
- Rejection of `nil` for an external `Int` parameter.
- Canonical inferred call bindings such as
  `let instance: wgpuCreateInstance(descriptor: nil)`.
- The focused inferred opaque identity call, including exact LLVM, native
  linkage, and exit `42`.
- wgpu-native instance creation, release, version query, linkage, and execution.

The final disposable compiler fixed inferred-local symbol validation by asking
the initializer expression for its resolved type rather than requiring a
resolution row on the application node itself. Calls retain their resolution on
the callee node. That compiler emitted LLVM hash
`af5c448a21913a18a44bb8d3de78fa908a18de7c335e9a6a3bd9d6b5e7289a17`.

### Not Accepted or Promoted

No compiler was promoted during this work. The accepted bootstrap artifacts and
their manifest were not changed by the GPU work.

The canonical focused gate currently stops before candidate construction with:

```text
Range compiler candidate check failed: runtime input 0 hash mismatch: RangeCompiler/Runtime/RangeCompilerHost.c
```

The runtime, bootstrap LLVM, executable, manifest, and unrelated compiler work
were already modified in the shared worktree. The GPU work deliberately used a
disposable compiler instead of rewriting another checkpoint's provenance.

The maintainer explicitly chose to continue development without waiting for
manifest reconciliation. That is valid for disposable development proof, but it
is not a promotion proof.

## Canonical Range Syntax

Range local initialization uses `:`, not `=`. The desired inferred call form is:

```range
let instance: wgpuCreateInstance(descriptor: nil)
```

Do not replace it with either of these forms:

```range
let instance = wgpuCreateInstance(descriptor: nil)
let instance: RangeViewWGPUInstance(wgpuCreateInstance(descriptor: nil))
```

The first introduces the wrong assignment syntax. The second redundantly states
a result type the call already determines.

Existing explicit conversion/annotation forms such as this remain separate:

```range
let waitStatus: Int(sleep(seconds: 3))
```

The body parser currently distinguishes labeled call-form initialization and
records that local as inferred. This parser change needs the focused and broader
compiler proofs described below.

## Architecture

The native path is:

```text
Range source
  -> Range-authored registration macros
  -> typed declaration/function classification
  -> body resolution and MIR
  -> LLVM declare/call plus range-link-v1 metadata
  -> clang plus selected native libraries
  -> native executable
  -> SDL2 and/or wgpu-native
  -> Metal on macOS
```

There is no browser, DOM, JavaScript, Rust host program, or handwritten C GPU
wrapper in this path. C files are still linked as the ordinary Range runtime,
but they do not wrap SDL or wgpu calls.

## Macro-Owned FFI

### `@extern`

Source: `RangeCompiler/Sources/Core/Macro/Extern.range`

```range
construct ExternRegistration {
    let function: Function
}

macro extern(): Function -> ExternRegistration {
    return ExternRegistration(function: #environment.target)
}
```

The compiler recognizes the typed `ExternRegistration` result. It does not
special-case the macro name. Result-compatible aliases can therefore register
external functions as well.

An external declaration must be top-level, bodyless, and non-generic, and its
signature must fit the supported C ABI. It lowers to an LLVM `declare`; calls use
the authored symbol name verbatim.

### `@link`

Source: `RangeCompiler/Sources/Core/Macro/Link.range`

Current closed native library identities are:

- `.sqlite3`
- `.glfw`
- `.wgpuNative`
- `.pthread`
- `.sdl2`

The compiler emits deterministic module metadata such as:

```llvm
; range-link-v1 kind=library id=wgpuNative
```

`scripts/run-range-project` consumes that typed requirement. SDL2 is resolved
through `sdl2-config`. wgpu-native is resolved through `WGPU_NATIVE_DIR`, which
may point either to the extracted release root or directly to its `lib`
directory.

### `@opaque`

Source: `RangeCompiler/Sources/Core/Macro/Opaque.range`

Each registered construct is a distinct Range nominal type with LLVM `ptr`
representation at the external boundary. It has no emitted aggregate layout and
cannot be directly constructed as a normal Range value.

Current opaque handles are borrowed pointer tokens. Ownership, nullable state,
release policy, and reference-count behavior are not encoded in the type yet.

## Authoritative Function Classification

`compilerFunctionImplementation(...)` classifies a canonical function as one
of:

- invalid;
- Range-authored;
- external; or
- runtime intrinsic.

Resolution, reachability, MIR validation, and LLVM emission consume this one
classification. This avoids treating bodylessness or a macro spelling as an
independent authority.

Relevant files include:

- `RangeCompiler/Sources/Compiler/Syntax/CompilerFrontend.range`
- `RangeCompiler/Sources/Compiler/Body/CompilerBodyCFG.range`
- `RangeCompiler/Sources/Compiler/Body/CompilerBodyMIR.range`
- `RangeCompiler/Sources/Compiler/Body/CompilerBodyTypes.range`
- `RangeCompiler/Sources/Compiler/LLVM/CompilerBodyLLVM.range`
- `RangeCompiler/Sources/Compiler/LLVM/CompilerLLVMPlan.range`

## Nullable Opaque Arguments

The existing identifier `nil` is contextually resolved for an argument to an
external construct-typed parameter. External ABI validation remains responsible
for proving that the construct is actually an `@opaque` ABI type.

The compiler adds a distinct MIR operation:

```range
compilerBodyMIROperationForeignNull(): Int { return 55 }
```

It is intentionally separate from optional-enum absence. LLVM planning assigns
it an immediate `ptr null` value and emits no runtime instruction to construct
it.

Focused pass fixture:

- `Testing/Extern/Pass/NullableOpaqueArgument.range`

Expected LLVM:

```llvm
declare void @free(ptr %pointer)
call void @free(ptr null)
```

Focused rejection fixture:

- `Testing/Extern/Fail/NilIntArgument.range`

Expected rejection:

```text
compilerError	kind=invalidEntryReachability	stage=2
```

The disposable compiler emitted the exact `free(ptr null)` call, linked it,
executed it safely, and returned `42`. The `Int` control rejected at the exact
expected boundary.

## Inferred Call Bindings

The body parser now treats a labeled call after `let name:` as an initializer
whose result type is inferred. It records no redundant authored type span for
that local. Symbol type queries obtain the type from the resolved initializer.

Affected compiler areas:

- `CompilerBodyParsing.range` records inferred local type spans.
- `CompilerBodyTypes.range` resolves inferred symbol type kind and type ID.
- `CompilerBodyCFG.range` accepts a symbol with an inferred, resolved type.
- `CompilerBodyMIR.range` uses symbol type queries instead of raw source spans.
- `CompilerBodyOwnership.range` uses the inferred symbol type ID.

Focused fixture:

- `Testing/Extern/Pass/InferredOpaqueCall.range`
- `Testing/Extern/Pass/InferredOpaqueCallHost.c`

Required source:

```range
let pointer: rangeExternOpaqueIdentity(value: nil)
```

Expected LLVM:

```llvm
call ptr @rangeExternOpaqueIdentity(ptr null)
```

This fixture is wired into `scripts/check-range-value-ownership`. It still needs
one final disposable compiler rebuild and execution.

### Inference Risk to Check

The parser marks labeled call-form local initialization as inferred. Existing
source such as `let value: SomeType(label: argument)` also enters that branch.
Its call returns `SomeType`, so inference should preserve behavior, but this is
a broad parser semantic change and must be checked against the complete focused
suite before acceptance.

## SDL2 RangeView Checkpoint

Framework source:

- `RangeCompiler/Sources/Frameworks/RangeView/Native/Window.range`

Entry fixture:

- `Testing/RangeView/Pass/NativeWindow.range`

The Range source declares and calls:

- `SDL_Init`
- `SDL_GetPlatform`
- `SDL_CreateWindow`
- `SDL_GetWindowID`
- `SDL_ShowWindow`
- `SDL_RaiseWindow`
- `SDL_CreateRenderer`
- `SDL_SetRenderDrawColor`
- `SDL_RenderClear`
- `SDL_RenderDrawLine`
- `SDL_RenderPresent`
- `SDL_PumpEvents`
- `SDL_HasEvent`
- `SDL_Delay`
- `SDL_DestroyRenderer`
- `SDL_DestroyWindow`
- `SDL_Quit`

The proof opens an 800 by 600 native window, creates an accelerated renderer,
clears to a dark background, draws an orange triangle outline with exactly three
line calls, presents it, explicitly shows and raises the window, then services
SDL events until a quit request, then releases resources and exits `42`. With
no quit request it remains alive until the process is terminated. A blocking
libc `sleep` is not enough
on macOS: it can create the dock process without giving AppKit a presentation
cycle for the window.

The executable adapter coordinates now belong to an ordinary Range-authored
`NativeTriangle` construct whose three members are shared `Point` values.
`Size` and `DrawingSpace` are also backend-neutral RangeView values, and the
SDL window width and height are read from that drawing space rather than passed
as unrelated literals.
`Window` and `WindowRenderer` are now distinct Range-authored `@opaque`
resource identities that lower directly to pointer-backed SDL handles. The
event loop routes its close query through `rangeViewWindowShouldClose(window:)`
and currently recognizes the global SDL quit event; per-window event identity
is deliberately deferred until multiple windows are introduced.
`rangeViewDrawTriangle(renderer:triangle:)` receives the adapter by the native
Range aggregate ABI and owns the three SDL edge calls; the window lifecycle
constructs one hardcoded triangle and invokes the primitive once. Focused LLVM
inspection proves `%Range.Point`, `%Range.Size`, `%Range.DrawingSpace`,
`%Range.NativeTriangle`, its by-value draw function, one primitive call, and
exactly three external line calls. The linked native run
exited `42`; however, the original blocking-sleep version only produced a dock
application for the maintainer and did not visibly present the window. The
explicit show/raise and event-pumping revision below is the current source and
was visually confirmed by the maintainer.

The same checkpoint is now a public-run example at
`Examples/RangeViewNativeTriangle/Main.range`. Repeatable `--source` inputs let
the example consume the real framework directory without copying it:

```sh
RANGE_DEVELOPMENT_COMPILER=/path/to/RangeCompiler \
  scripts/range run Examples/RangeViewNativeTriangle \
  --source RangeCompiler/Sources/Frameworks/RangeView/Drawing/Geometry.range \
  --source RangeCompiler/Sources/Frameworks/RangeView/Drawing/Style.range \
  --source RangeCompiler/Sources/Frameworks/RangeView/Macros/Iterable.range \
  --source RangeCompiler/Sources/Frameworks/RangeView/Native
```

The source-first semantic surface keeps `Color` as an ordinary open OKLCH
construct and composes named colors inside `@iterable construct RangePalette`.
Enums remain reserved for genuine alternatives. `@iterable` registers the
construct's stored values as its source-ordered traversal relationship, so the
palette itself can map into a matrix without a generated `elements` field,
`Array`, or parallel palette list. The SDL checkpoint
continues to own final RGBA bytes until that general derived-collection path is
compiler-backed.

The example now also presents all twelve chromatic presets as a 6 by 2 matrix
of filled rectangles beneath the Triangle. A native `NativeRectangle` adapter
owns `Point` plus `Size`, and `rangeViewFillRectangle` fills it with horizontal
SDL scanlines. The focused LLVM boundary contains twelve rectangle calls and
the linked example still exits `42`.

The reusable framework surface defines `Matrix<Element>` as the canonical
ordered collection and layout model, `MatrixPosition` for coordinates,
`RectangleRepresentation` as the first area representation, and
`ForEachRepresentation<Element, Representation>` as the matrix-to-output
mapping. Lists, tables, grids, and kanbans are intended as matrix projections,
not distinct flexbox-like containers. This surface is source-first: the
compiler's general relationship-backed member materialization must consume
`@many`; Matrix must not receive a special storage lowering. Until that path is
complete, the executable SDL adapter spells out the twelve cells explicitly.

The idealized drawing surface also contains `@shape`, a `Triangle` with
`@many(3)` points and a required `draw(): ShapeRepresentation`, plus
`@styleModifier` fill and line transforms. Those declarations lead the current
compiler: fixed-cardinality member construction and exact reflected return-type
validation are not part of the executable native proof yet.

The explicit development compiler escape hatch bypasses accepted-manifest
verification only for ordinary compile/run work and reports its unpromoted
status on stderr. The default command remains strict. The current disposable
compiler public-run proof emitted LLVM SHA-256
`149a560e73ca0afea635c2e78c86bab1479a3aaaa424473fcff2a16e6072be86`,
emitted the unbounded SDL event-pump loop and linked. The public-run process
remained alive beyond the former ten-second cutoff and was then explicitly
terminated. User-visible window presentation remains distinct from that
execution proof; the maintainer previously visually confirmed the explicit
`SDL_ShowWindow`/`SDL_RaiseWindow` revision.

This is a native accelerated drawing checkpoint. It is not a shader-driven
wgpu triangle and must not be described as one.

The focused harness checks exact declarations, unsigned-byte color ABI, three
triangle line calls plus the rectangle scanline primitive, `Void` presentation,
all cleanup calls, LLVM validity, linkage, continued liveness, and explicit
process termination.

Visual screenshot capture was attempted earlier but was not retained because
`screencapture` could not write to the intended destination. Native execution
and API boundaries are proven; screenshot evidence is not.

## wgpu-native Checkpoint

Tracked fixture:

- `Testing/RangeView/Pass/WGPUInstance.range`

Canonical Range source:

```range
@opaque
construct RangeViewWGPUInstanceDescriptor {}

@opaque
construct RangeViewWGPUInstance {}

@extern
@link(.wgpuNative)
function wgpuCreateInstance(descriptor: RangeViewWGPUInstanceDescriptor): RangeViewWGPUInstance

@extern
function wgpuInstanceRelease(instance: RangeViewWGPUInstance): Void

@extern
function wgpuGetVersion(): Int

@main {
    let instance: wgpuCreateInstance(descriptor: nil)
    wgpuInstanceRelease(instance: instance)
    if wgpuGetVersion() <= 0 {
        return 1
    }
    return 42
}
```

### Pinned Dependency

- Release: `gfx-rs/wgpu-native` `v29.0.1.1`
- wgpu-native commit: `6aed50955d934ac36049ba8d002034841633ae02`
- webgpu-headers commit: `673658bc2bd70ec39fc55ebe6bb0173cf6d0a603`
- Asset: `wgpu-macos-aarch64-release.zip`
- SHA-256:
  `a5797a37b1adf720bcd5dcffb291edbbd5b7b14be0a3874c28e6393a655a7a3e`

The archive contains:

- `lib/libwgpu_native.a`
- `lib/libwgpu_native.dylib`
- C headers under `include/`

The dylib is arm64 and links to the macOS Metal, QuartzCore, Foundation, and
CoreFoundation frameworks.

### Disposable Proof Artifacts

The proof used temporary storage outside the repository:

```text
/var/folders/0h/zp0dm3ds14bbhvf68ndvl_fh0000gn/T/opencode/range-wgpu-null/
```

Important files, if the OS has not cleaned the directory:

- `RangeCompiler`: disposable compiler that supports opaque `nil`;
- `nullable-opaque.ll`: exact `free(ptr null)` proof;
- `wgpu-instance.range`: generated proof bundle;
- `wgpu-instance.ll`: generated wgpu LLVM;
- `wgpu-instance`: linked executable;
- `wgpu-macos-aarch64-release.zip`: verified release archive;
- `wgpu-native-v29.0.1.1/`: extracted release.

The temporary `RangeCompiler.ll` may be empty because an interrupted later
self-hosted rebuild truncated its output before completion. The linked
`RangeCompiler` executable remained usable and produced the successful wgpu
proof.

### Exact Result

The disposable compiler emitted:

```llvm
; range-link-v1 kind=library id=wgpuNative
%r0 = call ptr @wgpuCreateInstance(ptr null)
call void @wgpuInstanceRelease(ptr %r0)
```

The module validated with clang, linked against the pinned dylib with an rpath,
executed, and exited `42`.

This proves:

- typed wgpu link metadata;
- resolution of a pinned native dylib;
- opaque descriptor and instance pointer ABI;
- a nullable descriptor parameter;
- real wgpu instance creation;
- release through the authored opaque handle;
- scalar wgpu version return; and
- Metal-backed native library loading on the current macOS arm64 host.

It does not prove adapter enumeration, adapter selection, device creation,
surface creation, command encoding, WGSL compilation, presentation, or drawing.

## Linker Behavior

`scripts/run-range-project` now handles `.wgpuNative` as follows:

1. Require `WGPU_NATIVE_DIR`.
2. Accept either the extracted root or its `lib` directory.
3. Require `libwgpu_native.dylib` or `libwgpu_native.a`.
4. Add `-L`, `-lwgpu_native`, and an rpath to the resolved directory.

Example environment:

```bash
export WGPU_NATIVE_DIR=/path/to/wgpu-native-v29.0.1.1
```

`RangeCompiler/Sources/Core/Package/LinkPlan.range` currently adds only
`-lwgpu_native`; it does not yet mirror `WGPU_NATIVE_DIR` discovery. Keep the
shell runner and Range-authored link planner behavior aligned in the next build
tooling slice.

## Focused Harness Integration

`scripts/check-range-value-ownership` contains checks for:

- scalar `@extern` registration, declarations, calls, native execution, aliases,
  and rejection controls;
- typed SQLite `@link` metadata and native linkage;
- opaque pthread handles and identity-preserving pointer calls;
- nullable opaque `free(nil)` lowering and execution;
- the non-opaque `nil` rejection control;
- inferred opaque call binding and host execution; and
- the SDL2 RangeView triangle window and cleanup.

The inferred binding additions pass when executed directly with the final
disposable compiler. They have not run through the supported harness because
the harness stops at the unrelated runtime manifest mismatch.

## Verification Completed

The following checks passed during the native GPU work:

- disposable compiler construction from current source snapshots;
- exact LLVM `declare` and `call` inspection for FFI checkpoints;
- clang LLVM validation for emitted native modules;
- SQLite external linkage and exit `42`;
- pthread opaque-handle linkage and exit `42`;
- SDL2 native window linkage, event-driven liveness, and explicit termination;
- `free(ptr null)` linkage and exit `42`;
- rejection of `nil` as an `Int` external argument;
- pinned wgpu archive SHA-256 verification;
- wgpu dylib architecture and dependency inspection;
- wgpu instance creation, release, version query, and exit `42`;
- the unchanged inferred opaque identity fixture, including exact
  `call ptr @rangeExternOpaqueIdentity(ptr null)`, LLVM validation, native
  linkage, and exit `42`;
- the unchanged tracked wgpu fixture, including typed `wgpuNative` link
  metadata, `wgpuCreateInstance(ptr null)`, release, version query, LLVM
  validation, native dylib linkage, and exit `42`;
- `bash -n scripts/check-range-value-ownership`;
- `bash -n scripts/run-range-project`;
- C syntax validation for `InferredOpaqueCallHost.c`; and
- `git diff --check`.

## Verification Still Required

Run these in order once bootstrap/runtime provenance is internally consistent:

1. Run `scripts/range check-value-ownership` once bootstrap/runtime provenance
   is internally consistent.
2. Run `scripts/range check-value-ownership --controls` to include the complete
   positive and rejection set.
3. Continue through the repository validation ladder only when preparing a
   deliberate stable compiler checkpoint.

Do not promote merely to test these source changes. Promotion requires explicit
maintainer approval and the canonical candidate/reproduction proof.

## Next wgpu ABI Boundary

### Instance Creation Is Complete

wgpu-native v29 exposes:

```c
WGPUInstance wgpuCreateInstance(
    WGPU_NULLABLE const WGPUInstanceDescriptor *descriptor);
```

Passing `NULL` selects default instance behavior, so no C descriptor layout was
needed for the first checkpoint.

### Adapter Acquisition Is the Next Hard Boundary

wgpu-native v29 exposes adapter request through a by-value callback descriptor
and a by-value future result. Conceptually:

```c
WGPUFuture wgpuInstanceRequestAdapter(
    WGPUInstance instance,
    const WGPURequestAdapterOptions *options,
    WGPURequestAdapterCallbackInfo callbackInfo);
```

`options` may be `NULL` for the first macOS proof. The blocking requirements are:

- C-layout aggregates passed by value;
- a C function pointer callback;
- callback userdata pointers;
- a `WGPUFuture` containing a 64-bit ID;
- callback mode enum/scalar handling; and
- a way to poll or wait until the callback completes.

The callback-info layout includes a chain pointer, callback mode, callback
function, and two userdata pointers. Do not fake this with a C wrapper if the
goal remains Range-authored FFI.

### Recommended ABI Sequence

1. Add fixed C-layout construct registration for fields composed of supported
   scalars and opaque pointers.
2. Prove one by-value C struct parameter against a small local C host fixture.
3. Add 64-bit unsigned scalar support required by `WGPUFuture` and size-like
   fields.
4. Add external callback/function-pointer values with a focused synchronous C
   host fixture.
5. Add callback userdata and lifetime rules.
6. Declare `WGPURequestAdapterCallbackInfo` in Range.
7. Call `wgpuInstanceRequestAdapter(instance, nil, callbackInfo)` and prove a
   successful adapter callback.
8. Add device request through the same callback model.

Do not combine all of these into one unreviewable FFI patch.

## Path From Adapter to Triangle

After adapter and device acquisition, the minimum real wgpu rendering path is:

1. Obtain a native SDL window handle appropriate for macOS.
2. Create a Metal-compatible `WGPUSurface` through the WebGPU chained surface
   descriptor.
3. Query surface capabilities and choose a supported texture format.
4. Configure the surface with device, format, usage, dimensions, present mode,
   and alpha mode.
5. Create a WGSL shader module from a `WGPUStringView` and chained WGSL source
   descriptor.
6. Create a pipeline layout and render pipeline.
7. Acquire the current surface texture and create a texture view.
8. Create a command encoder.
9. Begin a render pass with a color attachment.
10. Bind the pipeline and call `draw(3, 1, 0, 0)`.
11. End the pass, finish the command buffer, submit it, and present the surface.
12. Release all resources in reverse ownership order.

Additional ABI surfaces required along that path include:

- C string views and stable UTF-8 backing storage;
- chained descriptors;
- nullable pointers beyond the first descriptor;
- arrays plus count fields;
- enums and flags with exact widths;
- `size_t`, `uint32_t`, and `uint64_t` distinctions;
- aggregate return/out values such as surface textures;
- native platform handles; and
- deterministic release/lifetime policy.

The first shader-driven proof should be a clear-color render pass. Add a triangle
only after surface acquisition, configuration, submission, and presentation are
individually proven.

## RangeView Direction

RangeView remains the idealized language/framework design and may lead current
compiler support. The native files are an implementation checkpoint, not a
reason to reduce RangeView to SDL calls.

The intended layering is:

```text
RangeView components and geometry intent
  -> Range-authored render planning
  -> typed GPU resources and commands
  -> wgpu-native Range declarations
  -> Metal/Vulkan/DX12
```

Keep these distinctions:

- SDL2 currently proves native windowing and a drawing lifecycle.
- wgpu-native currently proves native GPU-library initialization.
- neither currently lowers a RangeView component tree to GPU commands.
- the final framework should own layout, resource lifetimes, shader values,
  event handling, and scheduling in Range source.

Do not hard-code shader concepts into compiler builtins. Add general FFI and
layout capabilities with focused proofs, then author the graphics framework on
top.

## Known Risks and Open Questions

- The inferred-local parser change affects all labeled call-form locals and
  needs the complete focused suite.
- `ForeignNull` is intentionally runtime FFI behavior; compile-time macro value
  evaluation does not currently materialize it.
- Opaque handles are borrowed tokens without ownership qualifiers.
- Comparing opaque pointers to `nil` is not proven. Existing pointer equality
  paths may be String-oriented and must not be assumed safe for handles.
- The current wgpu version return is declared as Range `Int` although the C API
  returns `uint32_t`; the positive value fits this checkpoint, but permanent C
  integer-width semantics should be explicit.
- `WGPU_NATIVE_DIR` is implemented in the shell runner but not yet in the
  Range-authored link planner.
- The release artifact is downloaded to temporary storage and is not vendored
  or cached by a repository-supported dependency command.
- A cross-platform policy is still needed for release asset selection and
  checksums.
- SDL window handles have not been bridged to a wgpu surface.
- No event loop exists; the SDL proof sleeps for three seconds.
- Error cleanup on every early SDL return is not complete; successful-path
  cleanup is proven.
- No visual screenshot artifact is retained.
- No adapter/device callback lifetime model exists.
- No accepted compiler contains this work yet.

## Immediate Next Actions

1. Implement one general by-value C-layout aggregate fixture.
2. Implement one general external callback fixture.
3. Use those capabilities for `wgpuInstanceRequestAdapter`.
4. Stop at a successful adapter callback and record exact LLVM and native
   execution before starting device or surface work.
5. Evolve RangeView `@app` from validation into one explicit native-window
   lifecycle only after its generated entry/body boundary is compiler-backed;
   add multiple independently identified windows after the single-window
   lifecycle and event ownership are explicit.

## Files Changed or Added for This Work

### Compiler and Core

- `RangeCompiler/Sources/Core/Macro/Extern.range`
- `RangeCompiler/Sources/Core/Macro/Link.range`
- `RangeCompiler/Sources/Core/Macro/Opaque.range`
- `RangeCompiler/Sources/Core/Package/LinkPlan.range`
- `RangeCompiler/Sources/Compiler/Syntax/CompilerFrontend.range`
- `RangeCompiler/Sources/Compiler/Body/CompilerBodyCFG.range`
- `RangeCompiler/Sources/Compiler/Body/CompilerBodyMIR.range`
- `RangeCompiler/Sources/Compiler/Body/CompilerBodyModel.range`
- `RangeCompiler/Sources/Compiler/Body/CompilerBodyOwnership.range`
- `RangeCompiler/Sources/Compiler/Body/CompilerBodyParsing.range`
- `RangeCompiler/Sources/Compiler/Body/CompilerBodyTypes.range`
- `RangeCompiler/Sources/Compiler/LLVM/CompilerBodyLLVM.range`
- `RangeCompiler/Sources/Compiler/LLVM/CompilerLLVMPlan.range`

### RangeView and Fixtures

- `RangeCompiler/Sources/Frameworks/RangeView/Native/Window.range`
- `Testing/Extern/Pass/NullableOpaqueArgument.range`
- `Testing/Extern/Pass/InferredOpaqueCall.range`
- `Testing/Extern/Pass/InferredOpaqueCallHost.c`
- `Testing/Extern/Fail/NilIntArgument.range`
- `Testing/RangeView/Pass/NativeWindow.range`
- `Testing/RangeView/Pass/WGPUInstance.range`
- other existing extern/link/opaque controls under `Testing/Extern/` and
  `Testing/Link/`

### Tooling and Tracking

- `scripts/check-range-value-ownership`
- `scripts/compile-range-project`
- `scripts/run-range-project`
- `TODO.md`

## Handoff Rules

- Preserve unrelated dirty worktree changes.
- Do not reset or rewrite accepted bootstrap artifacts.
- Do not promote without explicit maintainer approval.
- Use disposable compilers for continued development while provenance is dirty.
- Keep `let value: call(...)` as the canonical inferred binding syntax.
- Do not add `=` assignment syntax.
- Keep RangeView design-forward and distinguish it from proven compiler support.
- Do not call the SDL line triangle a wgpu render pass.
- Do not call wgpu instance creation GPU drawing.
- Add each new ABI feature with a focused pass fixture, exact LLVM assertions,
  native execution, and a neighboring rejection control.
