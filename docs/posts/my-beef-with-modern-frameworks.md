# My Beef With Modern Frameworks

Modern frameworks keep asking the runtime to recover meaning the source already had.

## Observation

Everything has state. It has values. It has metadata.

Then the framework wraps all of that in its own lifecycle, its own dependency rules, its own observation layer, and its own little ritual for discovering what changed.

The shape was there first. The framework arrives later and tries to reconstruct it.

## Shape

```neat
construct CounterView {
    binding count: Int

    function increment() {
        count += 1
    }
}

construct Screen {
    state count: Int = 0

    let counter: CounterView = CounterView(count: $count)
}
```

This starts to hint at another graph.

`Screen.count` owns the storage. `CounterView.count` is a live binding into it. When `CounterView` mutates `count`, the interesting runtime edge is already present in the source.

Not only the AST graph that says what syntax exists, but a memory graph and a reactivity graph derived from ownership and properties. That part is still WIP, but the direction matters: the source shape is already close to the runtime shape.

## Reason

Moving ownership onto properties frees up space before runtime.

The compiler can know which members are stable, which members own mutable storage, which members borrow, which members compute, and which members resolve from context. Runtime information stops being something a framework has to scrape out of a component after the fact.

The source can hand the runtime graphs that already know where the interesting edges are.
