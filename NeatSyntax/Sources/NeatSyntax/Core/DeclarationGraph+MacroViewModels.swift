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
    case function
    case construct
    case other(String)
}

func macroTargetKind(for macro: MacroDeclaration) -> MacroTargetKind {
    macroTargetKind(for: macro.target.typeReference)
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
    case "Property":
        return .property
    case "Function":
        return .function
    case "Construct":
        return .construct
    default:
        return .other(name)
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
            macroTargetKind(for: $0) == targetKind
        })
    }

    func macros(
        in applications: [MacroApplication],
        targetKind: MacroTargetKind
    ) -> [MacroDeclaration] {
        applications.compactMap { application in
            guard let macro = macrosByName[application.name], macroTargetKind(for: macro) == targetKind
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

    func allowedPaths(
        targetBinding: String,
        targetType: TypeReference
    ) -> Set<String> {
        guard let targetName = syntaxResolver.nominalName(of: targetType) else {
            return []
        }

        var paths: Set<String> = []

        func supportsRewrite(_ typeName: String) -> Bool {
            syntaxResolver.declaration(named: typeName, conformsTo: "SyntaxRewritable")
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

            if syntaxResolver.declaration(named: text, conformsTo: "Syntax")
                || syntaxResolver.declaration(named: text, conformsTo: "SyntaxRewritable")
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
                paths.insert("\(path).rewrite")
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
        guard let targetName = syntaxResolver.nominalName(of: targetType) else {
            return false
        }

        let directPath = "\(targetBinding).rewrite"
        if normalizedPath == directPath {
            return syntaxResolver.declaration(named: targetName, conformsTo: "SyntaxRewritable")
        }

        let prefix = "\(targetBinding)."
        let suffix = ".rewrite"
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

        return syntaxResolver.declaration(named: currentTypeName, conformsTo: "SyntaxRewritable")
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

        if syntaxResolver.declaration(named: text, conformsTo: "Syntax")
            || syntaxResolver.declaration(named: text, conformsTo: "SyntaxRewritable")
        {
            return (text, isArray)
        }

        return nil
    }
}

struct RewriteSiteDescriptor {
    let normalizedPath: String
    let site: ResolvedRewriteSite
}

struct MacroExpansionContext {
    let macroRealizationView: MacroRealizationView
    let rewriteSurfaceView: RewriteSurfaceView

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
            expected: macro.target.typeReference
        )
    }

    func validateRewriteSites(
        for macro: MacroDeclaration,
        targetKind: MacroTargetKind,
        operationExpressions: [Expression],
        acceptsResolvedRewrite: (Expression) -> Bool
    ) throws {
        let targetBinding = macro.bindings.target
        let targetPrefix = "\(targetBinding)."
        let allowedPaths = rewriteSurfaceView.allowedPaths(
            targetBinding: targetBinding,
            targetType: macro.target.typeReference
        )

        var invalidPaths: [String] = []
        for expression in operationExpressions {
            guard case .call(let name, let arguments) = expression, arguments.count == 1 else {
                continue
            }
            guard name.hasPrefix(targetPrefix), name.hasSuffix(".rewrite") else {
                continue
            }

            guard
                let normalizedPath = normalizedRewritePath(name, targetBinding: targetBinding),
                acceptsResolvedRewrite(expression),
                rewriteSurfaceView.declaredRewritePathExists(
                    normalizedPath,
                    targetBinding: targetBinding,
                    targetType: macro.target.typeReference
                )
            else {
                invalidPaths.append(name)
                continue
            }
        }

        guard invalidPaths.isEmpty else {
            let allowedDescription: String
            if allowedPaths.isEmpty {
                allowedDescription = "no rewrite paths"
            } else {
                allowedDescription = allowedPaths.sorted().joined(separator: ", ")
            }
            throw ParseError(
                "Macro #\(macro.name) targeting \(macro.target.typeReference.displayName) uses unsupported rewrite site '\(invalidPaths[0])'. Allowed: \(allowedDescription)."
            )
        }
    }

    private func normalizedRewritePath(
        _ name: String,
        targetBinding: String
    ) -> String? {
        let directPath = "\(targetBinding).rewrite"
        if name == directPath {
            return directPath
        }

        let prefix = "\(targetBinding)."
        let suffix = ".rewrite"
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

        return "\(targetBinding).\(normalized).rewrite"
    }

    func resolvedRewriteCall(
        from expression: Expression,
        targetBinding: String,
        targetType: TypeReference
    ) -> ResolvedRewriteCall? {
        guard case .call(let name, let arguments) = expression, arguments.count == 1 else {
            return nil
        }

        guard
            let normalizedPath = normalizedRewritePath(name, targetBinding: targetBinding),
            let descriptor = rewriteSurfaceView.rewriteSiteDescriptors(
                targetBinding: targetBinding,
                targetType: targetType
            ).first(where: { $0.normalizedPath == normalizedPath })
        else {
            return nil
        }

        return ResolvedRewriteCall(site: descriptor.site, payload: arguments[0].value)
    }
}

private struct MacroTargetTypeMatcher {
    let syntaxResolver: DeclarationSyntaxResolver
    let genericParameters: [GenericParameter]

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
        let directPath = "\(targetBinding).rewrite"
        if normalizedPath == directPath {
            switch targetKind {
            case .expression:
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
            case "application.rewrite":
                return .initApplication
            case "application.arguments[].expression.rewrite":
                return .initApplication
            default:
                return nil
            }
        case .function:
            switch relativePath {
            case "application.rewrite":
                return .functionApplication
            case "application.arguments[].expression.rewrite":
                return .functionArgumentExpression
            default:
                return nil
            }
        case .parameter:
            switch relativePath {
            case "declaration.type.rewrite":
                return .parameterDeclarationType
            case "application.expression.rewrite":
                return .parameterApplicationArgument
            case "application.arguments[].expression.rewrite":
                return .parameterApplicationArguments
            default:
                return nil
            }
        case .expression, .state, .immutable, .binding, .derived, .property, .construct, .other:
            return nil
        }
    }
}
