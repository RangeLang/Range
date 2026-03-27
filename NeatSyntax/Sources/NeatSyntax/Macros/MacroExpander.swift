import Foundation

public enum MacroExpander {
    public static func expand(files: [ParsedSourceFile]) throws -> [ParsedSourceFile] {
        let registry = collectMacros(from: files)
        return try files.map { parsedFile in
            ParsedSourceFile(
                path: parsedFile.path,
                sourceFile: try expand(sourceFile: parsedFile.sourceFile, macros: registry)
            )
        }
    }

    public static func expand(
        sourceFile: SourceFileNode,
        macros: [String: MacroDeclaration]
    ) throws -> SourceFileNode {
        switch sourceFile {
        case .mainBlock(let mainBlock):
            return .mainBlock(
                MainBlockNode(body: try expand(statements: mainBlock.body, macros: macros)))
        case .module(let module):
            return .module(
                ModuleFileNode(
                    mainBlock: try module.mainBlock.map {
                        MainBlockNode(body: try expand(statements: $0.body, macros: macros))
                    },
                    states: module.states,
                    callables: try module.callables.map {
                        try expand(callable: $0, macros: macros)
                    },
                    constructs: try module.constructs.map {
                        try expand(construct: $0, macros: macros)
                    },
                    enumerations: module.enumerations,
                    protocols: module.protocols,
                    macros: module.macros,
                    precedenceGroups: module.precedenceGroups,
                    operators: module.operators,
                    extensions: module.extensions
                )
            )
        case .construct(let declaration):
            return .construct(try expand(construct: declaration, macros: macros))
        case .macro, .enumeration, .protocolDefinition, .extensions:
            return sourceFile
        }
    }

    public static func collectMacros(from files: [ParsedSourceFile]) -> [String: MacroDeclaration] {
        var registry: [String: MacroDeclaration] = [:]
        for parsedFile in files {
            for macro in self.macros(in: parsedFile.sourceFile) {
                registry[macro.name] = macro
            }
        }
        return registry
    }

    static func macros(in sourceFile: SourceFileNode) -> [MacroDeclaration] {
        switch sourceFile {
        case .macro(let declaration):
            return [declaration]
        case .module(let module):
            return module.macros
        case .construct, .enumeration, .protocolDefinition, .mainBlock, .extensions:
            return []
        }
    }

    static func expand(construct: ConstructDeclaration, macros: [String: MacroDeclaration]) throws
        -> ConstructDeclaration
    {
        ConstructDeclaration(
            macros: construct.macros,
            kind: construct.kind,
            attribute: construct.attribute,
            name: construct.name,
            genericParameters: construct.genericParameters,
            conformances: construct.conformances,
            states: construct.states,
            environments: construct.environments,
            bindings: construct.bindings,
            deriveds: try construct.deriveds.map { try expand(derived: $0, macros: macros) },
            values: construct.values,
            initializers: try construct.initializers.map {
                try expand(initializer: $0, macros: macros)
            },
            callables: try construct.callables.map { try expand(callable: $0, macros: macros) }
        )
    }

    static func expand(callable: CallableDeclaration, macros: [String: MacroDeclaration]) throws
        -> CallableDeclaration
    {
        CallableDeclaration(
            macros: callable.macros,
            targetType: callable.targetType,
            name: callable.name,
            hasExplicitParameterClause: callable.hasExplicitParameterClause,
            parameters: callable.parameters,
            returnType: callable.returnType,
            body: try callable.body.map { try expand(statements: $0, macros: macros) }
        )
    }

    static func expand(initializer: InitializerDeclaration, macros: [String: MacroDeclaration])
        throws
        -> InitializerDeclaration
    {
        InitializerDeclaration(
            macros: initializer.macros,
            parameters: initializer.parameters,
            body: try initializer.body.map { try expand(statements: $0, macros: macros) }
        )
    }

    static func expand(derived: DerivedDeclaration, macros: [String: MacroDeclaration]) throws
        -> DerivedDeclaration
    {
        DerivedDeclaration(
            macros: derived.macros,
            builderName: derived.builderName,
            name: derived.name,
            typeName: derived.typeName,
            body: try derived.body.map { try expand(statements: $0, macros: macros) }
        )
    }

    static func expand(statements: [Statement], macros: [String: MacroDeclaration]) throws
        -> [Statement]
    {
        var expanded: [Statement] = []
        for statement in statements {
            expanded.append(contentsOf: try expand(statement: statement, macros: macros))
        }
        return expanded
    }

    static func expand(statement: Statement, macros: [String: MacroDeclaration]) throws
        -> [Statement]
    {
        switch statement {
        case .freestandingMacro(let name, let argumentClause, let body):
            guard let macro = macros[name] else {
                throw ParseError("Unknown freestanding macro #\(name).")
            }
            guard case .freestanding(let targetType) = macro.target,
                targetType.displayName == "Block"
            else {
                throw ParseError("Macro #\(name) is not a Freestanding<Block> macro.")
            }
            if argumentClause != nil {
                throw ParseError(
                    "Freestanding block macro #\(name) does not support argument clauses yet.")
            }
            let expandedTarget = try expand(statements: body, macros: macros)
            let rewriteBody = try rewriteBody(for: macro)
            let substituted = substituteMacroTargetCalls(
                in: rewriteBody,
                targetBinding: macro.bindings.target,
                targetBlock: expandedTarget
            )
            return try expand(statements: substituted, macros: macros)
        case .derived(let name, let typeName, let body):
            return [
                .derived(
                    name: name, typeName: typeName,
                    body: try expand(statements: body, macros: macros))
            ]
        case .forEach(let name, let sequence, let body):
            return [
                .forEach(
                    name: name, sequence: sequence,
                    body: try expand(statements: body, macros: macros))
            ]
        case .whileLoop(let condition, let body):
            return [
                .whileLoop(condition: condition, body: try expand(statements: body, macros: macros))
            ]
        case .conditional(let branches):
            return [
                .conditional(
                    try branches.map { branch in
                        StatementConditionalBranch(
                            condition: branch.condition,
                            body: try expand(statements: branch.body, macros: macros)
                        )
                    }
                )
            ]
        case .switchStatement(let expression, let cases, let defaultBody):
            return [
                .switchStatement(
                    expression: expression,
                    cases: try cases.map { switchCase in
                        SwitchCase(
                            value: switchCase.value,
                            body: try expand(statements: switchCase.body, macros: macros)
                        )
                    },
                    defaultBody: try defaultBody.map { try expand(statements: $0, macros: macros) }
                )
            ]
        default:
            return [statement]
        }
    }

    static func rewriteBody(for macro: MacroDeclaration) throws -> [Statement] {
        var rewriteCalls: [[Statement]] = []

        for statement in macro.body {
            guard case .expression(let expression) = statement else {
                continue
            }
            guard case .call(let name, let arguments) = expression else {
                continue
            }
            guard name == "\(macro.bindings.result).rewrite" else {
                continue
            }
            guard arguments.count == 1 else {
                continue
            }
            guard case .block(let body) = arguments[0].value else {
                throw ParseError(
                    "Macro #\(macro.name) result.rewrite(...) must receive a block expression for Freestanding<Block>."
                )
            }
            rewriteCalls.append(body)
        }

        guard let rewriteBody = rewriteCalls.first else {
            throw ParseError(
                "Macro #\(macro.name) must call \(macro.bindings.result).rewrite(...) with a block expression."
            )
        }

        if rewriteCalls.count > 1 {
            throw ParseError("Macro #\(macro.name) can only rewrite once in this bootstrap pass.")
        }

        return rewriteBody
    }

    static func substituteMacroTargetCalls(
        in statements: [Statement],
        targetBinding: String,
        targetBlock: [Statement]
    ) -> [Statement] {
        statements.flatMap { statement in
            substituteMacroTargetCall(
                in: statement, targetBinding: targetBinding, targetBlock: targetBlock)
        }
    }

    static func substituteMacroTargetCall(
        in statement: Statement,
        targetBinding: String,
        targetBlock: [Statement]
    ) -> [Statement] {
        switch statement {
        case .expression(.call(let name, let arguments))
        where name == targetBinding && arguments.isEmpty:
            return targetBlock
        case .derived(let name, let typeName, let body):
            return [
                .derived(
                    name: name,
                    typeName: typeName,
                    body: substituteMacroTargetCalls(
                        in: body,
                        targetBinding: targetBinding,
                        targetBlock: targetBlock
                    )
                )
            ]
        case .forEach(let name, let sequence, let body):
            return [
                .forEach(
                    name: name,
                    sequence: sequence,
                    body: substituteMacroTargetCalls(
                        in: body,
                        targetBinding: targetBinding,
                        targetBlock: targetBlock
                    )
                )
            ]
        case .whileLoop(let condition, let body):
            return [
                .whileLoop(
                    condition: condition,
                    body: substituteMacroTargetCalls(
                        in: body,
                        targetBinding: targetBinding,
                        targetBlock: targetBlock
                    )
                )
            ]
        case .conditional(let branches):
            return [
                .conditional(
                    branches.map { branch in
                        StatementConditionalBranch(
                            condition: branch.condition,
                            body: substituteMacroTargetCalls(
                                in: branch.body,
                                targetBinding: targetBinding,
                                targetBlock: targetBlock
                            )
                        )
                    }
                )
            ]
        case .switchStatement(let expression, let cases, let defaultBody):
            return [
                .switchStatement(
                    expression: expression,
                    cases: cases.map { switchCase in
                        SwitchCase(
                            value: switchCase.value,
                            body: substituteMacroTargetCalls(
                                in: switchCase.body,
                                targetBinding: targetBinding,
                                targetBlock: targetBlock
                            )
                        )
                    },
                    defaultBody: defaultBody.map {
                        substituteMacroTargetCalls(
                            in: $0,
                            targetBinding: targetBinding,
                            targetBlock: targetBlock
                        )
                    }
                )
            ]
        default:
            return [statement]
        }
    }
}
