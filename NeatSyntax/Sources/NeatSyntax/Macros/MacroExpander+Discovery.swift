import Foundation

extension MacroExpander {
    public static func collectMacros(from files: [ParsedSourceFile]) -> [String: MacroDeclaration] {
        var registry: [String: MacroDeclaration] = [:]
        for parsedFile in files {
            for macro in self.macros(in: parsedFile.sourceFile) {
                registry[macro.name] = macro
            }
        }
        return registry
    }

    public static func collectMacroExpansionTypes(from files: [ParsedSourceFile])
        -> [String: TypeReference]
    {
        collectMacros(from: files).compactMapValues(\.expansionType)
    }

    static func validateMacroSyntaxCaptures(
        macros: [MacroDeclaration],
        syntaxResolver: DeclarationSyntaxResolver
    ) throws {
        for macro in macros {
            for parameter in macro.parameters {
                guard syntaxResolver.typeConformsToSyntax(parameter.typeReference) else {
                    if parameter.capturesSyntax {
                        throw ParseError(
                            "Macro #\(macro.name) parameter \(parameter.localName) uses capture with non-syntax type \(parameter.typeReference?.displayName ?? "unknown")."
                        )
                    }
                    continue
                }
                guard parameter.capturesSyntax else {
                    throw ParseError(
                        "Macro #\(macro.name) parameter \(parameter.localName) must use capture \(parameter.typeReference?.displayName ?? "syntax") to bind syntax."
                    )
                }
            }
        }
    }

    static func collectAttachedParameterCallables(
        from files: [ParsedSourceFile],
        macros: [String: MacroDeclaration]
    )
        -> [AttachedParameterMacroSignature]
    {
        files.flatMap { parsedFile in
            callablesWithAttachedParameterMacros(in: parsedFile.sourceFile, macros: macros)
        }
    }

    static func collectAttachedFunctionCallables(
        from files: [ParsedSourceFile],
        macros: [String: MacroDeclaration]
    ) -> [AttachedFunctionMacroSignature] {
        files.flatMap { parsedFile in
            callablesWithAttachedFunctionMacros(in: parsedFile.sourceFile, macros: macros)
        }
    }

    static func macros(in sourceFile: SourceFileNode) -> [MacroDeclaration] {
        switch sourceFile {
        case .macro(let declaration):
            return [declaration]
        case .module(let module):
            return module.macros
        case .construct, .enumeration, .protocolDefinition, .mainBlock, .extensions:
            return []
        }
    }

    static func callablesWithAttachedParameterMacros(
        in sourceFile: SourceFileNode,
        macros: [String: MacroDeclaration]
    )
        -> [AttachedParameterMacroSignature]
    {
        switch sourceFile {
        case .module(let module):
            return module.callables.compactMap {
                attachedParameterMacroSignature(for: $0, macros: macros)
            }
        default:
            return []
        }
    }

    static func callablesWithAttachedFunctionMacros(
        in sourceFile: SourceFileNode,
        macros: [String: MacroDeclaration]
    ) -> [AttachedFunctionMacroSignature] {
        switch sourceFile {
        case .module(let module):
            return module.callables.compactMap {
                attachedFunctionMacroSignature(for: $0, macros: macros)
            }
        default:
            return []
        }
    }

    static func attachedParameterMacroSignature(
        for callable: CallableDeclaration,
        macros: [String: MacroDeclaration]
    )
        -> AttachedParameterMacroSignature?
    {
        guard callable.targetType == nil else {
            return nil
        }

        let attachedParameterMacrosByIndex: [Int: MacroDeclaration] = Dictionary(
            uniqueKeysWithValues: callable.parameters.enumerated().compactMap {
                index, parameter -> (Int, MacroDeclaration)? in
                guard
                    let macro = parameter.macros.lazy.compactMap({ macros[$0.name] }).first(where: {
                        macroTargetKind(for: $0) == .parameter
                    })
                else { return nil }

                return (index, macro)
            })

        guard !attachedParameterMacrosByIndex.isEmpty else {
            return nil
        }

        return AttachedParameterMacroSignature(
            name: callable.name,
            labels: callable.parameters.map(\.externalLabel),
            attachedParameterMacrosByIndex: attachedParameterMacrosByIndex
        )
    }

    static func attachedFunctionMacroSignature(
        for callable: CallableDeclaration,
        macros: [String: MacroDeclaration]
    ) -> AttachedFunctionMacroSignature? {
        guard callable.targetType == nil else {
            return nil
        }

        let attachedFunctionMacros: [MacroDeclaration] = callable.macros.compactMap { macroApplication in
            guard let macro = macros[macroApplication.name], macroTargetKind(for: macro) == .function
            else {
                return nil
            }
            return macro
        }

        guard !attachedFunctionMacros.isEmpty else {
            return nil
        }

        return AttachedFunctionMacroSignature(
            name: callable.name,
            labels: callable.parameters.map(\.externalLabel),
            attachedFunctionMacros: attachedFunctionMacros
        )
    }
}
