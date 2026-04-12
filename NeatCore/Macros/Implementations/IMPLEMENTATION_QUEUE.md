# Macro Implementation Queue

This is the execution queue for active macro work.

It is intentionally implementation-first:

- what is already working
- what is partially working
- what to implement next, in order

## Current Working Surface

### Expression target

- `stringify`
- `unwrap`

Status:

- rewrite execution works
- `-> ResultType` inference works
- generic result substitution works (`unwrap<T> -> T`)
- `capture Expression` works

### Block target

- `lock`
- `trace`

Status:

- rewrite execution works
- trailing block payload integration works

### Parameter target

- `autoclosure`
- `variadic`

Status:

- declaration-side type rewrite works
- application-side argument rewrite works
- variadic behavior works through `target.application.arguments`

Constraint:

- payload interpretation is still bootstrap-scoped, not fully general

### Init target

- `literal`

Status:

- declaration + application surface is active
- rewrite path is active
- literal bridge realization is graph-connected
- malformed literal rewrite fails explicitly

Constraint:

- generalized init macro execution is not complete yet

## Priority Queue

1. Rewrite-site diagnostics by target kind
- Detect invalid rewrite access early, for example:
  - `Expression` macro using `target.application.rewrite`
  - `Parameter` macro using `target.rewrite`
- Fail with explicit diagnostics instead of silent non-match behavior.
- Status: implemented for active targets (`Expression`, `Block`, `Parameter`,
  `Init`) with compile-fail fixture coverage.

2. Generalize `Init` execution from `literal` to reusable init-target pipeline
- Support reusable init rewrite interpretation pattern:
  - read `target.application.arguments`
  - emit via `target.declaration.expression(arguments:)`
- keep literal as one implementation using that shared pipeline.
- Status: base call-site pipeline implemented for attached init macros on
  matching construct calls; widening beyond current bootstrap rewrite
  expression subset is still open.

3. Stabilize declaration-target roadmap (Function/Construct/Enum/Protocol/Extension)
- Decide which declaration targets become active in bootstrap next.
- Add one target at a time with:
  - parser + surface validation
  - expander execution semantics
  - compile-pass and compile-fail fixtures

4. Remove remaining ad hoc macro-expander assumptions
- Ensure rewrite capability is resolved from target-kind + surface semantics.
- Continue reducing hardcoded path behavior that bypasses surface definitions.

5. Fixture expansion for macro confidence
- Add focused fixtures for each active target kind:
  - pass fixtures for happy-path rewrite
  - fail fixtures for invalid rewrite site and malformed payload

## Immediate Next Slice

If continuing immediately, implement in this order:

1. widen init rewrite expression interpreter beyond current subset
2. add compile-fail fixtures for invalid init rewrite payloads
3. declaration-target activation decision (`Function` or `Construct` first)
