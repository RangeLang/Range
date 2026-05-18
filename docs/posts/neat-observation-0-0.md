# Neat Observation #0.0

A smaller core model makes the language easier for agents, tools, and multimodal systems to read as structure.

## Observation

The useful shape is not a large set of special language cases.

It is a small set of repeated relationships:

```neat
construct User {
    let id: Int
    let name: String
}

let user: User(id: 1, name: "George")
```

```text
User
  declaration
    id: Int
    name: String

User(id: 1, name: "George")
  application
    id -> User.id
    name -> User.name
```

The source has a declaration.

The application points back to that declaration.

The graph keeps both facts visible.

## Shape

An agent does not need to infer a private compiler story from unrelated syntax nodes.

It can inspect a smaller model:

```text
declaration
application
ownership
projection
lowering
```

That same model can be shown through code, graph views, editor surfaces, generated UI, diagrams, or screenshots. The modality changes, but the structure stays named.

## Reason

Agentic and multimodal systems work better when the program exposes stable handles.

LSP-backed AIs and ACP-style agents already show the value of structured handles over the substrate.

A simplified core gives those systems fewer concepts to recover and clearer edges to follow. The source, compiler graph, and visual representation can describe the same structure instead of asking each tool to rediscover it from text.
