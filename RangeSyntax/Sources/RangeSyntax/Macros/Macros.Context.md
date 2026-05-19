# Macros Context

## Definition

Macros receive the compiler structure appropriate to the syntax target they declare.

Conceptually, the expansion binding should be understood through the target kind
itself, not by attaching application data directly onto the declaration model.

```text
target: <macro target kind>
```

This is a language model, not a fully generalized bootstrap implementation
today.

The important split is still the same:

- declaration-side surface
- application-side surface

The important rule is:

- the declaration graph may know many uses globally
- a macro expansion should normally see at most one canonical application at a
  time

Different target kinds do not need to expose the same surface. Each target kind
should only expose the facets that make sense for that target kind.

## Current Conceptual Mapping

These are the current active target kinds as they should be understood
conceptually today:

```text
Expression -> application-facing
Block      -> application-facing
Parameter  -> declaration + application
Init       -> declaration + application
Function   -> declaration + application
Construct  -> declaration-facing
Enum       -> declaration-facing
Protocol   -> declaration-facing
Extension  -> declaration-facing
```

This does not mean the compiler should attach application data directly onto the
declaration model itself. It means the target kind should define the
macro-facing surfaces it exposes.

## Current Preferred Shape

For declaration-targeted macro kinds that need both sides, the preferred
surface is for the target kind to expose:

- a `declaration` value
- an `application` value
- nested `Declaration` and `Application` facet types describing those values

Current preferred `Init` shape:

```range
#language
construct Init: Syntax {
    let declaration: Declaration
    let application: Application

    construct Declaration {
        let parameters: [Parameter.Declaration]
        let body: Block
    }

    construct Application: SupportsRewrite<Expression> {
        let type: TypeReference
        let arguments: [Parameter.Application]
    }
}
```

This keeps the model clean:

- `Init` remains the target kind
- `declaration` is a real facet value
- `application` is a real facet value
- `Declaration` owns initializer declaration data such as parameters and body
- `Application` owns the applied target type plus argument-named parameter applications
- `Application` remains the rewrite-capable expression boundary for init-targeted macros

Current aligned `Parameter` shape:

```range
#language
construct Parameter: Syntax {
    let declaration: Declaration
    let application: Application

    construct Declaration {
        let externalName: String?
        let localName: String
        let type: TypeReference
        let defaultValue: Expression?
    }

    construct Application {
        let label: String?
        let type: TypeReference
        let expression: Expression
    }
}
```

Current preferred `Function` shape:

```range
#language
construct Function: Syntax {
    let declaration: Declaration
    let application: Application

    construct Declaration {
        let identifier: Identifier
        let parameters: [Parameter.Declaration]
        let returnType: TypeReference?
        let body: Block
    }

    construct Application {
        let identifier: Identifier
        let arguments: [Parameter.Application]
    }
}
```

## Properties

- Expression-targeted macros receive expression syntax directly

```range
macro stringify(value _: capture Expression): Expression -> String { target, diagnostics in
    target.rewrite("\(value)")
}
```

```range
macro lock(): Block { target, diagnostics in
    target.rewrite({
        target()
    })
}
```

- Declaration-targeted macros receive the declared compiler structure directly

```range
macro codable(): Construct { target, diagnostics in
    target.declaration.self
    target.declaration.inits
    target.declaration.functions
}
```

```range
macro iterable(): Enum { target, diagnostics in
    target.declaration.self
    target.declaration.cases
}
```

```range
macro equatable(): Protocol { target, diagnostics in
    target.declaration.self
    target.declaration.inits
    target.declaration.functions
}
```

```range
macro tracedExtension(): Extension { target, diagnostics in
    target.target
    target.protocols
    target.functions
}
```

- The macro surface should expose language concepts rather than hidden compiler handles

```range
construct
property
parameter
init
function
expression
block
```

- Block and expression targets are syntax-first

```range
macro lock(): Block { target, diagnostics in
    target.rewrite({
        acquire()
        target()
        release()
    })
}
```

- Declaration targets are declaration-aware

```range
macro clamped(min: Int, max: Int): Property { target, diagnostics in
    target.bindingKind
    target.declaration.type
    target.owner
}
```

- Callable and initializer targets should prefer declaration and application
  facets rather than one flat bag of members

```range
macro literal<T>(): Function { target, diagnostics in
    let declaration = target.declaration
    let application = target.application
}
```

```range
macro traced(): Function { target, diagnostics in
    let declaration = target.declaration
    let application = target.application
}
```

- Attachment targets are compiler-known language concepts

```range
Expression
Block
Construct
Enum
Protocol
Extension
Property
Parameter
Init
Function
```

## Notes

- Macros should be low-level enough to express advanced features without new baked-in compiler mechanisms.
- Different target kinds do not need to share one fake universal context bag.
- Target surfaces should be selective, not universal:
  some targets are syntax-first and only need rewrite surface,
  some targets are declaration-first,
  and some targets need both declaration and application.
- For the current active surface:
  `Expression` and `Block` are effectively syntax/application-first;
  `Parameter` now uses declaration plus application facets in the active
  bootstrap surface;
  `Function` now uses declaration plus application facets authoritatively for
  `literal`.
- `@literal<T>` is the canonical literal bridge macro annotation form, with `T` constrained to compiler-recognized literal carrier types.
