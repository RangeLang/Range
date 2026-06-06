import Foundation

struct ParameterMacroSignature {
    let name: String
    let labels: [String?]
    let parameterMacrosByIndex: [Int: MacroDeclaration]
}

struct FunctionMacroSignature {
    let name: String
    let labels: [String?]
    let functionMacros: [MacroDeclaration]
}

enum MacroTargetKind: Hashable {
    case expression
    case parameter
    case initializer
    case state
    case immutable
    case binding
    case derived
    case property
    case block
    case function
    case construct
    case enumeration
    case protocolDefinition
    case typeExtension
    case other(String)
}

func macroTargetKind(for macro: MacroDeclaration) -> MacroTargetKind {
    guard let target = macro.target else {
        return .other("__freestanding")
    }
    let kinds = macroTargetKinds(for: target)
    for kind in macroTargetKindPriority() where kinds.contains(kind) {
        return kind
    }
    return kinds.first ?? .other("__unknown")
}

func macroTargetKindPriority() -> [MacroTargetKind] {
    [
        .block,
        .expression,
        .parameter,
        .initializer,
        .state,
        .immutable,
        .binding,
        .derived,
        .property,
        .function,
        .construct,
        .enumeration,
        .protocolDefinition,
        .typeExtension,
    ]
}

func syntaxSurfaceTargetKinds() -> Set<MacroTargetKind> {
    [
        .expression,
        .parameter,
        .initializer,
        .state,
        .immutable,
        .binding,
        .derived,
        .property,
        .block,
        .function,
        .construct,
        .enumeration,
        .protocolDefinition,
        .typeExtension,
    ]
}

func macroTargetKind(for typeReference: TypeReference) -> MacroTargetKind {
    let name: String
    switch typeReference {
    case .named(let named):
        name = named
    case .member(_, let member):
        name = member
    case .generic(let base, _):
        return macroTargetKind(for: base)
    case .array, .function, .optional, .variadic:
        name = typeReference.displayName
    }

    switch name {
    case "@expression":
        return .expression
    case "@parameter":
        return .parameter
    case "@init":
        return .initializer
    case "@state":
        return .state
    case "@let":
        return .immutable
    case "@binding":
        return .binding
    case "@derived":
        return .derived
    case "@property":
        return .property
    case "@block":
        return .block
    case "@function":
        return .function
    case "@construct":
        return .construct
    case "@enum":
        return .enumeration
    case "@protocol":
        return .protocolDefinition
    case "@extension":
        return .typeExtension
    case "Expression":
        return .expression
    case "Parameter":
        return .parameter
    case "Init":
        return .initializer
    case "State":
        return .state
    case "Let":
        return .immutable
    case "Binding":
        return .binding
    case "Derived":
        return .derived
    case "Function":
        return .function
    case "Block":
        return .block
    case "Construct":
        return .construct
    case "Enum":
        return .enumeration
    case "Protocol":
        return .protocolDefinition
    case "Extension":
        return .typeExtension
    default:
        return .other(name)
    }
}


func macroTargetKinds(for target: MacroTarget) -> Set<MacroTargetKind> {
    switch target {
    case .syntax(let typeReference):
        return [macroTargetKind(for: typeReference)]
    case .macroSurface(let name):
        if name == "syntax" {
            return syntaxSurfaceTargetKinds()
        }
        return [macroSurfaceTargetKind(named: name)]
    case .anyOf(let targets), .allOf(let targets):
        return Set(targets.flatMap { macroTargetKinds(for: $0) })
    }
}

func macroTargetAllows(_ target: MacroTarget, kind: MacroTargetKind) -> Bool {
    switch target {
    case .syntax(let typeReference):
        return macroTargetKind(for: typeReference) == kind
    case .macroSurface(let name):
        return name == "syntax" ? syntaxSurfaceTargetKinds().contains(kind) : macroSurfaceTargetKind(named: name) == kind
    case .anyOf(let targets):
        return targets.contains { macroTargetAllows($0, kind: kind) }
    case .allOf(let targets):
        return targets.allSatisfy { macroTargetAllows($0, kind: kind) }
    }
}

func macroTargetAllowsAny(_ target: MacroTarget, kinds: Set<MacroTargetKind>) -> Bool {
    kinds.contains { macroTargetAllows(target, kind: $0) }
}

func macroSurfaceTargetKind(named name: String) -> MacroTargetKind {
    switch name {
    case "expression":
        return .expression
    case "parameter":
        return .parameter
    case "init":
        return .initializer
    case "state":
        return .state
    case "let":
        return .immutable
    case "binding":
        return .binding
    case "derived":
        return .derived
    case "property":
        return .property
    case "block":
        return .block
    case "function":
        return .function
    case "construct":
        return .construct
    case "enum":
        return .enumeration
    case "protocol":
        return .protocolDefinition
    case "extension":
        return .typeExtension
    default:
        return .other("@\(name)")
    }
}

func indexedReference(
    _ identifier: String,
    prefix: String,
    suffix: String
) -> Int? {
    guard identifier.hasPrefix(prefix), identifier.hasSuffix(suffix) else {
        return nil
    }
    let start = identifier.index(identifier.startIndex, offsetBy: prefix.count)
    let end = identifier.index(identifier.endIndex, offsetBy: -suffix.count)
    guard start <= end else {
        return nil
    }
    return Int(identifier[start..<end])
}

struct MacroRealizationView {
    let parameterMacroSignatures: [ParameterMacroSignature]
    let functionMacroSignatures: [FunctionMacroSignature]
    let realizedLiteralBridges: [RealizedLiteralBridge]
    let realizedInitMacroTargets: [RealizedInitMacroTarget]
}

struct MacroRegistryView {
    let macrosByName: [String: MacroDeclaration]

    func firstMacro(
        in applications: [MacroApplication],
        targetKind: MacroTargetKind
    ) -> MacroDeclaration? {
        applications.lazy.compactMap { macrosByName[$0.name] }.first(where: {
            macroTargetAllows($0.target!, kind: targetKind)
        })
    }

    func macros(
        in applications: [MacroApplication],
        targetKind: MacroTargetKind
    ) -> [MacroDeclaration] {
        applications.compactMap { application in
            guard let macro = macrosByName[application.name], macroTargetAllows(macro.target!, kind: targetKind)
            else {
                return nil
            }

            return macro
        }
    }
}

struct RewriteSurfaceView {
    let syntaxResolver: DeclarationSyntaxResolver
    let constructsByName: [String: ConstructDeclaration]

    func emittedSyntaxKinds(
        forTargetPath path: String,
        targetBinding: String,
        targetType: TypeReference
    ) -> Set<EmittedSyntaxKind>? {
        guard path == targetBinding || path.hasPrefix("\(targetBinding).") else {
            return nil
        }
        guard let semanticType = semanticType(
            ofTargetPath: path,
            targetBinding: targetBinding,
            targetType: targetType
        ) else {
            return nil
        }
        return emittedSyntaxKinds(forSemanticType: semanticType)
    }

    func allowedPaths(
        targetBinding: String,
        targetType: TypeReference
    ) -> Set<String> {
        if macroTargetKind(for: targetType) == .initializer {
            return [
                "\(targetBinding).application.replace",
                "\(targetBinding).application.arguments[].expression.replace",
            ]
        }

        guard var targetName = syntaxResolver.nominalName(of: targetType) else {
            return []
        }
        if targetName.hasPrefix("@"),
            let syntaxTypeName = syntaxResolver.syntaxTypeName(forSurface: String(targetName.dropFirst()))
        {
            targetName = syntaxTypeName
        }

        var paths: Set<String> = []

        func supportsRewrite(_ typeName: String) -> Bool {
            syntaxResolver.declaration(named: typeName, conformsTo: "SyntaxReplaceable")
        }

        func resolvedValueType(
            named rawTypeName: String,
            ownerTypeName: String
        ) -> (typeName: String, isArray: Bool)? {
            var text = rawTypeName.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.hasSuffix("?") {
                text.removeLast()
                text = text.trimmingCharacters(in: .whitespacesAndNewlines)
            }

            let isArray = text.hasPrefix("[") && text.hasSuffix("]")
            if isArray {
                text.removeFirst()
                text.removeLast()
                text = text.trimmingCharacters(in: .whitespacesAndNewlines)
            }

            let qualifiedNestedName = "\(ownerTypeName).\(text)"
            if constructsByName[qualifiedNestedName] != nil {
                return (qualifiedNestedName, isArray)
            }

            if constructsByName[text] != nil {
                return (text, isArray)
            }

            if syntaxResolver.declarationIsSyntaxBoundary(named: text)
                || syntaxResolver.declaration(named: text, conformsTo: "SyntaxReplaceable")
                || syntaxResolver.declaration(named: text, conformsTo: "SyntaxExpandable")
                || syntaxResolver.declaration(named: text, conformsTo: "SyntaxOmittable")
            {
                return (text, isArray)
            }

            return nil
        }

        func collectRewritePaths(
            for typeName: String,
            path: String,
            activeTypes: Set<String>
        ) {
            if supportsRewrite(typeName) {
                paths.insert("\(path).replace")
            }

            guard !activeTypes.contains(typeName) else {
                return
            }

            guard let construct = constructsByName[typeName] else {
                return
            }

            let nextActiveTypes = activeTypes.union([typeName])

            for value in construct.values {
                guard let resolvedType = resolvedValueType(
                    named: value.typeName,
                    ownerTypeName: typeName
                ) else {
                    continue
                }

                let valuePath = "\(path).\(value.name)"
                if resolvedType.isArray {
                    collectRewritePaths(
                        for: resolvedType.typeName,
                        path: "\(valuePath)[]",
                        activeTypes: nextActiveTypes
                    )
                } else {
                    collectRewritePaths(
                        for: resolvedType.typeName,
                        path: valuePath,
                        activeTypes: nextActiveTypes
                    )
                }
            }
        }

        collectRewritePaths(for: targetName, path: targetBinding, activeTypes: [])
        return paths
    }

    func declaredRewritePathExists(
        _ normalizedPath: String,
        targetBinding: String,
        targetType: TypeReference
    ) -> Bool {
        if macroTargetKind(for: targetType) == .initializer {
            return normalizedPath == "\(targetBinding).application.replace"
                || normalizedPath == "\(targetBinding).application.arguments[].expression.replace"
        }

        guard var targetName = syntaxResolver.nominalName(of: targetType) else {
            return false
        }
        if targetName.hasPrefix("@"),
            let syntaxTypeName = syntaxResolver.syntaxTypeName(forSurface: String(targetName.dropFirst()))
        {
            targetName = syntaxTypeName
        }

        let directPath = "\(targetBinding).replace"
        if normalizedPath == directPath {
            return syntaxResolver.declaration(named: targetName, conformsTo: "SyntaxReplaceable")
        }

        let prefix = "\(targetBinding)."
        let suffix = ".replace"
        guard normalizedPath.hasPrefix(prefix), normalizedPath.hasSuffix(suffix) else {
            return false
        }

        let start = normalizedPath.index(normalizedPath.startIndex, offsetBy: prefix.count)
        let end = normalizedPath.index(normalizedPath.endIndex, offsetBy: -suffix.count)
        let memberPath = normalizedPath[start..<end]
        guard !memberPath.isEmpty else {
            return false
        }

        var currentTypeName = targetName
        for rawSegment in memberPath.split(separator: ".") {
            var segment = String(rawSegment)
            let expectsArray = segment.hasSuffix("[]")
            if expectsArray {
                segment.removeLast(2)
            }

            guard
                let currentConstruct = constructsByName[currentTypeName],
                let value = currentConstruct.values.first(where: { $0.name == segment }),
                let resolvedType = resolvedDeclaredValueType(
                    named: value.typeName,
                    ownerTypeName: currentTypeName
                )
            else {
                return false
            }

            if expectsArray != resolvedType.isArray {
                return false
            }

            currentTypeName = resolvedType.typeName
        }

        return syntaxResolver.declaration(named: currentTypeName, conformsTo: "SyntaxReplaceable")
    }

    func declaredExpansionPathExists(
        _ path: String,
        targetBinding: String,
        targetType: TypeReference
    ) -> Bool {
        guard
            let semanticType = semanticType(
                ofTargetPath: path,
                targetBinding: targetBinding,
                targetType: targetType
            ),
            let semanticName = syntaxResolver.nominalName(of: semanticType)
        else {
            return false
        }

        return syntaxResolver.declaration(named: semanticName, conformsTo: "SyntaxExpandable")
    }

    private func resolvedDeclaredValueType(
        named rawTypeName: String,
        ownerTypeName: String
    ) -> (typeName: String, isArray: Bool)? {
        var text = rawTypeName.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasSuffix("?") {
            text.removeLast()
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let isArray = text.hasPrefix("[") && text.hasSuffix("]")
        if isArray {
            text.removeFirst()
            text.removeLast()
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let qualifiedNestedName = "\(ownerTypeName).\(text)"
        if constructsByName[qualifiedNestedName] != nil {
            return (qualifiedNestedName, isArray)
        }

        if constructsByName[text] != nil {
            return (text, isArray)
        }

        if syntaxResolver.declarationIsSyntaxBoundary(named: text)
            || syntaxResolver.declaration(named: text, conformsTo: "SyntaxReplaceable")
            || syntaxResolver.declaration(named: text, conformsTo: "SyntaxExpandable")
            || syntaxResolver.declaration(named: text, conformsTo: "SyntaxOmittable")
        {
            return (text, isArray)
        }

        return nil
    }

    private func semanticType(
        ofTargetPath path: String,
        targetBinding: String,
        targetType: TypeReference
    ) -> TypeReference? {
        guard let targetName = syntaxResolver.nominalName(of: targetType) else {
            return nil
        }
        guard path != targetBinding else {
            return targetType
        }

        let prefix = "\(targetBinding)."
        guard path.hasPrefix(prefix) else {
            return nil
        }

        let start = path.index(path.startIndex, offsetBy: prefix.count)
        let memberPath = path[start...]
        var currentTypeName = targetName
        var currentType: TypeReference = targetType

        for segment in memberPath.split(separator: ".").map(String.init) {
            guard let currentConstruct = constructsByName[currentTypeName] else {
                return nil
            }
            guard let value = currentConstruct.values.first(where: { $0.name == segment }) else {
                return nil
            }
            guard let valueType = parseCoreTypeReference(value.typeName) else {
                return nil
            }

            currentType = resolveGenericType(valueType, in: currentConstruct)

            if let nextTypeName = resolvedNominalTypeName(
                for: currentType,
                ownerTypeName: currentTypeName
            ) {
                currentTypeName = nextTypeName
                if case .named = currentType {
                    currentType = .named(nextTypeName)
                }
            }
        }

        return currentType
    }

    private func parseCoreTypeReference(_ typeName: String) -> TypeReference? {
        var parser: Parser
        do {
            parser = try Parser(source: typeName)
            return try parser.parseTypeReferenceNode()
        } catch {
            return nil
        }
    }

    private func resolveGenericType(
        _ typeReference: TypeReference,
        in construct: ConstructDeclaration
    ) -> TypeReference {
        guard case .named(let name) = typeReference else {
            return typeReference
        }

        for parameter in construct.genericParameters {
            guard case .type(let parameterName, let constraint, _) = parameter,
                parameterName == name
            else {
                continue
            }
            return constraint ?? typeReference
        }

        return typeReference
    }

    private func resolvedNominalTypeName(
        for typeReference: TypeReference,
        ownerTypeName: String
    ) -> String? {
        guard let nominalName = syntaxResolver.nominalName(of: typeReference) else {
            return nil
        }

        let qualifiedNestedName = "\(ownerTypeName).\(nominalName)"
        if constructsByName[qualifiedNestedName] != nil {
            return qualifiedNestedName
        }

        if constructsByName[nominalName] != nil {
            return nominalName
        }

        return nil
    }

    func emittedSyntaxKinds(forSemanticType typeReference: TypeReference) -> Set<
        EmittedSyntaxKind
    > {
        guard let semanticName = syntaxResolver.nominalName(of: typeReference) else {
            return [.expression]
        }

        if semanticName == "Identifier" {
            return [.callableName, .declaration]
        }

        if semanticName == "NominalTypeReference"
            || syntaxResolver.declaration(named: semanticName, conformsTo: "NominalTypeReference")
        {
            return [.nominalTypeReference, .typeReference]
        }

        if semanticName == "TypeReference"
            || syntaxResolver.declaration(named: semanticName, conformsTo: "TypeReference")
        {
            return [.typeReference]
        }

        if semanticName == "Expression"
            || syntaxResolver.declaration(named: semanticName, conformsTo: "Expression")
        {
            return [.expression]
        }

        if syntaxResolver.declaration(named: semanticName, conformsTo: "SyntaxEmittable") {
            return [.declaration]
        }

        return [.expression]
    }
}

struct RewriteSiteDescriptor {
    let normalizedPath: String
    let site: ResolvedRewriteSite
}

struct MacroExpansionContext {
    let macroRealizationView: MacroRealizationView
    let rewriteSurfaceView: RewriteSurfaceView
    let graphContext: MacroGraphContext
    let macroDeclarationsByName: [String: MacroDeclaration]
    let macroMetadataByName: [String: MacroMetadataDeclaration]
    let diagnosticEngine: RangeDiagnosticEngine?
    let currentPath: String?

    func withCurrentPath(_ path: String) -> MacroExpansionContext {
        MacroExpansionContext(
            macroRealizationView: macroRealizationView,
            rewriteSurfaceView: rewriteSurfaceView,
            graphContext: graphContext,
            macroDeclarationsByName: macroDeclarationsByName,
            macroMetadataByName: macroMetadataByName,
            diagnosticEngine: diagnosticEngine,
            currentPath: path
        )
    }

    func propertyMacroTargetMatches(
        _ macro: MacroDeclaration,
        propertyTypeName: String,
        propertyValueType: TypeReference
    ) -> Bool {
        let actualTargetType = TypeReference.generic(
            base: .named(propertyTypeName),
            arguments: [propertyValueType]
        )

        let matcher = MacroTargetTypeMatcher(
            syntaxResolver: rewriteSurfaceView.syntaxResolver,
            genericParameters: macro.genericParameters
        )

        return matcher.matches(
            actual: actualTargetType,
            expected: macro.target!
        )
    }

    func propertyMacroMetadataTargetMatches(
        _ metadata: MacroMetadataDeclaration,
        propertyTypeName: String,
        propertyValueType: TypeReference
    ) -> Bool {
        let actualTargetType = TypeReference.generic(
            base: .named(propertyTypeName),
            arguments: [propertyValueType]
        )

        let matcher = MacroTargetTypeMatcher(
            syntaxResolver: rewriteSurfaceView.syntaxResolver,
            genericParameters: metadata.genericParameters
        )

        return matcher.matches(
            actual: actualTargetType,
            expected: metadata.target
        )
    }

    func validateRewriteSites(
        for macro: MacroDeclaration,
        targetKind: MacroTargetKind,
        operationExpressions: [Expression],
        acceptsResolvedRewrite: (Expression) -> Bool
    ) throws {
        let targetBinding = macro.bindings!.target
        let targetPrefix = "\(targetBinding)."
        let allowedPaths = rewriteSurfaceView.allowedPaths(
            targetBinding: targetBinding,
            targetType: macro.target!.typeReference
        )

        var invalidPaths: [String] = []
        for expression in operationExpressions {
            guard case .call(let name, let arguments) = expression, arguments.count == 1 else {
                continue
            }
            guard name.hasPrefix(targetPrefix), name.hasSuffix(".replace") else {
                continue
            }

            guard
                let normalizedPath = normalizedRewritePath(name, targetBinding: targetBinding),
                acceptsResolvedRewrite(expression),
                rewriteSurfaceView.declaredRewritePathExists(
                    normalizedPath,
                    targetBinding: targetBinding,
                    targetType: macro.target!.typeReference
                )
            else {
                invalidPaths.append(name)
                continue
            }
        }

        guard invalidPaths.isEmpty else {
            let allowedDescription: String
            if allowedPaths.isEmpty {
                allowedDescription = "no replace paths"
            } else {
                allowedDescription = allowedPaths.sorted().joined(separator: ", ")
            }
            throw ParseError(
                "Macro @\(macro.name) targeting \(macro.target!.displayName) uses unsupported replace site '\(invalidPaths[0])'. Allowed: \(allowedDescription)."
            )
        }
    }

    func validateExpansionPath(
        _ path: String,
        for macro: MacroDeclaration
    ) throws {
        guard rewriteSurfaceView.declaredExpansionPathExists(
            path,
            targetBinding: macro.bindings!.target,
            targetType: macro.target!.typeReference
        ) else {
            throw ParseError(
                "Macro @\(macro.name) targeting \(macro.target!.displayName) uses unsupported expand site '\(path).expand'."
            )
        }
    }

    private func normalizedRewritePath(
        _ name: String,
        targetBinding: String
    ) -> String? {
        let directPath = "\(targetBinding).replace"
        if name == directPath {
            return directPath
        }

        let prefix = "\(targetBinding)."
        let suffix = ".replace"
        guard name.hasPrefix(prefix), name.hasSuffix(suffix) else {
            return nil
        }

        let start = name.index(name.startIndex, offsetBy: prefix.count)
        let end = name.index(name.endIndex, offsetBy: -suffix.count)
        guard start <= end else {
            return nil
        }

        let raw = name[start..<end]
        if raw.isEmpty {
            return directPath
        }

        var normalized = ""
        var index = raw.startIndex
        while index < raw.endIndex {
            let character = raw[index]
            if character == "[" {
                normalized += "[]"
                while index < raw.endIndex, raw[index] != "]" {
                    index = raw.index(after: index)
                }
                if index < raw.endIndex {
                    index = raw.index(after: index)
                }
                continue
            }

            normalized.append(character)
            index = raw.index(after: index)
        }

        return "\(targetBinding).\(normalized).replace"
    }

    func resolvedRewriteCall(
        from expression: Expression,
        targetBinding: String,
        targetType: TypeReference
    ) -> ResolvedRewriteCall? {
        guard
            case .call(let name, let arguments) = expression,
            let payload = arguments.first(where: { $0.label == "with" })?.value
                ?? (arguments.count == 1 ? arguments[0].value : nil)
        else {
            return nil
        }

        guard
            let normalizedPath = normalizedRewritePath(name, targetBinding: targetBinding)
        else {
            return nil
        }

        if normalizedPath == "\(targetBinding).replace",
            rewriteSurfaceView.allowedPaths(targetBinding: targetBinding, targetType: targetType)
                .contains(normalizedPath)
        {
            return ResolvedRewriteCall(site: .targetDirect, payload: payload)
        }

        guard let descriptor = rewriteSurfaceView.rewriteSiteDescriptors(
            targetBinding: targetBinding,
            targetType: targetType
        ).first(where: { $0.normalizedPath == normalizedPath }) else {
            return nil
        }

        return ResolvedRewriteCall(site: descriptor.site, payload: payload)
    }
}

struct MacroGraphContext {
    let declarationsByID: [String: CompileTimeValue]
    let membersByID: [String: [CompileTimeValue]]
    let parentByID: [String: CompileTimeValue]
    let macrosByID: [String: [CompileTimeValue]]
    let macrosByName: [String: [CompileTimeValue]]
    let main: CompileTimeValue
    let writtenSyntaxByID: [String: CompileTimeValue]
    let sourcePathByID: [String: String]
    let sourceDirectoryByID: [String: String]

    init(
        declarationGraph: DeclarationGraph,
        macroDeclarationsByName: [String: MacroDeclaration],
        macroMetadataDeclarationsByName: [String: MacroMetadataDeclaration]
    ) {
        let writtenSyntaxByID = Self.writtenSyntaxByID(for: declarationGraph)
        let sourcePathByID = Self.sourcePathByID(for: declarationGraph)
        let sourceDirectoryByID = sourcePathByID.mapValues(Self.directoryPath(for:))
        let builder = MacroTargetValueBuilder(
            macroDeclarationsByName: macroDeclarationsByName,
            macroMetadataByName: macroMetadataDeclarationsByName,
            writtenSyntaxByID: writtenSyntaxByID
        )
        var declarationsByID: [String: CompileTimeValue] = [:]
        var membersByID: [String: [CompileTimeValue]] = [:]
        var parentByID: [String: CompileTimeValue] = [:]
        var macrosByID: [String: [CompileTimeValue]] = [:]
        var macrosByName: [String: [CompileTimeValue]] = [:]
        var main: CompileTimeValue = .nilValue

        func recordMacros(_ macros: [CompileTimeValue], id: String) {
            macrosByID[id] = macros
            for macro in macros {
                guard let name = Self.applicationIdentifierName(macro) else {
                    continue
                }
                macrosByName[name, default: []].append(macro)
            }
        }

        for construct in declarationGraph.constructsByName.values {
            let constructID = "construct:\(construct.name)"
            let constructValue = builder.declarationValue(for: construct, qualifiedName: construct.name)
            declarationsByID[constructID] = constructValue
            recordMacros(Self.macroValues(from: constructValue), id: constructID)

            var members: [CompileTimeValue] = []
            let constructIdentity = builder.graphIdentity(kind: "construct", name: construct.name)
            for value in construct.values {
                let id = "let:\(construct.name).\(value.name)"
                let valueValue = builder.value(for: value, ownerConstructName: construct.name)
                declarationsByID[id] = valueValue
                parentByID[id] = constructIdentity
                recordMacros(Self.macroValues(from: valueValue), id: id)
                members.append(builder.graphIdentity(kind: "let", name: "\(construct.name).\(value.name)"))
            }
            for state in construct.states {
                let id = "state:\(construct.name).\(state.name)"
                let stateValue = builder.value(for: state, ownerConstructName: construct.name)
                declarationsByID[id] = stateValue
                parentByID[id] = constructIdentity
                recordMacros(Self.macroValues(from: stateValue), id: id)
                members.append(builder.graphIdentity(kind: "state", name: "\(construct.name).\(state.name)"))
            }
            for binding in construct.bindings {
                let id = "binding:\(construct.name).\(binding.name)"
                let bindingValue = builder.value(for: binding, ownerConstructName: construct.name)
                declarationsByID[id] = bindingValue
                parentByID[id] = constructIdentity
                recordMacros(Self.macroValues(from: bindingValue), id: id)
                members.append(builder.graphIdentity(kind: "binding", name: "\(construct.name).\(binding.name)"))
            }
            for derived in construct.deriveds {
                let id = "derived:\(construct.name).\(derived.name)"
                let derivedValue = builder.value(for: derived, ownerConstructName: construct.name)
                declarationsByID[id] = derivedValue
                parentByID[id] = constructIdentity
                recordMacros(Self.macroValues(from: derivedValue), id: id)
                members.append(builder.graphIdentity(kind: "derived", name: "\(construct.name).\(derived.name)"))
            }
            for initializer in construct.initializers {
                let name = "init"
                let id = "init:\(construct.name).\(name)"
                let initializerValue = builder.value(for: initializer)
                declarationsByID[id] = initializerValue
                recordMacros(Self.macroValues(from: initializerValue), id: id)
                members.append(builder.graphIdentity(kind: "init", name: "\(construct.name).\(name)"))
            }
            for callable in construct.callables {
                let id = "function:\(construct.name).\(callable.name)"
                let callableValue = builder.value(for: callable)
                declarationsByID[id] = callableValue
                recordMacros(Self.macroValues(from: callableValue), id: id)
                members.append(builder.graphIdentity(kind: "function", name: "\(construct.name).\(callable.name)"))
            }
            for nested in construct.constructs {
                members.append(builder.graphIdentity(kind: "construct", name: "\(construct.name).\(nested.name)"))
            }
            membersByID[constructID] = members
        }

        for extensionDeclaration in declarationGraph.extensionsByTargetName.values.flatMap({ $0 }) {
            let extensionID = "extension:\(extensionDeclaration.targetType.displayName)"
            let extensionValue = builder.value(for: extensionDeclaration)
            declarationsByID[extensionID] = extensionValue
            recordMacros(Self.macroValues(from: extensionValue), id: extensionID)
        }

        for (index, application) in declarationGraph.mainBlockMacros.enumerated() {
            let applicationValue = builder.value(for: application)
            if index == 0 {
                main = applicationValue
            }
            recordMacros([applicationValue], id: "mainBlock:\(index)")
        }

        self.declarationsByID = declarationsByID
        self.membersByID = membersByID
        self.parentByID = parentByID
        self.macrosByID = macrosByID
        self.macrosByName = macrosByName
        self.main = main
        self.writtenSyntaxByID = writtenSyntaxByID
        self.sourcePathByID = sourcePathByID
        self.sourceDirectoryByID = sourceDirectoryByID
    }

    func declaration(for identity: CompileTimeValue) -> CompileTimeValue? {
        guard let id = identityID(identity) else { return nil }
        return declarationsByID[id]
    }

    func members(of identity: CompileTimeValue) -> CompileTimeValue? {
        guard let id = identityID(identity) else { return nil }
        return .array(membersByID[id, default: []])
    }

    func parent(of identity: CompileTimeValue) -> CompileTimeValue? {
        guard let id = identityID(identity) else { return nil }
        return parentByID[id]
    }

    func macros(on identity: CompileTimeValue) -> CompileTimeValue? {
        guard let id = identityID(identity) else { return nil }
        return .array(macrosByID[id, default: []])
    }

    func macros() -> CompileTimeValue {
        .array(macrosByName.values.flatMap { $0 })
    }

    func macros(named name: String) -> CompileTimeValue {
        .array(macrosByName[name, default: []])
    }

    func mainMacro() -> CompileTimeValue {
        main
    }

    func sourcePath(of identity: CompileTimeValue) -> CompileTimeValue? {
        guard let id = identityID(identity), let path = sourcePathByID[id] else { return nil }
        return .string(path)
    }

    func sourceDirectory(of identity: CompileTimeValue) -> CompileTimeValue? {
        guard let id = identityID(identity), let path = sourceDirectoryByID[id] else { return nil }
        return .string(path)
    }

    private static func writtenSyntaxByID(for graph: DeclarationGraph) -> [String: CompileTimeValue] {
        let builder = MacroTargetValueBuilder()
        var values: [String: CompileTimeValue] = [:]

        for location in graph.sourceLocations {
            guard let source = graph.sourceTextByPath[location.path] else {
                continue
            }
            let text = declarationText(in: source, startingAt: location.range.start.line)
            let written = builder.writtenSyntax(text)
            switch location.kind {
            case .type:
                if graph.constructsByName[location.name] != nil { values["construct:\(location.name)"] = written }
                if graph.enumsByName[location.name] != nil { values["enum:\(location.name)"] = written }
                if graph.protocolsByName[location.name] != nil { values["protocol:\(location.name)"] = written }
            case .function:
                values["function:\(location.name)"] = written
            case .macro:
                values["macro:\(location.name)"] = written
            }
        }

        return values
    }

    private static func sourcePathByID(for graph: DeclarationGraph) -> [String: String] {
        var values: [String: String] = [:]

        for location in graph.sourceLocations {
            switch location.kind {
            case .type:
                if graph.constructsByName[location.name] != nil { values["construct:\(location.name)"] = location.path }
                if graph.enumsByName[location.name] != nil { values["enum:\(location.name)"] = location.path }
                if graph.protocolsByName[location.name] != nil { values["protocol:\(location.name)"] = location.path }
            case .function:
                values["function:\(location.name)"] = location.path
            case .macro:
                values["macro:\(location.name)"] = location.path
            }
        }

        return values
    }

    private static func directoryPath(for path: String) -> String {
        URL(fileURLWithPath: path).deletingLastPathComponent().path
    }

    private static func declarationText(in source: String, startingAt line: Int) -> String {
        let lines = source.components(separatedBy: .newlines)
        guard line >= 0, line < lines.count else { return "" }
        var start = line
        while start > 0 {
            let previous = lines[start - 1].trimmingCharacters(in: .whitespaces)
            guard previous.hasPrefix("#") || previous.hasPrefix("@") else { break }
            start -= 1
        }
        var end = line
        var balance = 0
        var sawBrace = false
        for index in line..<lines.count {
            for character in lines[index] {
                if character == "{" { sawBrace = true; balance += 1 }
                else if character == "}" { balance -= 1 }
            }
            end = index
            if sawBrace && balance <= 0 { break }
            if !sawBrace { break }
        }
        return lines[start...end].joined(separator: "\n")
    }

    private func identityID(_ identity: CompileTimeValue) -> String? {
        guard case .object("GraphIdentity", let fields) = identity,
            case .string(let id)? = fields["id"]
        else { return nil }
        return id
    }

    private static func macroValues(from value: CompileTimeValue) -> [CompileTimeValue] {
        guard case .array(let macros)? = value.field("macros") else { return [] }
        return macros
    }

    private static func applicationIdentifierName(_ value: CompileTimeValue) -> String? {
        guard case .object("Macro.Application", let fields) = value,
            case .object(_, let identifierFields)? = fields["identifier"],
            case .string(let name)? = identifierFields["name"]
        else { return nil }
        return name
    }
}

private struct MacroTargetTypeMatcher {
    let syntaxResolver: DeclarationSyntaxResolver
    let genericParameters: [GenericParameter]

    func matches(
        actual: TypeReference,
        expected: MacroTarget
    ) -> Bool {
        switch expected {
        case .syntax(let typeReference):
            return matches(actual: actual, expected: typeReference)
        case .macroSurface(let name):
            return name == "syntax" && syntaxResolver.typeConformsToSyntax(actual)
                || syntaxResolver.type(actual, matchesSyntaxSurface: name)
        case .anyOf(let targets):
            return targets.contains { matches(actual: actual, expected: $0) }
        case .allOf(let targets):
            return targets.allSatisfy { matches(actual: actual, expected: $0) }
        }
    }

    func matches(
        actual: TypeReference,
        expected: TypeReference
    ) -> Bool {

        var bindings: [String: TypeReference] = [:]
        guard typeMatches(actual: actual, expected: expected, bindings: &bindings) else {
            return false
        }

        for parameter in genericParameters {
            guard case .type(let name, let constraint, _) = parameter,
                let constraint,
                let binding = bindings[name]
            else {
                continue
            }

            guard let constraintName = syntaxResolver.nominalName(of: constraint) else {
                return false
            }

            guard syntaxResolver.typeConforms(binding, to: constraintName) else {
                return false
            }
        }

        return true
    }

    private func typeMatches(
        actual: TypeReference,
        expected: TypeReference,
        bindings: inout [String: TypeReference]
    ) -> Bool {
        if case .named(let name) = expected,
            typeGenericParameterNames.contains(name)
        {
            if let existing = bindings[name] {
                return existing == actual
            }

            bindings[name] = actual
            return true
        }

        if case .optional(let actualWrapped) = actual,
            case .generic(.named("Optional"), let expectedArguments) = expected,
            expectedArguments.count == 1
        {
            return typeMatches(
                actual: actualWrapped,
                expected: expectedArguments[0],
                bindings: &bindings
            )
        }

        if case .generic(.named("Optional"), let actualArguments) = actual,
            actualArguments.count == 1,
            case .optional(let expectedWrapped) = expected
        {
            return typeMatches(
                actual: actualArguments[0],
                expected: expectedWrapped,
                bindings: &bindings
            )
        }

        switch (actual, expected) {
        case (.named(let actualName), .named(let expectedName)):
            return actualName == expectedName
                || syntaxResolver.declaration(named: actualName, conformsTo: expectedName)
        case (.generic(let actualBase, _), .named):
            return typeMatches(
                actual: actualBase,
                expected: expected,
                bindings: &bindings
            )
        case (.member(let actualBase, let actualName), .member(let expectedBase, let expectedName)):
            return actualName == expectedName
                && typeMatches(
                    actual: actualBase,
                    expected: expectedBase,
                    bindings: &bindings
                )
        case (
            .generic(let actualBase, let actualArguments),
            .generic(let expectedBase, let expectedArguments)
        ):
            guard actualArguments.count == expectedArguments.count,
                typeMatches(
                    actual: actualBase,
                    expected: expectedBase,
                    bindings: &bindings
                )
            else {
                return false
            }

            return zip(actualArguments, expectedArguments).allSatisfy { actualArgument, expectedArgument in
                typeMatches(
                    actual: actualArgument,
                    expected: expectedArgument,
                    bindings: &bindings
                )
            }
        case (.array(let actualElement), .array(let expectedElement)),
            (.optional(let actualElement), .optional(let expectedElement)),
            (.variadic(let actualElement), .variadic(let expectedElement)):
            return typeMatches(
                actual: actualElement,
                expected: expectedElement,
                bindings: &bindings
            )
        case (
            .function(let actualParameters, let actualReturn),
            .function(let expectedParameters, let expectedReturn)
        ):
            guard actualParameters.count == expectedParameters.count else {
                return false
            }

            return zip(actualParameters, expectedParameters).allSatisfy { actualParameter, expectedParameter in
                typeMatches(
                    actual: actualParameter,
                    expected: expectedParameter,
                    bindings: &bindings
                )
            } && typeMatches(
                actual: actualReturn,
                expected: expectedReturn,
                bindings: &bindings
            )
        default:
            return false
        }
    }

    private var typeGenericParameterNames: Set<String> {
        Set(
            genericParameters.compactMap { parameter in
                guard case .type(let name, _, _) = parameter else {
                    return nil
                }
                return name
            }
        )
    }
}

extension RewriteSurfaceView {
    func rewriteSiteDescriptors(
        targetBinding: String,
        targetType: TypeReference
    ) -> [RewriteSiteDescriptor] {
        let targetKind = macroTargetKind(for: targetType)
        return allowedPaths(
            targetBinding: targetBinding,
            targetType: targetType
        )
        .sorted()
        .compactMap { normalizedPath in
            guard
                let site = supportedRewriteSite(
                    normalizedPath: normalizedPath,
                    targetBinding: targetBinding,
                    targetKind: targetKind
                )
            else {
                return nil
            }

            return RewriteSiteDescriptor(normalizedPath: normalizedPath, site: site)
        }
    }

    private func supportedRewriteSite(
        normalizedPath: String,
        targetBinding: String,
        targetKind: MacroTargetKind
    ) -> ResolvedRewriteSite? {
        let directPath = "\(targetBinding).replace"
        if normalizedPath == directPath {
            switch targetKind {
            case .expression, .block:
                return .targetDirect
            default:
                return nil
            }
        }

        let prefix = "\(targetBinding)."
        guard normalizedPath.hasPrefix(prefix) else {
            return nil
        }
        let relativePath = String(normalizedPath.dropFirst(prefix.count))

        switch targetKind {
        case .initializer:
            switch relativePath {
            case "application.replace":
                return .initApplication
            case "application.arguments[].expression.replace":
                return .initApplication
            default:
                return nil
            }
        case .function:
            switch relativePath {
            case "call.replace":
                return .functionApplication
            case "call.arguments[].expression.replace":
                return .functionArgumentExpression
            default:
                return nil
            }
        case .parameter:
            switch relativePath {
            case "declaration.type.replace":
                return .parameterDeclarationType
            case "application.expression.replace":
                return .parameterApplicationArgument
            case "application.arguments[].expression.replace":
                return .parameterApplicationArguments
            default:
                return nil
            }
        case .expression, .state, .immutable, .binding, .derived, .property, .block, .construct,
            .enumeration, .protocolDefinition, .typeExtension, .other:
            return nil
        }
    }
}
