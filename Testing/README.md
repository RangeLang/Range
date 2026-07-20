# Native compiler proof fixtures

This folder contains only focused inputs consumed by the self-hosted compiler
candidate verifier. It is not a general language conformance suite.

- `SelfHosting/MacroFamilyMemory` protects candidate graph and macro-family
  memory behavior.
- `SelfHosting/ArrayWriteOutOfBounds.range` protects a native bounds failure.
- `CompileFail/Collections/ImmutableArrayIndexedAssignment.range` protects the
  one retained negative collection diagnostic used by candidate verification.

The retained `RangePlayground/Examples/LLVM` programs are likewise candidate
lowering checks, not evidence that the complete Foundation or project language
surface is operational. Run the supported gates with:

```sh
scripts/range check-compiler-candidate
scripts/range check-stage2-compiler
scripts/range compiler progression
```

Add a fixture only when it protects behavior implemented by the Range-authored
compiler and is wired into a native proof command.
