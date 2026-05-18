import Foundation

struct MacroTargetValueBuilder {
    let markerDeclarationsByName: [String: MarkerDeclaration]

    init(markerDeclarationsByName: [String: MarkerDeclaration] = [:]) {
        self.markerDeclarationsByName = markerDeclarationsByName
    }

    func targetValue(for construct: ConstructDeclaration) -> CompileTimeValue {
        .object(
            typeName: "Construct",
            fields: [
                "identity": graphIdentity(kind: "construct", name: construct.name),
                "declaration": declarationValue(for: construct, qualifiedName: construct.name),
            ]
        )
    }

    func targetValue(for enumeration: EnumDeclaration) -> CompileTimeValue {
        .object(
            typeName: "Enum",
            fields: [
                "identity": graphIdentity(kind: "enum", name: enumeration.name),
                "declaration": .object(
                    typeName: "Enum.Declaration",
                    fields: [
                        "identity": graphIdentity(kind: "enum", name: enumeration.name),
                        "self": nominalTypeReference(enumeration.name),
                        "generics": .array(enumeration.genericParameters.map(value(for:))),
                        "cases": .array(enumeration.cases.map(value(for:))),
                    ]
                )
            ]
        )
    }

    func targetValue(for protocolDeclaration: ProtocolDeclaration) -> CompileTimeValue {
        .object(
            typeName: "Protocol",
            fields: [
                "identity": graphIdentity(kind: "protocol", name: protocolDeclaration.name),
                "declaration": .object(
                    typeName: "Protocol.Declaration",
                    fields: [
                        "identity": graphIdentity(kind: "protocol", name: protocolDeclaration.name),
                        "self": nominalTypeReference(protocolDeclaration.name),
                        "generics": .array(protocolDeclaration.genericParameters.map(value(for:))),
                        "inits": .array(protocolDeclaration.initializers.map(value(for:))),
                        "functions": .array(protocolDeclaration.callables.map(value(for:))),
                    ]
                )
            ]
        )
    }

    func declarationName(for value: CompileTimeValue) -> String {
        guard let declaration = value.field("declaration"),
            let selfValue = declaration.field("self"),
            case .object(_, let fields) = selfValue,
            case .string(let name)? = fields["name"]
        else {
            return ""
        }
        return name
    }

    func declarationValue(for declaration: ConstructDeclaration, qualifiedName: String) -> CompileTimeValue {
        .object(
            typeName: "Construct.Declaration",
            fields: [
                "identity": graphIdentity(kind: "construct", name: qualifiedName),
                "self": nominalTypeReference(qualifiedName),
                "generics": .array(declaration.genericParameters.map(value(for:))),
                "conformances": .array(declaration.conformances.map(typeReferenceValue)),
                "inits": .array(declaration.initializers.map(value(for:))),
                "lets": .array(declaration.values.map(value(for:))),
                "states": .array(declaration.states.map(value(for:))),
                "bindings": .array(declaration.bindings.map(value(for:))),
                "deriveds": .array(declaration.deriveds.map(value(for:))),
                "functions": .array(declaration.callables.map(value(for:))),
                "constructs": .array(
                    declaration.constructs.map {
                        graphIdentity(kind: "construct", name: "\(qualifiedName).\($0.name)")
                    }
                ),
                "extensions": .array([]),
            ]
        )
    }

    func value(for declaration: ValueDeclaration) -> CompileTimeValue {
        return .object(
            typeName: "Let",
            fields: [
                "macros": .array(declaration.macros.map(value(for:))),
                "markers": .array(markerValues(for: declaration.macros)),
                "identifier": identifier(declaration.name),
                "type": typeReferenceValue(declaration.typeName),
                "typeName": .string(declaration.typeName),
            ]
        )
    }

    func value(for declaration: StateDeclaration) -> CompileTimeValue {
        .object(
            typeName: "State",
            fields: [
                "macros": .array(declaration.macros.map(value(for:))),
                "markers": .array(markerValues(for: declaration.macros)),
                "identifier": identifier(declaration.name),
                "type": typeReferenceValue(declaration.type.displayName),
            ]
        )
    }

    func value(for declaration: BindingDeclaration) -> CompileTimeValue {
        .object(
            typeName: "Binding",
            fields: [
                "macros": .array(declaration.macros.map(value(for:))),
                "markers": .array(markerValues(for: declaration.macros)),
                "identifier": identifier(declaration.name),
                "type": typeReferenceValue(declaration.typeName),
            ]
        )
    }

    func value(for declaration: DerivedDeclaration) -> CompileTimeValue {
        .object(
            typeName: "Derived",
            fields: [
                "macros": .array(declaration.macros.map(value(for:))),
                "markers": .array(markerValues(for: declaration.macros)),
                "identifier": identifier(declaration.name),
                "type": typeReferenceValue(declaration.typeName),
            ]
        )
    }

    private func markerValues(for applications: [MacroApplication]) -> [CompileTimeValue] {
        applications.compactMap { application in
            guard let marker = markerDeclarationsByName[application.name],
                let value = try? Self.evaluateMarkerValue(for: application, marker: marker)
            else {
                return nil
            }
            return .object(
                typeName: "Marker.Application",
                fields: [
                    "identifier": identifier(application.name),
                    "valueType": typeReferenceValue(marker.valueType),
                    "valueTypeName": .string(marker.valueType.displayName),
                    "value": value,
                ]
            )
        }
    }

    static func evaluateMarkerValue(
        for application: MacroApplication,
        marker: MarkerDeclaration,
        targetValue: CompileTimeValue = .object(typeName: "Marker.Target", fields: [:]),
        context: MacroExpansionContext? = nil
    ) throws -> CompileTimeValue {
        let bindings = try MacroExpander.parseMarkerArgumentBindings(
            for: marker,
            argumentClause: application.argumentClause
        )
        let markerBindings = marker.bindings

        let evaluator = CompileTimeValueEvaluator(
            targetBinding: markerBindings?.target ?? "__marker_target__",
            targetValue: targetValue,
            graphBinding: markerBindings?.graph,
            localBindings: bindings,
            context: context
        )

        var localBindings = bindings
        var value: CompileTimeValue?
        for statement in marker.body {
            switch statement {
            case .localBinding(let declaration):
                localBindings[declaration.name] = declaration.expression
            case .return(let expression?):
                value = evaluator.evaluate(expression, with: localBindings)
            case .expression(let expression):
                value = evaluator.evaluate(expression, with: localBindings)
            default:
                value = nil
            }
            if value != nil {
                break
            }
        }

        guard let value else {
            throw ParseError("Marker #\(marker.name) body could not be evaluated at compile time.")
        }

        guard markerValue(value, matches: marker.valueType) else {
            throw ParseError(
                "Marker #\(marker.name) evaluated value does not match \(marker.valueType.displayName)."
            )
        }

        return value
    }

    private static func markerValue(_ value: CompileTimeValue, matches type: TypeReference) -> Bool {
        switch (value, type) {
        case (.string, .named("String")):
            return true
        case (.integer, .named("Int")):
            return true
        case (.double, .named("Float")):
            return true
        case (.boolean, .named("Bool")):
            return true
        default:
            return false
        }
    }

    private func value(for application: MacroApplication) -> CompileTimeValue {
        .object(
            typeName: "Macro.Application",
            fields: [
                "identifier": identifier(application.name),
                "genericArguments": .array(application.genericArguments.map(typeReferenceValue)),
                "argumentClause": .string(application.argumentClause ?? ""),
                "arguments": .array(argumentValues(for: application)),
            ]
        )
    }

    private func argumentValues(for application: MacroApplication) -> [CompileTimeValue] {
        guard let argumentClause = application.argumentClause?.trimmingCharacters(
            in: .whitespacesAndNewlines
        ), !argumentClause.isEmpty else {
            return []
        }

        do {
            var parser = try Parser(source: "macro(\(argumentClause))")
            _ = try parser.consumeCallableName()
            let arguments = try parser.parseInvocationArgumentsIfPresent()
            try parser.consume(.eof)
            return arguments.compactMap { value(for: $0.value) }
        } catch {
            return []
        }
    }

    private func value(for expression: Expression) -> CompileTimeValue? {
        switch expression {
        case .string(let value):
            return .string(value)
        default:
            return nil
        }
    }

    func value(for declaration: InitializerDeclaration) -> CompileTimeValue {
        .object(
            typeName: "Init.Declaration",
            fields: [
                "parameters": .array(declaration.parameters.map(value(for:)))
            ]
        )
    }

    func value(for declaration: CallableDeclaration) -> CompileTimeValue {
        .object(
            typeName: "Function.Declaration",
            fields: [
                "identifier": identifier(declaration.name),
                "generics": .array(declaration.genericParameters.map(value(for:))),
                "parameters": .array(declaration.parameters.map(value(for:))),
                "returnType": declaration.returnType.map(typeReferenceValue) ?? .string("Void"),
            ]
        )
    }

    func value(for parameter: GenericParameter) -> CompileTimeValue {
        switch parameter {
        case .type(let name, let constraint, let defaultArgument):
            return .object(
                typeName: "TypeGeneric",
                fields: [
                    "identifier": identifier(name),
                    "constraint": constraint.map(typeReferenceValue) ?? .string(""),
                    "default": defaultArgument.map(typeReferenceValue) ?? .string(""),
                ]
            )
        case .value(let name, let typeReference, let defaultValue):
            return .object(
                typeName: "ValueGeneric",
                fields: [
                    "identifier": identifier(name),
                    "type": typeReferenceValue(typeReference),
                    "default": defaultValue.flatMap(value(for:)) ?? .string(""),
                ]
            )
        }
    }

    func value(for declaration: NeatFunctionParameter) -> CompileTimeValue {
        .object(
            typeName: "Parameter.Declaration",
            fields: [
                "externalName": declaration.externalLabel.map(CompileTimeValue.string) ?? .string(""),
                "localName": .string(declaration.localName),
                "type": declaration.typeReference.map(typeReferenceValue) ?? .string("Void"),
                "defaultValue": declaration.defaultValue.flatMap(value(for:)) ?? .string(""),
            ]
        )
    }

    func value(for declaration: EnumCaseDeclaration) -> CompileTimeValue {
        .object(
            typeName: "Enum.Case",
            fields: [
                "identifier": identifier(declaration.name),
                "associatedValues": .array(
                    declaration.associatedValues.map { associatedValue in
                        .object(
                            typeName: "Enum.AssociatedValue",
                            fields: [
                                "name": associatedValue.label.map(CompileTimeValue.string) ?? .string(""),
                                "type": typeReferenceValue(associatedValue.typeReference),
                            ]
                        )
                    }
                ),
            ]
        )
    }

    private func nominalTypeReference(_ name: String) -> CompileTimeValue {
        .object(typeName: "NamedTypeReference", fields: ["name": .string(name)])
    }

    private func identifier(_ name: String) -> CompileTimeValue {
        .object(typeName: "Identifier", fields: ["name": .string(name)])
    }

    private func typeReferenceValue(_ typeReference: TypeReference) -> CompileTimeValue {
        typeReferenceValue(typeReference.displayName)
    }

    private func typeReferenceValue(_ name: String) -> CompileTimeValue {
        nominalTypeReference(name)
    }

    func graphIdentity(kind: String, name: String) -> CompileTimeValue {
        .object(
            typeName: "Graph.Identity",
            fields: [
                "id": .string("\(kind):\(name)"),
                "kind": .string(kind),
                "name": .string(name),
            ]
        )
    }
}
