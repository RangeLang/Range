# Range May Not Need Concurrency Syntax

Most languages ask the author to describe concurrency twice.

First, the program describes which values depend on which other values. Then it
adds tasks, workers, channels, futures, `async`, and `await` to describe how
those same dependencies should execute.

Range already builds a graph of value flow, control, ownership, and effects.
That graph can answer the important question directly: which applications are
ready and independent right now?

```range
let syntax: Syntax(parse(source: source))
let settings: Settings(load(path: settingsPath))

let program: Program(
    build(syntax: syntax, settings: settings)
)
```

`parse` and `load` have no dependency between them. If their ownership and
effects do not conflict, the compiler may execute them concurrently. `build`
becomes ready when both values exist. The authored code already contains the
fan-out and the join.

The same applies to collections. Independent transformations may run in any
completion order while results commit to their original input indices. A
single-lane run and a many-lane run must produce the same values, diagnostics,
graph hashes, LLVM, and program behavior.

This changes the division of responsibility:

```text
the author describes truth
the compiler proves legal parallelism
the runtime adapts execution to the machine
```

The runtime can respond to CPU availability, memory pressure, queue depth, and
parked I/O without exposing those scheduling decisions in source. Dependencies
become joins. Returned values become communication. Unavailable values suspend
their consumers. Blocking operations park graph applications rather than
forcing the language to expose thread management.

This does not mean “parallelize everything.” Concurrency is allowed only when it
is behaviorally unobservable. Unknown effects, mutable aliases, and ordered
side effects remain ordered.

It also does not rule out future syntax for genuinely long-lived streams or
services. It means Range should first prove how far its existing graph semantics
can go before adding another concurrency model.

The next step is deliberately small: execute one existing compiler boundary
through a one-lane ready graph, prove byte-for-byte equivalence, and only then
place that same graph behind one bounded adaptive scheduler.

Range may not need a concurrency feature. It may only need a better graph
executor.
