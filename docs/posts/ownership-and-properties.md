# Ownership & Properties

Ownership gets awkward when one type has to carry one story for every member.

## Observation

Some data is stable, some changes, some is borrowed, some is computed, and some comes from the surrounding graph.

The usual move is to make the whole type carry that tension.

Neat keeps `construct` as the identity-bearing shape and lets each property describe how it participates.

## Shape

```neat
construct ProfileView {
    let title: String
    state isExpanded: Bool = false

    binding name: String

    environment theme: Theme
    environment state session: Session

    derived displayTitle: String {
        return title + " - " + name
    }
}
```

`let` is immutable owned data.

```neat
let title: String
```

The binding owns the value, but access through that root is fixed after initialization.

`state` is mutable owned storage.

```neat
state isExpanded: Bool = false
```

It is the source of truth. Other code can share access to it, but the storage belongs here.

`binding` is borrowed storage.

```neat
binding name: String
```

It does not introduce a new source of truth. It points at storage owned somewhere else, usually through `$name` projection.

`derived` is computed data.

```neat
derived displayTitle: String {
    return title + " - " + name
}
```

It has no independent storage. It reads other graph bindings and changes when those inputs change.

`environment` is graph-resolved context.

```neat
environment theme: Theme
environment state session: Session
```

The read-only form reads state from higher in the graph. The `environment state` form can mutate the resolved outer state.

## Reason

A type gets called a value or a reference, and then every member has to live under that label.

At first that feels tidy. Then one member wants to be borrowed, another wants to be computed, another wants to read from context, and the label starts doing more theater than work.

Neat keeps the identity boundary on the construct and lets each property say the part that usually gets implied, argued about, or discovered too late.
