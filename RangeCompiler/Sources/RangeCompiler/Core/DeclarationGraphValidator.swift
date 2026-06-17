import Foundation

public struct DeclarationGraphValidator: CompiledProgramValidationPass {
    public let name = "DeclarationGraph"

    public init() {}

    public func validate(_ program: CompiledProgram) throws {
        try validateAttributeUsage(
            in: program.projectParsedFiles,
            declarationGraph: program.declarationGraph
        )
        let coreParsedFiles = program.parsedFiles.filter { program.sourceRole(forPath: $0.path) == .core }
        let closedCoreMacroMetadataNames = Set(
            MacroExpander.collectMacroMetadata(from: coreParsedFiles)
                .values
                .filter { $0.packageVisibility == .closed }
                .map(\.name)
        )
        let closedCoreMacroNames = Set(
            coreParsedFiles
                .flatMap { macroDeclarations(in: $0.sourceFile) }
                .filter { $0.packageVisibility == .closed }
                .map(\.name)
        )
        try validateClosedAttachedMacroUsage(
            in: program.projectParsedFiles,
            closedMacroMetadataNames: closedCoreMacroMetadataNames
        )
        try validateClosedMacroUsage(
            in: program.projectParsedFiles,
            closedMacroNames: closedCoreMacroNames
        )
        try validateEnumExtensionCases(in: program.declarationGraph)
        try validatePrimaryDeclarations(in: program.parsedFiles)
        try validateTopLevelStates(in: program.parsedFiles)
    }

    private func validateEnumExtensionCases(in declarationGraph: DeclarationGraph) throws {
        for (targetName, extensions) in declarationGraph.extensionsByTargetName {
            let extensionCases = extensions.flatMap(\.enumCases)
            guard !extensionCases.isEmpty else {
                continue
            }
            guard let enumeration = declarationGraph.enumsByName[targetName] else {
                throw SemanticValidationError(
                    "Extension cases can only target an enum. \(targetName) is not an enum."
                )
            }
            guard enumeration.extensibility == .open else {
                throw SemanticValidationError(
                    "Closed enum \(targetName) cannot be extended with new cases. Declare open enum \(targetName) to allow extension cases."
                )
            }

            var seenCases = Set<String>()
            for enumCase in declarationGraph.enumCases(onEnum: targetName) {
                guard seenCases.insert(enumCase.name).inserted else {
                    throw SemanticValidationError(
                        "Duplicate enum case \(targetName).\(enumCase.name)."
                    )
                }
            }
        }
    }

    public func validatePrimaryDeclarations(in program: CompiledProgram) throws {
        try validatePrimaryDeclarations(in: program.expandedFiles)
    }

    private func validatePrimaryDeclarations(in parsedFiles: [ParsedSourceFile]) throws {
        var firstDeclarationByName: [String: String] = [:]

        for parsedFile in parsedFiles {
            for declaration in declarations(in: parsedFile.sourceFile) {
                if let firstPath = firstDeclarationByName[declaration.name] {
                    throw SemanticValidationError(
                        "Duplicate primary declaration #\(declaration.name) in \(lastPathComponent(of: parsedFile.path)). First declared in \(lastPathComponent(of: firstPath)). Use extension \(declaration.name) to augment an existing declaration."
                    )
                }

                firstDeclarationByName[declaration.name] = parsedFile.path
            }
        }
    }

    private func validateTopLevelStates(in parsedFiles: [ParsedSourceFile]) throws {
        var firstStateByName: [String: String] = [:]

        for parsedFile in parsedFiles {
            for state in topLevelStates(in: parsedFile.sourceFile) {
                if let firstPath = firstStateByName[state.name] {
                    throw SemanticValidationError(
                        "Duplicate top-level state \(state.name) in \(lastPathComponent(of: parsedFile.path)). First declared in \(lastPathComponent(of: firstPath))."
                    )
                }

                firstStateByName[state.name] = parsedFile.path
            }
        }
    }

    private func validateAttributeUsage(
        in parsedFiles: [ParsedSourceFile],
        declarationGraph: DeclarationGraph
    ) throws {
        for parsedFile in parsedFiles {
            for declaration in attributedConstructs(in: parsedFile.sourceFile) {
                try validateAttribute(
                    declaration.attribute,
                    declarationName: declaration.name,
                    filePath: parsedFile.path,
                    declarationGraph: declarationGraph
                )
                try validateBuiltinAttachedMacroUsage(
                    declaration.macros,
                    declarationName: declaration.name,
                    filePath: parsedFile.path
                )
            }
            for callable in callables(in: parsedFile.sourceFile) {
                try validateAttribute(
                    callable.attribute,
                    declarationName: callable.name,
                    filePath: parsedFile.path,
                    declarationGraph: declarationGraph
                )
                try validateBuiltinAttachedMacroUsage(
                    callable.macros,
                    declarationName: callable.name,
                    filePath: parsedFile.path
                )
            }
            for declaration in enumerations(in: parsedFile.sourceFile) {
                try validateAttribute(
                    declaration.attribute,
                    declarationName: declaration.name,
                    filePath: parsedFile.path,
                    declarationGraph: declarationGraph
                )
                try validateBuiltinAttachedMacroUsage(
                    declaration.macros,
                    declarationName: declaration.name,
                    filePath: parsedFile.path
                )
            }
        }
    }

    private func validateAttribute(
        _ attribute: AttributeApplication?,
        declarationName: String,
        filePath: String,
        declarationGraph: DeclarationGraph
    ) throws {
        guard let attribute else {
            return
        }

        if attribute.isLanguageBoundary {
            throw SemanticValidationError(
                "@\(attribute.name) can only be used in RangeCore. Remove @\(attribute.name) from \(declarationName) in \(lastPathComponent(of: filePath))."
            )
        }

        guard RangeSyntax.attributeIdentifiers.contains(attribute.name) else {
            throw SemanticValidationError(
                "Unknown attribute @\(attribute.name) in \(lastPathComponent(of: filePath)). Use @ for macros and built-in attribute surfaces."
            )
        }
    }

    private func validateBuiltinAttachedMacroUsage(
        _ macros: [MacroApplication],
        declarationName: String,
        filePath: String
    ) throws {
        if macros.contains(where: { $0.name == "syntax" }) {
            throw SemanticValidationError(
                "@syntax can only be used in RangeCore. Remove @syntax from \(declarationName) in \(lastPathComponent(of: filePath))."
            )
        }
    }

    private func validateClosedAttachedMacroUsage(
        in parsedFiles: [ParsedSourceFile],
        closedMacroMetadataNames: Set<String>
    ) throws {
        guard !closedMacroMetadataNames.isEmpty else {
            return
        }

        for parsedFile in parsedFiles {
            for usage in attachedMacroUsages(in: parsedFile.sourceFile) {
                guard let macro = usage.macros.first(where: { closedMacroMetadataNames.contains($0.name) }) else {
                    continue
                }
                throw SemanticValidationError(
                    "Closed macro @\(macro.name) can only be used inside its declaring package. Remove #\(macro.name) from \(usage.declarationName) in \(lastPathComponent(of: parsedFile.path))."
                )
            }
        }
    }

    private func validateClosedMacroUsage(
        in parsedFiles: [ParsedSourceFile],
        closedMacroNames: Set<String>
    ) throws {
        guard !closedMacroNames.isEmpty else {
            return
        }

        for parsedFile in parsedFiles {
            for usage in macroUsages(in: parsedFile.sourceFile) {
                guard let macro = usage.macros.first(where: { closedMacroNames.contains($0.name) }) else {
                    continue
                }
                throw SemanticValidationError(
                    "Closed macro @\(macro.name) can only be used inside its declaring package. Remove #\(macro.name) from \(usage.declarationName) in \(lastPathComponent(of: parsedFile.path))."
                )
            }
        }
    }

    private func attachedMacroUsages(in sourceFile: SourceFileNode) -> [AttachedMacroUsage] {
        switch sourceFile {
        case .construct(let declaration):
            return attachedMacroUsages(in: declaration)
        case .enumeration(let declaration):
            return [AttachedMacroUsage(macros: declaration.macros, declarationName: declaration.name)]
        case .extensions(let declarations):
            return declarations.flatMap(attachedMacroUsages(in:))
        case .module(let module):
            let mainBlockUsages = module.mainBlock.map {
                [AttachedMacroUsage(macros: $0.macros, declarationName: "@main")]
            } ?? []
            return mainBlockUsages
                + module.states.map { AttachedMacroUsage(macros: $0.macros, declarationName: $0.name) }
                + module.callables.flatMap(attachedMacroUsages(in:))
                + module.constructs.flatMap(attachedMacroUsages(in:))
                + module.enumerations.map { AttachedMacroUsage(macros: $0.macros, declarationName: $0.name) }
                + module.extensions.flatMap(attachedMacroUsages(in:))
        case .mainBlock(let mainBlock):
            return [AttachedMacroUsage(macros: mainBlock.macros, declarationName: "@main")]
        case .macro:
            return []
        }
    }

    private func attachedMacroUsages(in declaration: ConstructDeclaration) -> [AttachedMacroUsage] {
        var usages = [AttachedMacroUsage(macros: declaration.macros, declarationName: declaration.name)]
        usages += declaration.values.map { AttachedMacroUsage(macros: $0.macros, declarationName: $0.name) }
        usages += declaration.states.map { AttachedMacroUsage(macros: $0.macros, declarationName: $0.name) }
        usages += declaration.bindings.map { AttachedMacroUsage(macros: $0.macros, declarationName: $0.name) }
        usages += declaration.deriveds.map { AttachedMacroUsage(macros: $0.macros, declarationName: $0.name) }
        usages += declaration.initializers.flatMap(attachedMacroUsages(in:))
        usages += declaration.callables.flatMap(attachedMacroUsages(in:))
        usages += declaration.constructs.flatMap(attachedMacroUsages(in:))
        return usages
    }

    private func attachedMacroUsages(in declaration: ExtensionDeclaration) -> [AttachedMacroUsage] {
        var usages = [AttachedMacroUsage(macros: declaration.macros, declarationName: declaration.targetName)]
        usages += declaration.initializers.flatMap(attachedMacroUsages(in:))
        usages += declaration.callables.flatMap(attachedMacroUsages(in:))
        usages += declaration.constructs.flatMap(attachedMacroUsages(in:))
        usages += declaration.enumerations.map { AttachedMacroUsage(macros: $0.macros, declarationName: $0.name) }
        return usages
    }

    private func attachedMacroUsages(in declaration: InitializerDeclaration) -> [AttachedMacroUsage] {
        [AttachedMacroUsage(macros: declaration.macros, declarationName: "init")]
            + declaration.parameters.map { AttachedMacroUsage(macros: $0.macros, declarationName: $0.name) }
    }

    private func attachedMacroUsages(in declaration: CallableDeclaration) -> [AttachedMacroUsage] {
        [AttachedMacroUsage(macros: declaration.macros, declarationName: declaration.name)]
            + declaration.parameters.map { AttachedMacroUsage(macros: $0.macros, declarationName: $0.name) }
    }

    private func macroUsages(in sourceFile: SourceFileNode) -> [AttachedMacroUsage] {
        attachedMacroUsages(in: sourceFile) + expressionMacroUsages(in: sourceFile)
    }

    private func expressionMacroUsages(in sourceFile: SourceFileNode) -> [AttachedMacroUsage] {
        switch sourceFile {
        case .mainBlock(let mainBlock):
            return expressionMacroUsages(in: mainBlock.body, declarationName: "@main")
        case .module(let module):
            return module.mainBlock.map { expressionMacroUsages(in: $0.body, declarationName: "@main") } ?? []
        default:
            return []
        }
    }

    private func expressionMacroUsages(in statements: [Statement], declarationName: String) -> [AttachedMacroUsage] {
        statements.flatMap { expressionMacroUsages(in: $0, declarationName: declarationName) }
    }

    private func expressionMacroUsages(in statement: Statement, declarationName: String) -> [AttachedMacroUsage] {
        switch statement {
        case .expression(let expression), .return(let expression?):
            return expressionMacroUsages(in: expression, declarationName: declarationName)
        case .localBinding(let declaration):
            return expressionMacroUsages(in: declaration.expression, declarationName: declaration.name)
        case .assignment(_, let expression), .compoundAssignment(_, _, let expression):
            return expressionMacroUsages(in: expression, declarationName: declarationName)
        case .forEach(_, let sequence, let body):
            return expressionMacroUsages(in: sequence, declarationName: declarationName)
                + expressionMacroUsages(in: body, declarationName: declarationName)
        case .whileLoop(let condition, let body):
            return expressionMacroUsages(in: condition, declarationName: declarationName)
                + expressionMacroUsages(in: body, declarationName: declarationName)
        case .conditional(let branches):
            return branches.flatMap { branch in
                (branch.condition.map { expressionMacroUsages(in: $0, declarationName: declarationName) } ?? [])
                    + expressionMacroUsages(in: branch.body, declarationName: declarationName)
            }
        case .switchStatement(let expression, let cases, let defaultBody):
            return expressionMacroUsages(in: expression, declarationName: declarationName)
                + cases.flatMap { expressionMacroUsages(in: $0.body, declarationName: declarationName) }
                + (defaultBody.map { expressionMacroUsages(in: $0, declarationName: declarationName) } ?? [])
        case .background(let background):
            return expressionMacroUsages(in: background.body, declarationName: declarationName)
        case .deferBlock(let deferred):
            return expressionMacroUsages(in: deferred.body, declarationName: declarationName)
        case .localCallable(let declaration):
            return expressionMacroUsages(in: declaration.body, declarationName: declaration.name)
        case .macroInvocation, .expand, .derived, .return(nil), .break, .continue:
            return []
        }
    }

    private func expressionMacroUsages(in expression: Expression, declarationName: String) -> [AttachedMacroUsage] {
        switch expression {
        case .macroInvocation(let name, let arguments):
            return [AttachedMacroUsage(macros: [MacroApplication(name: name, genericArguments: [], argumentClause: nil)], declarationName: declarationName)]
                + arguments.flatMap { expressionMacroUsages(in: $0.value, declarationName: declarationName) }
        case .call(_, let arguments):
            return arguments.flatMap { expressionMacroUsages(in: $0.value, declarationName: declarationName) }
        case .array(let elements):
            return elements.flatMap { expressionMacroUsages(in: $0, declarationName: declarationName) }
        case .dictionary(let elements):
            return elements.flatMap {
                expressionMacroUsages(in: $0.key, declarationName: declarationName)
                    + expressionMacroUsages(in: $0.value, declarationName: declarationName)
            }
        case .ternary(let condition, let trueExpression, let falseExpression):
            return expressionMacroUsages(in: condition, declarationName: declarationName)
                + expressionMacroUsages(in: trueExpression, declarationName: declarationName)
                + expressionMacroUsages(in: falseExpression, declarationName: declarationName)
        case .unary(_, let expression):
            return expressionMacroUsages(in: expression, declarationName: declarationName)
        case .binary(let lhs, _, let rhs):
            return expressionMacroUsages(in: lhs, declarationName: declarationName)
                + expressionMacroUsages(in: rhs, declarationName: declarationName)
        case .block(let statements):
            return expressionMacroUsages(in: statements, declarationName: declarationName)
        case .integer, .double, .string, .interpolatedString, .boolean, .nilLiteral, .identifier, .bindingReference:
            return []
        }
    }

    private func macroDeclarations(in sourceFile: SourceFileNode) -> [MacroDeclaration] {
        switch sourceFile {
        case .macro(let declaration):
            return [declaration]
        case .module(let module):
            return module.macros
        case .construct, .enumeration, .mainBlock, .extensions:
            return []
        }
    }

    private func attributedConstructs(in sourceFile: SourceFileNode) -> [ConstructDeclaration] {
        switch sourceFile {
        case .construct(let declaration):
            return [declaration] + declaration.constructs.flatMap {
                attributedConstructs(in: .construct($0))
            }
        case .module(let module):
            return module.constructs.flatMap { attributedConstructs(in: .construct($0)) }
                + module.extensions.flatMap { attributedConstructs(in: $0) }
        case .extensions(let declarations):
            return declarations.flatMap { attributedConstructs(in: $0) }
        case .mainBlock, .enumeration, .macro:
            return []
        }
    }

    private func attributedConstructs(in declaration: ExtensionDeclaration) -> [ConstructDeclaration] {
        declaration.constructs.flatMap { attributedConstructs(in: .construct($0)) }
    }

    private func declarations(in declaration: ExtensionDeclaration) -> [ConstructDeclaration] {
        declaration.constructs + declaration.constructs.flatMap { declarations(in: .construct($0)) }
    }

    private func callables(in declaration: ExtensionDeclaration) -> [CallableDeclaration] {
        declaration.callables
            + declaration.constructs.flatMap { $0.callables }
    }

    private func enumerations(in declaration: ExtensionDeclaration) -> [EnumDeclaration] {
        declaration.enumerations
    }

    private func declarations(in sourceFile: SourceFileNode) -> [ConstructDeclaration] {
        switch sourceFile {
        case .construct(let declaration):
            return [declaration]
        case .module(let module):
            return module.constructs
        case .mainBlock, .extensions, .enumeration, .macro:
            return []
        }
    }

    private func topLevelStates(in sourceFile: SourceFileNode) -> [StateDeclaration] {
        switch sourceFile {
        case .module(let module):
            return module.states
        case .construct, .mainBlock, .extensions, .enumeration, .macro:
            return []
        }
    }

    private func callables(in sourceFile: SourceFileNode) -> [CallableDeclaration] {
        switch sourceFile {
        case .module(let module):
            return module.callables
                + module.constructs.flatMap { callables(in: .construct($0)) }
                + module.extensions.flatMap { callables(in: $0) }
        case .construct(let declaration):
            return declaration.callables + declaration.constructs.flatMap { callables(in: .construct($0)) }
        case .extensions(let declarations):
            return declarations.flatMap { callables(in: $0) }
        case .mainBlock, .enumeration, .macro:
            return []
        }
    }

    private func enumerations(in sourceFile: SourceFileNode) -> [EnumDeclaration] {
        switch sourceFile {
        case .enumeration(let declaration):
            return [declaration]
        case .module(let module):
            return module.enumerations + module.extensions.flatMap { enumerations(in: $0) }
        case .extensions(let declarations):
            return declarations.flatMap { enumerations(in: $0) }
        case .construct, .mainBlock, .macro:
            return []
        }
    }

    private func lastPathComponent(of path: String) -> String {
        URL(fileURLWithPath: path).lastPathComponent
    }
}

private struct AttachedMacroUsage {
    let macros: [MacroApplication]
    let declarationName: String
}
