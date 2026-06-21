import Foundation

struct MacroTargetValueBuilder {
    let macroDeclarationsByName: [String: MacroDeclaration]
    let macroMetadataByName: [String: MacroMetadataDeclaration]
    let writtenSyntaxByID: [String: CompileTimeValue]
    let knownObjectTypeNames: Set<String>
    let extensionsByTargetName: [String: [ExtensionDeclaration]]

    init(
        macroDeclarationsByName: [String: MacroDeclaration] = [:],
        macroMetadataByName: [String: MacroMetadataDeclaration] = [:],
        writtenSyntaxByID: [String: CompileTimeValue] = [:],
        knownObjectTypeNames: Set<String> = [],
        extensionsByTargetName: [String: [ExtensionDeclaration]] = [:]
    ) {
        self.macroDeclarationsByName = macroDeclarationsByName
        self.macroMetadataByName = macroMetadataByName
        self.writtenSyntaxByID = writtenSyntaxByID
        self.knownObjectTypeNames = knownObjectTypeNames
        self.extensionsByTargetName = extensionsByTargetName
    }

    func targetValue(
        for construct: ConstructDeclaration,
        applicationArguments: [TypeReference] = []
    ) -> CompileTimeValue {
        let id = "construct:\(construct.name)"
        return .object(
            typeName: "Construct",
            fields: [
                "identity": graphIdentity(kind: "construct", name: construct.name),
                "written": writtenSyntaxByID[id] ?? writtenSyntax(""),
                "declaration": declarationValue(
                    for: construct,
                    qualifiedName: construct.name,
                    applicationArguments: applicationArguments
                ),
                "application": constructApplicationValue(
                    for: construct,
                    applicationArguments: applicationArguments
                ),
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
                        "generics": .array(enumeration.genericParameters.map { value(for: $0) }),
                        "cases": .array(enumeration.cases.map(value(for:))),
                    ]
                ),
            ]
        )
    }

    func targetValue(for extensionDeclaration: ExtensionDeclaration) -> CompileTimeValue {
        let target = typeReferenceValue(extensionDeclaration.targetType)
        let declaration = value(for: extensionDeclaration)
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
                "written": writtenSyntaxByID[
                    "extension:\(extensionDeclaration.targetType.displayName)"]
                    ?? writtenSyntax(""),
                "target": target,
                "declaration": declaration,
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

    func declarationValue(
        for declaration: ConstructDeclaration,
        qualifiedName: String,
        applicationArguments: [TypeReference] = []
    )
        -> CompileTimeValue
    {
        // Extensions targeting this construct contribute their members to the
        // construct's collected declarations, so extension functions and inits
        // are not treated differently from members declared in the body.
        let extensions = extensionsByTargetName[qualifiedName, default: []]
        let extensionCallables = extensions.flatMap(\.callables)
        let extensionInitializers = extensions.flatMap(\.initializers)
        let allCallables = declaration.callables + extensionCallables
        let allInitializers = declaration.initializers + extensionInitializers

        let memberIdentities =
            declaration.values.map {
                graphIdentity(kind: "let", name: "\(qualifiedName).\($0.name)")
            }
            + declaration.states.map {
                graphIdentity(kind: "state", name: "\(qualifiedName).\($0.name)")
            }
            + declaration.bindings.map {
                graphIdentity(kind: "binding", name: "\(qualifiedName).\($0.name)")
            }
            + declaration.deriveds.map {
                graphIdentity(kind: "derived", name: "\(qualifiedName).\($0.name)")
            }
            + allCallables.map {
                graphIdentity(kind: "function", name: "\(qualifiedName).\($0.name)")
            }
            + declaration.constructs.map {
                graphIdentity(
                    kind: "construct",
                    name: qualifiedNestedName(owner: qualifiedName, member: $0.name))
            }

        return .object(
            typeName: "Construct.Declaration",
            fields: [
                "identity": graphIdentity(kind: "construct", name: qualifiedName),
                "identifier": identifier(declaration.name),
                "self": nominalTypeReference(qualifiedName),
                "macros": .array(declaration.macros.map(value(for:))),
                "generics": .array(
                    declaration.genericParameters.enumerated().map { index, parameter in
                        value(
                            for: parameter,
                            applicationArgument: applicationArguments.indices.contains(index)
                                ? applicationArguments[index] : nil
                        )
                    }
                ),
                "conformances": .array(declaration.conformances.map(typeReferenceValue)),
                "inits": .array(allInitializers.map(value(for:))),
                "lets": .array(
                    declaration.values.map {
                        value(for: $0, ownerConstructName: qualifiedName)
                    }),
                "states": .array(
                    declaration.states.map {
                        value(for: $0, ownerConstructName: qualifiedName)
                    }),
                "bindings": .array(
                    declaration.bindings.map {
                        value(for: $0, ownerConstructName: qualifiedName)
                    }),
                "deriveds": .array(
                    declaration.deriveds.map {
                        value(for: $0, ownerConstructName: qualifiedName)
                    }),
                "members": .array(memberIdentities),
                "functions": .array(
                    allCallables.map {
                        value(for: $0, ownerConstructName: qualifiedName)
                    }),
                "constructs": .array(
                    declaration.constructs.map {
                        declarationValue(
                            for: $0,
                            qualifiedName: qualifiedNestedName(
                                owner: qualifiedName, member: $0.name)
                        )
                    }
                ),
                "extensions": .array([]),
            ]
        )
    }

    private func constructApplicationValue(
        for declaration: ConstructDeclaration,
        applicationArguments: [TypeReference]
    ) -> CompileTimeValue {
        .object(
            typeName: "Construct.Application",
            fields: [
                "type": typeReferenceValue(
                    constructApplicationType(
                        name: declaration.name,
                        arguments: applicationArguments
                    )
                ),
                "arguments": .array(
                    declaration.genericParameters.enumerated().map { index, parameter in
                        genericApplicationValue(
                            for: parameter,
                            applicationArgument: applicationArguments.indices.contains(index)
                                ? applicationArguments[index] : nil
                        )
                    }
                ),
            ]
        )
    }

    private func constructApplicationType(
        name: String,
        arguments: [TypeReference]
    ) -> TypeReference {
        guard !arguments.isEmpty else {
            return .named(name)
        }
        return .generic(base: .named(name), arguments: arguments)
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

    func storedStateValue(for storage: StateStorage) -> CompileTimeValue {
        switch storage {
        case .stored(let expression):
            return value(for: expression) ?? .nilValue
        case .declared:
            return .nilValue
        }
    }

    func value(
        for declaration: StateDeclaration,
        ownerConstructName: String?
    ) -> CompileTimeValue {
        var fields: [String: CompileTimeValue] = [
            "macros": .array(declaration.macros.map(value(for:))),
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

    func qualifiedNestedName(owner: String, member: String) -> String {
        member.hasPrefix("\(owner).") ? member : "\(owner).\(member)"
    }

    static func evaluateMacroMetadataValue(
        for application: MacroApplication,
        metadata: MacroMetadataDeclaration,
        targetValue: CompileTimeValue = .object(typeName: "Macro.Target", fields: [:]),
        knownObjectTypeNames: Set<String> = [],
        context: MacroExpansionContext? = nil
    ) throws -> CompileTimeValue {
        let bindings = try MacroExpander.parseMacroMetadataArgumentBindings(
            for: metadata,
            argumentClause: application.argumentClause,
            rawBody: application.rawBody
        )
        let genericBindings = MacroExpander.macroMetadataGenericArgumentBindings(
            for: metadata,
            application: application
        )
        let initialBindings = bindings.merging(genericBindings) { _, generic in generic }
        if metadata.body.isEmpty, metadata.foreignBodyLanguage != nil {
            let value: CompileTimeValue = .string(application.rawBody ?? "")
            guard macroMetadataValue(value, matches: metadata.valueType) else {
                throw ParseError(
                    "Macro @\(metadata.name) raw body value does not match \(metadata.valueType.displayName)."
                )
            }
            return value
        }
        let metadataBindings = metadata.bindings

        let evaluator = CompileTimeValueEvaluator(
            targetBinding: metadataBindings?.target ?? "__metadata_target__",
            targetValue: targetValue,
            graphBinding: metadataBindings?.graph,
            selfValue: MacroTargetValueBuilder(knownObjectTypeNames: knownObjectTypeNames)
                .value(for: metadata),
            localBindings: initialBindings,
            macroDeclarationsByName: context?.macroDeclarationsByName ?? [:],
            knownObjectTypeNames: knownObjectTypeNames,
            context: context
        )

        var localBindings = initialBindings
        let value = evaluator.evaluateStatements(metadata.body, locals: &localBindings)

        if metadata.valueType == .named("Void") {
            return .object(typeName: "Void", fields: [:])
        }

        guard let value else {
            throw ParseError("Macro @\(metadata.name) body could not be evaluated at compile time.")
        }

        guard macroMetadataValue(value, matches: metadata.valueType) else {
            throw ParseError(
                "Macro @\(metadata.name) evaluated value does not match \(metadata.valueType.displayName)."
            )
        }

        return value
    }



    private static func macroMetadataValue(_ value: CompileTimeValue, matches type: TypeReference)
        -> Bool
    {
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
            return macroMetadataValue(value, matches: wrapped)
        case (.object(let typeName, _), .named(let name)):
            return typeName == name
        default:
            return false
        }
    }

    func value(for application: MacroApplication) -> CompileTimeValue {
        let rawBody = application.rawBody ?? ""
        var fields: [String: CompileTimeValue] = [
            "name": .string(application.name),
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
        if let metadata = macroMetadataByName[application.name] {
            fields["valueType"] = typeReferenceValue(metadata.valueType)
            fields["valueTypeName"] = .string(metadata.valueType.displayName)
            if metadata.valueType.isMacroMetadataEffect {
                fields["value"] = .object(typeName: "Macro.Effect", fields: [:])
            } else if metadata.valueType == .named("Void") {
                fields["value"] = .object(typeName: "Void", fields: [:])
            } else if let evaluatedValue = try? Self.evaluateMacroMetadataValue(
                for: application,
                metadata: metadata,
                knownObjectTypeNames: knownObjectTypeNames
            ) {
                fields["value"] = evaluatedValue
            }
        }

        return .object(
            typeName: "Macro.Application",
            fields: fields
        )
    }

    func value(for declaration: MacroDeclaration) -> CompileTimeValue {
        let bodyText = renderStatements(declaration.body)
        return .object(
            typeName: "Macro.Declaration",
            fields: [
                "name": .string(declaration.name),
                "identifier": identifier(declaration.name),
                "macros": .array(declaration.macros.map(value(for:))),
                "target": declaration.target.map(value(for:)) ?? .nilValue,
                "expansionType": declaration.expansionType.map(typeReferenceValue) ?? .string(""),
                "expansionTypeName": .string(declaration.expansionType?.displayName ?? ""),
                "generics": .array(declaration.genericParameters.map { value(for: $0) }),
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

    func value(for metadata: MacroMetadataDeclaration) -> CompileTimeValue {
        let bodyText = renderStatements(metadata.body)
        return .object(
            typeName: "Macro.Declaration",
            fields: [
                "name": .string(metadata.name),
                "identifier": identifier(metadata.name),
                "target": value(for: metadata.target),
                "expansionType": typeReferenceValue(metadata.valueType),
                "expansionTypeName": .string(metadata.valueType.displayName),
                "generics": .array(metadata.genericParameters.map { value(for: $0) }),
                "parameters": .array(metadata.parameters.map(value(for:))),
                "writtenBody": writtenSyntax(bodyText),
                "parsedBody": parsedValue(
                    written: bodyText,
                    value: blockValue(for: metadata.body),
                    diagnostics: []
                ),
                "body": .string(bodyText),
                "syntaxBody": .string(""),
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
        let statementValues = statements.map(statementValue)
        return .object(
            typeName: "Block",
            fields: [
                "declaration": .object(
                    typeName: "Block.Declaration",
                    fields: [
                        "body": .array(statementValues),
                        "statements": .array(statementValues),
                    ]
                ),
                "body": .array(statementValues),
                "statements": .array(statementValues),
            ]
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
                    "expression": writtenSyntax(
                        MacroExpander.renderExpressionForStringify(declaration.expression)),
                ]
            )
        case .return(let expression):
            return .object(
                typeName: "Return",
                fields: [
                    "expression": expression.map {
                        writtenSyntax(MacroExpander.renderExpressionForStringify($0))
                    } ?? writtenSyntax("")
                ]
            )
        case .expression(let expression):
            return .object(
                typeName: "ExpressionStatement",
                fields: [
                    "expression": writtenSyntax(
                        MacroExpander.renderExpressionForStringify(expression))
                ]
            )
        case .background(let background):
            return .object(
                typeName: "Background", fields: ["body": blockValue(for: background.body)])
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
        case .replace(let targetPath, _):
            return [targetPath, "replace"].compactMap { $0 }.joined(separator: ".")
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
                return
                    "#(\(MacroExpander.renderExpressionForStringify(expression)): \(expected.rawValue))"
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
        guard
            let argumentClause = application.argumentClause?.trimmingCharacters(
                in: .whitespacesAndNewlines
            ), !argumentClause.isEmpty
        else {
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
        case .integer(let value):
            return .integer(value)
        case .double(let value):
            return .double(value)
        case .boolean(let value):
            return .boolean(value)
        case .call(_, let arguments):
            // Literal-shaped constructions like String("64") carry their value
            // as a single unlabeled argument; surface that inner literal.
            guard arguments.count == 1, arguments[0].label == nil else {
                return nil
            }
            return value(for: arguments[0].value)
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
        value(for: declaration, ownerConstructName: nil)
    }

    func value(
        for declaration: CallableDeclaration,
        ownerConstructName: String?
    ) -> CompileTimeValue {
        var fields: [String: CompileTimeValue] = [
            "identifier": identifier(declaration.name),
            "generics": .array(declaration.genericParameters.map { value(for: $0) }),
            "parameters": .array(declaration.parameters.map(value(for:))),
            "returnType": declaration.returnType.map(typeReferenceValue) ?? .string("Void"),
        ]
        if let ownerConstructName {
            fields["identity"] = graphIdentity(
                kind: "function", name: "\(ownerConstructName).\(declaration.name)")
            fields["parent"] = graphIdentity(kind: "construct", name: ownerConstructName)
        }
        return .object(
            typeName: "Function.Declaration",
            fields: fields
        )
    }

    func value(
        for parameter: GenericParameter,
        applicationArgument: TypeReference? = nil
    ) -> CompileTimeValue {
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
            let defaultString = defaultValue.flatMap(genericDefaultString) ?? ""
            let effectiveValue = applicationArgument.map(genericArgumentString) ?? defaultString
            return .object(
                typeName: "ValueGeneric",
                fields: [
                    "identifier": identifier(name),
                    "type": typeReferenceValue(typeReference),
                    "value": .string(effectiveValue),
                    "default": .string(defaultString),
                ]
            )
        }
    }

    private func genericApplicationValue(
        for parameter: GenericParameter,
        applicationArgument: TypeReference?
    ) -> CompileTimeValue {
        let name: String
        let type: TypeReference
        let syntax: String
        switch parameter {
        case .type(let parameterName, let constraint, let defaultArgument):
            name = parameterName
            type = applicationArgument ?? defaultArgument ?? constraint ?? .named("")
            syntax = type.displayName
        case .value(let parameterName, let typeReference, let defaultValue):
            name = parameterName
            type = typeReference
            syntax = applicationArgument.map(genericArgumentString)
                ?? defaultValue.flatMap(genericDefaultString)
                ?? ""
        }
        return .object(
            typeName: "Parameter.Application",
            fields: [
                "identifier": identifier(name),
                "type": typeReferenceValue(type),
                "syntax": writtenSyntax(syntax),
            ]
        )
    }

    private func genericDefaultString(_ expression: Expression) -> String {
        if case .call(let name, let arguments) = expression,
            arguments.isEmpty,
            let lastComponent = name.split(separator: ".").last
        {
            return String(lastComponent)
        }
        if let value = value(for: expression) {
            return stringValue(for: value) ?? MacroExpander.renderExpressionForStringify(expression)
        }
        return MacroExpander.renderExpressionForStringify(expression)
    }

    private func genericArgumentString(_ argument: TypeReference) -> String {
        let text = argument.displayName
        if text.count >= 2, text.first == "\"", text.last == "\"" {
            return String(text.dropFirst().dropLast())
        }
        if text.hasPrefix(".") {
            return String(text.dropFirst())
        }
        return text
    }

    private func stringValue(for value: CompileTimeValue) -> String? {
        switch value {
        case .string(let string):
            return string
        case .integer(let integer):
            return String(integer)
        case .double(let double):
            return String(double)
        case .boolean(let boolean):
            return boolean ? "true" : "false"
        default:
            return nil
        }
    }

    func value(for declaration: RangeFunctionParameter) -> CompileTimeValue {
        .object(
            typeName: "Parameter.Declaration",
            fields: [
                "name": .string(declaration.name),
                "identifier": identifier(declaration.name),
                "type": declaration.typeReference.map(typeReferenceValue) ?? .string("Void"),
                "macros": .array(declaration.macros.map(value(for:))),
                "capturesSyntax": .boolean(declaration.capturesSyntax),
                "captureMetadataType": declaration.captureMetadataType.map(typeReferenceValue)
                    ?? .string(""),
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
                                "name": associatedValue.label.map(CompileTimeValue.string)
                                    ?? .string(""),
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
