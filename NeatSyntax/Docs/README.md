# Neat Docs

This folder describes the Neat language as it exists in `NeatSyntax` today.

Examples here are intentionally small. The goal is to show the real parser surface first, then the framework-level concepts built on top of it.

## What Neat Supports Today

- declaration-first syntax with `@Name { ... }`
- composition with `@Name: OtherThing { ... }`
- builtin app entry with `@main MyApp: App { ... }`
- typed members with `var name: Type { ... }`
- local `var` and `let` bindings inside statement blocks
- callable entrypoints with `#name(...) { ... }`
- `state` for component/page state
- arrays in type position like `[Color]`
- array literals in expressions like `[1, 2, 3]`
- case-bearing declarations with `case today, tomorrow`
- `for` loops and `switch` statements in action blocks
- `for` loops in view bodies

## Basics

- [00-overview.md](./Basics/00-overview.md)
- [01-bindings-and-state.md](./Basics/01-bindings-and-state.md)
- [05-types.md](./Basics/05-types.md)
- [01-declarations.md](./Basics/01-declarations.md)
- [02-members-and-init.md](./Basics/02-members-and-init.md)
- [04-attribute-roles.md](./Basics/04-attribute-roles.md)
- [ControlFlow/00-overview.md](./Basics/ControlFlow/00-overview.md)

## Concepts

- [01-main-entry.md](./Concepts/01-main-entry.md)
- [02-renderable-roles.md](./Concepts/02-renderable-roles.md)
- [03-style-modifier.md](./Concepts/03-style-modifier.md)

## Current Boundaries

- there is no separate `protocol` keyword
- there is no separate `enum` keyword
- `namespace` is gone; `@Meta { ... }` provides scoped members instead
- projection headers like `on Renderable` parse, but projection semantics are not fully implemented yet
