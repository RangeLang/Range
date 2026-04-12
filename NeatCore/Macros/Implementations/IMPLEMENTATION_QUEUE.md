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

- declaration-side type rewrite remains the active behavior
- `Parameter` has been collapsed toward a declaration-owned shape in NeatCore
- older application-side parameter rewrite behavior is no longer the preferred model

Constraint:

- attached parameter macros still need follow-up alignment with the newer declaration-only direction

### Init target

- `literal`

Status:

- declaration + application surface is active
- `Init.Declaration` now carries `parameters` plus `body`
- `Init.Application` now carries `type` plus `arguments`
- init application remains the expression rewrite boundary
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
- Support reusable init rewrite interpretation around the current settled shape:
  - read `target.application.type`
  - read `target.application.arguments`
  - treat `target.application.rewrite(...)` as the authoritative init rewrite boundary
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
- Status:
  - `Function`: target-kind and rewrite-site validation active; execution still
    pending full support.
  - `Construct`: target attachment + rewrite-site validation active; execution
    still pending.

4. Remove remaining ad hoc macro-expander assumptions
- Ensure rewrite capability is resolved from target-kind + surface semantics.
- Continue reducing hardcoded path behavior that bypasses surface definitions.

5. Fixture expansion for macro confidence
- Add focused fixtures for each active target kind:
  - pass fixtures for happy-path rewrite
  - fail fixtures for invalid rewrite site and malformed payload

## Immediate Next Slice

If continuing immediately, implement in this order:

1. align attached parameter macro behavior with the newer declaration-only `Parameter` shape
2. widen init rewrite expression interpreter beyond current subset
3. add compile-fail fixtures for invalid init rewrite payloads

Progress note:

- `Function` target is now recognized by target-kind validation, including
  rewrite-site diagnostics.
- `Function` call-site execution through `target.application.rewrite(...)` is
  still pending for official support.
- next declaration-target decision is now effectively `Construct` vs `Enum`
  for the next activation slice.
