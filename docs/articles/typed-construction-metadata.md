# Typed Construction Metadata

The declaration owns construction.

Not assignment.

Not sugar.

## Shape

```neat
let version: Version(0.1.8)
let count: Int(5)?
let input: Channel<Int>
```

Read it as:

```text
binding version
  type: Version
  construction data: 0.1.8

binding count
  type: Int?
  construction data: 5

binding input
  type: Channel<Int>
  default construction
```

The `:` opens the type.

The type may receive construction data.

The optional marker applies to the resulting type.

## Replacement Rule

Assignment-shaped construction teaches the wrong model.

It makes initialization look like assignment into a slot.

Use declaration-shaped construction instead:

```neat
let input: Channel<Int>
let version: Version(0.1.8)
```

## Boundary

Assignment remains mutation or value transfer after a binding already exists.

```neat
state current: Int = 0
current = 1
```

Backend lowering may still emit ordinary Swift initializer calls.

That is backend shape.

The source graph should keep declaration construction as a declaration fact.
