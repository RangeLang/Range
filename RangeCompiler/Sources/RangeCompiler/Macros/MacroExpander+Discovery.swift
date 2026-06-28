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

    public static func collectMacroDeclarations(from files: [ParsedSourceFile]) -> [String: MacroDeclaration] {
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
            guard macro.target != nil else {
                continue
            }
            for parameter in macro.parameters {
                guard syntaxResolver.typeConformsToSyntax(parameter.typeReference) else {
                    if parameter.capturesSyntax {
                        throw ParseError(
                            "Macro @\(macro.name) parameter \(parameter.localName) uses @capture with non-syntax type \(parameter.typeReference?.displayName ?? "unknown")."
                        )
                    }
                    continue
                }
                guard parameter.capturesSyntax else {
                    throw ParseError(
                        "Macro @\(macro.name) parameter \(parameter.localName) must use @capture<\(parameter.typeReference?.displayName ?? "Syntax")> to bind syntax."
                    )
                }
            }
        }
    }

    static func macros(in sourceFile: ModuleFileNode) -> [MacroDeclaration] {
        sourceFile.macros
    }

    public static func collectMacroMetadata(from files: [ParsedSourceFile]) -> [String: MacroMetadataDeclaration] {
        var registry: [String: MacroMetadataDeclaration] = [:]
        for parsedFile in files {
            for macro in self.macros(in: parsedFile.sourceFile) {
                guard let metadata = metadataDeclaration(from: macro) else {
                    continue
                }
                registry[metadata.name] = metadata
            }
        }
        return registry
    }

    static func metadataDeclaration(from macro: MacroDeclaration) -> MacroMetadataDeclaration? {
        guard let firstTarget = macro.target else {
            return nil
        }
        guard macro.expansionType != nil else {
            return nil
        }
        let firstType = firstTarget.typeReference
        let target: MacroTarget
        let valueType: TypeReference
        if let expansionType = macro.expansionType {
            target = firstTarget
            valueType = expansionType
        } else if let effectTarget = firstType.macroMetadataEffectTarget {
            target = .syntax(effectTarget)
            valueType = firstType
        } else {
            return nil
        }

        return MacroMetadataDeclaration(
            name: macro.name,
            genericParameters: macro.genericParameters,
            parameters: macro.parameters,
            target: target,
            valueType: valueType,
            body: macro.body
        )
    }

}
