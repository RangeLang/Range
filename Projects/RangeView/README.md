# RangeView project

This directory is the standalone RangeView project. It contains the framework
sources plus the application entrypoint and example shapes under
`Sources/RangeView/`. Compiler B is a separate sibling project at
`Projects/RangeCompilerB/`.

The old GPUCanvas and native-triangle demos are not project boundaries anymore.

Run the complete RangeView source set with:

```sh
scripts/range run Projects/RangeView
```

---

# Framework reference

RangeView turns Range values into application views. Platform backends can
present those views natively or emit web artifacts; the application model is
not organized around URLs or a virtual DOM.

- `Macros/` owns every RangeView macro, one independently named concern per
  file. `App.range` owns `@app`; `View.range` owns `@view`.
- `Drawing/` owns backend-neutral geometry, shapes, and styles.
- `Application/` owns application-level views such as `Window` and
  `NavigationStack`.
- `Views/` owns reusable general views such as `Stack`.
- `Sources/RangeView/` keeps the example app and every independent example view
  in its own file.
- `@view` is the single identity for every presentable value.
- `@app` marks the application root that owns the program entry and root view.
- `rangeViewEmit(path:html:css:javaScript:)` writes the rendered `.html`,
  `.css`, and `.js` files.

The first built-in composed view is:

```range
@view
construct Stack {
    state axis: Axis
    state spacing: Float
    state alignment: LayoutAlignment

    derived body: @view {
        // Composed view content.
    }
}
```

RangeView is the idealized language and framework surface. These declarations
may intentionally lead the supported compiler boundary; they are not compiler
fixtures and must not be used as evidence that the complete source currently
compiles.

## Authoring model

The intended RangeView surface recovers the useful builder model from the
earlier Neat web declarations:

```range
@view
construct Stack {
    state axis: Axis
    state spacing: Float
}

Stack(axis: .vertical, spacing: 10) {
    Header().alignment(.top, .center)
    Text("Range").alignment(.top, .leading)
}
.geometry { geometry in
    geometry.shape(.circle)
}
.padding(10)
```

`@view` marks declarations such as `Stack`, `Header`, and `Text`. Their values
appear inside the builder closure; the macro annotation itself does not appear
at the call site.

Every composed `@view` declaration can own one derived body:

```range
derived body: @view {
    // zero or more drawable values
}
```

There is no separate component or page category. Composite views expose a
`body`; primitive views can be lowered directly by their authored rendering
relationships. Shapes gain the same view identity through `@shape`, while leaf
values such as `Text("Hello")` carry `@view` directly.

The earlier Neat builder separated expression, block, optional, either, and
array collection. RangeView should recover those general builder operations
through the current Range-authored syntax and macro graph rather than
special-casing `Stack` or reparsing its source.

Placement is a local layout relationship. `alignment`, `position`, and
`offset` are layout modifiers attached to individual view values; a
container supplies the available boundary and resolves those values. The
result is backend-neutral `ResolvedViewGeometry`: local position, world
position, 2D size, and a separate paint layer. Occupancy is derived from that
geometry and is never stored on a view.

The trailing closure is a view's direct construction input. A
`derived body: @view` is an ordinary derived Range value and is consumed before
runtime memory layout.

## Application and navigation

`@app` declarations own one root view body. Navigation is composed inside that
body rather than declared as an application-wide route tree:

```range
@app
construct RangeViewApp {
    derived body: @view {
        NavigationStack {
            RangeViewHome()
        }
    }
}
```

The `@app` macro requires exactly one `derived body: @view` and emits the
program's single top-level `@main` block through `#environment`; application
entry ownership therefore lives with the app declaration rather than with an
example file. The root graph stores `main` as an optional single value, so two
app applications cannot produce two entry blocks: main collection rejects the
duplicate before LLVM emission.

`NavigationStack` owns the mutable ordered view path. Its root binding is
presented when the path is empty; pushing or removing `@view` values changes
the presented stack. A platform may map URLs, restoration data, or system
activities into that path, but those are adapters to navigation state rather
than route declarations owned by `@app`.

The emitted main constructs the application's Window directly:

```range
@main {
    Window(
        title: "RangeViewApp",
        application: RangeViewApp()
    )
}
```

Window is an ordinary `@view` declaration with a Range `String` title and an
`@app` binding. It is not an opaque platform handle. Child view, shape, text,
material, and modifier relationships lower under that Window application, so
there is no source-level renderer identity or native-C-string wrapper.

Window dimensions and placement are not intrinsic fields. They will arrive
through the same layout-modifier graph as other views (`frame`, `position`,
and related operations), after which platform lowering consumes the resolved
layout. Compiler B must consume the real `@app` expansion and Window graph
through its ordinary project pipeline; RangeView has no dedicated backend.

The first executable project slice now runs with
`scripts/range run Projects/RangeView`. The accepted compiler builds Compiler
B, Compiler B discovers the RangeView sources separately, and its ordinary
project emitter lowers the generated `@main` Process and the Range-authored
native lifecycle directly to LLVM. `@framework(name:)` relationships select
Metal and AppKit at link time, and the linked application contains no compiler
runtime, raw-buffer runtime, C adapter, Rust crate, or GPUI layer. This proves
the application/Metal boundary; lowering the authored Window and complete view
tree remains the next rendering slice.

The canonical application example is
`Sources/RangeView/RangeViewApp.range`. Its app/view surface is intentionally
written in RangeView terms:

```range
@app
construct RangeViewApp {
    derived body: @view {
        NavigationStack {
            RangeViewHome()
        }
    }
}

@shape
construct Rectangle {
    @many(4)
    let points: Point
}

@view
construct RangeViewHome {
    derived body: @view {
        Text("RangeView")
        Stack(.vertical, spacing: 10) {
            Rectangle().fill(.cyan)
        }
    }
}
```

The native backend may lower that geometry to a `NativeRectangle`, but that
adapter is not part of the application source. `fill` contributes a
`StyleTransform` to the render node; graph lowering resolves it into a
backend-neutral `PaintSpec` before the native color adapter runs.

`@view` emits one ordered relationship shared by every modifier family:

```range
#environment {
    extension #environment.target.Declaration.identity {
        @many
        let modifiers: @modifier
    }
}
```

`@modifier(.style)`, `@modifier(.layout)`, and future behavior modifiers append
typed values to this relationship. They do not add one stored field per
modifier to every view. The relationship ordinal preserves authored
modifier order while each lowering phase selects the categories it consumes.

The stack is an ordinary view whose navigation state belongs to the view
hierarchy:

```range
@view
construct NavigationStack {
    @many
    state path: @view

    binding _ root: () -> @view

    derived body: @view {
        root()
    }
}
```

The current declaration establishes ownership only. Path mutation, destination
selection, restoration, and backend presentation still require focused graph
and compiler proofs before they are claimed as executable Range behavior.

Builder output is a graph of backend-neutral view, layout, and geometry intent.
It is not an HTML node tree and it is not a text-to-CSS program.

Functions marked `@modifier` contribute typed values to the current
view's ordered modifier relationship:

```range
@modifier(.style)
function fill<Paint: @color>(_ color: Paint): StyleTransform
```

That makes `.fill(Color.cyan)` available through ordinary member access without
creating an artificial wrapper view or adding a stored `fill` field to every
view. `.geometry { ... }` remains the more general geometry
observation and transformation boundary.

## Drawing model

`Vector(2, Float)`, `Size`, and `DrawingSpace` are the backend-neutral 2D
values. The graph-owned `Viewport` is fixed at 800 x 600 for the first native
proof and flows into recursive Stack layout.

`Stack` owns an ordered `@many` collection of `@view` children. Nested stacks
express composition recursively; layout does not need a parallel matrix or
position representation.

`Rectangle` is the canonical first area primitive. Its four ordered points are
transformed by resolved position and size; there is no second rectangle or
layout-rectangle representation.

Shapes are their ordered points. `@shape` contributes `@view`, and the ordered
`@many` value is the path that Compiler B lowers directly:

```range
@shape
construct Triangle {
    @many(3)
    let points: Point(
        Point(x: 0, y: 100),
        Point(x: 50, y: 0),
        Point(x: 100, y: 100)
    )
}
```

The first point starts the path, each successor extends it, and the path closes
after the final point. There is no `draw()` registration wrapper and no
Triangle-specific backend rule; the exact `@shape` and `@many` relationships
select the canonical applications. A Range-authored Metal pipeline must consume
that ordered path through general Application and foreign-call lowering.

`Color` is ordinary open data, and palettes are ordinary compositions of those
values:

```range
@color
construct RGBA {
    @bounded(minimum: 0, maximum: 255)
    let red: Int

    @bounded(minimum: 0, maximum: 255)
    let green: Int

    @bounded(minimum: 0, maximum: 255)
    let blue: Int

    @bounded(minimum: 0, maximum: 255)
    let alpha: Int
}

@color
construct OKLCH {
    @bounded(minimum: 0, maximum: 1)
    let lightness: Float

    @lowerBounded(minimum: 0)
    let chroma: Float

    @cyclic(origin: 0, period: 360)
    let hue: Float

    @bounded(minimum: 0, maximum: 1)
    let alpha: Float
}

@color
enum Color {
    case red: OKLCH(
        lightness: 0.627955361,
        chroma: 0.257683308,
        hue: 29.233885192,
        alpha: 1)
}

extension Color {
    case myCustomColor: RGBA(red: 18, green: 52, blue: 86, alpha: 255)
}
```

Scalar storage stays scalar. Domain semantics attach to each member as macro
relationships: RGBA channels are bounded integers, OKLCH lightness and alpha
are bounded Floats, chroma is non-negative without inventing a false finite
maximum, and hue is cyclic rather than merely constrained between two numbers.
There is no `Bounded<Float, ...>` wrapper, generic specialization, or second
LLVM storage type. Each constraint is an `@member -> Value` transformation and
reads `#environment.target.Application.value`: bounded forms diagnose rejected
values and preserve accepted values, while cyclic forms produce the
Euclidean-modulo normalized value. The Range source now owns that behavior.
Compiler B still needs to execute implicit final macro expressions before
these observers are enforced in emitted programs.

The compiler now captures those composed expressions in the ordinary
`Enum.Case.value` syntax slot, including cases added by extensions. The next
general enum step is to evaluate the captured value and forward its
capabilities, at which point `Color.map { color in ... }` needs no synthesized
`elements` field, parallel `Array`, or separately maintained palette
container.

The six anchors and six adjacent-pair derivatives remain ordinary `Color`
values owned by `Color`. An `RGBA(...)` or `OKLCH(...)` application is already
the color representation emitted into the graph. Renderer lowering consumes
that application and maps its fields to the selected platform format; RangeView
does not route color semantics through a native `Color.c` implementation or a
parallel conversion identity. Compiler B must lower the graph-resolved
`@color` applications directly; no extraction fixture or packed renderer
placeholder represents this route.

`Sources/RangeView/RangeViewApp.range` is the source-first reference for the
intended app, navigation, view, rendering, and command-line shapes.
Each capability must receive its own compiler fixture and supported proof
before RangeView adopts it as executable infrastructure.
