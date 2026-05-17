# Embedded Swift Direction

Neat's Swift implementation should be designed under Embedded Swift pressure: the compiler, CLI, backend, and generated Swift code should avoid depending on runtime features that make the system heavy, opaque, or hard to lower.

This does not mean every package can become a bare-metal firmware target immediately. It means Swift code in Neat should be written so Embedded Swift compatibility is a design constraint, not an afterthought.

## Why

Embedded Swift forces the compiler implementation toward the same values Neat wants in its own language model:

- explicit structure over runtime discovery
- predictable lowering over hidden runtime behavior
- graph metadata over reflection
- small binaries and simple linkage
- generated code that can run close to the metal

That is especially important for the compiler and Swift backend. If Neat's implementation leans on dynamic Swift behavior, it becomes harder for Neat to produce small, inspectable Swift output later.

## Practical Rule

All Swift targets should be checked against Embedded Swift restrictions during normal development.

The first step is warning-level diagnostics:

```swift
swiftSettings: [
    .treatWarning("EmbeddedRestrictions", as: .warning),
]
```

The long-term target is stricter:

```swift
swiftSettings: [
    .enableExperimentalFeature("Embedded"),
]
```

That stricter mode should be introduced target by target once the package can be built with an Embedded-capable SDK/toolchain setup.

## Porting Order

Start with `NeatSyntax`.

The syntax, graph, parser, validator, and macro-expansion model are closest to pure compiler logic. They should have the fewest reasons to depend on process APIs, filesystem APIs, runtime reflection, Objective-C interop, or Foundation-heavy behavior.

Next, port `NeatBackendSwift`.

The backend currently emits Swift and manages workspace files. The pure lowering/emission parts should move toward Embedded-compatible Swift first. Host-only file emission can remain isolated behind a small boundary.

Port `NeatCLI` last.

The CLI necessarily touches argument parsing, files, processes, terminal behavior, package operations, and the language server. That code may need host-only adapters around a smaller Embedded-compatible compiler core.

## Generated Swift

Generated Swift should also be Embedded-aware. Avoid relying on:

- reflection
- Objective-C interop
- untyped dynamic values
- broad `Any`-based runtime plumbing
- Foundation types where a small Neat runtime type would be clearer

If generated Swift needs host functionality, keep it explicit and isolated.

## Current Blocker

A direct local attempt to build `NeatSyntax` with:

```sh
swift build --package-path NeatSyntax -Xswiftc -enable-experimental-feature -Xswiftc Embedded -Xswiftc -wmo
```

failed before source diagnostics with:

```text
unable to load standard library for target 'arm64-apple-macosx13.0'
```

So the immediate path is:

1. Keep Embedded restriction warnings enabled.
2. Remove or isolate warnings from `NeatSyntax`.
3. Set up an Embedded-capable SDK/toolchain build lane.
4. Promote compatible targets from warning checks to actual Embedded builds.
