import Foundation

struct MacroTargetValueBuilder {
    let macroDeclarationsByName: [String: MacroDeclaration]
    let markerDeclarationsByName: [String: MarkerDeclaration]
    let writtenSyntaxByID: [String: CompileTimeValue]

    init(
        macroDeclarationsByName: [String: MacroDeclaration] = [:],
        markerDeclarationsByName: [String: MarkerDeclaration] = [:],
        writtenSyntaxByID: [String: CompileTimeValue] = [:]
    ) {
        self.macroDeclarationsByName = macroDeclarationsByName
        self.markerDeclarationsByName = markerDeclarationsByName
        self.writtenSyntaxByID = writtenSyntaxByID
    }

    func targetValue(for construct: ConstructDeclaration) -> CompileTimeValue {
        let id = "construct:\(construct.name)"
        return .object(
            typeName: "Construct",
            fields: [
                "identity": graphIdentity(kind: "construct", name: construct.name),
                "written": writtenSyntaxByID[id] ?? writtenSyntax(""),
                "declaration": declarationValue(for: construct, qualifiedName: construct.name),
            ]
        )
    }

    func targetValue(for enumeration: EnumDeclaration) -> CompileTimeValue {
        let id = "enum:\(enumeration.name)"
        return .object(
            typeName: "Enum",
            fields: [
                "identity": graphIdentity(kind: "enum", name: enumeration.name),
                "written": writtenSyntaxByID[id] ?? writtenSyntax(""),
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
        let id = "protocol:\(protocolDeclaration.name)"
        return .object(
            typeName: "Protocol",
            fields: [
                "identity": graphIdentity(kind: "protocol", name: protocolDeclaration.name),
                "written": writtenSyntaxByID[id] ?? writtenSyntax(""),
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

    func targetValue(for extensionDeclaration: ExtensionDeclaration) -> CompileTimeValue {
        let target = typeReferenceValue(extensionDeclaration.targetType)
        let declaration = value(for: extensionDeclaration)
        let protocols = extensionDeclaration.protocols.map {
            graphIdentity(kind: "protocol", name: $0.name)
        }
        let initializers = extensionDeclaration.initializers.map { value(for: $0) }
        let functions = extensionDeclaration.callables.map { value(for: $0) }
        let constructs = extensionDeclaration.constructs.map {
            graphIdentity(kind: "construct", name: $0.name)
        }
        let enumerations = extensionDeclaration.enumerations.map {
            graphIdentity(kind: "enum", name: $0.name)
        }

        return .object(
            typeName: "Extension",
            fields: [
                "identity": graphIdentity(
                    kind: "extension",
                    name: extensionDeclaration.targetType.displayName
                ),
                "written": writtenSyntaxByID["extension:\(extensionDeclaration.targetType.displayName)"] ?? writtenSyntax(""),
                "target": target,
                "declaration": declaration,
                "markers": .array(markerValues(for: extensionDeclaration.macros)),
                "protocols": .array(protocols),
                "inits": .array(initializers),
                "functions": .array(functions),
                "constructs": .array(constructs),
                "enums": .array(enumerations),
            ]
        )
    }

    func value(for declaration: ExtensionDeclaration) -> CompileTimeValue {
        let target = typeReferenceValue(declaration.targetType)
        let conformances = declaration.conformances.map(typeReferenceValue)
        let protocols = declaration.protocols.map {
            graphIdentity(kind: "protocol", name: $0.name)
        }
        let initializers = declaration.initializers.map { value(for: $0) }
        let functions = declaration.callables.map { value(for: $0) }
        let constructs = declaration.constructs.map {
            graphIdentity(kind: "construct", name: $0.name)
        }
        let enumerations = declaration.enumerations.map {
            graphIdentity(kind: "enum", name: $0.name)
        }

        return .object(
            typeName: "Extension.Declaration",
            fields: [
                "identity": graphIdentity(
                    kind: "extension",
                    name: declaration.targetType.displayName
                ),
                "target": target,
                "conformances": .array(conformances),
                "markers": .array(markerValues(for: declaration.macros)),
                "protocols": .array(protocols),
                "inits": .array(initializers),
                "functions": .array(functions),
                "constructs": .array(constructs),
                "enums": .array(enumerations),
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
                "macros": .array(declaration.macros.map(value(for:))),
                "markers": .array(markerValues(for: declaration.macros)),
                "generics": .array(declaration.genericParameters.map(value(for:))),
                "conformances": .array(declaration.conformances.map(typeReferenceValue)),
                "inits": .array(declaration.initializers.map(value(for:))),
                "lets": .array(declaration.values.map {
                    value(for: $0, ownerConstructName: qualifiedName)
                }),
                "states": .array(declaration.states.map {
                    value(for: $0, ownerConstructName: qualifiedName)
                }),
                "bindings": .array(declaration.bindings.map {
                    value(for: $0, ownerConstructName: qualifiedName)
                }),
                "deriveds": .array(declaration.deriveds.map {
                    value(for: $0, ownerConstructName: qualifiedName)
                }),
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
        value(for: declaration, ownerConstructName: nil)
    }

    func value(
        for declaration: ValueDeclaration,
        ownerConstructName: String?
    ) -> CompileTimeValue {
        var fields: [String: CompileTimeValue] = [
            "macros": .array(declaration.macros.map(value(for:))),
            "markers": .array(markerValues(for: declaration.macros)),
            "identifier": identifier(declaration.name),
            "type": typeReferenceValue(declaration.typeName),
            "typeName": .string(declaration.typeName),
        ]
        addPropertyGraphFields(
            to: &fields,
            kind: "let",
            name: declaration.name,
            ownerConstructName: ownerConstructName
        )
        return .object(
            typeName: "Let",
            fields: fields
        )
    }

    func value(for declaration: StateDeclaration) -> CompileTimeValue {
        value(for: declaration, ownerConstructName: nil)
    }

    func value(
        for declaration: StateDeclaration,
        ownerConstructName: String?
    ) -> CompileTimeValue {
        var fields: [String: CompileTimeValue] = [
            "macros": .array(declaration.macros.map(value(for:))),
            "markers": .array(markerValues(for: declaration.macros)),
            "identifier": identifier(declaration.name),
            "type": typeReferenceValue(declaration.type.displayName),
        ]
        addPropertyGraphFields(
            to: &fields,
            kind: "state",
            name: declaration.name,
            ownerConstructName: ownerConstructName
        )
        return .object(
            typeName: "State",
            fields: fields
        )
    }

    func value(for declaration: BindingDeclaration) -> CompileTimeValue {
        value(for: declaration, ownerConstructName: nil)
    }

    func value(
        for declaration: BindingDeclaration,
        ownerConstructName: String?
    ) -> CompileTimeValue {
        var fields: [String: CompileTimeValue] = [
            "macros": .array(declaration.macros.map(value(for:))),
            "markers": .array(markerValues(for: declaration.macros)),
            "identifier": identifier(declaration.name),
            "type": typeReferenceValue(declaration.typeName),
        ]
        addPropertyGraphFields(
            to: &fields,
            kind: "binding",
            name: declaration.name,
            ownerConstructName: ownerConstructName
        )
        return .object(
            typeName: "Binding",
            fields: fields
        )
    }

    func value(for declaration: DerivedDeclaration) -> CompileTimeValue {
        value(for: declaration, ownerConstructName: nil)
    }

    func value(
        for declaration: DerivedDeclaration,
        ownerConstructName: String?
    ) -> CompileTimeValue {
        var fields: [String: CompileTimeValue] = [
            "macros": .array(declaration.macros.map(value(for:))),
            "markers": .array(markerValues(for: declaration.macros)),
            "identifier": identifier(declaration.name),
            "type": typeReferenceValue(declaration.typeName),
        ]
        addPropertyGraphFields(
            to: &fields,
            kind: "derived",
            name: declaration.name,
            ownerConstructName: ownerConstructName
        )
        return .object(
            typeName: "Derived",
            fields: fields
        )
    }

    private func addPropertyGraphFields(
        to fields: inout [String: CompileTimeValue],
        kind: String,
        name: String,
        ownerConstructName: String?
    ) {
        guard let ownerConstructName else {
            return
        }
        fields["identity"] = graphIdentity(kind: kind, name: "\(ownerConstructName).\(name)")
        fields["parent"] = graphIdentity(kind: "construct", name: ownerConstructName)
    }

    private func markerValues(for applications: [MacroApplication]) -> [CompileTimeValue] {
        applications.compactMap { application in
            guard let marker = markerDeclarationsByName[application.name] else {
                return nil
            }
            let value: CompileTimeValue
            if marker.valueType.isMarkerEffect {
                value = .object(typeName: "Marker.Effect", fields: [:])
            } else if marker.valueType == .named("Void") {
                value = .object(typeName: "Void", fields: [:])
            } else if let evaluatedValue = try? Self.evaluateMarkerValue(for: application, marker: marker) {
                value = evaluatedValue
            } else {
                return nil
            }
            return .object(
                typeName: "Marker.Application",
                fields: [
                    "identifier": identifier(application.name),
                    "packageVisibility": .string(packageVisibilityName(for: marker.packageVisibility)),
                    "valueType": typeReferenceValue(marker.valueType),
                    "valueTypeName": .string(marker.valueType.displayName),
                    "value": value,
                ]
            )
        }
    }

    private func packageVisibilityName(for packageVisibility: PackageVisibility) -> String {
        switch packageVisibility {
        case .open:
            return "open"
        case .closed:
            return "closed"
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
            argumentClause: application.argumentClause,
            rawBody: application.rawBody
        )
        let genericBindings = MacroExpander.markerGenericArgumentBindings(
            for: marker,
            application: application
        )
        let initialBindings = bindings.merging(genericBindings) { _, generic in generic }
        if marker.body.isEmpty, marker.foreignBodyLanguage != nil {
            let value: CompileTimeValue = .string(application.rawBody ?? "")
            guard markerValue(value, matches: marker.valueType) else {
                throw ParseError(
                    "Marker #\(marker.name) raw body value does not match \(marker.valueType.displayName)."
                )
            }
            return value
        }
        let markerBindings = marker.bindings

        let evaluator = CompileTimeValueEvaluator(
            targetBinding: markerBindings?.target ?? "__marker_target__",
            targetValue: targetValue,
            graphBinding: markerBindings?.graph,
            localBindings: initialBindings,
            context: context
        )

        var localBindings = initialBindings
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

        if marker.valueType == .named("Void") {
            return .object(typeName: "Void", fields: [:])
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
        case (.string, let type) where type.foreignBodyLanguageName != nil:
            return true
        case (.integer, .named("Int")):
            return true
        case (.double, .named("Float")):
            return true
        case (.boolean, .named("Bool")):
            return true
        case (.object("Void", _), .named("Void")):
            return true
        case (.nilValue, .optional):
            return true
        case (let value, .optional(let wrapped)):
            return markerValue(value, matches: wrapped)
        case (.object(let typeName, _), .named(let name)):
            return typeName == name
        default:
            return false
        }
    }

    private func value(for application: MacroApplication) -> CompileTimeValue {
        let rawBody = application.rawBody ?? ""
        var fields: [String: CompileTimeValue] = [
            "identifier": identifier(application.name),
            "genericArguments": .array(application.genericArguments.map(typeReferenceValue)),
            "argumentClause": .string(application.argumentClause ?? ""),
            "rawBodyLanguage": .string(application.rawBodyLanguage ?? ""),
            "rawBody": writtenSyntax(rawBody),
            "rawBodyText": .string(rawBody),
            "arguments": .array(argumentValues(for: application)),
        ]

        if let declaration = macroDeclarationsByName[application.name] {
            fields["declaration"] = value(for: declaration)
        }

        return .object(
            typeName: "Macro.Application",
            fields: fields
        )
    }

    private func value(for declaration: MacroDeclaration) -> CompileTimeValue {
        let bodyText = renderStatements(declaration.body)
        return .object(
            typeName: "Macro.Declaration",
            fields: [
                "identifier": identifier(declaration.name),
                "packageVisibility": .string(packageVisibilityName(for: declaration.packageVisibility)),
                "target": .string(declaration.target?.displayName ?? ""),
                "targetSyntax": declaration.target.map(value(for:)) ?? .string(""),
                "expansionType": declaration.expansionType.map(typeReferenceValue) ?? .string(""),
                "generics": .array(declaration.genericParameters.map(value(for:))),
                "parameters": .array(declaration.parameters.map(value(for:))),
                "writtenBody": writtenSyntax(bodyText),
                "parsedBody": parsedValue(
                    written: bodyText,
                    value: blockValue(for: declaration.body),
                    diagnostics: []
                ),
                "body": .string(bodyText),
                "syntaxBody": .string(renderEmittedCodeBlock(declaration.syntaxBody)),
            ]
        )
    }

    private func value(for target: MacroTarget) -> CompileTimeValue {
        switch target {
        case .syntax(let typeReference):
            return .object(
                typeName: "Macro.Target",
                fields: [
                    "kind": .string("type"),
                    "name": .string(typeReference.displayName),
                    "type": typeReferenceValue(typeReference),
                    "elements": .array([]),
                    "written": writtenSyntax(typeReference.displayName),
                ]
            )
        case .macroSurface(let name):
            return .object(
                typeName: "Macro.Target",
                fields: [
                    "kind": .string("macroSurface"),
                    "name": .string(name),
                    "elements": .array([]),
                    "written": writtenSyntax("@\(name)"),
                ]
            )
        case .anyOf(let targets):
            let text = targets.map(\.displayName).joined(separator: " | ")
            return .object(
                typeName: "Macro.Target",
                fields: [
                    "kind": .string("anyOf"),
                    "name": .string(""),
                    "elements": .array(targets.map(value(for:))),
                    "written": writtenSyntax(text),
                ]
            )
        case .allOf(let targets):
            let text = targets.map(\.displayName).joined(separator: " & ")
            return .object(
                typeName: "Macro.Target",
                fields: [
                    "kind": .string("allOf"),
                    "name": .string(""),
                    "elements": .array(targets.map(value(for:))),
                    "written": writtenSyntax(text),
                ]
            )
        }
    }

    func writtenSyntax(_ text: String) -> CompileTimeValue {
        .object(
            typeName: "WrittenSyntax",
            fields: [
                "text": .string(text),
                "range": zeroSourceRange(),
            ]
        )
    }

    private func parsedValue(
        written: String,
        value: CompileTimeValue,
        diagnostics: [String]
    ) -> CompileTimeValue {
        .object(
            typeName: "Parsed",
            fields: [
                "written": writtenSyntax(written),
                "value": value,
                "diagnostics": .array(diagnostics.map { .string($0) }),
            ]
        )
    }

    private func zeroSourceRange() -> CompileTimeValue {
        .object(
            typeName: "SourceRange",
            fields: [
                "start": zeroSourceLocation(),
                "end": zeroSourceLocation(),
            ]
        )
    }

    private func zeroSourceLocation() -> CompileTimeValue {
        .object(
            typeName: "SourceLocation",
            fields: [
                "line": .integer(0),
                "character": .integer(0),
            ]
        )
    }

    private func blockValue(for statements: [Statement]) -> CompileTimeValue {
        .object(
            typeName: "Block",
            fields: ["statements": .array(statements.map(statementValue))]
        )
    }

    private func statementValue(_ statement: Statement) -> CompileTimeValue {
        switch statement {
        case .localBinding(let declaration):
            return .object(
                typeName: "LocalBinding",
                fields: [
                    "mutable": .boolean(declaration.kind == .mutable),
                    "identifier": identifier(declaration.name),
                    "type": typeReferenceValue(declaration.type),
                    "expression": writtenSyntax(MacroExpander.renderExpressionForStringify(declaration.expression)),
                ]
            )
        case .return(let expression):
            return .object(
                typeName: "Return",
                fields: [
                    "expression": expression.map { writtenSyntax(MacroExpander.renderExpressionForStringify($0)) } ?? writtenSyntax("")
                ]
            )
        case .expression(let expression):
            return .object(
                typeName: "ExpressionStatement",
                fields: [
                    "expression": writtenSyntax(MacroExpander.renderExpressionForStringify(expression))
                ]
            )
        case .background(let background):
            return .object(typeName: "Background", fields: ["body": blockValue(for: background.body)])
        case .deferBlock(let deferred):
            return .object(typeName: "Defer", fields: ["body": blockValue(for: deferred.body)])
        case .break:
            return .object(typeName: "Break", fields: [:])
        default:
            return writtenSyntax(renderStatement(statement))
        }
    }

    private func renderStatements(_ statements: [Statement]) -> String {
        statements.map(renderStatement).joined(separator: "\n")
    }

    private func renderStatement(_ statement: Statement) -> String {
        switch statement {
        case .localBinding(let declaration):
            let keyword = declaration.kind == .constant ? "let" : "state"
            let expression = MacroExpander.renderExpressionForStringify(declaration.expression)
            return "\(keyword) \(declaration.name): \(declaration.type.displayName)(\(expression))"
        case .return(let expression?):
            return "return \(MacroExpander.renderExpressionForStringify(expression))"
        case .return(nil):
            return "return"
        case .expression(let expression):
            return MacroExpander.renderExpressionForStringify(expression)
        case .macroInvocation(let name, let argumentClause, let body):
            let arguments = argumentClause.map { "(\($0))" } ?? ""
            return "#\(name)\(arguments) { \(renderStatements(body)) }"
        case .expand(let targetPath, _):
            return [targetPath, "expand"].compactMap { $0 }.joined(separator: ".")
        default:
            return String(describing: statement)
        }
    }

    private func renderEmittedCodeBlock(_ block: EmittedCodeBlock?) -> String {
        guard let block else {
            return ""
        }

        return block.parts.map { part in
            switch part {
            case .text(let text):
                return text
            case .splice(let expression, let expected):
                return "#(\(MacroExpander.renderExpressionForStringify(expression)): \(expected.rawValue))"
            case .syntaxMacroInvocation(let name, let arguments):
                let renderedArguments = arguments.map { argument in
                    let value = MacroExpander.renderExpressionForStringify(argument.value)
                    return argument.label.map { "\($0): \(value)" } ?? value
                }.joined(separator: ", ")
                return "#\(name)(\(renderedArguments))"
            }
        }.joined()
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

    func value(for declaration: RangeFunctionParameter) -> CompileTimeValue {
        .object(
            typeName: "Parameter.Declaration",
            fields: [
                "externalName": declaration.externalLabel.map(CompileTimeValue.string) ?? .string(""),
                "localName": .string(declaration.localName),
                "type": declaration.typeReference.map(typeReferenceValue) ?? .string("Void"),
                "captureMetadataType": declaration.captureMetadataType.map(typeReferenceValue) ?? .string(""),
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
            typeName: "GraphIdentity",
            fields: [
                "id": .string("\(kind):\(name)"),
                "kind": .string(kind),
                "name": .string(name),
            ]
        )
    }
}
