# Think Outside The Box

The class versus struct question is usually the wrong fight.

Humans describe things through many axes at once.

An editor can have value, state, behavior, recomputation, identity, and shared access.

A lot of programming asks you to split that into hard categories.

Reference or value. Mutable or immutable. Class or struct.

The idea is richer than the boxes.

Most of the time you already know the real shape: this owns the data, this borrows it, this does work, this is recalculated from it.

## Example

```range
construct Editor {
    state document: Document
    binding selection: Selection

    derived title: String {
        return document.title
    }
}
```

## Reason

`state` is the source of truth.

`binding` is shared access to storage owned somewhere else.

`derived` is not stored. It is reconstructed from dependencies.

Together, those declarations describe the dependency shape directly.

From that shape, Range can derive a memory graph for ownership and storage.

For UI interfaces, it can derive reactivity from the same declarations.

The way you think about the code is reflected directly in the source you write.
