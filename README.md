# Range

Range runs `.range` programs by expanding Range-authored macros to LLVM IR and
linking that IR with `clang`.

## Run

Run a Range source file directly from the repository:

```sh
scripts/range run path/to/Main.range
```

Emit LLVM IR without linking:

```sh
scripts/range emit-llvm path/to/Main.range .range/Build/llvm/Main.ll
```

The script currently invokes the `range` compiler host through SwiftPM:

```sh
swift run --package-path RangeCompiler range emit-llvm input.range output.ll
```

That Swift host is temporary bootstrap plumbing. The outer command surface is a
shell script so it can later call a Range-built compiler binary instead.

## Current Minimal Program

```range
@main {}
```

The bundled `@main` macro currently emits:

```llvm
define i32 @main() {
entry:
  ret i32 0
}
```

## License

Copyright 2026 George Tchelidze.

Range is licensed under the [Apache License, Version 2.0](LICENSE).
