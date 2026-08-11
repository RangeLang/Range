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

RangeView turns Range values into web files. It does not define a virtual DOM
or require a browser runtime.

- `Macros/` owns every RangeView macro, grouped into concern-specific files.
- `Macros/Core.range` owns the foundational `@app`, `@component`, and `@page`
  macros.
- `Drawing/` owns backend-neutral geometry, shapes, and styles.
- `@component` marks a reusable renderer.
- `@page` marks a declaration that can be attached to a route.
- `@app` marks the site root that owns page discovery and emission.
- `rangeViewEmit(path:html:css:javaScript:)` writes the rendered `.html`,
  `.css`, and `.js` files.

The first built-in component is:

```range
@component
construct Stack {
    state axis: Axis
    state spacing: Float
    state alignment: LayoutAlignment
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
@component
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

`@component` marks declarations such as `Stack`, `Header`, and `Text`. Their
values appear inside the builder closure; the macro annotation itself does
not appear at the call site.

Every `@component` declaration owns exactly one derived component view:

```range
derived view: [@component] {
    // zero or more component values
}
```

The `@component` macro queries the underlying construct and rejects a missing
view, duplicate view, or a view whose type is not `[@component]`. Primitive
leaf components still declare an empty view. `@page` retains its separate
`derived body` contract until the page surface moves to the same model.

The earlier Neat builder separated expression, block, optional, either, and
array collection. RangeView should recover those general builder operations
through the current Range-authored syntax and macro graph rather than
special-casing `Stack` or reparsing its source.

Placement is a local layout relationship. `alignment`, `position`, and
`offset` are layout modifiers attached to individual component values; a
container supplies the available rectangle and resolves those values. The
result is backend-neutral `LayoutRect` data, not HTML or native drawing calls.

The trailing closure is the component's direct view construction input. The
`@component` macro validates that the construct exposes exactly one
`derived view: [@component]`; the result is compile-time builder syntax and is
consumed before runtime memory layout.

## Routes

`@app` declarations own one derived route tree:

```range
@app
construct Website {
    derived routes: Route {
        Route("/") {
            Route("home", HomePage())
        }
    }
}
```

The `@app` macro requires exactly one member named `routes`, declared as
`derived routes: Route`. It rejects a missing routes declaration, a duplicate
routes declaration, or a routes declaration with the wrong type. Once that
shape is valid, it emits the program's single top-level `@main` block through
`#environment`; application entry ownership therefore lives with the app
declaration rather than with an example file. The root graph stores `main` as
an optional single value, so two app applications cannot produce two entry
blocks: main collection rejects the duplicate before LLVM emission.

The emitted main calls `rangeViewRunApplication()`. The native backend owns
that function and performs `SDL_Init`, creates the window and renderer, enters
the event loop, and calls `SDL_Quit` during teardown. `rangeViewOpenNativeWindow`
remains a direct compatibility entry for focused native fixtures.

The canonical application example is
`Examples/RangeViewApp.range`. Its app/page surface is intentionally written
in RangeView terms:

```range
@app
construct RangeViewApp { ... }

@shape
construct Rectangle {
    @many(4)
    let points: Point
}

@page
construct RangeViewHome {
    derived body: [@component] {
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

`@component` emits one ordered relationship shared by every modifier family:

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
modifier to every component. The relationship ordinal preserves authored
modifier order while each lowering phase selects the categories it consumes.

Routes own paths; `@page` only marks declarations that can occupy a route:

```range
construct Route {
    let _ path: String
    binding _ page: @page?
    binding _ children: () -> [Route]
}
```

Nested route paths inherit their parent prefix. A route may contain a page,
children, or both. The final route graph provides forward path matching and
reverse page-to-path lookup before the selected pages are lowered.

An omitted route-builder binding produces an empty route collection, so the
declaration does not spell an explicit empty-closure default.

`Route` owns normalization and parent/child path composition. It produces a
canonical matcher signature for each resolved node. Parameter names do not
make otherwise identical matchers unique, so `/users/:id` and
`/users/:name` have the same signature.

The `@app` macro owns whole-tree validation. After resolving every node, it
rejects:

- two nodes with the same canonical matcher signature; and
- one `@page` declaration attached to multiple canonical routes.

The second rule keeps reverse page-to-path lookup deterministic. Route aliases
can be introduced later as an explicit declaration rather than silently
choosing one repeated page path.

Builder output is backend-neutral view and geometry intent. It is not an HTML
node tree. The current backend lowers that intent into HTML, CSS, and only the
JavaScript required for observation, interaction, or runtime updates.

Functions marked `@modifier` contribute typed values to the current
component's ordered modifier relationship:

```range
@modifier(.style)
function fill<Paint: @color>(_ color: Paint): StyleTransform
```

That makes `.fill(Color.cyan)` available through ordinary member access without
creating an artificial wrapper component or adding a stored `fill` field to
every component. `.geometry { ... }` remains the more general geometry
observation and transformation boundary.

## Drawing model

`Point`, `Size`, and `DrawingSpace` are the first backend-neutral 2D values.
Window dimensions come from the drawing space instead of being repeated in a
native backend call.

`Matrix<Element>` is both the ordered collection and multidimensional layout
substrate. A list is a one-column matrix; tables, grids, and kanbans retain the
same model instead of introducing parallel container types or flexbox
semantics. `ForEachRepresentation<Element, Representation>` maps each element
and `MatrixPosition` directly into its output representation.

`RectangleRepresentation` is the first area primitive, defined by an origin
and size. The native checkpoint fills rectangles with horizontal scanlines
until a direct native rectangle ABI is proven.

Shapes expose one explicit drawing representation:

```range
@shape
construct Triangle {
    @many(3)
    let points: Point

    function draw(): ShapeRepresentation {
        return ShapeRepresentation(points: points)
    }
}
```

The `@shape` macro currently requires exactly one zero-argument `draw`
function with an explicit return type. Exact return-type identity and general
relationship-backed member materialization remain compiler work. `@many(3)`
already expresses Triangle cardinality; the compiler must consume that fact
without a Triangle-specific lowering.

`Color` is ordinary open data, and palettes are ordinary compositions of those
values:

```range
@color
construct OKLCH {
    let lightness: Float
    let chroma: Float
    let hue: Float
    let alpha: Float
}

function toRGBA(color: OKLCH): RGBA

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

The compiler now captures those composed expressions in the ordinary
`Enum.Case.value` syntax slot, including cases added by extensions. The next
general enum step is to evaluate the captured value and forward its
capabilities, at which point `Color.red.toRGBA()` and
`Color.map { color in ... }` need no synthesized `elements` field, parallel
`Array`, or separately maintained palette container.

The six anchors and six adjacent-pair derivatives remain ordinary `Color`
values owned by `Color`. Renderer adapters consume `toRGBA(color: color)`;
the resulting `RGBA` is a lowering product rather than the authored color
identity. The intended postfix
`color.toRGBA()` spelling is ordinary member-call sugar for the same operation;
reachable aggregate-return member lowering is not compiler-backed yet.

`Examples/HomePage.range` is the source-first reference for the intended app,
route, component, page, rendering, and command-line shapes. Each capability
must receive its own compiler fixture and supported proof before RangeView
adopts it as executable infrastructure.
