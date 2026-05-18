# Marker-Carried Namespaces

Markers can move declaration data into graph concepts.

## Feature

A namespace can be declared as an ordinary construct tagged with `#namespace`. The marker registers the construct globally, then the construct body becomes the namespace payload.

## Example / Shape

```neat
marker namespace(): Namespace<Construct>

#namespace
construct Math {
    function clamp(_ value: Int, min: Int, max: Int) -> Int {
        if value < min {
            return min
        }

        if value > max {
            return max
        }

        return value
    }
}

#Math
construct Vector {
    let x: Float
    let y: Float
}
```

Graph shape:

```text
namespace Math
  functions:
    clamp

construct Vector
  markers:
    Math
  available namespace:
    Math
```

## Reason

The namespace is no longer a separate keyword shape with a private compiler path. It is data moved through the marker system.

`#namespace` tags `Math`, the marker registration makes `Math` globally discoverable, and `#Math` attaches that namespace data to `Vector`.

That keeps the source small while giving the graph the thing it actually needs: a named concept, its payload, and the declarations that opt into it.
