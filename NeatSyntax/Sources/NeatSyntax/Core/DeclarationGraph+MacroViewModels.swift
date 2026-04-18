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

enum MacroTargetKind: Equatable {
    case expression
    case block
    case parameter
    case initializer
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
    case "Block":
        return .block
    case "Parameter":
        return .parameter
    case "Init":
        return .initializer
    case "Function":
        return .function
    case "Construct":
        return .construct
    default:
        return .other(name)
    }
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
            syntaxResolver.declaration(named: typeName, conformsTo: "SupportsRewrite")
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
                || syntaxResolver.declaration(named: text, conformsTo: "SupportsRewrite")
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
            return syntaxResolver.declaration(named: targetName, conformsTo: "SupportsRewrite")
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

        return syntaxResolver.declaration(named: currentTypeName, conformsTo: "SupportsRewrite")
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
            || syntaxResolver.declaration(named: text, conformsTo: "SupportsRewrite")
        {
            return (text, isArray)
        }

        return nil
    }
}

struct MacroExpansionContext {
    let macroRealizationView: MacroRealizationView
    let rewriteSurfaceView: RewriteSurfaceView

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
}
