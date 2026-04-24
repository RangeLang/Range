import Foundation

struct MacroTargetValueBuilder {
    func targetValue(for construct: ConstructDeclaration) -> MacroValue {
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

    func targetValue(for enumeration: EnumDeclaration) -> MacroValue {
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

    func targetValue(for protocolDeclaration: ProtocolDeclaration) -> MacroValue {
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

    func declarationName(for value: MacroValue) -> String {
        guard let declaration = value.field("declaration"),
            let selfValue = declaration.field("self"),
            case .object(_, let fields) = selfValue,
            case .string(let name)? = fields["name"]
        else {
            return ""
        }
        return name
    }

    private func declarationValue(for declaration: ConstructDeclaration) -> MacroValue {
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

    private func value(for declaration: ValueDeclaration) -> MacroValue {
        .object(
            typeName: "Let",
            fields: [
                "name": .string(declaration.name),
                "type": typeReferenceValue(declaration.typeName),
            ]
        )
    }

    private func value(for declaration: StateDeclaration) -> MacroValue {
        .object(
            typeName: "State",
            fields: [
                "name": .string(declaration.name),
                "type": typeReferenceValue(declaration.type.displayName),
            ]
        )
    }

    private func value(for declaration: BindingDeclaration) -> MacroValue {
        .object(
            typeName: "Binding",
            fields: [
                "name": .string(declaration.name),
                "type": typeReferenceValue(declaration.typeName),
            ]
        )
    }

    private func value(for declaration: DerivedDeclaration) -> MacroValue {
        .object(
            typeName: "Derived",
            fields: [
                "name": .string(declaration.name),
                "type": typeReferenceValue(declaration.typeName),
            ]
        )
    }

    private func value(for declaration: InitializerDeclaration) -> MacroValue {
        .object(
            typeName: "Init.Declaration",
            fields: [
                "parameters": .array(declaration.parameters.map(value(for:)))
            ]
        )
    }

    private func value(for declaration: CallableDeclaration) -> MacroValue {
        .object(
            typeName: "Function.Declaration",
            fields: [
                "name": .string(declaration.name),
                "parameters": .array(declaration.parameters.map(value(for:))),
                "returnType": declaration.returnType.map(typeReferenceValue) ?? .string("Void"),
            ]
        )
    }

    private func value(for declaration: NeatFunctionParameter) -> MacroValue {
        .object(
            typeName: "Parameter.Declaration",
            fields: [
                "name": .string(declaration.name),
                "type": declaration.typeReference.map(typeReferenceValue) ?? .string("Void"),
            ]
        )
    }

    private func value(for declaration: EnumCaseDeclaration) -> MacroValue {
        .object(
            typeName: "Enum.Case",
            fields: [
                "name": .string(declaration.name),
                "associatedValues": .array(
                    declaration.associatedValues.map { associatedValue in
                        .object(
                            typeName: "Enum.AssociatedValue",
                            fields: [
                                "name": associatedValue.label.map(MacroValue.string) ?? .string(""),
                                "type": typeReferenceValue(associatedValue.typeReference),
                            ]
                        )
                    }
                ),
            ]
        )
    }

    private func nominalTypeReference(_ name: String) -> MacroValue {
        .object(typeName: "NamedTypeReference", fields: ["name": .string(name)])
    }

    private func typeReferenceValue(_ typeReference: TypeReference) -> MacroValue {
        typeReferenceValue(typeReference.displayName)
    }

    private func typeReferenceValue(_ name: String) -> MacroValue {
        nominalTypeReference(name)
    }
}

