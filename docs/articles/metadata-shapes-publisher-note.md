# Metadata Shapes Publisher Note

Neat is moving small declaration ideas into metadata shapes.

## Source Shape

```neat
let version: Version(0.1.8)
let count: Int(5)?
let value: Optional<Int>
@package {
    let name: Title("Neat")
    let version: Version(0.1.8)
    let author: String("George")
}
namespace Math {}

public construct Package {
    public function publish()
    private function sign()
}
```

## Publisher Shape

```neat
let version: Version(0.1.8)
let count: Int(5)?
let value: Optional<Int>

@package {
    let name: Title("Neat")
    let version: Version(0.1.8)
    let author: String("George")
}

#namespace(.locked)
construct Math {}

construct Package {
    function publish()
    private function sign()
}
```

## Why

The source shape keeps declaration facts on the declaration instead of spreading them across namespace keywords and visibility noise.

`let version: Version(0.1.8)` says the binding is born as `Version` with construction data. It is not assignment into a slot.

`let count: Int(5)?` keeps the same construction shape and makes the resulting type optional.

Optional is still a type shape. `Optional<Int>` stays explicit because the source is naming the wrapped type relationship, not attaching a separate declaration flag.

`@package { ... }` creates a package metadata space. It is not a namespace, but the graph can collect the package facts globally.

`#namespace(.locked)` says the construct is namespace-shaped, and that outside code cannot reopen or modify it.

Visibility gets quieter too. Public is the normal published shape. `private` marks the exception.

The graph gets a cleaner job:

```text
declaration
  metadata
  type
  construction data
  package metadata
  visibility
  namespace behavior
```

The publisher can read the declaration shape directly.

No reverse-engineering.

No keyword pile.

The source says the thing the package model needs.
