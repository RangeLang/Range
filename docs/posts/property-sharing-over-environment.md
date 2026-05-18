# Property Sharing Over Environment

Implementing `environment` was a hasty decision.

## Observation

The shape tried to make data sharing visible:

```neat
construct ProfileView {
    environment theme: Theme
    environment state session: Session
}
```

But `environment` makes context feel like a separate semantic lane.

The better substrate is still properties:

```neat
construct ProfileView {
    let title: String
    state isExpanded: Bool = false

    #shared
    let theme: Theme

    #shared
    binding session: Session
}
```

The property owns the data shape.

The marker describes how that property participates in sharing.

## Shape

Macros and markers can accommodate this through the application/declaration graph.

```text
declaration
  ProfileView.theme
    property: Let<Theme>
    marker: shared

application
  ProfileView(...)
    theme -> ProfileView.theme

graph
  shared property edge
  declaration <-> application
```

The compiler does not need a separate `environment` declaration kind to know that a value can be supplied, projected, inherited, or resolved through context.

It already has the property declaration.

It already has the application edge.

The marker can tell the graph which sharing rule applies.

## Reason

`environment` repeated the same mistake Neat is trying to avoid: adding a new surface kind when the graph already has a place for the fact.

Properties are the right substrate for data sharing because they keep the data shape local and let macros or markers add behavior around that shape. Sharing becomes a graph relationship on a property, not a new category beside properties.
