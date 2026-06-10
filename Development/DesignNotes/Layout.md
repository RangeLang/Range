# Layout

Range layout is a graph-backed value system.

The layout engine should not treat views as external UI objects that are
rediscovered after type checking. A view is a declared value in the compiler
graph. Backend lowering should be able to move from the graph entry for a view
to the lowered layout tree in one hop.

## Model

The first surface is function-based:

```range
@view
function App(): Layout {
    return Text(value: "Hello")
}
```

For reusable data and behavior, the view function lives on a construct:

```range
construct UserCard {
    let name: String
    let subtitle: String
    let isSelected: Bool

    @view
    function body(): Layout {
        return Padding(
            insets: EdgeInsets(top: 8.0, leading: 12.0, bottom: 8.0, trailing: 12.0),
            child: Text(value: name)
        )
    }
}
```

The construct is the grouped value. There is no separate view model layer.

## Graph Semantics

`@view` is a function-targeted declaration macro. The declaration graph should
realize it as a view fact:

- the function identity
- the owning construct identity, when the function is a member
- the parameter list
- the return layout type
- the source location
- the direct lowering entry point

This keeps rendering and lowering graph-oriented:

```text
view function declaration -> view graph fact -> lowered layout tree
```

Backends should consume that graph fact directly instead of scanning arbitrary
functions for layout-looking return types.

## Layout Values

Concrete layout nodes are ordinary values:

- `Padding`
- `FixedLayout`
- future stacks, text, images, controls, and renderer-specific nodes

Each layout node participates in measurement and placement:

```range
protocol Layout {
    function measure(_ proposal: SizeProposal): Size
    function place(in bounds: Rect): LayoutPlacement
}
```

Padding is therefore a layout container, not a style side effect. It receives a
proposal, measures its child in the inset proposal, reports the child size
outset by its insets, and places the child inside inset bounds.

## Imperative Boundary

View functions may use small local imperative code when it clarifies layout
construction. The boundary remains value-oriented: a view function returns a
`Layout`, and the graph records that returned layout value as the thing lowering
consumes.
