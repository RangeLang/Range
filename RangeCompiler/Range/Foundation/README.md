# Range Foundation

`Foundation` contains Range source that ships with the compiler but is not part
of the minimal `RangeCompiler/Range/Core` package surface.

The compiler loads Foundation beside Core, so these definitions are available by
default to normal Range programs. The separation keeps Core focused on the
smallest semantic substrate while still letting the toolchain provide practical
language features out of the box.

## `Macros`

Bundled macro implementations live here. They are authored in Range and loaded
by the compiler, but conceptually sit above the macro surface types in
`RangeCompiler/Range/Core/Macro`.
