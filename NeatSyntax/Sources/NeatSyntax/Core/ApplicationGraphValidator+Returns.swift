import Foundation

extension ApplicationGraphValidator {
    func validateCallableReturnSemantics(
        in parsedFiles: [ParsedSourceFile],
        declarationGraph: DeclarationGraph,
        registryView: DeclarationRegistryView,
        resolver: LiteralBridgeResolver,
        memberResolver: DeclarationMemberResolver,
        operatorResolver: DeclarationOperatorResolver
    ) throws {
        for parsedFile in parsedFiles {
            let fileName = lastPathComponent(of: parsedFile.path)

            switch parsedFile.sourceFile {
            case .construct(let declaration):
                try validateCallableReturnSemantics(
                    in: declaration,
                    declarationGraph: declarationGraph,
                    resolver: resolver,
                    memberResolver: memberResolver,
                    operatorResolver: operatorResolver,
                    fileName: fileName
                )
            case .namespace(let declaration):
                try validateCallableReturnSemantics(
                    in: declaration,
                    declarationGraph: declarationGraph,
                    resolver: resolver,
                    memberResolver: memberResolver,
                    operatorResolver: operatorResolver,
                    fileName: fileName
                )
            case .module(let module):
                let topLevelAccessibleTypes = Dictionary(
                    uniqueKeysWithValues: registryView.topLevelStates(inFilePath: parsedFile.path).map {
                        ($0.name, BootstrapLiteralType.typed($0.type))
                    }
                )

                for callable in module.callables {
                    try validateCallableReturnSemantics(
                        callable,
                        accessibleTypes: topLevelAccessibleTypes,
                        resolver: resolver,
                        memberResolver: memberResolver,
                        operatorResolver: operatorResolver,
                        fileName: fileName
                    )
                }

                for declaration in module.constructs {
                    try validateCallableReturnSemantics(
                        in: declaration,
                        declarationGraph: declarationGraph,
                        resolver: resolver,
                        memberResolver: memberResolver,
                        operatorResolver: operatorResolver,
                        fileName: fileName
                    )
                }
                for declaration in module.namespaces {
                    try validateCallableReturnSemantics(
                        in: declaration,
                        declarationGraph: declarationGraph,
                        resolver: resolver,
                        memberResolver: memberResolver,
                        operatorResolver: operatorResolver,
                        fileName: fileName
                    )
                }
            case .mainBlock, .enumeration, .protocolDefinition, .macro, .extensions:
                break
            }
        }
    }

    func validateCallableReturnSemantics(
        in declaration: NamespaceDeclaration,
        declarationGraph: DeclarationGraph,
        resolver: LiteralBridgeResolver,
        memberResolver: DeclarationMemberResolver,
        operatorResolver: DeclarationOperatorResolver,
        fileName: String
    ) throws {
        for callable in declaration.callables {
            try validateCallableReturnSemantics(
                callable,
                accessibleTypes: [:],
                resolver: resolver,
                memberResolver: memberResolver,
                operatorResolver: operatorResolver,
                fileName: fileName
            )
        }

        for construct in declaration.constructs {
            try validateCallableReturnSemantics(
                in: construct,
                declarationGraph: declarationGraph,
                resolver: resolver,
                memberResolver: memberResolver,
                operatorResolver: operatorResolver,
                fileName: fileName
            )
        }

        for namespace in declaration.namespaces {
            try validateCallableReturnSemantics(
                in: namespace,
                declarationGraph: declarationGraph,
                resolver: resolver,
                memberResolver: memberResolver,
                operatorResolver: operatorResolver,
                fileName: fileName
            )
        }
    }

    func validateCallableReturnSemantics(
        in declaration: ConstructDeclaration,
        declarationGraph: DeclarationGraph,
        resolver: LiteralBridgeResolver,
        memberResolver: DeclarationMemberResolver,
        operatorResolver: DeclarationOperatorResolver,
        fileName: String
    ) throws {
        let environmentTypes = Dictionary(
            uniqueKeysWithValues: declarationGraph.environments(onConstruct: declaration.name).map {
                ($0.name, BootstrapLiteralType.typed($0.type))
            }
        )
        let stateTypes = Dictionary(
            uniqueKeysWithValues: declarationGraph.states(onConstruct: declaration.name).map {
                ($0.name, BootstrapLiteralType.typed($0.type))
            }
        )
        let accessibleTypes = stateTypes.merging(environmentTypes) { current, _ in current }

        for callable in declarationGraph.callables(onConstruct: declaration.name) {
            try validateCallableReturnSemantics(
                callable,
                accessibleTypes: accessibleTypes,
                resolver: resolver,
                memberResolver: memberResolver,
                operatorResolver: operatorResolver,
                fileName: fileName
            )
        }
    }

    func validateCallableReturnSemantics(
        _ callable: CallableDeclaration,
        accessibleTypes: [String: BootstrapLiteralType],
        resolver: LiteralBridgeResolver,
        memberResolver: DeclarationMemberResolver,
        operatorResolver: DeclarationOperatorResolver,
        fileName: String
    ) throws {
        guard let body = callable.body else {
            return
        }

        try validateCallableReturnSemanticsInLocalCallables(
            in: body,
            accessibleTypes: accessibleTypes,
            resolver: resolver,
            memberResolver: memberResolver,
            operatorResolver: operatorResolver,
            fileName: fileName
        )

        let explicitReturnType = callable.returnType
        let needsValueReturn = callableRequiresValueReturn(
            explicitReturnType: explicitReturnType,
            expectedReturnType: explicitReturnType
        )
        let returnExpressions = collectReturnExpressions(in: body)

        if explicitReturnType == nil {
            if returnExpressions.contains(where: { $0 != nil }) {
                throw SemanticValidationError(
                    "Callable \(renderCallableSignature(callable)) in \(fileName) has no return type and cannot return a value."
                )
            }
            return
        }

        if isVoidType(explicitReturnType!) {
            if returnExpressions.contains(where: { $0 != nil }) {
                throw SemanticValidationError(
                    "Callable \(renderCallableSignature(callable)) in \(fileName) declares return type Void and cannot return a value."
                )
            }
            return
        }

        if needsValueReturn {
            guard blockAlwaysReturnsValue(body) else {
                throw SemanticValidationError(
                    "Callable \(renderCallableSignature(callable)) in \(fileName) declares return type \(explicitReturnType!.displayName) but does not return a value on all paths."
                )
            }

            if returnExpressions.contains(where: { $0 == nil }) {
                throw SemanticValidationError(
                    "Callable \(renderCallableSignature(callable)) in \(fileName) declares return type \(explicitReturnType!.displayName) and cannot use bare return."
                )
            }
        }

        guard let explicitReturnType, explicitReturnType.displayName != "Void" else {
            return
        }

        let parameterTypes: [String: BootstrapLiteralType] = Dictionary(
            uniqueKeysWithValues: callable.parameters.compactMap { parameter in
                guard let typeReference = parameter.typeReference else {
                    return nil
                }
                return (parameter.localName, BootstrapLiteralType.typed(typeReference))
            }
        )
        let visibleTypes = accessibleTypes.merging(parameterTypes) { current, _ in current }

        for expression in returnExpressions.compactMap({ $0 }) {
            guard
                let inferred = try? ExpressionTypeSemantics.inferType(
                    of: expression,
                    accessibleTypes: visibleTypes,
                    resolver: resolver,
                    memberResolver: memberResolver,
                    operatorResolver: operatorResolver
                )
            else {
                continue
            }

            if inferred.isLiteralLike {
                continue
            }

            guard
                ExpressionTypeSemantics.isCompatible(
                    actual: inferred,
                    expected: explicitReturnType,
                    resolver: resolver
                )
            else {
                throw SemanticValidationError(
                    "Callable \(renderCallableSignature(callable)) in \(fileName) expects return type \(explicitReturnType.displayName), got \(inferred.displayName)."
                )
            }
        }
    }

    func validateCallableReturnSemanticsInLocalCallables(
        in statements: [Statement],
        accessibleTypes: [String: BootstrapLiteralType],
        resolver: LiteralBridgeResolver,
        memberResolver: DeclarationMemberResolver,
        operatorResolver: DeclarationOperatorResolver,
        fileName: String
    ) throws {
        for statement in statements {
            switch statement {
            case .expand:
                continue
            case .localCallable(let declaration):
                try validateCallableReturnSemantics(
                    CallableDeclaration(
                        macros: declaration.macros,
                        attribute: declaration.attribute,
                        targetType: nil,
                        name: declaration.name,
                        genericParameters: declaration.genericParameters,
                        hasExplicitParameterClause: declaration.hasExplicitParameterClause,
                        parameters: declaration.parameters,
                        returnType: declaration.returnType,
                        isThrowing: declaration.isThrowing,
                        body: declaration.body
                    ),
                    accessibleTypes: accessibleTypes,
                    resolver: resolver,
                    memberResolver: memberResolver,
                    operatorResolver: operatorResolver,
                    fileName: fileName
                )
            case .macroInvocation(_, _, let body),
                .derived(_, _, let body),
                .forEach(_, _, let body),
                .whileLoop(_, let body):
                try validateCallableReturnSemanticsInLocalCallables(
                    in: body,
                    accessibleTypes: accessibleTypes,
                    resolver: resolver,
                    memberResolver: memberResolver,
                    operatorResolver: operatorResolver,
                    fileName: fileName
                )
            case .doCatch(let body, _, let catchBody):
                try validateCallableReturnSemanticsInLocalCallables(
                    in: body,
                    accessibleTypes: accessibleTypes,
                    resolver: resolver,
                    memberResolver: memberResolver,
                    operatorResolver: operatorResolver,
                    fileName: fileName
                )
                try validateCallableReturnSemanticsInLocalCallables(
                    in: catchBody,
                    accessibleTypes: accessibleTypes,
                    resolver: resolver,
                    memberResolver: memberResolver,
                    operatorResolver: operatorResolver,
                    fileName: fileName
                )
            case .background(let background):
                try validateCallableReturnSemanticsInLocalCallables(
                    in: background.body,
                    accessibleTypes: accessibleTypes,
                    resolver: resolver,
                    memberResolver: memberResolver,
                    operatorResolver: operatorResolver,
                    fileName: fileName
                )
            case .deferBlock(let deferred):
                try validateCallableReturnSemanticsInLocalCallables(
                    in: deferred.body,
                    accessibleTypes: accessibleTypes,
                    resolver: resolver,
                    memberResolver: memberResolver,
                    operatorResolver: operatorResolver,
                    fileName: fileName
                )
            case .conditional(let branches):
                for branch in branches {
                    try validateCallableReturnSemanticsInLocalCallables(
                        in: branch.body,
                        accessibleTypes: accessibleTypes,
                        resolver: resolver,
                        memberResolver: memberResolver,
                        operatorResolver: operatorResolver,
                        fileName: fileName
                    )
                }
            case .switchStatement(_, let cases, let defaultBody):
                for switchCase in cases {
                    try validateCallableReturnSemanticsInLocalCallables(
                        in: switchCase.body,
                        accessibleTypes: accessibleTypesForSwitchCasePattern(
                            switchCase.pattern,
                            base: accessibleTypes
                        ),
                        resolver: resolver,
                        memberResolver: memberResolver,
                        operatorResolver: operatorResolver,
                        fileName: fileName
                    )
                }
                if let defaultBody {
                    try validateCallableReturnSemanticsInLocalCallables(
                        in: defaultBody,
                        accessibleTypes: accessibleTypes,
                        resolver: resolver,
                        memberResolver: memberResolver,
                        operatorResolver: operatorResolver,
                        fileName: fileName
                    )
                }
            case .localBinding, .environmentProvision, .assignment, .compoundAssignment,
                .throw,
                .expression, .return, .break, .continue:
                continue
            }
        }
    }

    func collectReturnExpressions(in statements: [Statement]) -> [Expression?] {
        var expressions: [Expression?] = []

        for statement in statements {
            switch statement {
            case .expand:
                continue
            case .macroInvocation(_, _, let body):
                expressions.append(contentsOf: collectReturnExpressions(in: body))
            case .return(let expression):
                expressions.append(expression)
            case .forEach(_, _, let body):
                expressions.append(contentsOf: collectReturnExpressions(in: body))
            case .whileLoop(_, let body):
                expressions.append(contentsOf: collectReturnExpressions(in: body))
            case .doCatch(let body, _, let catchBody):
                expressions.append(contentsOf: collectReturnExpressions(in: body))
                expressions.append(contentsOf: collectReturnExpressions(in: catchBody))
            case .conditional(let branches):
                for branch in branches {
                    expressions.append(contentsOf: collectReturnExpressions(in: branch.body))
                }
            case .switchStatement(_, let cases, let defaultBody):
                for switchCase in cases {
                    expressions.append(contentsOf: collectReturnExpressions(in: switchCase.body))
                }
                if let defaultBody {
                    expressions.append(contentsOf: collectReturnExpressions(in: defaultBody))
                }
            case .background:
                continue
            case .deferBlock(let deferred):
                expressions.append(contentsOf: collectReturnExpressions(in: deferred.body))
            case .localCallable:
                continue
            case .localBinding, .derived, .environmentProvision, .assignment, .compoundAssignment,
                .throw,
                .expression, .break, .continue:
                continue
            }
        }

        return expressions
    }

    func callableRequiresValueReturn(
        explicitReturnType: TypeReference?,
        expectedReturnType: TypeReference?
    ) -> Bool {
        guard explicitReturnType != nil else { return false }
        guard let expectedReturnType else { return true }
        return !isVoidType(expectedReturnType)
    }

    func isVoidType(_ typeReference: TypeReference) -> Bool {
        typeReference.displayName == "Void"
    }

    func blockAlwaysReturnsValue(_ statements: [Statement]) -> Bool {
        for statement in statements {
            if statementAlwaysReturnsValue(statement) {
                return true
            }
        }
        return false
    }

    func statementAlwaysReturnsValue(_ statement: Statement) -> Bool {
        switch statement {
        case .macroInvocation(_, _, let body):
            return blockAlwaysReturnsValue(body)
        case .return(let expression):
            return expression != nil
        case .conditional(let branches):
            guard branches.contains(where: { $0.condition == nil }) else {
                return false
            }
            return branches.allSatisfy { blockAlwaysReturnsValue($0.body) }
        case .switchStatement(_, let cases, let defaultBody):
            guard let defaultBody else { return false }
            guard cases.allSatisfy({ blockAlwaysReturnsValue($0.body) }) else { return false }
            return blockAlwaysReturnsValue(defaultBody)
        case .doCatch(let body, _, let catchBody):
            return blockAlwaysReturnsValue(body) && blockAlwaysReturnsValue(catchBody)
        case .throw:
            return true
        case .background, .localCallable:
            return false
        case .deferBlock(let deferred):
            return blockAlwaysReturnsValue(deferred.body)
        default:
            return false
        }
    }

    func renderCallableSignature(_ callable: CallableDeclaration) -> String {
        let rendered = callable.parameters.map(renderParameterSignature).joined(separator: ", ")
        if let targetType = callable.targetType {
            return "\(targetType.displayName)@\(callable.name)(\(rendered))"
        }
        return "@\(callable.name)(\(rendered))"
    }

    func renderParameterSignature(_ parameter: NeatFunctionParameter) -> String {
        let typeName =
            parameter.slotName.map { "@\($0)" } ?? parameter.renderedTypeName
            ?? "_"
        if let externalLabel = parameter.externalLabel {
            if externalLabel == parameter.localName {
                return "\(parameter.localName): \(typeName)"
            }
            return "\(externalLabel) \(parameter.localName): \(typeName)"
        }
        return "_ \(parameter.localName): \(typeName)"
    }
}
