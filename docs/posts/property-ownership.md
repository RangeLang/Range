# Class v. Struct

The old argument is tired, but it keeps walking back into the room.

## Observation

Structs: great for isolated values, predictable copying, stack allocation, and making ownership easier to reason about.

Classes: useful when one thing needs to stay one thing across several systems, even when that shared identity starts to make ownership harder to see.

## Verdict

Neither is the whole answer.

The split is trying to protect two useful ideas: values should be understandable in isolation, and some things should keep a stable identity as they move through a system.

`construct` is already an identity-bearing type.

The compiler already knows what a thing is after parsing it. It already has identity, connections, and relationships inside the compiler graph.

Struct and class both decide a lot at the type level.

Neat does not need a second keyword to tell the compiler whether a thing is real enough to have identity. The construct is the identity boundary. It gives the graph a named thing to hold onto: this declaration, this application, this relationship to another construct, this marker metadata exposed by macros.

Ownership is a different question.

So instead of saying "this whole type is value-like" or "this whole type is reference-like," Neat lets the members carry their own storage story.

One construct. Enough identity for the graph. Enough room for the property system to say the rest.

The example is not a class pretending to be a struct, or a struct trying to smuggle in class behavior. It is one construct with different ownership facts at different properties.

## Example / Shape

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

    function signOut() {
        session = .signedOut
    }
}
```

## Reason

The class and struct split turns identity and ownership into one type-level verdict.

Neat can let `construct` carry identity, then let the property system describe the storage details without making the whole type swear allegiance to one old camp.
