# Syntax Declarations And Applications

The syntax model is organized around language concepts first, then the ways those concepts appear in source.

## Observation

`@syntax` is the marker for compiler-visible syntax surfaces.

Specific protocols describe how a compiler phase can consume a node:

```neat
@syntax
protocol Statement {}

@syntax
protocol Expression: Statement, SyntaxReplaceable<Expression> {
    let type: TypeReference?
}

@syntax
protocol TypeReference: SyntaxReplaceable<TypeReference> {}
```

Those protocols are not the whole tree.

The AST language tree is owned by the thing being described:

```neat
@syntax
construct Construct {
    let declaration: Declaration
    let application: Application

    @syntax
    construct Declaration<SelfType: NominalTypeReference>: SyntaxExpandable<SelfType>, SyntaxEmittable {
        let self: SelfType
        let lets: [Let]
        let states: [State]
        let functions: [Function.Declaration]

        function expand(_ expansion: () -> [Syntax])
    }

    @syntax
    construct Application: SyntaxReplaceable<Expression> {
        let type: TypeReference
        let arguments: [Parameter.Application]

        function replace(with replacement: Expression) -> Expression
    }
}
```

A construct declaration and a construct application are related, but they are not the same syntax shape.

The same split appears again for functions and parameters:

```neat
@syntax
construct Function {
    let declaration: Declaration
    let application: Application

    @syntax
    construct Declaration: SyntaxEmittable {
        let identifier: Identifier
        let parameters: [Parameter.Declaration]
        let returnType: TypeReference?
        let body: Block
    }

    @syntax
    construct Application: SyntaxEmittable, SyntaxReplaceable<Expression> {
        let identifier: Identifier
        let arguments: [Parameter.Application]
    }
}
```

```neat
@syntax
construct Parameter {
    let declaration: Declaration
    let application: Application

    @syntax
    construct Declaration {
        let externalName: String?
        let localName: String
        let type: TypeReference
        let defaultValue: Expression?
    }

    @syntax
    construct Application {
        let label: String?
        let type: TypeReference
        let expression: Expression
    }
}
```

The declaration side records what exists.

The application side records a use of what exists.

## Shape

```text
@syntax
  Statement
  Expression
  TypeReference

  Construct
    Declaration
    Application

  Function
    Declaration
    Application

  Parameter
    Declaration
    Application

  Protocol
    Declaration
    Application<Conformer>
```

Protocols cut across the tree. Nested declarations keep ownership local.

`Function.Application` can be consumed as emitted syntax and replaceable expression syntax. `Construct.Declaration` can be consumed as expandable emitted syntax. `Protocol.Application<Construct.Declaration>` describes a graph-backed relationship from a protocol to a conforming declaration.

## Reason

This keeps the syntax model from becoming a flat bag of parser node names.

The compiler can ask broad questions from `@syntax` and capability protocols, while the language tree still says where each shape belongs. Declarations, applications, expansions, replacements, and graph-backed relationships get distinct names instead of being hidden inside one overloaded AST node.
