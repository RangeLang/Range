# Namespace Shaped Configuration

Namespace configuration now lives on a declaration shape.

## Before

```neat
namespace Styling {}
```

The old form named a namespace, but it had no clear place for namespace-owned configuration.

## After

```neat
#namespace
construct Language {
    let defaultLocale: String("en")
    let fallbackLocale: String("en-US")

    function identifier() -> String {
        return defaultLocale
    }
}
```

## Macro Shape

```neat
macro namespace(): Construct { target, diagnostics in
    target.declaration.projectNamespace {
        name: target.declaration.self
        configuration: target.declaration.lets
        functions: target.declaration.functions
        declarations: target.declaration.constructs
    }
}
```

## Reason

`#namespace` says the construct is namespace-shaped. Its `let` declarations are configuration for the namespace, not fields on instances.

That gives Neat a static-like place for shared facts without adding a separate static variable model.

Macros are the compiler access surface here. The namespace marker reads the declaration graph through `target.declaration` and asks the compiler to project a namespace from that declaration; the language does not need a second namespace declaration form or a separate public graph export API.
