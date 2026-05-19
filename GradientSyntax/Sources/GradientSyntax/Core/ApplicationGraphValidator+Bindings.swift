import Foundation

extension ApplicationGraphValidator {
    func validateBindingReferences(
        in parsedFiles: [ParsedSourceFile],
        declarationGraph: DeclarationGraph,
        registryView: DeclarationRegistryView
    ) throws {
        for parsedFile in parsedFiles {
            let fileName = lastPathComponent(of: parsedFile.path)

            switch parsedFile.sourceFile {
            case .construct(let declaration):
                try validateBindingReferences(
                    in: declaration,
                    declarationGraph: declarationGraph,
                    fileName: fileName
                )
            case .namespace(let declaration):
                try validateBindingReferences(
                    in: declaration,
                    declarationGraph: declarationGraph,
                    fileName: fileName
                )
            case .module(let module):
                let topLevelMutable = Set(
                    registryView.topLevelStates(inFilePath: parsedFile.path).map(\.name)
                )
                if let mainBlock = module.mainBlock {
                    try validateBindingReferences(
                        in: mainBlock.body,
                        declarationGraph: declarationGraph,
                        context: BindingReferenceContext(
                            mutableNames: topLevelMutable,
                            selfAvailable: false,
                            currentConstructName: nil
                        ),
                        fileName: fileName
                    )
                }
                for callable in module.callables {
                    guard let body = callable.body else { continue }
                    try validateBindingReferences(
                        in: body,
                        declarationGraph: declarationGraph,
                        context: bindingReferenceContext(
                            mutableNames: topLevelMutable,
                            selfAvailable: false,
                            currentConstructName: nil,
                            parameters: callable.parameters
                        ),
                        fileName: fileName
                    )
                }
                for declaration in module.constructs {
                    try validateBindingReferences(
                        in: declaration,
                        declarationGraph: declarationGraph,
                        fileName: fileName
                    )
                }
                for declaration in module.namespaces {
                    try validateBindingReferences(
                        in: declaration,
                        declarationGraph: declarationGraph,
                        fileName: fileName
                    )
                }
            case .mainBlock(let mainBlock):
                try validateBindingReferences(
                    in: mainBlock.body,
                    declarationGraph: declarationGraph,
                    context: BindingReferenceContext(
                        mutableNames: [],
                        selfAvailable: false,
                        currentConstructName: nil
                    ),
                    fileName: fileName
                )
            case .enumeration, .protocolDefinition, .macro, .marker, .extensions:
                break
            }
        }
    }

    func validateBindingReferences(
        in declaration: NamespaceDeclaration,
        declarationGraph: DeclarationGraph,
        fileName: String
    ) throws {
        for callable in declaration.callables {
            guard let body = callable.body else { continue }
            try validateBindingReferences(
                in: body,
                declarationGraph: declarationGraph,
                context: bindingReferenceContext(
                    mutableNames: [],
                    selfAvailable: false,
                    currentConstructName: nil,
                    parameters: callable.parameters
                ),
                fileName: fileName
            )
        }
        for construct in declaration.constructs {
            try validateBindingReferences(
                in: construct,
                declarationGraph: declarationGraph,
                fileName: fileName
            )
        }
        for namespace in declaration.namespaces {
            try validateBindingReferences(
                in: namespace,
                declarationGraph: declarationGraph,
                fileName: fileName
            )
        }
    }

    func validateBindingReferences(
        in declaration: ConstructDeclaration,
        declarationGraph: DeclarationGraph,
        fileName: String
    ) throws {
        let memberMutableNames =
            Set(declarationGraph.states(onConstruct: declaration.name).map(\.name))
            .union(declarationGraph.bindings(onConstruct: declaration.name).map(\.name))

        for derived in declarationGraph.deriveds(onConstruct: declaration.name) {
            if let body = derived.body {
                try validateBindingReferences(
                    in: body,
                    declarationGraph: declarationGraph,
                    context: BindingReferenceContext(
                        mutableNames: memberMutableNames,
                        selfAvailable: true,
                        currentConstructName: declaration.name
                    ),
                    fileName: fileName
                )
            }
        }

        for initializer in declarationGraph.initializers(onConstruct: declaration.name) {
            if let body = initializer.body {
                try validateBindingReferences(
                    in: body,
                    declarationGraph: declarationGraph,
                    context: bindingReferenceContext(
                        mutableNames: memberMutableNames,
                        selfAvailable: true,
                        currentConstructName: declaration.name,
                        parameters: initializer.parameters
                    ),
                    fileName: fileName
                )
            }
        }

        for callable in declarationGraph.callables(onConstruct: declaration.name) {
            if let body = callable.body {
                try validateBindingReferences(
                    in: body,
                    declarationGraph: declarationGraph,
                    context: bindingReferenceContext(
                        mutableNames: memberMutableNames,
                        selfAvailable: true,
                        currentConstructName: declaration.name,
                        parameters: callable.parameters
                    ),
                    fileName: fileName
                )
            }
        }

        for nested in declaration.constructs {
            try validateBindingReferences(
                in: nested,
                declarationGraph: declarationGraph,
                fileName: fileName
            )
        }
    }

    func bindingReferenceContext(
        mutableNames: Set<String>,
        selfAvailable: Bool,
        currentConstructName: String?,
        parameters: [GradientFunctionParameter]
    ) -> BindingReferenceContext {
        let parameterMutableNames = Set(parameters.filter(\.isBinding).map(\.localName))
        return BindingReferenceContext(
            mutableNames: mutableNames.union(parameterMutableNames),
            selfAvailable: selfAvailable,
            currentConstructName: currentConstructName
        )
    }

    func validateBindingReferences(
        in statements: [Statement],
        declarationGraph: DeclarationGraph,
        context: BindingReferenceContext,
        fileName: String
    ) throws {
        var context = context

        for statement in statements {
            switch statement {
            case .expand:
                continue
            case .macroInvocation(_, _, let body):
                try validateBindingReferences(
                    in: body,
                    declarationGraph: declarationGraph,
                    context: context,
                    fileName: fileName
                )
            case .background(let background):
                try validateBindingReferences(
                    in: background.body,
                    declarationGraph: declarationGraph,
                    context: context,
                    fileName: fileName
                )
            case .deferBlock(let deferred):
                try validateBindingReferences(
                    in: deferred.body,
                    declarationGraph: declarationGraph,
                    context: context,
                    fileName: fileName
                )
            case .localBinding(let declaration):
                try validateBindingReferences(
                    in: declaration.expression,
                    declarationGraph: declarationGraph,
                    context: context,
                    fileName: fileName
                )
                if declaration.kind == .mutable {
                    context.mutableNames.insert(declaration.name)
                }
            case .localCallable(let declaration):
                try validateBindingReferences(
                    in: declaration.body,
                    declarationGraph: declarationGraph,
                    context: bindingReferenceContext(
                        mutableNames: context.mutableNames,
                        selfAvailable: context.selfAvailable,
                        currentConstructName: context.currentConstructName,
                        parameters: declaration.parameters
                    ),
                    fileName: fileName
                )
            case .derived(_, _, let body):
                try validateBindingReferences(
                    in: body,
                    declarationGraph: declarationGraph,
                    context: context,
                    fileName: fileName
                )
            case .assignment(_, let expression), .compoundAssignment(_, _, let expression),
                .expression(let expression):
                try validateBindingReferences(
                    in: expression,
                    declarationGraph: declarationGraph,
                    context: context,
                    fileName: fileName
                )
            case .forEach(_, let sequence, let body):
                try validateBindingReferences(
                    in: sequence,
                    declarationGraph: declarationGraph,
                    context: context,
                    fileName: fileName
                )
                try validateBindingReferences(
                    in: body,
                    declarationGraph: declarationGraph,
                    context: context,
                    fileName: fileName
                )
            case .whileLoop(let condition, let body):
                try validateBindingReferences(
                    in: condition,
                    declarationGraph: declarationGraph,
                    context: context,
                    fileName: fileName
                )
                try validateBindingReferences(
                    in: body,
                    declarationGraph: declarationGraph,
                    context: context,
                    fileName: fileName
                )
            case .conditional(let branches):
                for branch in branches {
                    if let condition = branch.condition {
                        try validateBindingReferences(
                            in: condition,
                            declarationGraph: declarationGraph,
                            context: context,
                            fileName: fileName
                        )
                    }
                    try validateBindingReferences(
                        in: branch.body,
                        declarationGraph: declarationGraph,
                        context: context,
                        fileName: fileName
                    )
                }
            case .return(let expression):
                if let expression {
                    try validateBindingReferences(
                        in: expression,
                        declarationGraph: declarationGraph,
                        context: context,
                        fileName: fileName
                    )
                }
            case .switchStatement(let expression, let cases, let defaultBody):
                try validateBindingReferences(
                    in: expression,
                    declarationGraph: declarationGraph,
                    context: context,
                    fileName: fileName
                )
                for switchCase in cases {
                    try validateBindingReferences(
                        in: switchCase.pattern,
                        declarationGraph: declarationGraph,
                        context: context,
                        fileName: fileName
                    )
                    try validateBindingReferences(
                        in: switchCase.body,
                        declarationGraph: declarationGraph,
                        context: bindingReferenceContext(
                            for: switchCase.pattern,
                            base: context
                        ),
                        fileName: fileName
                    )
                }
                if let defaultBody {
                    try validateBindingReferences(
                        in: defaultBody,
                        declarationGraph: declarationGraph,
                        context: context,
                        fileName: fileName
                    )
                }
            case .break, .continue:
                continue
            }
        }
    }

    func validateBindingReferences(
        in pattern: SwitchCasePattern,
        declarationGraph: DeclarationGraph,
        context: BindingReferenceContext,
        fileName: String
    ) throws {
        if case .expression(let expression) = pattern {
            try validateBindingReferences(
                in: expression,
                declarationGraph: declarationGraph,
                context: context,
                fileName: fileName
            )
        }
    }

    func validateBindingReferences(
        in expression: Expression,
        declarationGraph: DeclarationGraph,
        context: BindingReferenceContext,
        fileName: String
    ) throws {
        switch expression {
        case .bindingReference(let path):
            let root = path.split(separator: ".").first.map(String.init) ?? path
            if root == "self" {
                guard context.selfAvailable else {
                    throw SemanticValidationError(
                        "Binding reference '$\(path)' in \(fileName) is invalid because self is not available in this scope."
                    )
                }
                if path != "self" {
                    guard let currentConstructName = context.currentConstructName else {
                        throw SemanticValidationError(
                            "Binding reference '$\(path)' in \(fileName) is invalid because self has no declaration context."
                        )
                    }
                    let memberSuffix = String(path.dropFirst("self.".count))
                    let declaredPath = "\(currentConstructName).\(memberSuffix)"
                    guard
                        declarationGraph.declaresMemberPath(
                            declaredPath,
                            onConstruct: currentConstructName
                        )
                    else {
                        throw SemanticValidationError(
                            "Binding reference '$\(path)' in \(fileName) is invalid because \(declaredPath) is not a declared member path."
                        )
                    }
                }
                return
            }
            guard context.mutableNames.contains(root) else {
                throw SemanticValidationError(
                    "Binding reference '$\(path)' in \(fileName) must reference mutable storage."
                )
            }
        case .macroInvocation(_, let arguments), .call(_, let arguments):
            for argument in arguments {
                try validateBindingReferences(
                    in: argument.value,
                    declarationGraph: declarationGraph,
                    context: context,
                    fileName: fileName
                )
            }
        case .array(let elements):
            for element in elements {
                try validateBindingReferences(
                    in: element,
                    declarationGraph: declarationGraph,
                    context: context,
                    fileName: fileName
                )
            }
        case .dictionary(let elements):
            for element in elements {
                try validateBindingReferences(
                    in: element.key,
                    declarationGraph: declarationGraph,
                    context: context,
                    fileName: fileName
                )
                try validateBindingReferences(
                    in: element.value,
                    declarationGraph: declarationGraph,
                    context: context,
                    fileName: fileName
                )
            }
        case .ternary(let condition, let trueExpression, let falseExpression):
            try validateBindingReferences(
                in: condition,
                declarationGraph: declarationGraph,
                context: context,
                fileName: fileName
            )
            try validateBindingReferences(
                in: trueExpression,
                declarationGraph: declarationGraph,
                context: context,
                fileName: fileName
            )
            try validateBindingReferences(
                in: falseExpression,
                declarationGraph: declarationGraph,
                context: context,
                fileName: fileName
            )
        case .unary(_, let nested):
            try validateBindingReferences(
                in: nested,
                declarationGraph: declarationGraph,
                context: context,
                fileName: fileName
            )
        case .binary(let lhs, _, let rhs):
            try validateBindingReferences(
                in: lhs,
                declarationGraph: declarationGraph,
                context: context,
                fileName: fileName
            )
            try validateBindingReferences(
                in: rhs,
                declarationGraph: declarationGraph,
                context: context,
                fileName: fileName
            )
        case .interpolatedString(let string):
            for segment in string.segments {
                if case .expression(let nested) = segment {
                    try validateBindingReferences(
                        in: nested,
                        declarationGraph: declarationGraph,
                        context: context,
                        fileName: fileName
                    )
                }
            }
        case .block(let body):
            try validateBindingReferences(
                in: body,
                declarationGraph: declarationGraph,
                context: context,
                fileName: fileName
            )
        case .integer, .double, .string, .boolean, .nilLiteral, .identifier:
            break
        }
    }

    func bindingReferenceContext(
        for pattern: SwitchCasePattern,
        base: BindingReferenceContext
    ) -> BindingReferenceContext {
        guard case .enumCase(_, let binding?) = pattern,
            binding.kind == .mutable
        else {
            return base
        }

        return BindingReferenceContext(
            mutableNames: base.mutableNames.union([binding.name]),
            selfAvailable: base.selfAvailable,
            currentConstructName: base.currentConstructName
        )
    }
}
