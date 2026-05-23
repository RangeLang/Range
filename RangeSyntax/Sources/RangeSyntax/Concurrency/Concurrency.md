# Range Concurrency

This document describes the current intended direction for Range concurrency.

The model is intentionally moving toward a simpler, more Go-like shape:

- explicit spawning
- explicit communication
- explicit blocking points
- ordinary functions stay ordinary
- channels are the main concurrency primitive

The goal is to keep concurrency understandable at the source level and avoid hiding synchronization inside ordinary-looking declarations or bindings.

## Design Principles

- Concurrency is a language feature, not a backend-specific feature.
- Backend implementation details must not become source-language truth.
- Work should start explicitly.
- Communication and synchronization should happen explicitly.
- Ordinary procedural code should remain ordinary procedural code.
- Concurrency structure should scale beyond one-shot async results.

## Core Direction

Range concurrency centers on two ideas:

1. `@background { ... }` starts concurrent work
2. `Channel<T>` is used to communicate between concurrent parts of the program

This means the language does **not** treat Promise-like result types as the core concurrency abstraction.

Instead of returning live async handles and implicitly settling them later, Range prefers:

- spawn work explicitly
- send values explicitly
- receive values explicitly
- block only at obvious operations such as `receive()`

## Anonymous Background Blocks

Anonymous background blocks remain the spawn primitive.

Example:

```range
@background {
    doSomething()
}
```

Intended meaning:

- start concurrent work immediately
- no special named async declaration is introduced
- no implicit result handle is returned
- the block body is its own control-flow boundary

This is the explicit "start work now" operation.

## Control Flow Inside Background Blocks

Control flow inside an anonymous background block follows straightforward structured rules:

- `return` exits the background block body
- `break` applies only to loops or switches inside that background block
- `continue` applies only to loops inside that background block

Anonymous background blocks do not produce a direct return value.

So this is allowed:

```range
@background {
    if shouldStop {
        return
    }

    Logger.info("continuing background work")
}
```

And this is not part of the model:

```range
@background {
    return 42
}
```

A background block is for concurrent execution, not for implicitly returning an async value to the surrounding expression context.

## Ordinary Functions Remain Ordinary

Functions do not become special just because they may be used from concurrent code.

Example:

```range
function fetchUserName(id: Int): String {
    if id == 0 {
        return "system"
    }

    return "george"
}
```

This is just a normal function.

If you want to run it concurrently, you do that at the use site:

```range
let names: Channel<String>

@background {
    let name = fetchUserName(id: 1)
    names.send(name)
}

let received = names.receive()
```

The concurrency is visible where it happens:

- the spawn is visible
- the send is visible
- the receive is visible

The function itself does not need Promise-returning syntax or a special async declaration form.

## Channels

`Channel<T>` is the main communication primitive.

Current surface shape:

```range
construct Channel<Element> {
    init()
    init(capacity: Int)
    function send(element _: Element)
    function receive(): Element
    function close()
}
```

Channels are intended to support:

- one concurrent part sending data to another
- explicit handoff of work or results
- producer/consumer patterns
- worker coordination
- buffered or unbuffered communication depending on capacity

This is closer to message passing than to future/promise result plumbing.

## Explicit Communication

The intended style is explicit communication through channel operations.

Example:

```range
function loadUser(id: Int) {
    let output: Channel<String>

    @background {
        let name = fetchUserName(id: id)
        output.send(name)
    }

    let name = output.receive()
    Logger.info(name)
}
```

Reading this code should make synchronization obvious:

- the background block starts concurrent work
- `send(...)` communicates the produced value
- `receive()` is the explicit synchronization point

There is no hidden join disguised as an ordinary binding.

## Blocking and Synchronization

Blocking should happen at explicit concurrency operations.

Most importantly:

- `receive()` is an explicit synchronization point
- a send on some channels may also synchronize, depending on channel capacity and runtime behavior

This is preferred over designs where something like:

```range
let result = worker()
```

looks like an ordinary binding but secretly waits for background work to finish.

In the channel-first model, waiting should be visible in the source.

## Buffered and Unbuffered Channels

`Channel(capacity: ...)` exists to support different communication shapes.

Intended reading:

- `Channel()` or `Channel(capacity: 0)` represents direct handoff behavior
- `Channel(capacity: n)` allows bounded buffering

This gives the language room to express:

- synchronous handoff
- bounded queues
- staged pipelines
- worker pools
- backpressure-oriented designs

Exact backend implementation can vary, but the source model remains channel-based rather than Promise-based.

## Close Semantics

Channels support `close()`.

Close exists so channel-based coordination can model completion and shutdown, not just single-value handoff.

The exact source-level closed-channel behavior should remain clearly specified by Range itself, not inferred from backend runtime conventions.

That means any final semantics around:

- receiving after close
- sending after close
- draining buffered values after close

must be defined as Range behavior.

## Result as a Normal Data Type

`Result<T, E>` may still be useful as an ordinary data type for success/failure modeling.

Example:

```range
enum LoadError {
    case missing
    case denied
}

function parseUser(id: Int): Result<String, LoadError> {
    if id == 0 {
        return .success(result: "system")
    }

    return .failure(cause: .missing)
}
```

What changes is its role:

- `Result` is a normal value type
- it is **not** the language's hidden async-join result form
- it does not imply background execution by itself

## What Is Not the Core Model

The concurrency model should avoid centering around:

- named background worker declarations
- Promise-returning callable forms
- special binding semantics where `let` joins async work
- hidden synchronization points
- backend-shaped async concepts leaking into source semantics

Range may still have useful general-purpose types for success/failure or streaming data in the future, but those should not define the core concurrency story.

## Why This Direction

This spawn-plus-channel direction is preferred because it makes concurrency structure more obvious.

It avoids several problems that arise in Promise-centered designs:

- ordinary-looking bindings hiding joins
- declarations carrying too much async meaning
- local live async handles with weak practical value
- drift toward a Swift-style future/async-result model
- poor fit for pipelines, queues, and coordination patterns

A channel-first model better fits:

- explicit message passing
- richer concurrent structure
- clearer blocking behavior
- systems-ish or OS-ish coordination patterns

## Shared State

The intended direction is still to avoid user-facing lock ceremony.

The long-term goal is that concurrency safety comes from:

- the dependency graph
- effect classification
- concurrency-aware validation
- explicit communication structure

The user-facing model should prefer message passing and structured concurrent behavior over manual synchronization APIs.

## Backend Notes

A backend may implement `@background` using runtime mechanisms such as tasks or threads.

A backend may implement channels using locks, conditions, queues, or other runtime support.

Those details are implementation choices.

They must not redefine the language model.

Range source semantics should stay stable even if different backends realize the runtime differently.

## Example Shapes

### Fire-and-forget work

```range
function refreshCache() {
    @background {
        Logger.info("refresh started")
        performRefresh()
        Logger.info("refresh finished")
    }

    Logger.info("caller continues immediately")
}
```

### Single result handoff

```range
function loadName(id: Int) {
    let output: Channel<String>

    @background {
        output.send(fetchUserName(id: id))
    }

    let name = output.receive()
    Logger.info(name)
}
```

### Producer / consumer shape

```range
function processJobs() {
    let jobs: Channel<Int>(capacity: 8)

    @background {
        jobs.send(1)
        jobs.send(2)
        jobs.close()
    }

    let first = jobs.receive()
    let second = jobs.receive()

    Logger.info(first)
    Logger.info(second)
}
```

## Current Scope

At this stage, concurrency-related behavior lives across several areas:

- parsing of anonymous background blocks
- control-flow validation for background bodies
- core channel surface definitions
- backend lowering/runtime support for spawning and channels

This document exists to keep the intended language direction clear as implementation continues.

## Summary

Range concurrency is moving toward:

- anonymous `@background { ... }` for explicit spawning
- `Channel<T>` for communication
- explicit blocking at channel operations
- ordinary functions staying ordinary
- no Promise-centered core concurrency model
- no hidden join semantics in ordinary bindings

In short:

- spawn explicitly
- communicate explicitly
- block explicitly
- keep the source model simple
