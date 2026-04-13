# Neat Concurrency

This document describes the current intended direction for Neat's concurrency model inside `NeatSyntax`.

The goal is a model that feels closer to Go than Swift:

- lightweight background work
- explicit data flow
- minimal ceremony
- strong static structure
- backend implementation details must not become language truth

## Design Principles

- Concurrency is a language feature, not a backend feature.
- A backend such as Swift may use runtime primitives like `Task`, but Neat semantics must stay source-defined.
- Background work should be easy to spawn and easy to reason about.
- Shared-state safety should come from the dependency graph and effect analysis, not from user-facing lock APIs.
- Async result flow should use a small core set of language-visible types.

## Current Direction

Neat currently centers concurrency around named and anonymous background work.

### Anonymous background block

```neat
@background {
    doSomething()
}
```

Intended meaning:

- starts background work immediately
- fire-and-forget
- no handle is returned
- body is its own control-flow boundary

Control flow inside anonymous background blocks follows the Go-style intuition:

- `return` exits the background body
- `break` applies only to loops or switches inside that background body
- `continue` applies only to loops inside that background body

Anonymous background blocks do not return values.

### Named background worker

```neat
@background fetchUsername(id: Int) -> Promise<String, FetchError> {
    return "george"
}
```

Intended meaning:

- each call starts fresh background work immediately
- the worker declaration is not a normal `function`
- the worker explicitly declares `Promise<T, E>`
- the worker body returns the success payload type `T`

So:

```neat
@background loadName() -> Promise<String, LoadError> {
    return "George"
}
```

means:

- the call expression produces async work
- the body returns `String`
- the language-visible async result type is `Promise<String, LoadError>`

## Core Async Types

Neat should expose a small core async type family in `NeatCore`.

Current direction:

```neat
enum Result<Success, Failure> {
    case success(result: Success)
    case failure(cause: Failure)
}

enum Promise<Success, Failure> {
    case loading
    case success(result: Success)
    case failure(cause: Failure)
}

enum Stream<Element, Failure> {
    case loading
    case value(item: Element)
    case failure(cause: Failure)
    case completed
}
```

These are core language-facing types. A backend may internally represent them with runtime-managed state, but that is an implementation detail.

## Binding Rules

A key design rule is that `state` and `value` interact with background results differently.

### `state` keeps async work live

```neat
state request = fetchUsername(id: 1)
```

Intended meaning:

- the worker starts immediately
- the binding is established immediately
- the bound type is `Promise<String, FetchError>`
- the promise may be `.loading`, then later `.success(...)` or `.failure(...)`

This is the non-blocking form.

### `value` joins async work into a settled result

```neat
value result = fetchUsername(id: 1)
```

Intended meaning:

- the worker starts
- evaluation does not continue until the worker settles
- the bound type is `Result<String, FetchError>`
- the value is never `.loading`

This is the settling or joining form.

That means the same worker call expression behaves differently depending on binding context:

- `state <- Promise`
- `value <- Result`

### Example

```neat
enum FetchError {
    case missing
    case network
}

@background fetchUsername(id: Int) -> Promise<String, FetchError> {
    if id == 0 {
        return "system"
    }

    return "george"
}

@main {
    state liveRequest: Promise<String, FetchError> = fetchUsername(id: 1)
    Logger.info("request started")

    value settledResult: Result<String, FetchError> = fetchUsername(id: 1)
    Logger.info("request finished")
}
```

The intended reading is:

- `liveRequest` is a live async value
- `settledResult` is a final settled outcome

## Why This Split Exists

The language wants both:

- a live async state model
- a simple final settled result model

`Promise<T, E>` represents ongoing background work.

`Result<T, E>` represents a settled outcome.

This keeps the type story clean:

- `Promise` may still be loading
- `Result` is already settled

## Switching

Long-term intended syntax should be straightforward:

```neat
switch liveRequest {
    case .loading { ... }
    case .success(name) { ... }
    case .failure(error) { ... }
}

switch settledResult {
    case .success(name) { ... }
    case .failure(error) { ... }
}
```

The source language should stay simple even if the backend uses helper runtime structures underneath.

## Shared State

The intended direction is to avoid user-facing lock ceremony.

Instead of requiring explicit lock syntax, Neat should rely on:

- the dependency graph
- effect classification
- concurrency-aware validation

Target behavior:

- safe concurrent access is allowed
- conflicting concurrent access is rejected
- serialization should come from dependency structure, not manual mutex APIs

This keeps the model closer to:

- Go-like in execution feel
- stronger than Go in static safety
- simpler than Swift in ceremony

## Non-Goals

The model should avoid drifting toward backend-specific concurrency concepts such as:

- executor-specific annotations
- actor-style ceremony everywhere
- source semantics that depend on Swift runtime terminology
- exposing implementation details just because the backend uses them

If Neat later needs concepts for UI affinity, scheduling domains, or cancellation, those should be introduced as Neat concepts, not imported backend concepts.

## Current Scope in `NeatSyntax`

At this stage, concurrency-related behavior is spread across several areas:

- control-flow parsing and validation
- callable parsing
- local binding and state binding inference
- semantic validation
- backend lowering support

This folder exists to give concurrency a clear home as the model grows.

## Planned Responsibilities for This Folder

Over time, the `Concurrency` area should become the home for:

- concurrency design notes
- background worker rules
- promise and result binding rules
- future worker chaining rules
- future stream rules
- future concurrency-specific validation helpers

## Future Work

Likely next steps include:

- formalizing direct switch pattern handling for `Promise` and `Result`
- worker chaining semantics
- typed failure production
- stream production rules
- dependency-graph-based race validation
- clearer specification of how live async values interact with observation and reevaluation

## Summary

Neat concurrency should aim for:

- Go-like spawning
- explicit async result types
- `state` for live async values
- `value` for settled outcomes
- compiler-owned safety rules
- minimal ceremony
- no backend leakage into source semantics

That is the current intended direction for `NeatSyntax`.