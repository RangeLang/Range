# View System Handoff

This note captures the current direction for Range views and layout.

## Core Thought

Views are values that live in the graph.

The compiler should not treat UI as a separate runtime system that is scanned
after the fact. A view should be a graph fact with direct access to lowering:

```text
@view function -> declaration graph view value -> lowered layout tree
```

That gives backends one-hop access from the graph to the thing they need to
lower.

## Layout Engine

Range layout starts as ordinary values:

```range
protocol Layout {
    function measure(_ proposal: SizeProposal): Size
    function place(in bounds: Rect): LayoutPlacement
}
```

Concrete layout nodes are just constructs:

```range
Padding(...)
VStack(...)
Text(...)
Frame(...)
```

Padding is a layout container, not a style side effect. It measures its child
inside an inset proposal and reports the child size plus its insets.

## Views

`@view` attaches directly to functions.

Global view:

```range
@view
function App(): Layout {
    return Text(value: "Hello")
}
```

Member view:

```range
construct UserCard {
    let name: String
    let subtitle: String
    let isSelected: Bool

    @view
    function body(): Layout {
        return VStack {
            Text(value: name)
            Text(value: subtitle)
        }
    }
}
```

The construct is the component/data grouping. No `Model` suffix, no MVVM layer.
Use a construct when the view has properties, behavior, or state worth grouping.
Use a global `@view function` when it does not.

## Imperative Code

Imperative programming is acceptable inside a view when it is local and small.

Good:

```range
@view
function body(): Layout {
    let spacing: 8.0

    if isSelected {
        return SelectedCard(...)
    }

    return PlainCard(...)
}
```

The boundary is the important part: a view returns a `Layout` value. The graph
tracks that value and lowering consumes it.

## Graph Registration

`@view` should register a graph fact for the annotated function:

```text
View
- function identity
- owning construct identity, if member function
- parameters
- return layout type
- source location
- lowering entry point
```

Backends should not scan all functions for layout-shaped return types. They
should query the view graph directly.

## View Modifiers

View modifiers should also be macro-registered.

```range
@viewModifier
function padding(_ amount: Float, content: Layout): Layout {
    return Padding(
        insets: EdgeInsets(top: amount, leading: amount, bottom: amount, trailing: amount),
        child: content
    )
}
```

Graph fact:

```text
ViewModifier
- function identity
- modifier name
- content parameter
- parameters
- return layout type
- lowering entry point
```

Sugar:

```range
Text(value: "Hello").padding(12.0)
```

can resolve through the modifier graph to:

```range
padding(12.0, content: Text(value: "Hello"))
```

No runtime modifier object is required at first. A modifier is a registered
layout-transforming function.

## Mental Model

```text
construct = grouped value with properties and behavior
@view function = graph-registered layout producer
@viewModifier function = graph-registered layout transformer
Layout construct = concrete layout node
Backend lowering = consumes graph facts directly
```

The goal is React-like composability without React's component ceremony, and
SwiftUI-like layout values without hiding everything behind framework magic.
