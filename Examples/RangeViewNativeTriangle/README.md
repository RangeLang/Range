# RangeView native Triangle

This example opens one native SDL2 window, draws the framework's hardcoded
`Triangle`, then displays the twelve anchor-and-derivative colors as a 6 by 2
matrix of filled rectangles. It keeps pumping native events until the window
closes or the process is killed; a normal window close releases the native
resources and returns `42`. `Window` and `WindowRenderer` are distinct
Range-authored opaque resource types.

Run it with the accepted compiler after the next approved compiler promotion:

```sh
scripts/range run Examples/RangeViewNativeTriangle \
  --source RangeCompiler/Sources/Frameworks/RangeView/Drawing/Geometry.range \
  --source RangeCompiler/Sources/Frameworks/RangeView/Drawing/Style.range \
  --source RangeCompiler/Sources/Frameworks/RangeView/Macros/Iterable.range \
  --source RangeCompiler/Sources/Frameworks/RangeView/Native
```

While developing compiler changes before promotion, select the disposable
compiler explicitly:

```sh
RANGE_DEVELOPMENT_COMPILER=/path/to/RangeCompiler \
  scripts/range run Examples/RangeViewNativeTriangle \
  --source RangeCompiler/Sources/Frameworks/RangeView/Drawing/Geometry.range \
  --source RangeCompiler/Sources/Frameworks/RangeView/Drawing/Style.range \
  --source RangeCompiler/Sources/Frameworks/RangeView/Macros/Iterable.range \
  --source RangeCompiler/Sources/Frameworks/RangeView/Native
```

RangeView's source-first semantic model keeps `Color` as ordinary OKLCH data
and composes the named values in an `@iterable RangePalette` construct. The
macro registers the palette itself for source-ordered traversal; it does not
synthesize an `elements` field or an `Array`. Collection operations such as
`map` will consume that relationship directly.
The native checkpoint keeps final RGBA bytes inside its SDL adapter until that
general derived-collection path is compiler-backed.

The reusable RangeView model treats `Matrix<Element>` as the collection and
layout substrate. `ForEachRepresentation` maps each element and its
`MatrixPosition` into a representation; lists, tables, and kanbans are
dimensional projections of that matrix rather than separate flexbox-like
containers. The ordinary relationship-backed storage path must materialize
`@many` elements without a Matrix-specific lowering; until that general path
is complete, the native adapter spells out twelve cells while proving the
rectangle drawing boundary.
