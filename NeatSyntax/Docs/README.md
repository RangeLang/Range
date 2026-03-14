# Neat Docs

This folder documents Neat as a programming language.

The focus here is the core syntax implemented in `NeatSyntax`: declarations, members, callables, bindings, types, and control flow. Framework concepts belong elsewhere.

## What Neat Supports Today

- declaration headers like `#Name { ... }`
- declaration composition with `#Name: Contract { ... }`
- projected declarations with `#Name on Target: Contract { ... }`
- typed members with `value name: Type`
- declaration state with `state name: Type = value`
- declaration bindings with `binding name: Type`
- local `let` and `var` bindings inside statement blocks
- callable members with `@name(...)`
- explicit binding references with `$name`
- optional types like `Int?` and empty optional values with `none`
- arrays in type position like `[Int]`
- array literals in expressions like `[1, 2, 3]`
- case-bearing declarations with `case ready, running, done`
- control flow with `if`, `while`, `for`, `break`, `continue`, `return`, and `switch`
- comparisons, boolean operators, and ternary expressions

## Basics

- [00-overview.md](./Basics/00-overview.md)
- [01-declarations.md](./Basics/01-declarations.md)
- [01-bindings-and-state.md](./Basics/01-bindings-and-state.md)
- [02-members-and-init.md](./Basics/02-members-and-init.md)
- [04-attribute-roles.md](./Basics/04-attribute-roles.md)
- [05-types.md](./Basics/05-types.md)
- [ControlFlow/00-overview.md](./Basics/ControlFlow/00-overview.md)

## Current Boundaries

- Neat does not use separate `struct`, `class`, `protocol`, `enum`, `namespace`, or `interface` keywords
- projection semantics are still evolving beyond the currently parsed header surface
- the semantic type system is still smaller than the full language direction
