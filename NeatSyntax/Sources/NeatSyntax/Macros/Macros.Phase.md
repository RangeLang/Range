# Macro Phase

## Immediate Attached Macros
An immediate attached macro expands on the declaration it is directly attached to.

```neat
#clamped(min: 0, max: 10)
state count: Int = 0
```

`#clamped` expands on that `state` declaration itself.

## Deferred Requirement Macros
A deferred requirement macro is attached to a protocol requirement, but expands on the concrete declaration that fulfills that requirement.

```neat
protocol ExpressableByIntLiteral {
    #literal(RawInt)
    init(literal: RawInt)
}
```

`#literal(RawInt)` does not expand on the protocol. It is carried by the requirement and expands when a conforming construct provides the matching `init`.

## Deferred Conformance Macros
A protocol can also carry macros targeted at declaration kinds that conform to it, such as constructs or enums.

```neat
#equatable
protocol Equatable {
    function ==(lhs: Self, rhs: Self) -> Bool
}
```

`#equatable` does not expand on the protocol body itself. It is carried by the protocol and expands when a conforming declaration of the matching kind is realized.

## Rule
Macros attached to protocol requirements or protocols themselves are part of that protocol's semantics. They expand when those semantics are realized by a concrete conforming declaration of the matching kind.
