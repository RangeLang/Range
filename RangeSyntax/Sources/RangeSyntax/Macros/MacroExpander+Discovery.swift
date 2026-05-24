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
            guard macro.target != nil else {
                continue
            }
            for parameter in macro.parameters {
                guard syntaxResolver.typeConformsToSyntax(parameter.typeReference) else {
                    if parameter.capturesSyntax {
                        throw ParseError(
                            "Macro #\(macro.name) parameter \(parameter.localName) uses @capture with non-syntax type \(parameter.typeReference?.displayName ?? "unknown")."
                        )
                    }
                    continue
                }
                guard parameter.capturesSyntax else {
                    throw ParseError(
                        "Macro #\(macro.name) parameter \(parameter.localName) must use @capture<\(parameter.typeReference?.displayName ?? "Syntax")> to bind syntax."
                    )
                }
                guard parameter.captureMetadataType != nil else {
                    throw ParseError(
                        "Macro #\(macro.name) parameter \(parameter.localName) must use typed capture metadata, for example @capture<\(parameter.typeReference?.displayName ?? "Syntax")>."
                    )
                }
            }
        }
    }

    static func macros(in sourceFile: SourceFileNode) -> [MacroDeclaration] {
        switch sourceFile {
        case .macro(let declaration):
            return [declaration]
        case .module(let module):
            return module.macros
        case .construct, .namespace, .enumeration, .protocolDefinition, .marker, .mainBlock, .extensions:
            return []
        }
    }

    public static func collectMarkers(from files: [ParsedSourceFile]) -> [String: MarkerDeclaration] {
        var registry: [String: MarkerDeclaration] = [:]
        for parsedFile in files {
            for marker in self.markers(in: parsedFile.sourceFile) {
                registry[marker.name] = marker
            }
        }
        return registry
    }

    static func markers(in sourceFile: SourceFileNode) -> [MarkerDeclaration] {
        switch sourceFile {
        case .marker(let declaration):
            return [declaration]
        case .module(let module):
            return module.markers
        case .construct, .namespace, .enumeration, .protocolDefinition, .macro, .mainBlock, .extensions:
            return []
        }
    }

}
