# Gradient Visual Model

Gradient should share the same visual framework as Shadow.

The honest relation for a gradient is a math function:

```range
Gradient: Sample -> Color<space>
```

Everything else is definition/control data for that function.

A gradient point is not just a coordinate. It is a coordinate plus a link to
shared color state.

```range
construct SharedColor<let space: ColorSpace> {
    state value: Color<space>
}

construct BoundColor<let space: ColorSpace> {
    binding value: Color<space>
}

construct GradientPoint<let space: ColorSpace> {
    let x: Float
    let y: Float
    let color: SharedColor<space>
}
```

Because the color is shared state, multiple points and edges can refer to the
same declared color. Updating the color updates every visual contribution that
links to it.

Use `state` when the gradient owns the color. Use `binding` when the color is
provided by another model, theme, component, or editor selection.

## Algorithmic Color Links

Colors also need to be linkable by math, not only by direct reference.

```range
construct ColorLink<Sample, let space: ColorSpace> {
    let source: SharedColor<space>
    let transform: MathFunction<Sample, Color<space>>
}

construct BoundColorLink<Sample, let space: ColorSpace> {
    binding source: Color<space>
    let transform: MathFunction<Sample, Color<space>>
}
```

The direct link is `source`. The algorithmic link is `transform`. A backend can
evaluate the function at a point, along an edge, across a surface sample, or in a
shader lowering pass.

## Stops

Stops are control metadata for the gradient function.

```range
construct GradientStop<let space: ColorSpace> {
    state position: Float
    binding color: Color<space>
}
```

The position is owned by the gradient definition because the stop belongs to the
gradient's internal control structure. The color is a binding because color is
often shared with a palette, theme token, editor swatch, or another point.

That means stops are not the gradient itself. They are metadata used to define,
inspect, edit, and lower the function.

## Edges And Axes

An edge should be generic. A gradient edge is one specialization.

```range
construct MathLine<Point> {
    let start: Point
    let end: Point
}

construct Edge<Node> {
    let start: Node
    let end: Node
}

construct Axis<EdgeType> {
    let edges: [EdgeType]
}
```

For gradients:

```range
construct GradientEdge<let space: ColorSpace> {
    let line: MathLine<GradientPoint<space>>
    let color: ColorLink<GradientPoint<space>, space>?
}

construct GradientAxis<let space: ColorSpace> {
    let edges: [GradientEdge<space>]
}
```

That gives the model multiple edges per axis, and multiple axes per gradient.
The mathematical line is the geometric path. The edge is the visual relation.
The axis is an ordered family of edges.

## Gradient Is A Function

The gradient itself should be stored as a typed math function from a sample
domain to color.

```range
construct GradientDefinition<Sample, let space: ColorSpace> {
    let stops: [GradientStop<space>]
    let points: [GradientPoint<space>]
    let axes: [GradientAxis<space>]
}

construct Gradient<Sample, let space: ColorSpace> {
    let color: MathFunction<Sample, Color<space>>
    let definition: GradientDefinition<Sample, space>
}
```

`color` is the real gradient. Given a sample, it returns a color.

`definition` explains how the function is controlled: stops, points, shared
color state, axes, and edges. A backend can use that definition to build or
optimize the function, but the semantic model remains `Sample -> Color<space>`.

## State And Binding

Mathematical concepts in this visual language are mostly metadata. That makes
state and binding important:

- `state` means the visual model owns the value and can mutate it directly
- `binding` means the visual model links to a value owned somewhere else
- `let` means the relation should be structurally stable

For gradients:

- stop position is `state`
- stop color is usually `binding`
- shared palette color is `state`
- externally provided theme color is `binding`
- points, axes, and edges are `let` unless the topology itself is being edited

This keeps the math honest: the gradient is still a function, while stops and
links are editable metadata around that function.

## Why This Belongs With Shadow

Shadow, filters, and gradients all need the same base idea:

- shared visual state
- mathematical sampling through `Sample -> Color<space>`
- edges/axes as reusable graph concepts
- backend-specific lowering after the model is checked

So Gradient should be a sibling visual framework, not a detached editor-only
feature.
