# Introductory Math Relations In Range

Introductory math in Range should be described by the most honest relation each
idea actually has.

The goal is not to make every beginner concept sound abstract. The goal is to
avoid lying about what the concept does.

## Values

A value is a point in a value space.

```range
1
2
-5
true
false
```

`Bool` is the cleanest introductory example: it is a closed binary value space.
There are exactly two values, `true` and `false`.

`Int` is different. It has finite literal values and can participate in a
dynamic numeric case space such as `DynamicInt.zero`,
`DynamicInt.positiveInfinity`, and `DynamicInt.negativeInfinity`.

## Equality

Equality is not a number. It is a relation between two values.

```range
lhs == rhs
```

The honest relation is:

```range
MathRelation<Value, Value>
```

For `Equatable`, that relation returns `Bool`.

## Order

Order is also a relation between two values, but it has direction.

```range
lhs < rhs
```

The honest meaning is not "less is a number." It is:

- compare left to right
- return a binary truth value
- allow sorting, ranges, bounds, and intervals to be built from that relation

## Pair

A pair is two values held together.

```range
construct MathPair<A, B> {
    let first: A
    let second: B
}
```

Pairs are the honest base for coordinates, bounds, endpoints, and binary
relations.

## Function

A function maps one value space into another.

```range
construct MathFunction<Input, Output> {
    let signature: FunctionTypeReference
    let body: Closure
    let source: WrittenSyntax?
}
```

This is the cleanest way to store math in Range: the input and output are typed,
the body is parsed Range syntax, and the source text is only provenance.

## Field

A field is a function sampled over a domain.

```range
construct MathField<Sample, Output> {
    let value: MathFunction<Sample, Output>
}
```

This is honest for gradients, shadows, filters, geometry, and shader-like visual
work. A field is not a bitmap. It is a typed function that can be sampled.

## Line

A mathematical line in the current model is an endpoint relation.

```range
construct MathLine<Point> {
    let start: Point
    let end: Point
}
```

This is intentionally simple. It does not claim to be every possible analytic
line. It says: here are two points, and the line relation connects them.

## Edge

An edge is a relation between nodes.

```range
construct MathEdge<Node> {
    let start: Node
    let end: Node
}
```

A line is geometric. An edge is graph-like. A gradient edge can carry a line,
color link, and visual meaning. A graph edge can carry dependency meaning. The
word edge should mean relation first, not pixels.

## Axis

An axis is an ordered family of edges.

```range
construct MathAxis<Edge> {
    let edges: [Edge]
}
```

This matches the visual model: a gradient can have multiple axes, and each axis
can have multiple edges. It also matches layout and state: an axis is a
directional relation space.

## Sample

A sample names the domain being read.

```range
construct MathSample<Domain> {
    let domain: Domain
}
```

For visuals, a sample may be a surface coordinate, a gradient point, or a shadow
sample. The honest relation is: evaluate something at this domain position.

## Practical Rule

When adding math to Range, pick the relation first:

- value: a member of a value space
- equality: relation between two values
- order: directed comparison relation
- pair: two values held together
- function: typed mapping
- field: sampled function over a domain
- line: geometric endpoint relation
- edge: node relation
- axis: ordered family of edges
- sample: a domain read

That gives beginners real names without pretending that every idea is just a
number or every visual feature is just a renderer trick.
