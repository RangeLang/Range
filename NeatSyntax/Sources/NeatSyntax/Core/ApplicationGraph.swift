import Foundation

struct GraphCollector {
    private let declarationGraph: DeclarationGraph
    private let baseProgramGraph: ProgramGraph
    private let baseEntityIDs: Set<String>
    private let baseEdges: Set<ApplicationGraphEdge>
    private var nodesByID: [String: ApplicationGraphNode] = [:]
    private var edges: Set<ApplicationGraphEdge> = []
    private let registryView: DeclarationRegistryView
    private var resolutionIndex = DependencyResolutionIndex()
    private var flowState = DependencyFlowState()

    init(declarationGraph: DeclarationGraph) {
        self.declarationGraph = declarationGraph
        self.baseProgramGraph = declarationGraph.programGraph
        self.baseEntityIDs = Set(declarationGraph.programGraph.entities.map(\.id))
        self.baseEdges = Set(
            declarationGraph.programGraph.relations.compactMap { relation in
                guard let applicationKind = Self.applicationEdgeKind(for: relation.kind) else {
                    return nil
                }
                return ApplicationGraphEdge(
                    sourceID: relation.sourceID,
                    targetID: relation.targetID,
                    kind: applicationKind
                )
            }
        )
        self.registryView = declarationGraph.registryView
    }

    mutating func seedDeclarationProjection() {
        indexBaseProgramGraph()
    }

    mutating func resolveApplicationEdges() {
        addResolutionEdges()
    }

    func materialize() -> ApplicationGraph {
        let baseNodes = baseProgramGraph.entities.compactMap { entity in
            applicationNode(for: entity)
        }
        return ApplicationGraph(
            nodes: baseNodes + Array(nodesByID.values),
            edges: Array(baseEdges.union(edges))
        )
    }

    mutating func add(_ parsedFile: ParsedSourceFile) {
        let fileID = "file:\(parsedFile.path)"

        switch parsedFile.sourceFile {
        case .construct(let declaration):
            analyzeConstructDeclaration(declaration, parentID: fileID)
        case .enumeration, .protocolDefinition, .macro, .extensions:
            return
        case .module(let module):
            let topLevelStates = declarationGraph.topLevelStates(inFilePath: parsedFile.path)
            for state in topLevelStates {
                analyzeStateDeclaration(state, parentID: fileID)
            }
            for declaration in module.constructs {
                analyzeConstructDeclaration(declaration, parentID: fileID)
            }
            let moduleScope = MemoryScope(
                symbols: Dictionary(uniqueKeysWithValues: topLevelStates.map { state in
                    (state.name, "\(fileID)/state:\(state.name)")
                })
            )
            for callable in module.callables {
                analyzeCallableDeclaration(callable, parentID: fileID, scope: moduleScope)
            }

            if let mainBlock = module.mainBlock {
                analyzeMainBlock(
                    mainBlock,
                    parentID: fileID,
                    topLevelStates: topLevelStates
                )
            }
        case .mainBlock(let mainBlock):
            analyzeMainBlock(mainBlock, parentID: fileID, topLevelStates: [])
        }
    }

    private mutating func analyzeConstructDeclaration(
        _ declaration: ConstructDeclaration,
        parentID: String
    ) {
        let constructID = "\(parentID)/construct:\(declaration.name)"
        let bindings = declarationGraph.bindings(onConstruct: declaration.name)
        let deriveds = declarationGraph.deriveds(onConstruct: declaration.name)
        let environments = declarationGraph.environments(onConstruct: declaration.name)
        let states = declarationGraph.states(onConstruct: declaration.name)
        let values = declarationGraph.values(onConstruct: declaration.name)
        let initializers = declarationGraph.initializers(onConstruct: declaration.name)
        let callables = declarationGraph.callables(onConstruct: declaration.name)
        let scope = makeScope(
            bindings: bindings.map { ($0.name, "\(constructID)/binding:\($0.name)") },
            deriveds: deriveds.map { ($0.name, "\(constructID)/derived:\($0.name)") },
            environments: environments.map {
                ($0.name, "\(constructID)/environment:\($0.name)")
            },
            states: states.map { ($0.name, "\(constructID)/state:\($0.name)") },
            values: values.map { ($0.name, "\(constructID)/value:\($0.name)") },
            selfID: constructID
        )

        for binding in bindings where declarationGraph.hasConstruct(named: binding.typeName) {
            flowState.inferredConstructTypeByNodeID["\(constructID)/binding:\(binding.name)"] =
                binding.typeName
        }
        for value in values where declarationGraph.hasConstruct(named: value.typeName) {
            flowState.inferredConstructTypeByNodeID["\(constructID)/value:\(value.name)"] =
                value.typeName
        }
        for state in states {
            analyzeStateDeclaration(state, parentID: constructID)
        }
        for derived in deriveds {
            let derivedID = "\(constructID)/derived:\(derived.name)"
            if let body = derived.body {
                analyzeStatements(body, ownerID: derivedID, scope: scope)
            }
        }
        for initializer in initializers {
            let initializerID = "\(constructID)/init:\(renderParameterList(initializer.parameters))"
            var initializerScope = scope
            for parameter in initializer.parameters {
                let label = parameter.externalLabel ?? "_"
                let parameterID = "\(initializerID)/parameter:\(label):\(parameter.localName)"
                initializerScope.symbols[parameter.name] = parameterID
                if let typeReference = parameter.typeReference,
                    case .named(let name) = typeReference,
                    declarationGraph.hasConstruct(named: name)
                {
                    flowState.inferredConstructTypeByNodeID[parameterID] = name
                }
            }
            if let body = initializer.body {
                analyzeStatements(body, ownerID: initializerID, scope: initializerScope)
            }
        }
        for callable in callables {
            analyzeCallableDeclaration(callable, parentID: constructID, scope: scope)
        }
        for nested in declaration.constructs {
            analyzeConstructDeclaration(nested, parentID: constructID)
        }
    }

    private mutating func analyzeStateDeclaration(
        _ declaration: StateDeclaration,
        parentID: String
    ) {
        let stateID = "\(parentID)/state:\(declaration.name)"
        if case .stored(let expression) = declaration.storage {
            captureConstructType(for: stateID, from: expression)
            analyzeInitializer(expression, ownerID: stateID, scope: MemoryScope(), visitedCalls: [])
        }
    }

    private mutating func analyzeCallableDeclaration(
        _ declaration: CallableDeclaration,
        parentID: String,
        scope: MemoryScope
    ) {
        let callableID =
            "\(parentID)/function:\(declaration.name)(\(renderParameterList(declaration.parameters)))"
        var callableScope = scope
        for parameter in declaration.parameters {
            let label = parameter.externalLabel ?? "_"
            let parameterID = "\(callableID)/parameter:\(label):\(parameter.localName)"
            callableScope.symbols[parameter.name] = parameterID
            if let typeReference = parameter.typeReference,
                case .named(let name) = typeReference,
                declarationGraph.hasConstruct(named: name)
            {
                flowState.inferredConstructTypeByNodeID[parameterID] = name
            }
        }
        if let body = declaration.body {
            analyzeStatements(body, ownerID: callableID, scope: callableScope)
        }
    }

    private mutating func addNode(id: String, kind: ApplicationGraphNodeKind, label: String) {
        guard !baseEntityIDs.contains(id) else { return }
        nodesByID[id] = ApplicationGraphNode(id: id, kind: kind, label: label)
    }

    private mutating func addEdge(
        from sourceID: String, to targetID: String, kind: ApplicationGraphEdgeKind
    ) {
        let edge = ApplicationGraphEdge(sourceID: sourceID, targetID: targetID, kind: kind)
        guard !baseEdges.contains(edge) else { return }
        edges.insert(edge)
    }

    private mutating func addStorageTypeReference(_ reference: TypeReference, from sourceID: String)
    {
        let edgeKind: ApplicationGraphEdgeKind
        if case .named(let name) = reference,
            declarationGraph.hasConstruct(named: name),
            !declarationGraph.isCoreConstruct(named: name)
        {
            edgeKind = .referencesIdentity
        } else {
            edgeKind = .referencesType
        }

        let typeID = "type:\(reference.displayName)"
        addNode(id: typeID, kind: .typeReference, label: reference.displayName)
        addEdge(from: sourceID, to: typeID, kind: edgeKind)
    }

    private mutating func indexBaseProgramGraph() {
        for entity in baseProgramGraph.entities {
            guard let applicationKind = Self.applicationNodeKind(for: entity.kind) else {
                continue
            }
            registerDeclarationProjectionIfNeeded(
                entityID: entity.id,
                kind: applicationKind,
                label: entity.label
            )
        }
    }

    private func applicationNode(for entity: SemanticGraphEntity) -> ApplicationGraphNode? {
        guard let applicationKind = Self.applicationNodeKind(for: entity.kind) else {
            return nil
        }
        return ApplicationGraphNode(id: entity.id, kind: applicationKind, label: entity.label)
    }

    private static func applicationNodeKind(for kind: SemanticGraphEntityKind) -> ApplicationGraphNodeKind? {
        switch kind {
        case .file: return .file
        case .construct: return .construct
        case .enumeration: return .enumeration
        case .protocolDefinition: return .protocolDefinition
        case .macro: return .macro
        case .typeExtension: return .typeExtension
        case .mainBlock: return .mainBlock
        case .state: return .state
        case .environment: return .environment
        case .binding: return .binding
        case .derived: return .derived
        case .value: return .value
        case .initializer: return .initializer
        case .function: return .function
        case .parameter: return .parameter
        case .member: return .member
        case .typeReference: return .typeReference
        case .macroApplication: return .macroApplication
        case .localSymbol, .unresolved: return nil
        }
    }

    private static func applicationEdgeKind(for kind: SemanticGraphRelationKind) -> ApplicationGraphEdgeKind? {
        switch kind {
        case .contains: return .contains
        case .conformsTo: return .conformsTo
        case .extends: return .extends
        case .referencesType: return .referencesType
        case .referencesIdentity: return .referencesIdentity
        case .appliesMacro: return .appliesMacro
        case .targetsMacro: return .targetsMacro
        case .resolvesTo: return .resolvesTo
        case .dependsOn: return .dependsOn
        case .mutates: return .mutates
        case .aliases: return .aliases
        case .calls: return .calls
        }
    }

    private mutating func registerDeclarationProjectionIfNeeded(
        entityID: String,
        kind: ApplicationGraphNodeKind,
        label: String
    ) {
        switch kind {
        case .construct, .enumeration, .protocolDefinition, .macro:
            let name = declarationName(for: entityID, fallbackLabel: label)
            resolutionIndex.declarationProjectionNodeIDsByName[name, default: []].insert(entityID)
        case .function:
            guard
                let parentComponent = entityID.split(separator: "/").dropLast().last,
                parentComponent.hasPrefix("construct:")
            else {
                break
            }
            let constructName = String(parentComponent.dropFirst("construct:".count))
            resolutionIndex.constructCallableProjectionNodeIDs[constructName, default: [:]][label] =
                entityID
        default:
            break
        }
    }

    private func declarationName(for entityID: String, fallbackLabel: String) -> String {
        if let component = entityID.split(separator: "/").last {
            let raw = String(component)
            if let colonIndex = raw.firstIndex(of: ":") {
                return String(raw[raw.index(after: colonIndex)...])
            }
        }
        return fallbackLabel
    }

    private mutating func addResolutionEdges() {
        let typeNodes =
            baseProgramGraph.entities.compactMap { applicationNode(for: $0) }.filter {
                $0.kind == .typeReference
            }
            + nodesByID.values.filter { $0.kind == .typeReference }
        for typeNode in typeNodes {
            guard let targetNodeIDs = resolutionIndex.declarationProjectionNodeIDsByName[typeNode.label] else {
                continue
            }
            for targetNodeID in targetNodeIDs {
                addEdge(from: typeNode.id, to: targetNodeID, kind: .resolvesTo)
            }
        }
    }

    private mutating func analyzeMainBlock(
        _ mainBlock: MainBlockNode,
        parentID: String,
        topLevelStates: [StateDeclaration]
    ) {
        let mainID = "\(parentID)/main"
        var scope = MemoryScope()
        for state in topLevelStates {
            scope.symbols[state.name] = "\(parentID)/state:\(state.name)"
        }
        analyzeStatements(mainBlock.body, ownerID: mainID, scope: scope)
    }

    private mutating func analyzeStatements(
        _ statements: [Statement],
        ownerID: String,
        scope: MemoryScope,
        visitedCalls: Set<String> = []
    ) {
        var scope = scope
        for (index, statement) in statements.enumerated() {
            let statementID = "\(ownerID)/stmt:\(index)"
            switch statement {
            case .macroInvocation(_, _, let body):
                analyzeStatements(
                    body, ownerID: statementID, scope: scope, visitedCalls: visitedCalls)
            case .background(let background):
                analyzeStatements(
                    background.body, ownerID: statementID, scope: scope, visitedCalls: visitedCalls)
            case .localCallable(let declaration):
                let callableID = "\(statementID)/localCallable:\(declaration.name)"
                addNode(id: callableID, kind: .function, label: declaration.name)
                addEdge(from: ownerID, to: callableID, kind: .contains)
                analyzeStatements(
                    declaration.body, ownerID: callableID, scope: scope, visitedCalls: visitedCalls)
            case .localBinding(let declaration):
                let nodeKind: ApplicationGraphNodeKind =
                    declaration.kind == .mutable ? .state : .value
                let localID = "\(ownerID)/local:\(declaration.name)"
                addNode(id: localID, kind: nodeKind, label: declaration.name)
                addEdge(from: ownerID, to: localID, kind: .contains)
                addStorageTypeReference(declaration.type, from: localID)
                if declarationGraph.hasConstruct(named: declaration.type.displayName) {
                    flowState.inferredConstructTypeByNodeID[localID] = declaration.type.displayName
                }
                captureConstructType(for: localID, from: declaration.expression)
                scope.symbols[declaration.name] = localID
                analyzeInitializer(
                    declaration.expression,
                    ownerID: localID,
                    scope: scope,
                    visitedCalls: visitedCalls
                )

            case .derived(let name, let typeName, let body):
                let derivedID = "\(ownerID)/local-derived:\(name)"
                addNode(id: derivedID, kind: .derived, label: name)
                addEdge(from: ownerID, to: derivedID, kind: .contains)
                addStorageTypeReference(.named(typeName), from: derivedID)
                scope.symbols[name] = derivedID
                analyzeStatements(
                    body, ownerID: derivedID, scope: scope, visitedCalls: visitedCalls)

            case .assignment(let target, let expression):
                let targetID = resolveAssignmentTarget(target, scope: scope)
                addEdge(from: ownerID, to: targetID, kind: .mutates)
                if case .bindingReference(let name) = expression,
                    let sourceID = resolveSimpleName(name, scope: scope)
                {
                    addAlias(from: targetID, to: sourceID)
                } else {
                    analyzeExpression(
                        expression, ownerID: ownerID, scope: scope, visitedCalls: visitedCalls)
                }

            case .compoundAssignment(let target, _, let expression):
                let targetID = resolveAssignmentTarget(target, scope: scope)
                addEdge(from: ownerID, to: targetID, kind: .mutates)
                addEdge(from: ownerID, to: targetID, kind: .dependsOn)
                analyzeExpression(
                    expression, ownerID: ownerID, scope: scope, visitedCalls: visitedCalls)

            case .expression(let expression):
                analyzeExpression(
                    expression, ownerID: ownerID, scope: scope, visitedCalls: visitedCalls)

            case .forEach(let name, let sequence, let body):
                analyzeExpression(
                    sequence, ownerID: ownerID, scope: scope, visitedCalls: visitedCalls)
                let loopID = "\(statementID)/forEach:\(name)"
                addNode(id: loopID, kind: .value, label: name)
                addEdge(from: ownerID, to: loopID, kind: .contains)
                var loopScope = scope
                loopScope.symbols[name] = loopID
                analyzeStatements(
                    body, ownerID: ownerID, scope: loopScope, visitedCalls: visitedCalls)

            case .whileLoop(let condition, let body):
                analyzeExpression(
                    condition, ownerID: ownerID, scope: scope, visitedCalls: visitedCalls)
                analyzeStatements(body, ownerID: ownerID, scope: scope, visitedCalls: visitedCalls)

            case .conditional(let branches):
                for branch in branches {
                    if let condition = branch.condition {
                        analyzeExpression(
                            condition, ownerID: ownerID, scope: scope, visitedCalls: visitedCalls)
                    }
                    analyzeStatements(
                        branch.body, ownerID: ownerID, scope: scope, visitedCalls: visitedCalls)
                }

            case .return(let expression):
                if let expression {
                    analyzeExpression(
                        expression, ownerID: ownerID, scope: scope, visitedCalls: visitedCalls)
                }

            case .switchStatement(let expression, let cases, let defaultBody):
                analyzeExpression(
                    expression, ownerID: ownerID, scope: scope, visitedCalls: visitedCalls)
                for switchCase in cases {
                    analyzeSwitchCasePattern(
                        switchCase.pattern,
                        ownerID: ownerID,
                        scope: scope,
                        visitedCalls: visitedCalls
                    )
                    analyzeStatements(
                        switchCase.body, ownerID: ownerID, scope: scope, visitedCalls: visitedCalls)
                }
                if let defaultBody {
                    analyzeStatements(
                        defaultBody, ownerID: ownerID, scope: scope, visitedCalls: visitedCalls)
                }

            case .environmentProvision, .break, .continue:
                continue
            }
        }
    }

    private mutating func analyzeSwitchCasePattern(
        _ pattern: SwitchCasePattern,
        ownerID: String,
        scope: MemoryScope,
        visitedCalls: Set<String>
    ) {
        if case .expression(let expression) = pattern {
            analyzeExpression(
                expression,
                ownerID: ownerID,
                scope: scope,
                visitedCalls: visitedCalls
            )
        }
    }

    private mutating func analyzeInitializer(
        _ expression: Expression,
        ownerID: String,
        scope: MemoryScope,
        visitedCalls: Set<String>
    ) {
        analyzeExpression(expression, ownerID: ownerID, scope: scope, visitedCalls: visitedCalls)
        if case .bindingReference(let name) = expression,
            let sourceID = resolveSimpleName(name, scope: scope)
        {
            addAlias(from: ownerID, to: sourceID)
        }
        if case .call(let name, let arguments) = expression,
            declarationGraph.hasConstruct(named: name)
        {
            flowState.inferredConstructTypeByNodeID[ownerID] = name
            bindConstructArguments(
                ownerID: ownerID, constructName: name, arguments: arguments, scope: scope)
        }
    }

    private mutating func analyzeExpression(
        _ expression: Expression,
        ownerID: String,
        scope: MemoryScope,
        visitedCalls: Set<String>
    ) {
        switch expression {
        case .identifier(let name):
            if let resolved = resolvePath(name, scope: scope) {
                addEdge(from: ownerID, to: resolved, kind: .dependsOn)
            }
        case .bindingReference(let name):
            if let resolved = resolveSimpleName(name, scope: scope) {
                addEdge(from: ownerID, to: resolved, kind: .dependsOn)
            }
        case .macroInvocation(_, let arguments):
            for argument in arguments {
                analyzeExpression(
                    argument.value, ownerID: ownerID, scope: scope, visitedCalls: visitedCalls)
            }
        case .call(let name, let arguments):
            for argument in arguments {
                analyzeExpression(
                    argument.value, ownerID: ownerID, scope: scope, visitedCalls: visitedCalls)
            }
            analyzeCall(
                name: name, arguments: arguments, ownerID: ownerID, scope: scope,
                visitedCalls: visitedCalls)
        case .interpolatedString(let string):
            for segment in string.segments {
                if case .expression(let expression) = segment {
                    analyzeExpression(
                        expression, ownerID: ownerID, scope: scope, visitedCalls: visitedCalls)
                }
            }
        case .array(let elements):
            for element in elements {
                analyzeExpression(
                    element, ownerID: ownerID, scope: scope, visitedCalls: visitedCalls)
            }
        case .dictionary(let elements):
            for element in elements {
                analyzeExpression(
                    element.key, ownerID: ownerID, scope: scope, visitedCalls: visitedCalls)
                analyzeExpression(
                    element.value, ownerID: ownerID, scope: scope, visitedCalls: visitedCalls)
            }
        case .ternary(let condition, let trueExpression, let falseExpression):
            analyzeExpression(condition, ownerID: ownerID, scope: scope, visitedCalls: visitedCalls)
            analyzeExpression(
                trueExpression, ownerID: ownerID, scope: scope, visitedCalls: visitedCalls)
            analyzeExpression(
                falseExpression, ownerID: ownerID, scope: scope, visitedCalls: visitedCalls)
        case .unary(_, let expression):
            analyzeExpression(
                expression, ownerID: ownerID, scope: scope, visitedCalls: visitedCalls)
        case .binary(let lhs, _, let rhs):
            analyzeExpression(lhs, ownerID: ownerID, scope: scope, visitedCalls: visitedCalls)
            analyzeExpression(rhs, ownerID: ownerID, scope: scope, visitedCalls: visitedCalls)
        case .block:
            return
        case .integer, .double, .string, .boolean, .nilLiteral:
            return
        }
    }

    private mutating func analyzeCall(
        name: String,
        arguments: [CallArgument],
        ownerID: String,
        scope: MemoryScope,
        visitedCalls: Set<String>
    ) {
        let parts = name.split(separator: ".").map(String.init)
        guard parts.count >= 2 else { return }
        let basePath = parts.dropLast().joined(separator: ".")
        let methodName = parts.last ?? name
        guard let baseNodeID = resolvePath(basePath, scope: scope) else { return }
        let canonicalBaseID = resolvedAlias(of: baseNodeID)
        guard
            let constructName = flowState.inferredConstructTypeByNodeID[canonicalBaseID]
                ?? flowState.inferredConstructTypeByNodeID[baseNodeID]
        else {
            return
        }
        guard
            let callable = declarationGraph.callable(named: methodName, onConstruct: constructName),
            let callableNodeID = resolutionIndex.constructCallableProjectionNodeIDs[constructName]?[methodName]
        else {
            return
        }

        addEdge(from: ownerID, to: callableNodeID, kind: .calls)

        let callKey = "\(ownerID)->\(callableNodeID)->\(canonicalBaseID)"
        guard !visitedCalls.contains(callKey) else { return }

        var callableScope = scopeForConstructInstance(
            instanceNodeID: baseNodeID,
            constructName: constructName
        )
        for (index, parameter) in callable.parameters.enumerated() {
            let parameterID = "\(ownerID)/call:\(methodName)/parameter:\(parameter.name):\(index)"
            addNode(id: parameterID, kind: .parameter, label: parameter.name)
            addEdge(from: ownerID, to: parameterID, kind: .contains)
            callableScope.symbols[parameter.name] = parameterID
            if index < arguments.count {
                analyzeInitializer(
                    arguments[index].value,
                    ownerID: parameterID,
                    scope: scope,
                    visitedCalls: visitedCalls.union([callKey])
                )
            }
        }

        if let body = callable.body {
            analyzeStatements(
                body,
                ownerID: ownerID,
                scope: callableScope,
                visitedCalls: visitedCalls.union([callKey])
            )
        }
    }

    private mutating func bindConstructArguments(
        ownerID: String,
        constructName: String,
        arguments: [CallArgument],
        scope: MemoryScope
    ) {
        let memberKinds = declarationGraph.memberKinds(forConstruct: constructName)

        for argument in arguments {
            guard let label = argument.label, let kind = memberKinds[label] else { continue }
            let memberID = ensureMemberNode(baseID: ownerID, name: label, kind: kind)
            captureConstructTypeForMember(
                named: label,
                onConstruct: constructName,
                nodeID: memberID
            )
            if case .bindingReference(let name) = argument.value,
                let sourceID = resolveSimpleName(name, scope: scope)
            {
                addAlias(from: memberID, to: sourceID)
            } else if let resolved = resolveExpressionNode(argument.value, scope: scope) {
                addEdge(from: memberID, to: resolved, kind: .dependsOn)
            }
        }
    }

    private mutating func scopeForConstructInstance(
        instanceNodeID: String,
        constructName: String
    ) -> MemoryScope {
        var scope = MemoryScope()
        scope.symbols["self"] = instanceNodeID
        let memberKinds = declarationGraph.memberKinds(forConstruct: constructName)
        let constructTypedMembers = declarationGraph.constructTypedMemberNames(
            forConstruct: constructName
        )

        for (memberName, kind) in memberKinds {
            guard kind == .state else { continue }
            scope.symbols[memberName] = ensureMemberNode(
                baseID: instanceNodeID, name: memberName, kind: kind)
        }
        for (memberName, kind) in memberKinds {
            guard kind == .environment else { continue }
            scope.symbols[memberName] = ensureMemberNode(
                baseID: instanceNodeID, name: memberName, kind: kind)
        }
        for (memberName, kind) in memberKinds {
            guard kind == .binding || kind == .derived || kind == .value else { continue }
            let nodeID = ensureMemberNode(baseID: instanceNodeID, name: memberName, kind: kind)
            if let typeName = constructTypedMembers[memberName] {
                flowState.inferredConstructTypeByNodeID[nodeID] = typeName
            }
            scope.symbols[memberName] = nodeID
        }
        return scope
    }

    private mutating func captureConstructType(for nodeID: String, from expression: Expression) {
        guard case .call(let name, _) = expression, declarationGraph.hasConstruct(named: name) else {
            return
        }
        flowState.inferredConstructTypeByNodeID[nodeID] = name
    }

    private mutating func captureConstructTypeForMember(
        named memberName: String,
        onConstruct constructName: String,
        nodeID: String
    ) {
        if let typeName = declarationGraph.constructTypedMemberNames(
            forConstruct: constructName
        )[memberName] {
            flowState.inferredConstructTypeByNodeID[nodeID] = typeName
        }
    }

    private mutating func resolveAssignmentTarget(
        _ target: AssignmentTarget,
        scope: MemoryScope
    ) -> String {
        switch target {
        case .state(let name), .binding(let name), .environment(let name), .local(let name):
            return resolveSimpleName(name, scope: scope) ?? ensureFallbackNode(name: name)
        case .member(let base, let name):
            let baseID = resolveAssignmentTarget(base, scope: scope)
            return ensureMemberNode(baseID: baseID, name: name, kind: .member)
        }
    }

    private mutating func resolveExpressionNode(
        _ expression: Expression,
        scope: MemoryScope
    ) -> String? {
        switch expression {
        case .identifier(let name):
            return resolvePath(name, scope: scope)
        case .bindingReference(let name):
            return resolvePath(name, scope: scope)
        default:
            return nil
        }
    }

    private mutating func resolvePath(_ path: String, scope: MemoryScope) -> String? {
        let parts = path.split(separator: ".").map(String.init)
        guard let first = parts.first, var currentID = resolveSimpleName(first, scope: scope) else {
            return nil
        }
        for member in parts.dropFirst() {
            currentID = ensureMemberNode(baseID: currentID, name: member, kind: .member)
        }
        return currentID
    }

    private func resolveSimpleName(_ name: String, scope: MemoryScope) -> String? {
        scope.symbols[name]
    }

    private mutating func ensureMemberNode(
        baseID: String,
        name: String,
        kind: ApplicationGraphNodeKind
    ) -> String {
        let memberID = "\(baseID)/member:\(name)"
        if nodesByID[memberID] == nil {
            addNode(id: memberID, kind: kind, label: name)
            addEdge(from: baseID, to: memberID, kind: .contains)
        }

        let canonicalBaseID = resolvedAlias(of: baseID)
        if canonicalBaseID != baseID {
            let canonicalMemberID = ensureMemberNode(
                baseID: canonicalBaseID, name: name, kind: kind)
            addAlias(from: memberID, to: canonicalMemberID)
            if let constructName = flowState.inferredConstructTypeByNodeID[canonicalMemberID] {
                flowState.inferredConstructTypeByNodeID[memberID] = constructName
            }
        }

        return memberID
    }

    private mutating func addAlias(from sourceID: String, to targetID: String) {
        flowState.aliasTargetByNodeID[sourceID] = targetID
        addEdge(from: sourceID, to: targetID, kind: .aliases)
        if let constructName = flowState.inferredConstructTypeByNodeID[targetID] {
            flowState.inferredConstructTypeByNodeID[sourceID] = constructName
        }
    }

    private func resolvedAlias(of nodeID: String) -> String {
        var current = nodeID
        var seen: Set<String> = []
        while let next = flowState.aliasTargetByNodeID[current], !seen.contains(next) {
            seen.insert(current)
            current = next
        }
        return current
    }

    private mutating func ensureFallbackNode(name: String) -> String {
        let fallbackID = "unresolved:\(name)"
        if nodesByID[fallbackID] == nil {
            addNode(id: fallbackID, kind: .member, label: name)
        }
        return fallbackID
    }

    private func makeScope(
        bindings: [(String, String)],
        deriveds: [(String, String)],
        environments: [(String, String)],
        states: [(String, String)],
        values: [(String, String)],
        selfID: String? = nil
    ) -> MemoryScope {
        var scope = MemoryScope()
        if let selfID {
            scope.symbols["self"] = selfID
        }
        for (name, id) in states + environments + bindings + deriveds + values {
            scope.symbols[name] = id
        }
        return scope
    }

    private func renderParameterList(_ parameters: [NeatFunctionParameter]) -> String {
        parameters.map { parameter in
            let typeName =
                parameter.slotName.map { "@\($0)" } ?? parameter.typeReference?.displayName
                ?? "_"
            let label = parameter.externalLabel ?? "_"
            return "\(label):\(typeName)"
        }.joined(separator: ",")
    }
}
