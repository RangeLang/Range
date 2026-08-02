# RangeView

RangeView turns Range values into web files. It does not define a virtual DOM
or require a browser runtime.

- `Macros/` owns every RangeView macro, grouped into concern-specific files.
- `Macros/Core.range` owns the foundational `@app`, `@component`, and `@page`
  macros.
- `@component` marks a reusable renderer.
- `@page` marks a declaration that can be attached to a route.
- `@app` marks the site root that owns page discovery and emission.
- `rangeViewEmit(path:html:css:javaScript:)` writes the rendered `.html`,
  `.css`, and `.js` files.

The first built-in component is:

```range
@component
construct VStack {
    let spacing: Int
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
construct VStack {
    state spacing: Float
    binding _ children: () -> [@component]
}

VStack(spacing: 10) {
    Header()
    Text("Range")
}
.geometry { geometry in
    geometry.shape(.circle)
}
.padding(10)
```

`@component` marks declarations such as `VStack`, `Header`, and `Text`. Their
values appear inside the builder closure; the macro annotation itself does
not appear at the call site.

Every `@component` and `@page` declaration owns exactly one component body:

```range
derived body: [@component] {
    // zero or more component values
}
```

The macros reject a missing body, duplicate body, or a body whose type is not
`[@component]`. Primitive leaf components still declare an empty body.

The earlier Neat builder separated expression, block, optional, either, and
array collection. RangeView should recover those general builder operations
through the current Range-authored syntax and macro graph rather than
special-casing `VStack` or reparsing its source.

`binding _ children` gives the builder input an omitted external label while
retaining `children` as its local declaration name. The trailing closure is
therefore the direct second construction argument; its `[@component]` result
is compile-time builder syntax and must be consumed before runtime memory
layout.

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
routes declaration, or a routes declaration with the wrong type.

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

Functions marked `@styleModifier` contribute style transforms directly to the
current view:

```range
@styleModifier
function padding(_ value: Int): StyleTransform
```

That makes `.padding(10)` chainable on every component and page without
creating an artificial wrapper component. `.geometry { ... }` remains the
more general geometry observation and transformation boundary.

`Examples/HomePage.range` is the source-first reference for the intended app,
route, component, page, rendering, and command-line shapes. Each capability
must receive its own compiler fixture and supported proof before RangeView
adopts it as executable infrastructure.
