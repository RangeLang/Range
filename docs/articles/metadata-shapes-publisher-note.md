# Metadata Shapes Publisher Note

I am moving Neat away from small syntax traps and keyword piles.

Point A was this:

```neat
let version: Version = Version(0.1.8)
let value: Optional<Int>
namespace Math {}
```

Point B is this:

```neat
let version: Version(0.1.8)

#optional
let value: Int

#namespace(.locked)
construct Math {}
```

The change is simple: declarations should carry metadata. Not every idea needs a keyword. Not every shape needs punctuation. The graph should see the thing directly.

## Message 1

Typed construction moves initialization out of assignment language.

Before:

```neat
let version: Version = Version(0.1.8)
```

After:

```neat
let version: Version(0.1.8)
```

The binding is born as `Version` with construction data. The graph should not learn "slot, then value" when the source means "binding, type, data".

## Message 2

Optionality and namespace behavior become declaration metadata.

Before:

```neat
let value: Optional<Int>
namespace Math {}
```

After:

```neat
#optional
let value: Int

#namespace(.locked)
construct Math {}
```

This keeps optionality and namespace-ness out of type punctuation and keywords. `#namespace(.locked)` says the declaration is namespace-shaped and cannot be externally reopened or modified.

## Message 3

Visibility gets quieter.

Default public. Explicit private.

```neat
#namespace(.locked)
construct Math {
    function sin(_ x: Float) -> Float
    private function reduce(_ x: Float) -> Float
}
```

No `public` spam. Normal declarations are exported. Only the exception gets marked. The code gets smaller, and the graph gets clearer.
