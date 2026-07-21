# RangeView

RangeView models pages and components as identity-bearing Range graph nodes.
The framework macros live in
`RangeCompiler/Range/Frameworks/RangeView/RangeView.range`.

The first compiler slice is deliberately bounded to resolving one derived
component body to one concrete component application. Browser rendering and
WebAssembly lowering follow only after that graph is deterministic and invalid
graphs are rejected before artifact emission.

```range
@page(path: "/")
construct HomePage {
    derived body: @component {
        Header()
    }
}

@component(element: "header", text: "Range")
construct Header {}
```

The required graph edge is:

```text
HomePage --body--> Header
```

Both sides use nominal identities. A construct declaration introduces its
construct name (`Header`) as a nominal type. A macro declaration introduces
its family name (`@component`) as a nominal family type. Applying `@component`
to `Header` makes `Header` assignable to `@component`; structural similarity
or an unmarked construct does not.

`@page` and `@component` reuse the Range-authored `@inspect` macro. It requires
every page to declare exactly one `derived body: @component`. Components may
be leaves; when a component declares a body, the same inspection requires that
body to be unique and typed `@component`.

The program graph preserves the `@page(path: "/")` macro application and adds
the concrete `calls` relation only when a derived body is one unconditional
expression (or one explicit return expression) and the called construct has
one unambiguous identity. Multi-statement, branching, unknown, and ambiguous
bodies intentionally remain unresolved rather than receiving a guessed root.

This checkpoint proves deterministic page-to-component graph resolution. DOM
artifact emission belongs in the Range-authored compiler and is not yet
claimed. Nested component collections, event handling, runtime updates,
WebAssembly execution, and native self-hosted lowering of `derived` remain
future slices.
