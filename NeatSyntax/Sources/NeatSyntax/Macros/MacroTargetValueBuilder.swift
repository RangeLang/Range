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
                "declaration": .object(
                    typeName: "Construct.Declaration",
                    fields: [
                        "self": nominalTypeReference(construct.name),
                        "conformances": .array(construct.conformances.map(typeReferenceValue)),
                        "inits": .array(construct.initializers.map(value(for:))),
                        "lets": .array(construct.values.map(value(for:))),
                        "states": .array(construct.states.map(value(for:))),
                        "bindings": .array(construct.bindings.map(value(for:))),
                        "deriveds": .array(construct.deriveds.map(value(for:))),
                        "functions": .array(construct.callables.map(value(for:))),
                        "constructs": .array(construct.constructs.map(declarationValue(for:))),
                        "extensions": .array([]),
                    ]
                )
            ]
        )
    }

    func targetValue(for enumeration: EnumDeclaration) -> CompileTimeValue {
        .object(
            typeName: "Enum",
            fields: [
                "declaration": .object(
                    typeName: "Enum.Declaration",
                    fields: [
                        "self": nominalTypeReference(enumeration.name),
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
                "declaration": .object(
                    typeName: "Protocol.Declaration",
                    fields: [
                        "self": nominalTypeReference(protocolDeclaration.name),
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

    private func declarationValue(for declaration: ConstructDeclaration) -> CompileTimeValue {
        .object(
            typeName: "Construct.Declaration",
            fields: [
                "self": nominalTypeReference(declaration.name),
                "conformances": .array(declaration.conformances.map(typeReferenceValue)),
                "inits": .array(declaration.initializers.map(value(for:))),
                "lets": .array(declaration.values.map(value(for:))),
                "states": .array(declaration.states.map(value(for:))),
                "bindings": .array(declaration.bindings.map(value(for:))),
                "deriveds": .array(declaration.deriveds.map(value(for:))),
                "functions": .array(declaration.callables.map(value(for:))),
                "constructs": .array(declaration.constructs.map(declarationValue(for:))),
                "extensions": .array([]),
            ]
        )
    }

    private func value(for declaration: ValueDeclaration) -> CompileTimeValue {
        .object(
            typeName: "Let",
            fields: [
                "macros": .array(declaration.macros.map(value(for:))),
                "markers": .array(markerValues(for: declaration.macros)),
                "name": .string(declaration.name),
                "type": typeReferenceValue(declaration.typeName),
            ]
        )
    }

    private func value(for declaration: StateDeclaration) -> CompileTimeValue {
        .object(
            typeName: "State",
            fields: [
                "macros": .array(declaration.macros.map(value(for:))),
                "markers": .array(markerValues(for: declaration.macros)),
                "name": .string(declaration.name),
                "type": typeReferenceValue(declaration.type.displayName),
            ]
        )
    }

    private func value(for declaration: BindingDeclaration) -> CompileTimeValue {
        .object(
            typeName: "Binding",
            fields: [
                "macros": .array(declaration.macros.map(value(for:))),
                "markers": .array(markerValues(for: declaration.macros)),
                "name": .string(declaration.name),
                "type": typeReferenceValue(declaration.typeName),
            ]
        )
    }

    private func value(for declaration: DerivedDeclaration) -> CompileTimeValue {
        .object(
            typeName: "Derived",
            fields: [
                "macros": .array(declaration.macros.map(value(for:))),
                "markers": .array(markerValues(for: declaration.macros)),
                "name": .string(declaration.name),
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
                    "name": .string(application.name),
                    "value": value,
                ]
            )
        }
    }

    static func evaluateMarkerValue(
        for application: MacroApplication,
        marker: MarkerDeclaration
    ) throws -> CompileTimeValue {
        let bindings = try MacroExpander.parseMarkerArgumentBindings(
            for: marker,
            argumentClause: application.argumentClause
        )

        let evaluator = CompileTimeValueEvaluator(
            targetBinding: "__marker_target__",
            targetValue: .object(typeName: "Marker.Target", fields: [:]),
            localBindings: bindings
        )

        guard marker.body.count == 1 else {
            throw ParseError("Marker #\(marker.name) body must evaluate to one compile-time value.")
        }

        let value: CompileTimeValue?
        switch marker.body[0] {
        case .return(let expression?):
            value = evaluator.evaluate(expression)
        case .expression(let expression):
            value = evaluator.evaluate(expression)
        default:
            value = nil
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
                "name": .string(application.name),
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

    private func value(for declaration: InitializerDeclaration) -> CompileTimeValue {
        .object(
            typeName: "Init.Declaration",
            fields: [
                "parameters": .array(declaration.parameters.map(value(for:)))
            ]
        )
    }

    private func value(for declaration: CallableDeclaration) -> CompileTimeValue {
        .object(
            typeName: "Function.Declaration",
            fields: [
                "name": .string(declaration.name),
                "parameters": .array(declaration.parameters.map(value(for:))),
                "returnType": declaration.returnType.map(typeReferenceValue) ?? .string("Void"),
            ]
        )
    }

    private func value(for declaration: NeatFunctionParameter) -> CompileTimeValue {
        .object(
            typeName: "Parameter.Declaration",
            fields: [
                "name": .string(declaration.name),
                "type": declaration.typeReference.map(typeReferenceValue) ?? .string("Void"),
            ]
        )
    }

    private func value(for declaration: EnumCaseDeclaration) -> CompileTimeValue {
        .object(
            typeName: "Enum.Case",
            fields: [
                "name": .string(declaration.name),
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

    private func typeReferenceValue(_ typeReference: TypeReference) -> CompileTimeValue {
        typeReferenceValue(typeReference.displayName)
    }

    private func typeReferenceValue(_ name: String) -> CompileTimeValue {
        nominalTypeReference(name)
    }
}
