import Foundation

extension ApplicationGraphValidator {
    func validateLiteralBridgeCompatibility(
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
                try validateLiteralBridgeCompatibility(
                    in: declaration,
                    declarationGraph: declarationGraph,
                    resolver: resolver,
                    memberResolver: memberResolver,
                    operatorResolver: operatorResolver,
                    typeCompatibilityResolver: typeCompatibilityResolver,
                    fileName: fileName
                )
            case .namespace(let declaration):
                try validateLiteralBridgeCompatibility(
                    in: declaration,
                    declarationGraph: declarationGraph,
                    resolver: resolver,
                    memberResolver: memberResolver,
                    operatorResolver: operatorResolver,
                    typeCompatibilityResolver: typeCompatibilityResolver,
                    fileName: fileName
                )
            case .module(let module):
                try validateLiteralBridgeCompatibility(
                    in: registryView.topLevelStates(inFilePath: parsedFile.path),
                    accessibleTypes: [:],
                    resolver: resolver,
                    memberResolver: memberResolver,
                    operatorResolver: operatorResolver,
                    typeCompatibilityResolver: typeCompatibilityResolver,
                    fileName: fileName
                )

                let topLevelStateTypes = Dictionary(
                    uniqueKeysWithValues: registryView.topLevelStates(inFilePath: parsedFile.path).map {
                        ($0.name, BootstrapLiteralType.typed($0.type))
                    }
                )

                for callable in module.callables {
                    try validateLiteralBridgeCompatibility(
                        in: callable,
                        accessibleTypes: topLevelStateTypes,
                        resolver: resolver,
                        memberResolver: memberResolver,
                        operatorResolver: operatorResolver,
                        typeCompatibilityResolver: typeCompatibilityResolver,
                        fileName: fileName
                    )
                }

                for declaration in module.constructs {
                    try validateLiteralBridgeCompatibility(
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
                    try validateLiteralBridgeCompatibility(
                        in: declaration,
                        declarationGraph: declarationGraph,
                        resolver: resolver,
                        memberResolver: memberResolver,
                        operatorResolver: operatorResolver,
                        typeCompatibilityResolver: typeCompatibilityResolver,
                        fileName: fileName
                    )
                }
            case .mainBlock, .enumeration, .protocolDefinition, .macro, .extensions:
                break
            }
        }
    }

    func validateLiteralBridgeCompatibility(
        in declaration: NamespaceDeclaration,
        declarationGraph: DeclarationGraph,
        resolver: LiteralBridgeResolver,
        memberResolver: DeclarationMemberResolver,
        operatorResolver: DeclarationOperatorResolver,
        typeCompatibilityResolver: DeclarationTypeCompatibilityResolver,
        fileName: String
    ) throws {
        for callable in declaration.callables {
            try validateLiteralBridgeCompatibility(
                in: callable,
                accessibleTypes: [:],
                resolver: resolver,
                memberResolver: memberResolver,
                operatorResolver: operatorResolver,
                typeCompatibilityResolver: typeCompatibilityResolver,
                fileName: fileName
            )
        }
        for construct in declaration.constructs {
            try validateLiteralBridgeCompatibility(
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
            try validateLiteralBridgeCompatibility(
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

    func validateLiteralBridgeCompatibility(
        in declaration: ConstructDeclaration,
        declarationGraph: DeclarationGraph,
        resolver: LiteralBridgeResolver,
        memberResolver: DeclarationMemberResolver,
        operatorResolver: DeclarationOperatorResolver,
        typeCompatibilityResolver: DeclarationTypeCompatibilityResolver,
        fileName: String
    ) throws {
        try validateLiteralBridgeCompatibility(
            in: declarationGraph.states(onConstruct: declaration.name),
            accessibleTypes: [:],
            resolver: resolver,
            memberResolver: memberResolver,
            operatorResolver: operatorResolver,
            typeCompatibilityResolver: typeCompatibilityResolver,
            fileName: fileName
        )

        let stateTypes = Dictionary(
            uniqueKeysWithValues: declarationGraph.states(onConstruct: declaration.name).map {
                ($0.name, BootstrapLiteralType.typed($0.type))
            }
        )
        let accessibleTypes = stateTypes

        for callable in declarationGraph.callables(onConstruct: declaration.name) {
            try validateLiteralBridgeCompatibility(
                in: callable,
                accessibleTypes: accessibleTypes,
                resolver: resolver,
                memberResolver: memberResolver,
                operatorResolver: operatorResolver,
                typeCompatibilityResolver: typeCompatibilityResolver,
                fileName: fileName
            )
        }
    }

    func validateLiteralBridgeCompatibility(
        in states: [StateDeclaration],
        accessibleTypes initialAccessibleTypes: [String: BootstrapLiteralType],
        resolver: LiteralBridgeResolver,
        memberResolver: DeclarationMemberResolver,
        operatorResolver: DeclarationOperatorResolver,
        typeCompatibilityResolver: DeclarationTypeCompatibilityResolver,
        fileName: String
    ) throws {
        var accessibleTypes = initialAccessibleTypes

        for state in states {
            if state.hasExplicitTypeAnnotation,
                case .stored(let expression) = state.storage,
                let inferred = try? ExpressionTypeSemantics.inferType(
                    of: expression,
                    accessibleTypes: accessibleTypes,
                    resolver: resolver,
                    memberResolver: memberResolver,
                    operatorResolver: operatorResolver
                ),
                inferred.isLiteralLike,
                !ExpressionTypeSemantics.isCompatible(
                    actual: inferred,
                    expected: state.type,
                    resolver: resolver,
                    typeCompatibilityResolver: typeCompatibilityResolver
                )
            {
                throw SemanticValidationError(
                    "state '\(state.name)' in \(fileName) expects \(state.type.displayName), got \(inferred.displayName)."
                )
            }

            accessibleTypes[state.name] = .typed(state.type)
        }
    }

    func validateLiteralBridgeCompatibility(
        in callable: CallableDeclaration,
        accessibleTypes: [String: BootstrapLiteralType],
        resolver: LiteralBridgeResolver,
        memberResolver: DeclarationMemberResolver,
        operatorResolver: DeclarationOperatorResolver,
        typeCompatibilityResolver: DeclarationTypeCompatibilityResolver,
        fileName: String
    ) throws {
        guard
            let explicitReturnType = callable.returnType,
            explicitReturnType.displayName != "Void",
            let body = callable.body
        else {
            return
        }

        try validateLiteralBridgeCompatibilityInLocalCallables(
            in: body,
            accessibleTypes: accessibleTypes,
            resolver: resolver,
            memberResolver: memberResolver,
            operatorResolver: operatorResolver,
            typeCompatibilityResolver: typeCompatibilityResolver,
            fileName: fileName
        )

        let parameterTypes: [String: BootstrapLiteralType] = Dictionary(
            uniqueKeysWithValues: callable.parameters.compactMap { parameter in
                guard let typeReference = parameter.typeReference else {
                    return nil
                }
                return (parameter.localName, BootstrapLiteralType.typed(typeReference))
            }
        )
        let visibleTypes = accessibleTypes.merging(parameterTypes) { current, _ in current }

        for expression in collectReturnExpressions(in: body).compactMap({ $0 }) {
            guard
                let inferred = try? ExpressionTypeSemantics.inferType(
                    of: expression,
                    accessibleTypes: visibleTypes,
                    resolver: resolver,
                    memberResolver: memberResolver,
                    operatorResolver: operatorResolver
                ),
                ExpressionTypeSemantics.isLiteralExpression(expression)
            else {
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
                    "Callable \(callable.name) in \(fileName) expects return type \(explicitReturnType.displayName), got \(inferred.displayName)."
                )
            }
        }
    }

    func validateLiteralBridgeCompatibilityInLocalCallables(
        in statements: [Statement],
        accessibleTypes: [String: BootstrapLiteralType],
        resolver: LiteralBridgeResolver,
        memberResolver: DeclarationMemberResolver,
        operatorResolver: DeclarationOperatorResolver,
        typeCompatibilityResolver: DeclarationTypeCompatibilityResolver,
        fileName: String
    ) throws {
        for statement in statements {
            switch statement {
            case .expand, .require:
                continue
            case .localCallable(let declaration):
                try validateLiteralBridgeCompatibility(
                    in: CallableDeclaration(
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
                try validateLiteralBridgeCompatibilityInLocalCallables(
                    in: body,
                    accessibleTypes: accessibleTypes,
                    resolver: resolver,
                    memberResolver: memberResolver,
                    operatorResolver: operatorResolver,
                    typeCompatibilityResolver: typeCompatibilityResolver,
                    fileName: fileName
                )
            case .background(let background):
                try validateLiteralBridgeCompatibilityInLocalCallables(
                    in: background.body,
                    accessibleTypes: accessibleTypes,
                    resolver: resolver,
                    memberResolver: memberResolver,
                    operatorResolver: operatorResolver,
                    typeCompatibilityResolver: typeCompatibilityResolver,
                    fileName: fileName
                )
            case .deferBlock(let deferred):
                try validateLiteralBridgeCompatibilityInLocalCallables(
                    in: deferred.body,
                    accessibleTypes: accessibleTypes,
                    resolver: resolver,
                    memberResolver: memberResolver,
                    operatorResolver: operatorResolver,
                    typeCompatibilityResolver: typeCompatibilityResolver,
                    fileName: fileName
                )
            case .conditional(let branches):
                for branch in branches {
                    try validateLiteralBridgeCompatibilityInLocalCallables(
                        in: branch.body,
                        accessibleTypes: accessibleTypes,
                        resolver: resolver,
                        memberResolver: memberResolver,
                        operatorResolver: operatorResolver,
                        typeCompatibilityResolver: typeCompatibilityResolver,
                        fileName: fileName
                    )
                }
            case .switchStatement(_, let cases, let defaultBody):
                for switchCase in cases {
                    try validateLiteralBridgeCompatibilityInLocalCallables(
                        in: switchCase.body,
                        accessibleTypes: accessibleTypesForSwitchCasePattern(
                            switchCase.pattern,
                            base: accessibleTypes
                        ),
                        resolver: resolver,
                        memberResolver: memberResolver,
                        operatorResolver: operatorResolver,
                        typeCompatibilityResolver: typeCompatibilityResolver,
                        fileName: fileName
                    )
                }
                if let defaultBody {
                    try validateLiteralBridgeCompatibilityInLocalCallables(
                        in: defaultBody,
                        accessibleTypes: accessibleTypes,
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
}
