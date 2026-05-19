import Foundation

extension ApplicationGraphValidator {
    func validateCallableReturnSemantics(
        in parsedFiles: [ParsedSourceFile],
        declarationGraph: DeclarationGraph,
        registryView: DeclarationRegistryView,
        resolver: LiteralBridgeResolver,
        memberResolver: DeclarationMemberResolver,
        operatorResolver: DeclarationOperatorResolver,
        typeCompatibilityResolver: DeclarationTypeCompatibilityResolver
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
                    typeCompatibilityResolver: typeCompatibilityResolver,
                    fileName: fileName
                )
            case .namespace(let declaration):
                try validateCallableReturnSemantics(
                    in: declaration,
                    declarationGraph: declarationGraph,
                    resolver: resolver,
                    memberResolver: memberResolver,
                    operatorResolver: operatorResolver,
                    typeCompatibilityResolver: typeCompatibilityResolver,
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
                        declarationGraph: declarationGraph,
                        resolver: resolver,
                        memberResolver: memberResolver,
                        operatorResolver: operatorResolver,
                        typeCompatibilityResolver: typeCompatibilityResolver,
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
                        typeCompatibilityResolver: typeCompatibilityResolver,
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
                        typeCompatibilityResolver: typeCompatibilityResolver,
                        fileName: fileName
                    )
                }
            case .mainBlock, .enumeration, .protocolDefinition, .macro, .marker, .extensions:
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
        typeCompatibilityResolver: DeclarationTypeCompatibilityResolver,
        fileName: String
    ) throws {
        for callable in declaration.callables {
            try validateCallableReturnSemantics(
                callable,
                accessibleTypes: [:],
                declarationGraph: declarationGraph,
                resolver: resolver,
                memberResolver: memberResolver,
                operatorResolver: operatorResolver,
                typeCompatibilityResolver: typeCompatibilityResolver,
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
                typeCompatibilityResolver: typeCompatibilityResolver,
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
                typeCompatibilityResolver: typeCompatibilityResolver,
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
        typeCompatibilityResolver: DeclarationTypeCompatibilityResolver,
        fileName: String
    ) throws {
        let stateTypes = Dictionary(
            uniqueKeysWithValues: declarationGraph.states(onConstruct: declaration.name).map {
                ($0.name, BootstrapLiteralType.typed($0.type))
            }
        )
        let bindingTypes = Dictionary(
            uniqueKeysWithValues: declarationGraph.bindings(onConstruct: declaration.name).map {
                ($0.name, BootstrapLiteralType.typed(.named($0.typeName)))
            }
        )
        let derivedTypes = Dictionary(
            uniqueKeysWithValues: declarationGraph.deriveds(onConstruct: declaration.name).map {
                ($0.name, BootstrapLiteralType.typed(.named($0.typeName)))
            }
        )
        let valueTypes = Dictionary(
            uniqueKeysWithValues: declarationGraph.values(onConstruct: declaration.name).map {
                ($0.name, BootstrapLiteralType.typed(.named($0.typeName)))
            }
        )
        var accessibleTypes = stateTypes
            .merging(bindingTypes) { current, _ in current }
            .merging(derivedTypes) { current, _ in current }
            .merging(valueTypes) { current, _ in current }
        accessibleTypes["self"] = .typed(.named(declaration.name))

        for callable in declarationGraph.callables(onConstruct: declaration.name) {
            try validateCallableReturnSemantics(
                callable,
                accessibleTypes: accessibleTypes,
                declarationGraph: declarationGraph,
                resolver: resolver,
                memberResolver: memberResolver,
                operatorResolver: operatorResolver,
                typeCompatibilityResolver: typeCompatibilityResolver,
                fileName: fileName
            )
        }
    }

    func validateCallableReturnSemantics(
        _ callable: CallableDeclaration,
        accessibleTypes: [String: BootstrapLiteralType],
        declarationGraph: DeclarationGraph,
        resolver: LiteralBridgeResolver,
        memberResolver: DeclarationMemberResolver,
        operatorResolver: DeclarationOperatorResolver,
        typeCompatibilityResolver: DeclarationTypeCompatibilityResolver,
        fileName: String
    ) throws {
        guard let body = callable.body else {
            return
        }

        try validateCallableReturnSemanticsInLocalCallables(
            in: body,
            accessibleTypes: accessibleTypes,
            declarationGraph: declarationGraph,
            resolver: resolver,
            memberResolver: memberResolver,
            operatorResolver: operatorResolver,
            typeCompatibilityResolver: typeCompatibilityResolver,
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
            let parameterTypes: [String: BootstrapLiteralType] = Dictionary(
                uniqueKeysWithValues: callable.parameters.compactMap { parameter in
                    guard let typeReference = parameter.typeReference else {
                        return nil
                    }
                    return (parameter.localName, BootstrapLiteralType.typed(typeReference))
                }
            )
            let visibleTypes = accessibleTypes.merging(parameterTypes) { current, _ in current }

            guard blockAlwaysReturnsValue(
                body,
                accessibleTypes: visibleTypes,
                declarationGraph: declarationGraph,
                resolver: resolver,
                memberResolver: memberResolver,
                operatorResolver: operatorResolver
            ) else {
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
                    resolver: resolver,
                    typeCompatibilityResolver: typeCompatibilityResolver
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
        declarationGraph: DeclarationGraph,
        resolver: LiteralBridgeResolver,
        memberResolver: DeclarationMemberResolver,
        operatorResolver: DeclarationOperatorResolver,
        typeCompatibilityResolver: DeclarationTypeCompatibilityResolver,
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
                        receiverType: nil,
                        name: declaration.name,
                        genericParameters: declaration.genericParameters,
                        hasExplicitParameterClause: declaration.hasExplicitParameterClause,
                        parameters: declaration.parameters,
                        returnType: declaration.returnType,
                        body: declaration.body
                    ),
                    accessibleTypes: accessibleTypes,
                    declarationGraph: declarationGraph,
                    resolver: resolver,
                    memberResolver: memberResolver,
                    operatorResolver: operatorResolver,
                    typeCompatibilityResolver: typeCompatibilityResolver,
                    fileName: fileName
                )
            case .macroInvocation(_, _, let body),
                .derived(_, _, let body),
                .forEach(_, _, let body),
                .whileLoop(_, let body):
                try validateCallableReturnSemanticsInLocalCallables(
                    in: body,
                    accessibleTypes: accessibleTypes,
                    declarationGraph: declarationGraph,
                    resolver: resolver,
                    memberResolver: memberResolver,
                    operatorResolver: operatorResolver,
                    typeCompatibilityResolver: typeCompatibilityResolver,
                    fileName: fileName
                )
            case .background(let background):
                try validateCallableReturnSemanticsInLocalCallables(
                    in: background.body,
                    accessibleTypes: accessibleTypes,
                    declarationGraph: declarationGraph,
                    resolver: resolver,
                    memberResolver: memberResolver,
                    operatorResolver: operatorResolver,
                    typeCompatibilityResolver: typeCompatibilityResolver,
                    fileName: fileName
                )
            case .deferBlock(let deferred):
                try validateCallableReturnSemanticsInLocalCallables(
                    in: deferred.body,
                    accessibleTypes: accessibleTypes,
                    declarationGraph: declarationGraph,
                    resolver: resolver,
                    memberResolver: memberResolver,
                    operatorResolver: operatorResolver,
                    typeCompatibilityResolver: typeCompatibilityResolver,
                    fileName: fileName
                )
            case .conditional(let branches):
                for branch in branches {
                    try validateCallableReturnSemanticsInLocalCallables(
                        in: branch.body,
                        accessibleTypes: accessibleTypes,
                        declarationGraph: declarationGraph,
                        resolver: resolver,
                        memberResolver: memberResolver,
                        operatorResolver: operatorResolver,
                        typeCompatibilityResolver: typeCompatibilityResolver,
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
                        declarationGraph: declarationGraph,
                        resolver: resolver,
                        memberResolver: memberResolver,
                        operatorResolver: operatorResolver,
                        typeCompatibilityResolver: typeCompatibilityResolver,
                        fileName: fileName
                    )
                }
                if let defaultBody {
                    try validateCallableReturnSemanticsInLocalCallables(
                        in: defaultBody,
                        accessibleTypes: accessibleTypes,
                        declarationGraph: declarationGraph,
                        resolver: resolver,
                        memberResolver: memberResolver,
                        operatorResolver: operatorResolver,
                        typeCompatibilityResolver: typeCompatibilityResolver,
                        fileName: fileName
                    )
                }
            case .localBinding, .assignment, .compoundAssignment,
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
            case .localBinding, .derived, .assignment, .compoundAssignment,
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

    func blockAlwaysReturnsValue(
        _ statements: [Statement],
        accessibleTypes: [String: BootstrapLiteralType],
        declarationGraph: DeclarationGraph,
        resolver: LiteralBridgeResolver,
        memberResolver: DeclarationMemberResolver,
        operatorResolver: DeclarationOperatorResolver
    ) -> Bool {
        var accessibleTypes = accessibleTypes
        for statement in statements {
            if statementAlwaysReturnsValue(
                statement,
                accessibleTypes: accessibleTypes,
                declarationGraph: declarationGraph,
                resolver: resolver,
                memberResolver: memberResolver,
                operatorResolver: operatorResolver
            ) {
                return true
            }
            if case .localBinding(let declaration) = statement {
                accessibleTypes[declaration.name] = .typed(declaration.type)
            }
        }
        return false
    }

    func statementAlwaysReturnsValue(
        _ statement: Statement,
        accessibleTypes: [String: BootstrapLiteralType],
        declarationGraph: DeclarationGraph,
        resolver: LiteralBridgeResolver,
        memberResolver: DeclarationMemberResolver,
        operatorResolver: DeclarationOperatorResolver
    ) -> Bool {
        switch statement {
        case .macroInvocation(_, _, let body):
            return blockAlwaysReturnsValue(
                body,
                accessibleTypes: accessibleTypes,
                declarationGraph: declarationGraph,
                resolver: resolver,
                memberResolver: memberResolver,
                operatorResolver: operatorResolver
            )
        case .return(let expression):
            return expression != nil
        case .conditional(let branches):
            guard branches.contains(where: { $0.condition == nil }) else {
                return false
            }
            return branches.allSatisfy {
                blockAlwaysReturnsValue(
                    $0.body,
                    accessibleTypes: accessibleTypes,
                    declarationGraph: declarationGraph,
                    resolver: resolver,
                    memberResolver: memberResolver,
                    operatorResolver: operatorResolver
                )
            }
        case .switchStatement(let subject, let cases, let defaultBody):
            guard !cases.isEmpty else { return false }
            guard cases.allSatisfy({
                blockAlwaysReturnsValue(
                    $0.body,
                    accessibleTypes: accessibleTypesForSwitchCasePattern(
                        $0.pattern,
                        base: accessibleTypes
                    ),
                    declarationGraph: declarationGraph,
                    resolver: resolver,
                    memberResolver: memberResolver,
                    operatorResolver: operatorResolver
                )
            }) else { return false }
            guard let defaultBody else {
                return switchCoversAllEnumCases(
                    subject: subject,
                    cases: cases,
                    accessibleTypes: accessibleTypes,
                    declarationGraph: declarationGraph,
                    resolver: resolver,
                    memberResolver: memberResolver,
                    operatorResolver: operatorResolver
                )
            }
            return blockAlwaysReturnsValue(
                defaultBody,
                accessibleTypes: accessibleTypes,
                declarationGraph: declarationGraph,
                resolver: resolver,
                memberResolver: memberResolver,
                operatorResolver: operatorResolver
            )
        case .background, .localCallable:
            return false
        case .deferBlock(let deferred):
            return blockAlwaysReturnsValue(
                deferred.body,
                accessibleTypes: accessibleTypes,
                declarationGraph: declarationGraph,
                resolver: resolver,
                memberResolver: memberResolver,
                operatorResolver: operatorResolver
            )
        default:
            return false
        }
    }

    func switchCoversAllEnumCases(
        subject: Expression,
        cases: [SwitchCase],
        accessibleTypes: [String: BootstrapLiteralType],
        declarationGraph: DeclarationGraph,
        resolver: LiteralBridgeResolver,
        memberResolver: DeclarationMemberResolver,
        operatorResolver: DeclarationOperatorResolver
    ) -> Bool {
        guard
            let inferred = try? ExpressionTypeSemantics.inferType(
                of: subject,
                accessibleTypes: accessibleTypes,
                resolver: resolver,
                memberResolver: memberResolver,
                operatorResolver: operatorResolver
            ),
            case .typed(let subjectType) = inferred,
            let enumName = enumName(for: subjectType),
            let enumeration = declarationGraph.enumsByName[enumName]
        else {
            return false
        }

        let declaredCases = Set(enumeration.cases.map(\.name))
        let coveredCases = Set(cases.compactMap { switchCase -> String? in
            guard case .enumCase(let name, _) = switchCase.pattern else {
                return nil
            }
            return name.hasPrefix(".") ? String(name.dropFirst()) : name
        })
        return !declaredCases.isEmpty && declaredCases.isSubset(of: coveredCases)
    }

    func enumName(for type: TypeReference) -> String? {
        switch type {
        case .named(let name):
            return name
        case .member:
            return type.displayName
        case .generic(let base, _):
            return enumName(for: base)
        case .optional(let wrapped):
            return enumName(for: wrapped)
        case .array, .function, .variadic:
            return nil
        }
    }

    func renderCallableSignature(_ callable: CallableDeclaration) -> String {
        let rendered = callable.parameters.map(renderParameterSignature).joined(separator: ", ")
        if let targetType = callable.targetType {
            return "\(targetType.displayName)@\(callable.name)(\(rendered))"
        }
        return "@\(callable.name)(\(rendered))"
    }

    func renderParameterSignature(_ parameter: GradientFunctionParameter) -> String {
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
