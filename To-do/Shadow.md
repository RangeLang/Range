# Shadow

Shadow is the Range sub-framework for UI styling.

It should define the language-visible model for visual style before any renderer
chooses CSS, SwiftUI, Core Animation, Skia, Canvas, Metal, or another target.
The framework starts with shape shading because shadows are the smallest styling
surface that need geometry, state, and perceptual intent at the same time.

## Core Idea

A UI element has a shape. The shape owns visual children. Shadow is one of those
children, not an implicit property baked into the shape.

```range
@Shape<5>
construct Pentagon {
}

construct StyledShape<SurfaceType, let space: ColorSpace> {
    let shape: SurfaceType
    let shadow: ShadowStack<space>
}
```

This keeps Range's visual model explicit:

- `@Shape<5>` describes sidedness as marker metadata on an ordinary construct
- `Surface` is the graph-visible metadata returned by the marker
- the shape declaration describes hit testing, clipping, layout geometry, and contours
- the shadow stack describes visual projection from that shape
- inner and outer shadows are sibling layers in the stack
- rendering backends lower the checked model into their native primitives

Shape is not only a named primitive like `RoundedRectangle`. A project can define
shape declarations directly:

```range
@Shape<3>
construct Triangle {
}

@Shape<5>
construct Pentagon {
}

@Shape<0>
construct Circle {
}
```

The marker value is graph-visible sidedness. `0` is reserved for continuous
shapes without polygonal sides. More detailed shape metadata can grow from this
same marker surface instead of requiring a special parser rule for every shape.

The marker returns `Surface`, not a passive descriptor:

```range
construct Surface {
    let sides: IntLiteral
}

marker Shape<let sides: IntLiteral>(): Construct -> Surface
```

`Surface` is the sampleable/topological domain that filters, shadows, and math
fields attach to.

The easiest concrete surface is a rectangle:

```range
@Shape<4>
construct Rectangle {
    let width: Float
    let height: Float
}
```

Mathematically, the rectangle is a finite four-sided surface with a sample domain
over `width` and `height`. Shadows and filters attach to that surface; they are
not fields inside the rectangle itself.

## Edge Projection

Projection is the bridge between shape geometry and shadow filters.

A rectangle can expose an edge as a line over its surface sample domain:

```range
construct SurfaceEdge<SurfaceType> {
    let surface: SurfaceType
    let line: MathLine<SurfaceSample>
}
```

The edge is still geometric. It does not decide whether a shadow is inside or
outside. Shadow projection does that by splitting the same edge into filter
relations:

```range
construct ShadowProjectionSample {
    let edge: SurfaceSample
    let surface: SurfaceSample
    let placement: ShadowPlacement
}

construct ShadowFilter<SurfaceType, let space: ColorSpace> {
    let edge: SurfaceEdge<SurfaceType>
    let layer: ShadowLayer<space>
    let projection: MathFunction<ShadowProjectionSample, ShadowSample>?
}

construct ShadowProjection<SurfaceType, let space: ColorSpace> {
    let edge: SurfaceEdge<SurfaceType>
    let outer: ShadowFilter<SurfaceType, space>
    let inner: ShadowFilter<SurfaceType, space>
}
```

That means a rectangle edge can feed both an outer drop shadow and an inner
shadow highlight without duplicating the edge. The edge is the source relation;
`ShadowProjection` is the split; `ShadowFilter` is the layer-specific visual
effect.

For a default rectangle, the framework can build the split from the default
configuration:

```range
function shadowProjection<SurfaceType, let space: ColorSpace>(
    edge: SurfaceEdge<SurfaceType>,
    configuration: ShadowConfiguration<space>
): ShadowProjection<SurfaceType, space>
```

The optional `projection` function is where a more advanced model can describe
how edge samples map into shadow samples. Fixed CSS-style shadows can leave it
empty and lower from offset, blur, spread, and color.

## Shadow Stack

The first standard vocabulary is intentionally small:

```range
enum ShadowPlacement {
    case outer
    case inner
}

construct ShadowLayer<let space: ColorSpace> {
    let placement: ShadowPlacement
    let offset: ShadowVector
    let radius: ShadowRadius
    let color: Color<space>
    let field: MathFunction<ShadowSample, Color<space>>?
}

construct ShadowStack<let space: ColorSpace> {
    let layers: [ShadowLayer<space>]
}
```

Outer shadows project away from the shape contour. Inner shadows project inside
the shape contour and are clipped by it. Multiple shadows are ordered. A backend
may optimize, merge, rasterize, or approximate them, but the Range meaning is
the ordered stack.

## Default Configuration

Shadow needs named configurations so simple surfaces can render without every
call site spelling every color, blur, spread, and offset.

```range
construct ShadowConfiguration<let space: ColorSpace> {
    let outer: ShadowLayer<space>
    let inner: ShadowLayer<space>
}

function defaultRectangleShadowConfiguration(): ShadowConfiguration<.rgb> {
    return ShadowConfiguration<.rgb>(
        outer: ShadowLayer<.rgb>(
            placement: .outer,
            offset: ShadowVector(x: 0.0, y: 8.0),
            radius: ShadowRadius(blur: 24.0, spread: 0.0),
            color: ColorLibrary.rgb(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.18),
            field: nil
        ),
        inner: ShadowLayer<.rgb>(
            placement: .inner,
            offset: ShadowVector(x: 0.0, y: 1.0),
            radius: ShadowRadius(blur: 2.0, spread: 0.0),
            color: ColorLibrary.rgb(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.65),
            field: nil
        )
    )
}
```

This gives the framework a default drop shadow plus inner highlight for a plain
rectangle. More configurations can specialize by state, axis, elevation, theme,
or renderer.

The active core default uses a zero spread because negative literal construction
still needs a cleaner source-level spelling in RangeCore. Backends can still use
target-specific approximations such as a negative CSS spread.

## Stored Math

Shadow math should be stored as typed Range syntax, not as shader text.

```range
construct MathFunction<Input, Output> {
    let signature: FunctionTypeReference
    let body: Closure
    let source: WrittenSyntax?
}

construct MathField<Sample, Output> {
    let value: MathFunction<Sample, Output>
}
```

The neat storage rule is:

- `signature` is the checked function type, such as `ShadowSample -> Color<space>`
- `body` is the parsed Range closure syntax
- `source` is optional provenance for tooling, not the semantic source of truth
- `MathField` names the common renderer use case: sample a typed function over
  a shape, contour, or coordinate space

That lets a shadow keep simple fixed values and also carry typed procedural math:

```range
let softness: MathFunction<ShadowSample, Color<space>>
```

A preview tool can interpret the closure directly. A GPU backend can lower the
same checked body into shader code. A CSS backend can choose a best-effort
approximation. The stored Range model stays the same.

The intended framework spelling is still `Math.Function(...)`. The current
active core surface uses `MathFunction` until ordinary nested framework types are
supported outside compiler-recognized syntax constructs.

## Alignment Axes

Shadow needs an alignment language because UI style often varies by direction:
pressed, raised, inset, focused, selected, disabled, light-from-top, or
light-from-leading-edge.

Range should model those directions as marker metadata on declarations rather
than as stringly renderer flags.

```range
#shadow.axis(.elevation)
construct Raised {
}

#shadow.axis(.interaction)
construct Pressed {
}
```

The marker attaches a named axis to a declaration. The axis becomes graph
metadata. Style code can then talk about alignment through declaration facts
instead of asking a renderer to infer intent from numeric offsets.

## Existential State Sets

Shadow states should pluralize through metatype surfaces.

```range
let states: Array<#shadow.axis>()
```

The array is not a query. It is a collection whose elements satisfy the
`#shadow.axis` marker surface. The graph may provide those states, but the type
meaning is existential: each element carries the required marker metadata.

That lets a component accept a family of styling states without knowing every
concrete state in advance.

```range
construct ShadowState<Surface, let space: ColorSpace> {
    let surface: Surface
    let stack: ShadowStack<space>
}
```

The component can specialize its shadow stack for any state that satisfies the
axis surface:

```range
let visualStates: Array<#shadow.axis>()
```

This is the important metatype rule for Shadow: a state is not just an enum case.
It can be a declaration with marker metadata, and collections of those states are
existential over the marker surface.

## Framework Boundary

Shadow should live under `RangeCore/System/Visual` as the styling sub-framework.
It should own the semantic nouns:

- `Shadow`
- `ShadowPlacement`
- `ShadowLayer<space>`
- `ShadowStack<space>`
- `ShadowAxis`
- `ShadowState`

It should not own backend lowering policy. CSS `box-shadow`, SwiftUI `shadow`,
Canvas filters, and GPU passes are backend representations of the same checked
Range model.

## Target Lowering

The backend lowering should share one Shadow model and then split by target.

Swift graphics lowering:

```swift
.shadow(color: Color(red: r, green: g, blue: b, opacity: a),
        radius: blur,
        x: offsetX,
        y: offsetY)
```

Outer shadows lower directly to SwiftUI-style `shadow` operations. Inner shadows
lower as an overlay clipped back through the source shape:

```swift
.overlay {
    shape
        .fill(color)
        .blur(radius: blur)
        .offset(x: offsetX, y: offsetY)
        .mask(shape)
}
```

HTML + CSS lowering:

```css
box-shadow: 0px 8px 24px -4px rgba(0, 0, 0, 0.18),
            inset 0px 1px 2px 0px rgba(255, 255, 255, 0.65);
```

The CSS target preserves layer order and maps `ShadowPlacement.inner` to
`inset`. Procedural `MathFunction` fields are not representable as plain
`box-shadow`; CSS lowering should approximate from fixed shadow values unless a
future CSS paint/filter backend is selected.

For rectangle drawing, HTML/CSS lowering can emit the rectangle box and the
configured shadows directly:

```css
width: 160px;
height: 96px;
box-sizing: border-box;
box-shadow: 0px 8px 24px -4px rgba(0, 0, 0, 0.18),
            inset 0px 1px 2px 0px rgba(255, 255, 255, 0.65);
```

That is real HTML/CSS drawing for fixed rectangular surfaces. The mathematical
surface still matters because the same rectangle can later lower to SwiftUI,
Canvas, a signed-distance field, or a GPU path.

## Implementation Direction

1. Keep the `RangeCore` surface small and declarative.
2. Add marker metadata for `#shadow.axis` once nested marker namespaces are ready
   enough to make this first-class.
3. Teach declaration graph queries to expose Shadow axis metadata as ordinary
   marker facts.
4. Add renderer/backend lowering after the semantic model is stable.

The standard should grow from explicit visual children, marker-backed alignment
axes, and existential state sets. That combination is what makes UI styling feel
like Range instead of like a thin wrapper over a renderer API.
