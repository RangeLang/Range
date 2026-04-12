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

```neat
@core
construct Init: Syntax {
    value declaration: Declaration
    value application: Application

    construct Declaration {
        value parameters: [Parameter]
        value body: Block
    }

    construct Application: SupportsRewrite<Expression> {
        value type: TypeReference
        value arguments: [Argument]
    }
}
```

This keeps the model clean:

- `Init` remains the target kind
- `declaration` is a real facet value
- `application` is a real facet value
- `Declaration` owns initializer declaration data such as parameters and body
- `Application` owns the applied target type plus call arguments
- `Application` remains the rewrite-capable expression boundary for init-targeted macros

Current aligned `Parameter` shape:

```neat
@core
construct Parameter: Syntax {
    value externalName: String?
    value localName: String
    value type: TypeReference
    value defaultValue: Expression?
}
```

Current preferred `Function` shape:

```neat
@core
construct Function: Syntax {
    value declaration: Declaration
    value application: Application

    construct Declaration {
        value name: String
        value parameters: [Parameter]
        value returnType: TypeReference?
        value body: Block
    }

    construct Application {
        value name: String
        value arguments: [Argument]
    }
}
```

## Properties

- Expression-targeted macros receive expression syntax directly

```neat
macro stringify(value _: capture Expression): Expression -> String { target, diagnostics in
    target.rewrite("\(value)")
}
```

```neat
macro lock(): Block { target, diagnostics in
    target.rewrite({
        target()
    })
}
```

- Declaration-targeted macros receive the declared compiler structure directly

```neat
macro codable(): Construct { target, diagnostics in
    target.name
    target.self
    target.inits
    target.functions
}
```

```neat
macro iterable(): Enum { target, diagnostics in
    target.name
    target.self
    target.cases
}
```

```neat
macro equatable(): Protocol { target, diagnostics in
    target.name
    target.self
    target.inits
    target.functions
}
```

```neat
macro tracedExtension(): Extension { target, diagnostics in
    target.target
    target.protocols
    target.functions
}
```

- The macro surface should expose language concepts rather than hidden compiler handles

```neat
construct
property
parameter
init
function
expression
block
```

- Block and expression targets are syntax-first

```neat
macro lock(): Block { target, diagnostics in
    target.rewrite({
        acquire()
        target()
        release()
    })
}
```

- Declaration targets are declaration-aware

```neat
macro clamped(min: Int, max: Int): Property { target, diagnostics in
    target.bindingKind
    target.declaration.type
    target.owner
}
```

- Callable and initializer targets should prefer declaration and application
  facets rather than one flat bag of members

```neat
macro literal<T>(): Init { target, diagnostics in
    value declaration = target.declaration
    value application = target.application
}
```

```neat
macro traced(): Function { target, diagnostics in
    value declaration = target.declaration
    value application = target.application
}
```

- Attachment targets are compiler-known language concepts

```neat
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
  `Init` now uses declaration plus application facets authoritatively for
  `literal`, even though generalized init macro execution is still incomplete.
- `#literal<T>` is the canonical init-targeted literal bridge form, with `T` constrained to compiler-recognized literal carrier types.
