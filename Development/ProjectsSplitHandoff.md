# Projects split handoff

## Current direction

Range now has two explicit standalone projects:

```text
Projects/RangeView/
Projects/RangeCompilerB/
```

`Projects/RangeView` owns the RangeView framework sources (`Macros`,
`Application`, `Views`, `Drawing`, and `Native`) plus the source-level
application example in `Sources/RangeView/`. `@app` and `@view` are the only
application/view identities; every independently meaningful declaration lives
in an independently named file.

`Projects/RangeCompilerB` owns Compiler B's project declaration, Core,
compiler sources, native runtime, and the existing Compiler B example. It is a
standalone compiler project; Compiler A remains only the bootstrap authority.

The old standalone `GPUCanvas` and `RangeViewNativeTriangle` examples were
removed. The reusable RangeView `Triangle` declaration remains in the
RangeView framework source.

## Path updates

Active scripts now use the new project roots, including:

- `scripts/run-compiler-b-bootstrap`
- `scripts/check-range-compiler-b`
- `scripts/run-range-compiler-b-source-graph`
- RangeView ownership checks

The Compiler B Core inventory now records `Projects/RangeCompilerB/...` paths.

## Verification

Passed:

```text
git diff --check
scripts/run-compiler-b-bootstrap Projects/RangeCompilerB
scripts/run-compiler-b-bootstrap Projects/RangeView
```

The Compiler B bootstrap run printed the relocated B project files. The
RangeView route printed the complete relocated framework and application
source set.

The ordinary RangeView run was attempted with:

```text
scripts/range run Projects/RangeView
```

It is currently blocked before compilation by the known accepted-bootstrap
manifest mismatch for `RangeCompiler/Runtime/RangeRawBuffer.c`. That failure is
not caused by the project move.

## Next move

1. Resolve or explicitly audit the stale accepted runtime hash before claiming
   an ordinary RangeView compile proof.
2. Run the relocated RangeView project with its framework sources as one
   project input.
3. Continue Compiler B from its current file-discovery/lexer slice: add the
   B-owned token collection, parse a `construct` with an attached `@many(3)`
   annotation, and print the resulting syntax node before implementing macro
   expansion.

## Working-tree note

This handoff was written while the Compiler B bootstrap and project-layout
changes were still uncommitted. Preserve those dirty changes; do not reset or
promote them implicitly.
