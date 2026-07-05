import Foundation

extension ApplicationGraphValidator {
    func validateCallArgumentLabels(
        in parsedFiles: [ParsedSourceFile],
        declarationGraph: DeclarationGraph
    ) throws {
        let environment = callLabelValidationEnvironment(
            from: parsedFiles,
            declarationGraph: declarationGraph
        )

        for parsedFile in parsedFiles {
            let fileName = lastPathComponent(of: parsedFile.path)

            switch parsedFile.sourceFile {
            case .construct(let declaration):
                try validateCallArgumentLabels(
                    in: declaration,
                    environment: environment,
                    fileName: fileName
                )
            case .module(let module):
                if let mainBlock = module.mainBlock {
                    try validateCallArgumentLabels(
                        in: mainBlock.body,
                        environment: environment,
                        context: CallLabelValidationContext(
                            currentConstructName: nil,
                            localCallablesByName: [:],
                            accessibleConstructTypesByName: [:]
                        ),
                        fileName: fileName
                    )
                }

                for callable in module.callables {
                    guard let body = callable.body else { continue }
                    try validateCallArgumentLabels(
                        in: body,
                        environment: environment,
                        context: CallLabelValidationContext(
                            currentConstructName: nil,
                            localCallablesByName: localCallableMap([callable]),
                            accessibleConstructTypesByName: parameterConstructTypes(
                                callable.parameters,
                                declarationGraph: declarationGraph
                            )
                        ),
                        fileName: fileName
                    )
                }

                for declaration in module.constructs {
                    try validateCallArgumentLabels(
                        in: declaration,
                        environment: environment,
                        fileName: fileName
                    )
                }
            case .mainBlock(let mainBlock):
                try validateCallArgumentLabels(
                    in: mainBlock.body,
                    environment: environment,
                    context: CallLabelValidationContext(
                        currentConstructName: nil,
                        localCallablesByName: [:],
                        accessibleConstructTypesByName: [:]
                    ),
                    fileName: fileName
                )
            case .enumeration, .protocolDefinition, .macro, .extensions:
                break
            }
        }
    }
    func validateCallArgumentLabels(
        in declaration: ConstructDeclaration,
        environment: CallLabelValidationEnvironment,
        fileName: String
    ) throws {
        let constructContext = CallLabelValidationContext(
            currentConstructName: declaration.name,
            localCallablesByName: [:],
            accessibleConstructTypesByName: environment.declarationGraph.constructTypedMemberNames(
                forConstruct: declaration.name
            )
        )

        for derived in environment.declarationGraph.deriveds(onConstruct: declaration.name) {
            if let body = derived.body {
                try validateCallArgumentLabels(
                    in: body,
                    environment: environment,
                    context: constructContext,
                    fileName: fileName
                )
            }
        }

        for initializer in environment.declarationGraph.initializers(onConstruct: declaration.name) {
            if let body = initializer.body {
                try validateCallArgumentLabels(
                    in: body,
                    environment: environment,
                    context: constructContext,
                    fileName: fileName
                )
            }
        }

        for callable in environment.declarationGraph.callables(onConstruct: declaration.name) {
            if let body = callable.body {
                try validateCallArgumentLabels(
                    in: body,
                    environment: environment,
                    context: CallLabelValidationContext(
                        currentConstructName: declaration.name,
                        localCallablesByName: localCallableMap([callable]),
                        accessibleConstructTypesByName: constructContext.accessibleConstructTypesByName
                            .merging(
                                parameterConstructTypes(
                                    callable.parameters,
                                    declarationGraph: environment.declarationGraph
                                )
                            ) { current, _ in current }
                    ),
                    fileName: fileName
                )
            }
        }

        for nested in declaration.constructs {
            try validateCallArgumentLabels(
                in: nested,
                environment: environment,
                fileName: fileName
            )
        }
    }

    func validateCallArgumentLabels(
        in statements: [Statement],
        environment: CallLabelValidationEnvironment,
        context: CallLabelValidationContext,
        fileName: String
    ) throws {
        var context = context

        for statement in statements {
            switch statement {
            case .expand:
                continue
            case .macroInvocation(_, _, let body):
                try validateCallArgumentLabels(
                    in: body,
                    environment: environment,
                    context: context,
                    fileName: fileName
                )
            case .background(let background):
                try validateCallArgumentLabels(
                    in: background.body,
                    environment: environment,
                    context: context,
                    fileName: fileName
                )
            case .deferBlock(let deferred):
                try validateCallArgumentLabels(
                    in: deferred.body,
                    environment: environment,
                    context: context,
                    fileName: fileName
                )
            case .localBinding(let declaration):
                try validateCallArgumentLabels(
                    in: declaration.expression,
                    environment: environment,
                    context: context,
                    fileName: fileName
                )
                if let constructTypeName = constructTypeName(
                    from: declaration.type,
                    declarationGraph: environment.declarationGraph
                ) {
                    context.accessibleConstructTypesByName[declaration.name] = constructTypeName
                }
            case .localCallable(let declaration):
                context.localCallablesByName[declaration.name, default: []].append(
                    CallLabelCandidate(
                        name: declaration.name,
                        parameters: declaration.parameters
                    )
                )
                try validateCallArgumentLabels(
                    in: declaration.body,
                    environment: environment,
                    context: CallLabelValidationContext(
                        currentConstructName: context.currentConstructName,
                        localCallablesByName: context.localCallablesByName,
                        accessibleConstructTypesByName: context.accessibleConstructTypesByName
                    ),
                    fileName: fileName
                )
            case .derived(_, _, let body):
                try validateCallArgumentLabels(
                    in: body,
                    environment: environment,
                    context: context,
                    fileName: fileName
                )
            case .assignment(_, let expression), .expression(let expression):
                try validateCallArgumentLabels(
                    in: expression,
                    environment: environment,
                    context: context,
                    fileName: fileName
                )
            case .forEach(_, let sequence, let body):
                try validateCallArgumentLabels(
                    in: sequence,
                    environment: environment,
                    context: context,
                    fileName: fileName
                )
                try validateCallArgumentLabels(
                    in: body,
                    environment: environment,
                    context: context,
                    fileName: fileName
                )
            case .whileLoop(let condition, let body):
                try validateCallArgumentLabels(
                    in: condition,
                    environment: environment,
                    context: context,
                    fileName: fileName
                )
                try validateCallArgumentLabels(
                    in: body,
                    environment: environment,
                    context: context,
                    fileName: fileName
                )
            case .conditional(let branches):
                for branch in branches {
                    if let condition = branch.condition {
                        try validateCallArgumentLabels(
                            in: condition,
                            environment: environment,
                            context: context,
                            fileName: fileName
                        )
                    }
                    try validateCallArgumentLabels(
                        in: branch.body,
                        environment: environment,
                        context: context,
                        fileName: fileName
                    )
                }
            case .return(let expression):
                if let expression {
                    try validateCallArgumentLabels(
                        in: expression,
                        environment: environment,
                        context: context,
                        fileName: fileName
                    )
                }
            case .switchStatement(let expression, let cases, let defaultBody):
                try validateCallArgumentLabels(
                    in: expression,
                    environment: environment,
                    context: context,
                    fileName: fileName
                )
                for switchCase in cases {
                    try validateCallArgumentLabels(
                        in: switchCase.pattern,
                        environment: environment,
                        context: context,
                        fileName: fileName
                    )
                    try validateCallArgumentLabels(
                        in: switchCase.body,
                        environment: environment,
                        context: contextForSwitchCasePattern(switchCase.pattern, base: context),
                        fileName: fileName
                    )
                }
                if let defaultBody {
                    try validateCallArgumentLabels(
                        in: defaultBody,
                        environment: environment,
                        context: context,
                        fileName: fileName
                    )
                }
            case .break, .continue:
                continue
            }
        }
    }

    func validateCallArgumentLabels(
        in pattern: SwitchCasePattern,
        environment: CallLabelValidationEnvironment,
        context: CallLabelValidationContext,
        fileName: String
    ) throws {
        if case .expression(let expression) = pattern {
            try validateCallArgumentLabels(
                in: expression,
                environment: environment,
                context: context,
                fileName: fileName
            )
        }
    }

    func validateCallArgumentLabels(
        in expression: Expression,
        environment: CallLabelValidationEnvironment,
        context: CallLabelValidationContext,
        fileName: String
    ) throws {
        switch expression {
        case .call(let name, let arguments):
            if let (baseName, memberName) = splitMemberName(name),
                let constructName =
                    baseName == "self"
                    ? context.currentConstructName
                    : context.accessibleConstructTypesByName[baseName]
            {
                let candidates = callLabelCandidates(
                    for: name,
                    environment: environment,
                    context: context
                )

                guard let candidates else {
                    throw SemanticValidationError(
                        "Call \(name)(\(renderCallArguments(arguments))) in \(fileName) is invalid because \(constructName).\(memberName) is not a declared callable surface."
                    )
                }

                guard candidates.contains(where: { callArguments(arguments, match: $0.parameters) })
                    || literalConstructCall(
                        name: name,
                        arguments: arguments,
                        environment: environment
                    )
                else {
                    throw SemanticValidationError(
                        "Call \(name)(\(renderCallArguments(arguments))) in \(fileName) does not match any available parameter labels. Expected one of: \(renderExpectedCallShapes(for: candidates))."
                    )
                }
            } else if let candidates = callLabelCandidates(
                for: name,
                environment: environment,
                context: context
            ), !candidates.isEmpty {
                guard candidates.contains(where: { callArguments(arguments, match: $0.parameters) })
                    || literalConstructCall(
                        name: name,
                        arguments: arguments,
                        environment: environment
                    )
                else {
                    throw SemanticValidationError(
                        "Call \(name)(\(renderCallArguments(arguments))) in \(fileName) does not match any available parameter labels. Expected one of: \(renderExpectedCallShapes(for: candidates))."
                    )
                }
            }

            for argument in arguments {
                try validateCallArgumentLabels(
                    in: argument.value,
                    environment: environment,
                    context: context,
                    fileName: fileName
                )
            }
        case .macroInvocation(_, let arguments):
            for argument in arguments {
                try validateCallArgumentLabels(
                    in: argument.value,
                    environment: environment,
                    context: context,
                    fileName: fileName
                )
            }
        case .array(let elements):
            for element in elements {
                try validateCallArgumentLabels(
                    in: element,
                    environment: environment,
                    context: context,
                    fileName: fileName
                )
            }
        case .dictionary(let elements):
            for element in elements {
                try validateCallArgumentLabels(
                    in: element.key,
                    environment: environment,
                    context: context,
                    fileName: fileName
                )
                try validateCallArgumentLabels(
                    in: element.value,
                    environment: environment,
                    context: context,
                    fileName: fileName
                )
            }
        case .ternary(let condition, let trueExpression, let falseExpression):
            try validateCallArgumentLabels(
                in: condition,
                environment: environment,
                context: context,
                fileName: fileName
            )
            try validateCallArgumentLabels(
                in: trueExpression,
                environment: environment,
                context: context,
                fileName: fileName
            )
            try validateCallArgumentLabels(
                in: falseExpression,
                environment: environment,
                context: context,
                fileName: fileName
            )
        case .unary(_, let nested):
            try validateCallArgumentLabels(
                in: nested,
                environment: environment,
                context: context,
                fileName: fileName
            )
        case .binary(let lhs, _, let rhs):
            try validateCallArgumentLabels(
                in: lhs,
                environment: environment,
                context: context,
                fileName: fileName
            )
            try validateCallArgumentLabels(
                in: rhs,
                environment: environment,
                context: context,
                fileName: fileName
            )
        case .interpolatedString(let string):
            for segment in string.segments {
                if case .expression(let nested) = segment {
                    try validateCallArgumentLabels(
                        in: nested,
                        environment: environment,
                        context: context,
                        fileName: fileName
                    )
                }
            }
        case .block(let body):
            try validateCallArgumentLabels(
                in: body,
                environment: environment,
                context: context,
                fileName: fileName
            )
        case .identifier(let name):
            if let (baseName, memberName) = splitMemberName(name),
                let constructName =
                    baseName == "self"
                    ? context.currentConstructName
                    : context.accessibleConstructTypesByName[baseName]
            {
                let declaredPath = "\(constructName).\(memberName)"
                guard
                    environment.declarationGraph.declaresMemberPath(
                        declaredPath,
                        onConstruct: constructName
                    )
                else {
                    throw SemanticValidationError(
                        "Access \(name) in \(fileName) is invalid because \(declaredPath) is not a declared member path."
                    )
                }
            }
        case .integer, .double, .string, .boolean, .nilLiteral, .bindingReference:
            break
        }
    }

    func callLabelValidationEnvironment(
        from parsedFiles: [ParsedSourceFile],
        declarationGraph: DeclarationGraph
    ) -> CallLabelValidationEnvironment {
        var topLevelCallablesByName: [String: [CallLabelCandidate]] = [:]

        for surface in declarationGraph.topLevelCallableSurfaces() {
            topLevelCallablesByName[surface.name, default: []].append(
                CallLabelCandidate(name: surface.name, parameters: surface.parameters)
            )
        }

        return CallLabelValidationEnvironment(
            topLevelCallablesByName: topLevelCallablesByName,
            declarationGraph: declarationGraph
        )
    }

    func callLabelCandidates(
        for name: String,
        environment: CallLabelValidationEnvironment,
        context: CallLabelValidationContext
    ) -> [CallLabelCandidate]? {
        if let (baseName, memberName) = splitMemberName(name) {
            if baseName == "self", let currentConstructName = context.currentConstructName {
                let candidates = environment.declarationGraph.callableSurfaces(onConstruct: currentConstructName)
                    .filter { $0.name == memberName }
                    .map { CallLabelCandidate(name: $0.name, parameters: $0.parameters) }
                return candidates.isEmpty ? nil : candidates
            }
            if let constructName = context.accessibleConstructTypesByName[baseName] {
                let candidates = environment.declarationGraph.callableSurfaces(onConstruct: constructName)
                    .filter { $0.name == memberName }
                    .map { CallLabelCandidate(name: $0.name, parameters: $0.parameters) }
                return candidates.isEmpty ? nil : candidates
            }
            return nil
        }

        if let local = context.localCallablesByName[name], !local.isEmpty {
            return local
        }

        if let callables = environment.topLevelCallablesByName[name], !callables.isEmpty {
            return callables
        }

        if environment.declarationGraph.hasConstruct(named: name) {
            let candidates = environment.declarationGraph.initializerSurfaces(onConstruct: name).map {
                CallLabelCandidate(name: name, parameters: $0.parameters)
            }
            return candidates.isEmpty ? nil : candidates
        }

        return nil
    }

    func callArguments(_ arguments: [CallArgument], match parameters: [RangeFunctionParameter])
        -> Bool
    {
        if parameters.contains(where: { !$0.macros.isEmpty }),
            arguments.allSatisfy({ $0.label == nil })
        {
            return true
        }

        if !parameters.contains(where: { !$0.macros.isEmpty }),
            !parameters.contains(where: { $0.defaultValue != nil }),
            arguments.count != parameters.count
        {
            return false
        }

        let parameterSequence: [RangeFunctionParameter]

        if let variadicIndex = parameters.firstIndex(where: { parameter in
            if case .variadic = parameter.typeReference {
                return true
            }
            return false
        }) {
            guard variadicIndex == parameters.count - 1 else { return false }
            guard arguments.count >= variadicIndex else { return false }

            var expanded = Array(parameters.prefix(variadicIndex))
            let variadicParameter = parameters[variadicIndex]
            expanded.append(
                contentsOf: Array(
                    repeating: variadicParameter,
                    count: arguments.count - variadicIndex
                )
            )
            parameterSequence = expanded
        } else {
            guard let matchedParameters = matchArguments(arguments, to: parameters) else {
                return false
            }
            parameterSequence = matchedParameters
        }

        for (argument, parameter) in zip(arguments, parameterSequence) {
            if let actualLabel = argument.label {
                guard actualLabel == parameter.externalLabel else {
                    return false
                }
            } else if parameter.externalLabel != nil {
                return false
            }
        }

        return true
    }

    func matchArguments(
        _ arguments: [CallArgument],
        to parameters: [RangeFunctionParameter]
    ) -> [RangeFunctionParameter]? {
        var matched: [RangeFunctionParameter] = []
        var parameterIndex = 0

        for argument in arguments {
            var didMatch = false
            while parameterIndex < parameters.count {
                let candidate = parameters[parameterIndex]
                if argument.label == candidate.externalLabel {
                    matched.append(candidate)
                    parameterIndex += 1
                    didMatch = true
                    break
                }
                guard candidate.defaultValue != nil else {
                    return nil
                }
                parameterIndex += 1
            }

            if !didMatch {
                return nil
            }
        }

        while parameterIndex < parameters.count {
            guard parameters[parameterIndex].defaultValue != nil else {
                return nil
            }
            parameterIndex += 1
        }

        return matched
    }

    func renderCallArguments(_ arguments: [CallArgument]) -> String {
        arguments.map { argument in
            if let label = argument.label {
                return "\(label): ..."
            }
            return "..."
        }.joined(separator: ", ")
    }

    func renderExpectedCallShapes(for candidates: [CallLabelCandidate]) -> String {
        candidates
            .map { callable in
                let labels = callable.parameters.map { parameter in
                    if let label = parameter.externalLabel {
                        return "\(label): ..."
                    }
                    return "..."
                }.joined(separator: ", ")
                return "\(callable.name)(\(labels))"
            }
            .joined(separator: " or ")
    }

    func literalConstructCall(
        name: String,
        arguments: [CallArgument],
        environment: CallLabelValidationEnvironment
    ) -> Bool {
        let constructName = stripGenericArgumentClause(from: name)
        guard environment.declarationGraph.hasConstruct(named: constructName),
            arguments.count == 1,
            arguments[0].label == nil,
            let carrierTypeName = literalCarrierTypeName(for: arguments[0].value)
        else {
            return false
        }

        return environment.declarationGraph.literalBridgeResolver.isCompatible(
            expected: .named(constructName),
            carrierTypeName: carrierTypeName
        )
    }

    func literalCarrierTypeName(for expression: Expression) -> String? {
        switch expression {
        case .integer:
            return "IntLiteral"
        case .double:
            return "FloatLiteral"
        case .string, .interpolatedString:
            return "StringLiteral"
        case .boolean:
            return "BoolLiteral"
        case .nilLiteral:
            return "NilLiteral"
        default:
            return nil
        }
    }

    func contextForSwitchCasePattern(
        _ pattern: SwitchCasePattern,
        base: CallLabelValidationContext
    ) -> CallLabelValidationContext {
        base
    }

    func localCallableMap(_ callables: [CallableDeclaration]) -> [String: [CallLabelCandidate]] {
        Dictionary(
            grouping: callables.map {
                CallLabelCandidate(name: $0.name, parameters: $0.parameters)
            },
            by: \.name
        )
    }

    func splitMemberName(_ name: String) -> (base: String, member: String)? {
        guard let dot = name.lastIndex(of: ".") else {
            return nil
        }

        let base = String(name[..<dot])
        let rawMember = String(name[name.index(after: dot)...])
        let member = stripGenericArgumentClause(from: rawMember)
        guard !base.isEmpty, !member.isEmpty else {
            return nil
        }

        return (base, member)
    }

    func stripGenericArgumentClause(from name: String) -> String {
        guard let genericStart = name.firstIndex(of: "<") else {
            return name
        }
        return String(name[..<genericStart])
    }

    func constructTypeName(
        from typeReference: TypeReference?,
        declarationGraph: DeclarationGraph
    ) -> String? {
        guard let typeReference else {
            return nil
        }

        let typeName: String?
        switch typeReference {
        case .named(let name):
            typeName = name
        case .generic(let base, _):
            return constructTypeName(from: base, declarationGraph: declarationGraph)
        case .member:
            typeName = typeReference.displayName
        case .array, .function, .optional, .variadic:
            typeName = nil
        }

        guard let typeName, declarationGraph.hasConstruct(named: typeName) else {
            return nil
        }

        return typeName
    }

    func parameterConstructTypes(
        _ parameters: [RangeFunctionParameter],
        declarationGraph: DeclarationGraph
    ) -> [String: String] {
        Dictionary(
            uniqueKeysWithValues: parameters.compactMap { parameter in
                guard let typeName = constructTypeName(
                    from: parameter.typeReference,
                    declarationGraph: declarationGraph
                ) else {
                    return nil
                }
                return (parameter.localName, typeName)
            }
        )
    }
}
