# Neat Design Language

This document is the working map for Neat's language direction.

The short posts in `docs/posts` are the primary source for design intent. They
capture the small decisions that should guide implementation work. Longer
articles, syntax docs, and planning notes are supporting references.

When implementation and this document disagree, check the relevant post first,
then update this file and the working checklist together.

## Current Shape

Neat should prefer a small source surface with graph-backed meaning.

The language should not add a new keyword or declaration lane when an ordinary
declaration plus marker, macro, or graph relation can carry the same fact more
clearly.

The current baseline is:

- `construct` is the identity boundary.
- Properties carry storage shape: `let`, `state`, `binding`, and `derived`.
- Direct construct application binds to stored declarations.
- Macros perform compiler work.
- Markers attach durable semantic metadata.
- Namespace-like global surfaces are graph projections, not a separate global
  semantics model.
- The compiler graph is the standard communication layer between declarations,
  applications, macros, markers, diagnostics, and tooling.

## Source Priority

Use posts as the first source for what to watch while implementing:

- `docs/posts/source-and-compiler-one-model.md`
- `docs/posts/compiler-graph-projection.md`
- `docs/posts/property-sharing-over-environment.md`
- `docs/posts/sigils-modern-hieroglyphs.md`
- `docs/posts/marker-carried-namespaces.md`
- `docs/posts/namespace-shaped-configuration.md`
- `docs/posts/global-surface-without-global-semantics.md`
- `docs/posts/direct-construct-application.md`
- `docs/posts/property-ownership.md`
- `docs/posts/syntax-declarations-and-applications.md`

Use articles and plans to clarify implementation:

- `docs/articles/namespace-declarations-as-attributes.md`
- `docs/articles/metadata-shapes-publisher-note.md`
- `docs/articles/embedded-swift-direction.md`
- `STAGE_GRAPH_PLAN.md`
- `To-do/README.md`

## Sigils

The sigils should communicate intent.

`@name` is operational. It asks the compiler or a package macro to do work at
that declaration.

```neat
@provided(.keychain("stripe_key"))
let stripeKey: Key
```

`#name` is descriptive. It attaches metadata that the graph, macros, backend, or
tools can read later.

```neat
#secret
let stripeKey: Key
```

That split matters. A feature that transforms code, supplies values, rewrites
access, emits diagnostics, or synthesizes declarations should be a macro. A
feature that classifies a declaration or records a semantic fact should be a
marker.

## Markers

Markers are first-class metadata.

They should not become special parser keywords. Their effect type tells the
graph what kind of fact they project.

```neat
marker namespace(): Namespace<Construct>
marker secret<T>(): Let<T> -> Security.Secret<T>
```

Use markers for:

- secret or sensitive data classification
- namespace projection
- property sharing metadata
- coding keys and encoding hints
- ownership, storage, or tool-facing metadata

Avoid one-off fields such as `property.codingKey` when generic marker metadata
can expose the same fact as `Marker.Application`.

## Macros

Macros are compiler work.

They should receive typed compiler views and graph access, not scrape raw text
as their default path.

```neat
macro provided<T>(_ source: Provider): Let<T> { target, diagnostics, graph in
    target.declaration.initializer { current in
        Provider.load(source, as: T.self)
    }
}
```

Use macros for:

- automatic assignment
- getter and initializer transforms
- declaration synthesis
- validation with diagnostics
- graph-aware code generation
- syntax expansion

Macros and markers should communicate through graph identity and marker
applications. Do not add a private side table when the declaration graph can
carry the relationship.

## Properties Over New Lanes

Do not bring back `environment`.

Environment-like values are ordinary properties plus markers/macros:

```neat
construct Config {
    #secret
    @provided(.keychain("stripe_key"))
    let stripeKey: Key

    @provided(.system("API_BASE_URL"))
    let apiBaseURL: URL
}
```

The property owns the data shape.

The marker describes semantic policy.

The macro supplies or transforms behavior.

The graph records the relationship.

This keeps context, dependency injection, configuration, and shared values on
the same property substrate instead of creating another declaration category.

## Config And Secrets

Do not treat `.env` files as the language contract.

Configuration and secrets should be typed declarations. A local `.env` file can
be one provider, but the source of truth should be the graph-visible
declaration:

```neat
construct AppConfig {
    #secret
    @provided(.secretManager("stripe/prod/key"))
    let stripeKey: Key

    @provided(.build("API_BASE_URL"))
    let apiBaseURL: URL
}
```

The compiler and tooling can then derive:

- required configuration keys
- provider requirements
- local development fallbacks
- redaction policy
- generated loading code
- deployment manifests
- diagnostics for unsafe or missing providers

`#secret` should be visible to other macros such as `@codable`, debug output,
logging, test fixtures, and backend emitters so plaintext does not leak through
unrelated generated behavior.

## Namespace Projection

Namespace-like behavior is a graph projection.

```neat
marker namespace(): Namespace<Construct>

#namespace
construct Math {
    function clamp(_ value: Int, min: Int, max: Int) -> Int
}
```

`Math` remains an ordinary construct-shaped declaration. The marker tells the
graph to project a globally discoverable namespace surface.

This keeps global availability out of the core declaration model. The source
declares one thing; the graph can expose additional views of that thing.

## Graph Access

The compiler graph is the shared protocol between language items.

Macros and markers should receive:

- `target`
- `diagnostics`
- `graph`

Graph APIs should traffic in identities first:

```neat
let members: [Graph.Identity] = graph.members(of: target.identity)
let declaration: Construct.Declaration = graph.declaration(target.identity)
let markers: [Marker.Application] = graph.markers(on: target.identity)
```

Nested constructs and construct-to-construct references should not force
recursive inline expansion. The graph can expose identities and let the caller
ask for declarations intentionally.

## Construct Application

Construct application should bind to stored declarations directly.

```neat
construct User {
    let id: Int
    let name: String
}

let user: User(id: 1, name: "George")
```

No user-written `init` is needed for ordinary data shape. The application edge
is `User(id:) -> User.id`.

Functions carry behavior. Constructs carry data shape.

## What To Look Out For

Treat these as review checks before implementing a new feature:

- Is this really a new syntax keyword, or is it a marker, macro, or graph
  relation?
- Does the feature preserve the ordinary declaration shape?
- Can the graph carry this fact instead of a parser or validator side table?
- Is `@` being used for compiler work and `#` for metadata?
- Are properties still the substrate for data shape?
- Does a macro need graph identity instead of a recursive nested declaration?
- Is a marker exposing generic metadata instead of creating a one-off field?
- Is `.env` being treated as one provider rather than the source of truth?
- Does the backend consume graph facts instead of rediscovering source meaning?
- Does this keep Embedded Swift pressure in mind: explicit metadata over
  reflection and dynamic runtime behavior?

## Update Rule

When a post changes direction, update this file and `To-do/README.md` in the
same pass.

When implementation lands, add or update a focused fixture so the design
language has a compiler-backed example.
