import Foundation

public struct ApplicationGraphValidator: CompiledProgramValidationPass {
    public let name = "ApplicationGraph"

    public init() {}

    public func validate(_ program: CompiledProgram) throws {
        let graphViews = program.declarationViews
        try validateControlFlow(in: program.expandedFiles)
        try validateCallArgumentLabels(
            in: program.expandedFiles,
            declarationGraph: program.declarationGraph
        )
        try validateCallableReturnSemantics(
            in: program.expandedFiles,
            registryView: graphViews.registryView,
            resolver: program.literalBridgeResolver,
            memberResolver: graphViews.memberResolver,
            operatorResolver: graphViews.operatorResolver
        )
        try validateLiteralBridgeCompatibility(
            in: program.parsedFiles,
            registryView: graphViews.registryView,
            resolver: program.literalBridgeResolver,
            memberResolver: graphViews.memberResolver,
            operatorResolver: graphViews.operatorResolver
        )
        try validateBindingReferences(
            in: program.expandedFiles,
            declarationGraph: program.declarationGraph,
            registryView: graphViews.registryView
        )
        try validateEnvironmentStateResolution(in: program.expandedFiles)
        try validateValueBindings(in: program.expandedFiles)
    }

    private struct ControlFlowContext {
        let insideAnonymousBackground: Bool
        let loopDepth: Int
        let switchDepth: Int

        static let root = ControlFlowContext(
            insideAnonymousBackground: false,
            loopDepth: 0,
            switchDepth: 0
        )

        func enteringBackground() -> ControlFlowContext {
            ControlFlowContext(
                insideAnonymousBackground: true,
                loopDepth: 0,
                switchDepth: 0
            )
        }

        func enteringLoop() -> ControlFlowContext {
            ControlFlowContext(
                insideAnonymousBackground: insideAnonymousBackground,
                loopDepth: loopDepth + 1,
                switchDepth: switchDepth
            )
        }

        func enteringSwitch() -> ControlFlowContext {
            ControlFlowContext(
                insideAnonymousBackground: insideAnonymousBackground,
                loopDepth: loopDepth,
                switchDepth: switchDepth + 1
            )
        }
    }

    private struct CallLabelValidationContext {
        let currentConstructName: String?
        var localCallablesByName: [String: [CallLabelCandidate]]
    }

    private struct CallLabelValidationEnvironment {
        let topLevelCallablesByName: [String: [CallLabelCandidate]]
        let declarationGraph: DeclarationGraph
    }

    private struct CallLabelCandidate {
        let name: String
        let parameters: [NeatFunctionParameter]
    }

    private struct BindingReferenceContext {
        var mutableNames: Set<String>
        var selfAvailable: Bool
        var currentConstructName: String?
    }

    private func validateControlFlow(in parsedFiles: [ParsedSourceFile]) throws {
        for parsedFile in parsedFiles {
            let fileName = lastPathComponent(of: parsedFile.path)

            switch parsedFile.sourceFile {
            case .construct(let declaration):
                try validateControlFlow(in: declaration, fileName: fileName)
            case .module(let module):
                if let mainBlock = module.mainBlock {
                    try validateControlFlow(
                        in: mainBlock.body,
                        context: .root,
                        fileName: fileName
                    )
                }

                for callable in module.callables {
                    guard let body = callable.body else {
                        continue
                    }

                    try validateControlFlow(
                        in: body,
                        context: .root,
                        fileName: fileName
                    )
                }

                for declaration in module.constructs {
                    try validateControlFlow(in: declaration, fileName: fileName)
                }
            case .mainBlock(let mainBlock):
                try validateControlFlow(
                    in: mainBlock.body,
                    context: .root,
                    fileName: fileName
                )
            case .enumeration, .protocolDefinition, .macro, .extensions:
                break
            }
        }
    }

    private func validateControlFlow(
        in declaration: ConstructDeclaration,
        fileName: String
    ) throws {
        for derived in declaration.deriveds {
            guard let body = derived.body else {
                continue
            }

            try validateControlFlow(
                in: body,
                context: .root,
                fileName: fileName
            )
        }

        for initializer in declaration.initializers {
            guard let body = initializer.body else {
                continue
            }

            try validateControlFlow(
                in: body,
                context: .root,
                fileName: fileName
            )
        }

        for callable in declaration.callables {
            guard let body = callable.body else {
                continue
            }

            try validateControlFlow(
                in: body,
                context: .root,
                fileName: fileName
            )
        }

        for nestedDeclaration in declaration.constructs {
            try validateControlFlow(in: nestedDeclaration, fileName: fileName)
        }
    }

    private func validateControlFlow(
        in statements: [Statement],
        context: ControlFlowContext,
        fileName: String
    ) throws {
        for statement in statements {
            switch statement {
            case .macroInvocation(_, _, let body):
                try validateControlFlow(
                    in: body,
                    context: context,
                    fileName: fileName
                )
            case .background(let background):
                try validateControlFlow(
                    in: background.body,
                    context: context.enteringBackground(),
                    fileName: fileName
                )
            case .localCallable(let declaration):
                try validateControlFlow(
                    in: declaration.body,
                    context: .root,
                    fileName: fileName
                )
            case .derived(_, _, let body):
                try validateControlFlow(
                    in: body,
                    context: context,
                    fileName: fileName
                )
            case .forEach(_, _, let body):
                try validateControlFlow(
                    in: body,
                    context: context.enteringLoop(),
                    fileName: fileName
                )
            case .whileLoop(_, let body):
                try validateControlFlow(
                    in: body,
                    context: context.enteringLoop(),
                    fileName: fileName
                )
            case .conditional(let branches):
                for branch in branches {
                    try validateControlFlow(
                        in: branch.body,
                        context: context,
                        fileName: fileName
                    )
                }
            case .switchStatement(_, let cases, let defaultBody):
                let switchContext = context.enteringSwitch()

                for switchCase in cases {
                    try validateControlFlow(
                        in: switchCase.body,
                        context: switchContext,
                        fileName: fileName
                    )
                }

                if let defaultBody {
                    try validateControlFlow(
                        in: defaultBody,
                        context: switchContext,
                        fileName: fileName
                    )
                }
            case .return(let expression):
                if context.insideAnonymousBackground, expression != nil {
                    throw SemanticValidationError(
                        "Anonymous @background block in \(fileName) cannot return a value. Use bare return to exit early."
                    )
                }
            case .break:
                guard context.loopDepth > 0 || context.switchDepth > 0 else {
                    throw SemanticValidationError(
                        "'break' in \(fileName) can only be used inside a loop or switch."
                    )
                }
            case .continue:
                guard context.loopDepth > 0 else {
                    throw SemanticValidationError(
                        "'continue' in \(fileName) can only be used inside a loop."
                    )
                }
            case .localBinding, .environmentProvision, .assignment, .compoundAssignment,
                .expression:
                continue
            }
        }
    }

    private func validateEnvironmentStateResolution(in parsedFiles: [ParsedSourceFile]) throws {
        let topLevelStateNames = Set(
            parsedFiles.flatMap { parsedFile in
                topLevelStates(in: parsedFile.sourceFile).map(\.name)
            }
        )

        for parsedFile in parsedFiles {
            for declaration in declarations(in: parsedFile.sourceFile) {
                let localStateNames = Set(declaration.states.map(\.name))

                for environment in declaration.environments where environment.isState {
                    if localStateNames.contains(environment.name) {
                        continue
                    }

                    guard topLevelStateNames.contains(environment.name) else {
                        throw SemanticValidationError(
                            "environment state \(environment.name): \(environment.typeName) in \(lastPathComponent(of: parsedFile.path)) could not be resolved from lexical outer scope."
                        )
                    }
                }
            }
        }
    }

    private func validateCallArgumentLabels(
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
                            localCallablesByName: [:]
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
                            localCallablesByName: localCallableMap([callable])
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
                        localCallablesByName: [:]
                    ),
                    fileName: fileName
                )
            case .enumeration, .protocolDefinition, .macro, .extensions:
                break
            }
        }
    }

    private func validateCallArgumentLabels(
        in declaration: ConstructDeclaration,
        environment: CallLabelValidationEnvironment,
        fileName: String
    ) throws {
        let constructContext = CallLabelValidationContext(
            currentConstructName: declaration.name,
            localCallablesByName: [:]
        )

        for derived in declaration.deriveds {
            if let body = derived.body {
                try validateCallArgumentLabels(
                    in: body,
                    environment: environment,
                    context: constructContext,
                    fileName: fileName
                )
            }
        }

        for initializer in declaration.initializers {
            if let body = initializer.body {
                try validateCallArgumentLabels(
                    in: body,
                    environment: environment,
                    context: constructContext,
                    fileName: fileName
                )
            }
        }

        for callable in declaration.callables {
            if let body = callable.body {
                try validateCallArgumentLabels(
                    in: body,
                    environment: environment,
                    context: CallLabelValidationContext(
                        currentConstructName: declaration.name,
                        localCallablesByName: localCallableMap([callable])
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

    private func validateCallArgumentLabels(
        in statements: [Statement],
        environment: CallLabelValidationEnvironment,
        context: CallLabelValidationContext,
        fileName: String
    ) throws {
        var context = context

        for statement in statements {
            switch statement {
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
            case .localBinding(let declaration):
                try validateCallArgumentLabels(
                    in: declaration.expression,
                    environment: environment,
                    context: context,
                    fileName: fileName
                )
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
                        localCallablesByName: context.localCallablesByName
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
            case .environmentProvision(let provision):
                try validateCallArgumentLabels(
                    in: provision.expression,
                    environment: environment,
                    context: context,
                    fileName: fileName
                )
            case .assignment(_, let expression), .compoundAssignment(_, _, let expression),
                .expression(let expression):
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

    private func validateCallArgumentLabels(
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

    private func validateCallArgumentLabels(
        in expression: Expression,
        environment: CallLabelValidationEnvironment,
        context: CallLabelValidationContext,
        fileName: String
    ) throws {
        switch expression {
        case .call(let name, let arguments):
            if let (baseName, memberName) = splitMemberName(name),
                baseName == "self",
                let currentConstructName = context.currentConstructName
            {
                let candidates = callLabelCandidates(
                    for: name,
                    environment: environment,
                    context: context
                )

                guard let candidates else {
                    throw SemanticValidationError(
                        "Call \(name)(\(renderCallArguments(arguments))) in \(fileName) is invalid because \(currentConstructName).\(memberName) is not a declared callable surface."
                    )
                }

                guard candidates.contains(where: { callArguments(arguments, match: $0.parameters) }) else {
                    throw SemanticValidationError(
                        "Call \(name)(\(renderCallArguments(arguments))) in \(fileName) does not match any available parameter labels. Expected one of: \(renderExpectedCallShapes(for: candidates))."
                    )
                }
            } else if let candidates = callLabelCandidates(
                for: name,
                environment: environment,
                context: context
            ), !candidates.isEmpty {
                guard candidates.contains(where: { callArguments(arguments, match: $0.parameters) }) else {
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
        case .integer, .double, .string, .boolean, .nilLiteral, .identifier, .bindingReference:
            break
        }
    }

    private func callLabelValidationEnvironment(
        from parsedFiles: [ParsedSourceFile],
        declarationGraph: DeclarationGraph
    )
        -> CallLabelValidationEnvironment
    {
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

    private func callLabelCandidates(
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

    private func callArguments(_ arguments: [CallArgument], match parameters: [NeatFunctionParameter])
        -> Bool
    {
        if arguments.count != parameters.count,
            parameters.contains(where: { !$0.macros.isEmpty }),
            arguments.allSatisfy({ $0.label == nil })
        {
            return true
        }

        let parameterSequence: [NeatFunctionParameter]

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
            guard arguments.count == parameters.count else { return false }
            parameterSequence = parameters
        }

        for (argument, parameter) in zip(arguments, parameterSequence) {
            if let actualLabel = argument.label {
                guard actualLabel == parameter.externalLabel else {
                    return false
                }
            }
        }
        return true
    }

    private func renderCallArguments(_ arguments: [CallArgument]) -> String {
        arguments.map { argument in
            if let label = argument.label {
                return "\(label): ..."
            }
            return "..."
        }.joined(separator: ", ")
    }

    private func renderExpectedCallShapes(for candidates: [CallLabelCandidate]) -> String {
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

    private func contextForSwitchCasePattern(
        _ pattern: SwitchCasePattern,
        base: CallLabelValidationContext
    ) -> CallLabelValidationContext {
        base
    }

    private func localCallableMap(_ callables: [CallableDeclaration]) -> [String: [CallLabelCandidate]]
    {
        Dictionary(
            grouping: callables.map {
                CallLabelCandidate(name: $0.name, parameters: $0.parameters)
            },
            by: \.name
        )
    }

    private func splitMemberName(_ name: String) -> (base: String, member: String)? {
        guard let dot = name.lastIndex(of: ".") else {
            return nil
        }

        let base = String(name[..<dot])
        let member = String(name[name.index(after: dot)...])
        guard !base.isEmpty, !member.isEmpty else {
            return nil
        }

        return (base, member)
    }

    private func validateBindingReferences(
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
            case .enumeration, .protocolDefinition, .macro, .extensions:
                break
            }
        }
    }

    private func validateBindingReferences(
        in declaration: ConstructDeclaration,
        declarationGraph: DeclarationGraph,
        fileName: String
    ) throws {
        let memberMutableNames =
            Set(declaration.states.map(\.name))
            .union(declaration.bindings.map(\.name))
            .union(declaration.environments.filter(\.isState).map(\.name))

        for derived in declaration.deriveds {
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

        for initializer in declaration.initializers {
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

        for callable in declaration.callables {
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

    private func bindingReferenceContext(
        mutableNames: Set<String>,
        selfAvailable: Bool,
        currentConstructName: String?,
        parameters: [NeatFunctionParameter]
    ) -> BindingReferenceContext {
        let parameterMutableNames = Set(parameters.filter(\.isBinding).map(\.localName))
        return BindingReferenceContext(
            mutableNames: mutableNames.union(parameterMutableNames),
            selfAvailable: selfAvailable,
            currentConstructName: currentConstructName
        )
    }

    private func validateBindingReferences(
        in statements: [Statement],
        declarationGraph: DeclarationGraph,
        context: BindingReferenceContext,
        fileName: String
    ) throws {
        var context = context

        for statement in statements {
            switch statement {
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
            case .environmentProvision(let provision):
                try validateBindingReferences(
                    in: provision.expression,
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

    private func validateBindingReferences(
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

    private func validateBindingReferences(
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

    private func bindingReferenceContext(
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

    private func validateValueBindings(in parsedFiles: [ParsedSourceFile]) throws {
        let bindingConstructNames = Set(
            parsedFiles
                .flatMap { declarations(in: $0.sourceFile) }
                .filter { !$0.bindings.isEmpty }
                .map(\.name)
        )

        guard !bindingConstructNames.isEmpty else { return }

        for parsedFile in parsedFiles {
            let fileName = lastPathComponent(of: parsedFile.path)

            switch parsedFile.sourceFile {
            case .construct(let declaration):
                try validateValueBindings(
                    in: declaration,
                    bindingConstructNames: bindingConstructNames,
                    fileName: fileName
                )
            case .module(let module):
                for declaration in module.constructs {
                    try validateValueBindings(
                        in: declaration,
                        bindingConstructNames: bindingConstructNames,
                        fileName: fileName
                    )
                }
                if let mainBlock = module.mainBlock {
                    try validateValueDeclarations(
                        in: mainBlock.body,
                        bindingConstructNames: bindingConstructNames,
                        fileName: fileName
                    )
                }
                for callable in module.callables {
                    if let body = callable.body {
                        try validateValueDeclarations(
                            in: body,
                            bindingConstructNames: bindingConstructNames,
                            fileName: fileName
                        )
                    }
                }
            case .mainBlock(let mainBlock):
                try validateValueDeclarations(
                    in: mainBlock.body,
                    bindingConstructNames: bindingConstructNames,
                    fileName: fileName
                )
            case .enumeration, .protocolDefinition, .macro, .extensions:
                break
            }
        }
    }

    private func validateValueBindings(
        in declaration: ConstructDeclaration,
        bindingConstructNames: Set<String>,
        fileName: String
    ) throws {
        for value in declaration.values {
            if let constructName = normalizedTypeName(value.typeName),
                bindingConstructNames.contains(constructName)
            {
                throw SemanticValidationError(
                    "value \(value.name): \(constructName) in construct \(declaration.name) (\(fileName)) is not allowed because \(constructName) declares binding members. Use state or a snapshot construct."
                )
            }
        }

        for derived in declaration.deriveds {
            if let body = derived.body {
                try validateValueDeclarations(
                    in: body,
                    bindingConstructNames: bindingConstructNames,
                    fileName: fileName
                )
            }
        }

        for initializer in declaration.initializers {
            if let body = initializer.body {
                try validateValueDeclarations(
                    in: body,
                    bindingConstructNames: bindingConstructNames,
                    fileName: fileName
                )
            }
        }

        for callable in declaration.callables {
            if let body = callable.body {
                try validateValueDeclarations(
                    in: body,
                    bindingConstructNames: bindingConstructNames,
                    fileName: fileName
                )
            }
        }
    }

    private func validateValueDeclarations(
        in statements: [Statement],
        bindingConstructNames: Set<String>,
        fileName: String
    ) throws {
        for statement in statements {
            switch statement {
            case .macroInvocation(_, _, let body):
                try validateValueDeclarations(
                    in: body,
                    bindingConstructNames: bindingConstructNames,
                    fileName: fileName
                )
            case .localBinding(let declaration):
                guard declaration.kind == .constant else { continue }
                let explicitType = normalizedTypeName(declaration.type.displayName)
                let inferredType = inferredConstructName(from: declaration.expression)
                let constructName = explicitType ?? inferredType
                if let constructName, bindingConstructNames.contains(constructName) {
                    throw SemanticValidationError(
                        "value \(declaration.name): \(constructName) in \(fileName) is not allowed because \(constructName) declares binding members. Use state or a snapshot construct."
                    )
                }
            case .derived(_, _, let body):
                try validateValueDeclarations(
                    in: body,
                    bindingConstructNames: bindingConstructNames,
                    fileName: fileName
                )
            case .localCallable(let declaration):
                try validateValueDeclarations(
                    in: declaration.body,
                    bindingConstructNames: bindingConstructNames,
                    fileName: fileName
                )
            case .background(let background):
                try validateValueDeclarations(
                    in: background.body,
                    bindingConstructNames: bindingConstructNames,
                    fileName: fileName
                )
            case .forEach(_, _, let body):
                try validateValueDeclarations(
                    in: body,
                    bindingConstructNames: bindingConstructNames,
                    fileName: fileName
                )
            case .whileLoop(_, let body):
                try validateValueDeclarations(
                    in: body,
                    bindingConstructNames: bindingConstructNames,
                    fileName: fileName
                )
            case .conditional(let branches):
                for branch in branches {
                    try validateValueDeclarations(
                        in: branch.body,
                        bindingConstructNames: bindingConstructNames,
                        fileName: fileName
                    )
                }
            case .switchStatement(_, let cases, let defaultBody):
                for switchCase in cases {
                    try validateValueDeclarations(
                        in: switchCase.body,
                        bindingConstructNames: bindingConstructNames,
                        fileName: fileName
                    )
                }
                if let defaultBody {
                    try validateValueDeclarations(
                        in: defaultBody,
                        bindingConstructNames: bindingConstructNames,
                        fileName: fileName
                    )
                }
            case .environmentProvision, .assignment, .compoundAssignment, .expression, .return,
                .break, .continue:
                continue
            }
        }
    }

    private func inferredConstructName(from expression: Expression) -> String? {
        guard case .call(let name, _) = expression else { return nil }
        return normalizedTypeName(name)
    }

    private func normalizedTypeName(_ raw: String) -> String? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        while text.hasSuffix("?") {
            text.removeLast()
        }
        if text.hasSuffix("...") {
            text.removeLast(3)
        }

        if let genericStart = text.firstIndex(of: "<") {
            text = String(text[..<genericStart])
        }

        if text.hasPrefix("[") || text.hasPrefix("(") {
            return nil
        }

        if let lastDot = text.lastIndex(of: ".") {
            text = String(text[text.index(after: lastDot)...])
        }

        return text.isEmpty ? nil : text
    }

    private func validateLiteralBridgeCompatibility(
        in parsedFiles: [ParsedSourceFile],
        registryView: DeclarationRegistryView,
        resolver: LiteralBridgeResolver,
        memberResolver: DeclarationMemberResolver,
        operatorResolver: DeclarationOperatorResolver
    ) throws {
        for parsedFile in parsedFiles {
            let fileName = lastPathComponent(of: parsedFile.path)

            switch parsedFile.sourceFile {
            case .construct(let declaration):
                try validateLiteralBridgeCompatibility(
                    in: declaration,
                    resolver: resolver,
                    memberResolver: memberResolver,
                    operatorResolver: operatorResolver,
                    fileName: fileName
                )
            case .module(let module):
                try validateLiteralBridgeCompatibility(
                    in: registryView.topLevelStates(inFilePath: parsedFile.path),
                    accessibleTypes: [:],
                    resolver: resolver,
                    memberResolver: memberResolver,
                    operatorResolver: operatorResolver,
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
                        fileName: fileName
                    )
                }

                for declaration in module.constructs {
                    try validateLiteralBridgeCompatibility(
                        in: declaration,
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

    private func validateLiteralBridgeCompatibility(
        in declaration: ConstructDeclaration,
        resolver: LiteralBridgeResolver,
        memberResolver: DeclarationMemberResolver,
        operatorResolver: DeclarationOperatorResolver,
        fileName: String
    ) throws {
        let environmentTypes = Dictionary(
            uniqueKeysWithValues: declaration.environments.map {
                ($0.name, BootstrapLiteralType.typed($0.type))
            }
        )

        try validateLiteralBridgeCompatibility(
            in: declaration.states,
            accessibleTypes: environmentTypes,
            resolver: resolver,
            memberResolver: memberResolver,
            operatorResolver: operatorResolver,
            fileName: fileName
        )

        let stateTypes = Dictionary(
            uniqueKeysWithValues: declaration.states.map {
                ($0.name, BootstrapLiteralType.typed($0.type))
            }
        )
        let accessibleTypes = stateTypes.merging(environmentTypes) { current, _ in current }

        for callable in declaration.callables {
            try validateLiteralBridgeCompatibility(
                in: callable,
                accessibleTypes: accessibleTypes,
                resolver: resolver,
                memberResolver: memberResolver,
                operatorResolver: operatorResolver,
                fileName: fileName
            )
        }
    }

    private func validateLiteralBridgeCompatibility(
        in states: [StateDeclaration],
        accessibleTypes initialAccessibleTypes: [String: BootstrapLiteralType],
        resolver: LiteralBridgeResolver,
        memberResolver: DeclarationMemberResolver,
        operatorResolver: DeclarationOperatorResolver,
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
                    resolver: resolver
                )
            {
                throw SemanticValidationError(
                    "state '\(state.name)' in \(fileName) expects \(state.type.displayName), got \(inferred.displayName)."
                )
            }

            accessibleTypes[state.name] = .typed(state.type)
        }
    }

    private func validateLiteralBridgeCompatibility(
        in callable: CallableDeclaration,
        accessibleTypes: [String: BootstrapLiteralType],
        resolver: LiteralBridgeResolver,
        memberResolver: DeclarationMemberResolver,
        operatorResolver: DeclarationOperatorResolver,
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
                    resolver: resolver
                )
            else {
                throw SemanticValidationError(
                    "Callable \(callable.name) in \(fileName) expects return type \(explicitReturnType.displayName), got \(inferred.displayName)."
                )
            }
        }
    }

    private func validateLiteralBridgeCompatibilityInLocalCallables(
        in statements: [Statement],
        accessibleTypes: [String: BootstrapLiteralType],
        resolver: LiteralBridgeResolver,
        memberResolver: DeclarationMemberResolver,
        operatorResolver: DeclarationOperatorResolver,
        fileName: String
    ) throws {
        for statement in statements {
            switch statement {
            case .localCallable(let declaration):
                try validateLiteralBridgeCompatibility(
                    in: CallableDeclaration(
                        macros: declaration.macros,
                        attribute: declaration.attribute,
                        targetType: nil,
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
                    fileName: fileName
                )
            case .background(let background):
                try validateLiteralBridgeCompatibilityInLocalCallables(
                    in: background.body,
                    accessibleTypes: accessibleTypes,
                    resolver: resolver,
                    memberResolver: memberResolver,
                    operatorResolver: operatorResolver,
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
                        fileName: fileName
                    )
                }
            case .localBinding, .environmentProvision, .assignment, .compoundAssignment,
                .expression, .return, .break, .continue:
                continue
            }
        }
    }

    private func validateCallableReturnSemantics(
        in parsedFiles: [ParsedSourceFile],
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

    private func validateCallableReturnSemantics(
        in declaration: ConstructDeclaration,
        resolver: LiteralBridgeResolver,
        memberResolver: DeclarationMemberResolver,
        operatorResolver: DeclarationOperatorResolver,
        fileName: String
    ) throws {
        let environmentTypes = Dictionary(
            uniqueKeysWithValues: declaration.environments.map {
                ($0.name, BootstrapLiteralType.typed($0.type))
            }
        )
        let stateTypes = Dictionary(
            uniqueKeysWithValues: declaration.states.map {
                ($0.name, BootstrapLiteralType.typed($0.type))
            }
        )
        let accessibleTypes = stateTypes.merging(environmentTypes) { current, _ in current }

        for callable in declaration.callables {
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

    private func validateCallableReturnSemantics(
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

    private func validateCallableReturnSemanticsInLocalCallables(
        in statements: [Statement],
        accessibleTypes: [String: BootstrapLiteralType],
        resolver: LiteralBridgeResolver,
        memberResolver: DeclarationMemberResolver,
        operatorResolver: DeclarationOperatorResolver,
        fileName: String
    ) throws {
        for statement in statements {
            switch statement {
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
            case .background(let background):
                try validateCallableReturnSemanticsInLocalCallables(
                    in: background.body,
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
                .expression, .return, .break, .continue:
                continue
            }
        }
    }

    private func collectReturnExpressions(in statements: [Statement]) -> [Expression?] {
        var expressions: [Expression?] = []

        for statement in statements {
            switch statement {
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
            case .localCallable:
                continue
            case .localBinding, .derived, .environmentProvision, .assignment, .compoundAssignment,
                .expression, .break, .continue:
                continue
            }
        }

        return expressions
    }

    private func callableRequiresValueReturn(
        explicitReturnType: TypeReference?,
        expectedReturnType: TypeReference?
    ) -> Bool {
        guard explicitReturnType != nil else { return false }
        guard let expectedReturnType else { return true }
        return !isVoidType(expectedReturnType)
    }

    private func isVoidType(_ typeReference: TypeReference) -> Bool {
        typeReference.displayName == "Void"
    }

    private func blockAlwaysReturnsValue(_ statements: [Statement]) -> Bool {
        for statement in statements {
            if statementAlwaysReturnsValue(statement) {
                return true
            }
        }
        return false
    }

    private func statementAlwaysReturnsValue(_ statement: Statement) -> Bool {
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
        case .background, .localCallable:
            return false
        default:
            return false
        }
    }

    private func renderCallableSignature(_ callable: CallableDeclaration) -> String {
        let rendered = callable.parameters.map(renderParameterSignature).joined(separator: ", ")
        if let targetType = callable.targetType {
            return "\(targetType.displayName)@\(callable.name)(\(rendered))"
        }
        return "@\(callable.name)(\(rendered))"
    }

    private func renderParameterSignature(_ parameter: NeatFunctionParameter) -> String {
        let typeName =
            parameter.slotName.map { "@\($0)" } ?? parameter.renderedTypeName
            ?? "_"
        if let externalLabel = parameter.externalLabel {
            if externalLabel == parameter.localName {
                return "\(parameter.localName): \(typeName)"
            }
            return "\(externalLabel) \(parameter.localName): \(typeName)"
        }
        return "\(parameter.localName): \(typeName)"
    }

    private func accessibleTypesForSwitchCasePattern(
        _ pattern: SwitchCasePattern,
        base: [String: BootstrapLiteralType]
    ) -> [String: BootstrapLiteralType] {
        guard case .enumCase(_, let binding?) = pattern else {
            return base
        }

        var extended = base
        extended[binding.name] = .typed(.named("Never"))
        return extended
    }

    private func declarations(in sourceFile: SourceFileNode) -> [ConstructDeclaration] {
        switch sourceFile {
        case .construct(let declaration):
            return [declaration]
        case .module(let module):
            return module.constructs
        case .mainBlock, .extensions, .enumeration, .protocolDefinition, .macro:
            return []
        }
    }

    private func topLevelStates(in sourceFile: SourceFileNode) -> [StateDeclaration] {
        switch sourceFile {
        case .module(let module):
            return module.states
        case .construct, .mainBlock, .extensions, .enumeration, .protocolDefinition, .macro:
            return []
        }
    }

    private func lastPathComponent(of path: String) -> String {
        URL(fileURLWithPath: path).lastPathComponent
    }
}
