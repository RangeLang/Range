# Metadata Shapes Publisher Note

Neat is moving small declaration ideas into metadata shapes.

## Before

```neat
let version: Version = Version(0.1.8)
let count: Int? = 5
let value: Optional<Int>
namespace Math {}

public construct Package {
    public function publish()
    private function sign()
}
```

## After

```neat
let version: Version(0.1.8)
let count: Int(5)?
let value: Optional<Int>

#namespace(.locked)
construct Math {}

construct Package {
    function publish()
    private function sign()
}
```

## Why

The old shape works, but it spreads declaration meaning across assignment syntax, namespace keywords, and visibility noise.

The new shape keeps the facts on the declaration.

`let version: Version(0.1.8)` says the binding is born as `Version` with construction data. It is not assignment into a slot.

`let count: Int(5)?` keeps the same construction shape and makes the resulting type optional.

Optional is still a type shape. `Optional<Int>` stays explicit because the source is naming the wrapped type relationship, not attaching a separate declaration flag.

`#namespace(.locked)` says the construct is namespace-shaped, and that outside code cannot reopen or modify it.

Visibility gets quieter too. Public is the normal published shape. `private` marks the exception.

The graph gets a cleaner job:

```text
declaration
  metadata
  type
  construction data
  visibility
  namespace behavior
```

The publisher can read the declaration shape directly.

No reverse-engineering.

No keyword pile.

The source says the thing the package model needs.
