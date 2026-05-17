# Namespace Declarations As Attributes

I want namespace declarations to become attribute names.

Not through a side table in validation.

Through the declaration graph.

That is the important move.

A namespace is already a declaration.

So if `namespace Styling {}` makes `@Styling` valid, that fact should live where declarations are collected.

## The Question

Should namespace-backed attributes be checked by walking source files inside the validator?

Or should the declaration graph collect namespace attribute names as declaration facts?

My answer is the graph.

The validator should ask.

The graph should know.

## Point A

Point A worked.

The compiler could accept this:

```neat
namespace Styling {}

@Styling
construct Panel {
    let title: String
}
```

It also rejected this:

```neat
@Missing
construct Panel {
    let title: String
}
```

With the right diagnostic:

```text
Declare namespace Missing to use @Missing.
```

So the behavior was there.

But the model was in the wrong place.

The validator collected namespace names for itself:

```swift
private func validateAttributeUsage(
    in parsedFiles: [ParsedSourceFile],
    availableNamespaces: Set<String>
) throws {
    for parsedFile in parsedFiles {
        for declaration in attributedConstructs(in: parsedFile.sourceFile) {
            try validateAttribute(
                declaration.attribute,
                declarationName: declaration.name,
                filePath: parsedFile.path,
                availableNamespaces: availableNamespaces
            )
        }
    }
}
```

And then it checked the attribute against that local set:

```swift
guard NeatSyntax.attributeIdentifiers.contains(attribute.name)
    || availableNamespaces.contains(attribute.name)
else {
    throw SemanticValidationError(
        "Unknown attribute @\(attribute.name) in \(lastPathComponent(of: filePath)). Declare namespace \(attribute.name) to use @\(attribute.name)."
    )
}
```

This works.

But it makes validation rediscover declaration meaning.

That is the annoying part.

The validator had to know how to walk namespace declarations:

```swift
private func namespaceNames(in parsedFiles: [ParsedSourceFile]) -> Set<String> {
    Set(parsedFiles.flatMap { namespaces(in: $0.sourceFile).map(\.name) })
}

private func namespaces(in sourceFile: SourceFileNode) -> [NamespaceDeclaration] {
    switch sourceFile {
    case .namespace(let declaration):
        return [declaration] + declaration.namespaces.flatMap { namespaces(in: .namespace($0)) }
    case .module(let module):
        return module.namespaces.flatMap { namespaces(in: .namespace($0)) }
            + module.extensions.flatMap { namespaces(in: $0) }
    case .extensions(let declarations):
        return declarations.flatMap { namespaces(in: $0) }
    case .construct(let declaration):
        return declaration.constructs.flatMap { namespaces(in: .construct($0)) }
    case .mainBlock, .enumeration, .protocolDefinition, .macro, .marker:
        return []
    }
}
```

That is graph work.

Not validation work.

## Point B

Point B keeps the same source behavior.

But the source fact moves into the declaration graph:

```swift
public struct DeclarationGraph {
    public let protocolsByName: [String: ProtocolDeclaration]
    public let namespacesByName: [String: NamespaceDeclaration]
    public let namespaceAttributeNames: Set<String]
    public let constructsByName: [String: ConstructDeclaration]
}
```

The graph collects the names once:

```swift
static func collectNamespaceAttributeNames(from files: [ParsedSourceFile]) -> Set<String> {
    var names: Set<String> = []
    for parsedFile in files {
        for declaration in namespaces(in: parsedFile.sourceFile) {
            collectNamespaceAttributeName(declaration, into: &names)
        }
        for declaration in extensions(in: parsedFile.sourceFile) {
            collectNamespaceAttributeNames(in: declaration, into: &names)
        }
    }
    return names
}
```

Then it exposes the fact through a graph query:

```swift
public func hasNamespaceAttribute(named name: String) -> Bool {
    namespaceAttributeNames.contains(name)
}
```

The validator becomes smaller:

```swift
guard NeatSyntax.attributeIdentifiers.contains(attribute.name)
    || declarationGraph.hasNamespaceAttribute(named: attribute.name)
else {
    throw SemanticValidationError(
        "Unknown attribute @\(attribute.name) in \(lastPathComponent(of: filePath)). Declare namespace \(attribute.name) to use @\(attribute.name)."
    )
}
```

That is the shape I want.

Validation asks a semantic question.

The graph answers with collected declaration data.

## The Move

The visible move is small.

Remove:

```text
availableNamespaces
namespaceNames(in:)
validator-owned namespace walking
```

Add:

```text
DeclarationGraph.namespaceAttributeNames
DeclarationGraph.collectNamespaceAttributeNames(from:)
DeclarationGraph.hasNamespaceAttribute(named:)
```

The deeper move is about ownership.

Point A:

```text
validator
  walks source
  finds namespace names
  validates attributes
```

Point B:

```text
declaration graph
  collects namespace declarations
  derives namespace attribute names

validator
  validates attribute usage by querying graph
```

Same rule.

Better home.

## The Model

A namespace declaration now has two graph-level effects.

It declares a namespace:

```text
namespace Styling
```

And it declares an attribute name:

```text
attribute Styling
  source: namespace Styling
```

That second line is not a built-in attribute.

It is not magic.

It is a declaration-backed semantic tag.

The attribute surface stays simple:

```neat
@Styling
construct Panel {
    let title: String
}
```

But the compiler reads it as:

```text
attribute application
  name: Styling
  valid because declaration graph contains namespace attribute Styling
```

The attribute is not inventing a type.

It is naming a declared concept.

## Nested Namespaces

Namespace declarations already nest.

That matters.

The graph collects each declared namespace attribute name recursively:

```swift
private static func collectNamespaceAttributeName(
    _ declaration: NamespaceDeclaration,
    into names: inout Set<String>
) {
    names.insert(declaration.name)
    for child in declaration.namespaces {
        collectNamespaceAttributeName(child, into: &names)
    }
}
```

This keeps the attribute rule close to the namespace declaration rule.

If a namespace exists in the program shape, its name can be an attribute name.

The attribute name is collected as declaration metadata.

Not recovered later.

## Extensions

Extensions matter too.

Namespaces can be reopened through extensions.

So the graph also collects namespace attribute names inside extension declarations:

```swift
private static func collectNamespaceAttributeNames(
    in declaration: ExtensionDeclaration,
    into names: inout Set<String>
) {
    for namespace in declaration.namespaces {
        collectNamespaceAttributeName(namespace, into: &names)
    }
}
```

This keeps the rule stable.

It does not matter whether the namespace appears in a primary namespace declaration or inside an extension body.

The declaration graph sees it.

Then validation can use it.

## The Boundary

Built-in attributes still exist.

`@main`, `@background`, `@language`, and `@packaging` are compiler-known names.

Namespace attributes are different.

They are program-declared names.

So validation has two sources of truth:

```text
built-in attribute identifiers
namespace attribute names from declaration graph
```

That is the boundary.

The parser should not special-case every domain tag.

The validator should not rediscover namespace declarations.

The declaration graph should preserve the program's declared attribute vocabulary.

## The Path

The parser keeps parsing namespace declarations and attribute applications separately.

The declaration graph collects declarations:

```text
protocols
namespaces
namespace attribute names
constructs
enums
macros
markers
```

The validator checks only project attribute usage.

It rejects `@language` outside NeatCore.

It accepts built-in attributes.

It accepts namespace-backed attributes through:

```swift
declarationGraph.hasNamespaceAttribute(named: attribute.name)
```

The test now says both things.

The source compiles:

```swift
let program = try CompilerPipeline().buildValidated(inputs: inputs)
```

And the graph carries the fact:

```swift
#expect(program.declarationGraph.hasNamespaceAttribute(named: "Styling"))
```

That expectation is the important part.

The feature is not only that `@Styling` passes.

The feature is that the declaration graph knows why it passes.

## The Result

Namespace-backed attributes are now data-shaped.

A library can create a semantic tag with:

```neat
namespace Styling {}
```

Then declarations can use it:

```neat
@Styling
construct Panel {
    let title: String
}
```

The compiler does not need a new hardcoded attribute for that domain.

The graph records the declared vocabulary.

The validator queries it.

Later tools can query it too.

That is the real payoff.

The source declares a concept.

The graph preserves it.

Attribute validation becomes one consumer of that fact, not the place where the fact is born.
