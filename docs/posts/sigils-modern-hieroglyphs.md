# Sigils: Modern Hieroglyphs

Neat is standardizing macro calls and markers into two visible channels.

## Before

```neat
#codable(.snakeCase)
construct User {
    #primary
    let userId: Int
}
```

The old shape made compiler work and metadata tags look the same.

## After

```neat
marker namespace(): Namespace<Construct>

@codable(.snakeCase)
construct User {
    #primary
    let userId: Int
}

#namespace
construct Language {
    let defaultLocale: String("en")
}
```

`@macroName` means: ask the compiler to do work at this place.

`#markerName` means: tag this concept with additional metadata.

Markers can also register global concepts:

```neat
marker namespace(): Namespace<Construct>
```

That means `#namespace` is still metadata at the declaration site, but the marker declaration tells the graph that this metadata has a global effect. A construct tagged with `#namespace` becomes a namespace-shaped concept the rest of the compiler can discover.

## Reason

Sigils are modern hieroglyphs: small visual marks that carry a category of intent.

`@` is operational. It marks expansion, synthesis, validation, or another compiler action.

`#` is descriptive. It marks meaning on a declaration, field, expression, or region so the graph and tools can read it later.

This removes the awkward overlap where macros and metadata shared the same surface. The source now makes it easier to see which parts ask the compiler to act and which parts describe the thing already there.

The registration pattern keeps that distinction intact. Macros register compiler work by name. Markers register metadata meanings by name, and some markers can additionally register global concepts such as namespaces.

## Addendum: Function Type Colons

I also want to collapse the extra return-shape distance in function declarations.

```neat
construct User {
    let name: String

    function displayName() -> String
}
```

The return type is still a type relationship, but it uses a different visual operator from properties.

```neat
construct User {
    let name: String

    function displayName(): String
}
```

The colon already means "this declaration has this type."

Using the same mark for function result types keeps functions closer to construct properties. `let name: String` and `function displayName(): String` now read as two declarations with typed shapes, instead of making function results feel like a separate semantic category.
