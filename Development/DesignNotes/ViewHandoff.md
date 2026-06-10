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

`@view` attaches to constructs. A view component is a construct carrying a
`derived body: Layout`:

```range
@view
construct UserCard {
    let name: String
    let subtitle: String
    state isSelected: Bool(false)

    derived body: Layout {
        VStack {
            Text(value: name)
            Text(value: subtitle)
        }
    }
}
```

The construct is the component/data grouping. No `Model` suffix, no MVVM layer.
The `@view` macro finds `body` by convention: it queries its target for a
derived named `body` returning `Layout` and reports a diagnostic if missing.
This is checkable today with the existing `target` + `diagnostics` macro
bindings; the macro target type is the nominal `Construct`.

### Body Is A Derived, Not A Function

`body` being a `derived` is the semantic point, not a spelling choice. A view
body *is* a derived value: computed from the construct's `let`/`state`
properties, re-derived when its dependencies change. SwiftUI's `var body` is a
fake-pure computed var whose dependencies are discovered at runtime through
wrapper machinery; Range's `body` is a real graph node with statically traced
dependencies. View invalidation is just derived invalidation.

Parameterized layout producers (`row(item:)` helpers) remain ordinary
functions returning `Layout`. `derived body` is the component surface.

### No Existentials

`@view` membership replaces type conformance. SwiftUI needs `some View`,
`AnyView`, and `@ViewBuilder` because its type system must name a body's
return type, and erasing it costs dynamic dispatch. Range never asks the
question: backends query view graph facts and walk their layout values
directly. Membership over conformance means no existential, no opaque return
types, no erasure — the dispatch problem is dissolved rather than solved.

### Runtime Cache, Compile-Time Wiring

The graph statically wires invalidation: facts record that `body` depends on
`isSelected`, so the compiler can emit "when `isSelected` writes, recompute
`body`, diff, patch" directly. What remains at runtime is only a value slot
per derived — the current layout tree to diff against. The graph eliminates
runtime dependency *discovery* (SwiftUI's observation machinery), not the
cached value itself.

## Imperative Code

Imperative programming is acceptable inside a view when it is local and small.

Good:

```range
derived body: Layout {
    let spacing: 8.0

    if isSelected {
        return SelectedCard(...)
    }

    return PlainCard(...)
}
```

The boundary is the important part: a body produces a `Layout` value. The
graph tracks that value and lowering consumes it.

## Graph Registration

`@view` should register a graph fact for the annotated construct:

```text
View
- construct identity
- body derived identity
- body dependency set (states/lets read by the body)
- return layout type
- source location
- lowering entry point
```

Backends should not scan all constructs for layout-shaped deriveds. They
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
@view construct = graph-registered component with a derived body
derived body = statically wired layout producer; invalidation = derived invalidation
@viewModifier function = graph-registered layout transformer
Layout construct = concrete layout node
Backend lowering = consumes graph facts directly
```

The goal is React-like composability without React's component ceremony, and
SwiftUI-like layout values without hiding everything behind framework magic.
