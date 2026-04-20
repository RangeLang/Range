import Foundation

public enum MacroExpander {
    private static let expansionLock = NSLock()

    public static func expand(files: [ParsedSourceFile]) throws -> [ParsedSourceFile] {
        expansionLock.lock()
        defer { expansionLock.unlock() }

        let registry = collectMacros(from: files)
        let declarationGraph = DeclarationGraph(files: files)
        let protocols = declarationGraph.protocolsByName
        let graphViews = declarationGraph.views
        try validateMacroSyntaxCaptures(
            macros: Array(registry.values),
            syntaxResolver: graphViews.syntaxResolver
        )
        let context = declarationGraph.macroExpansionContext(macrosByName: registry)
        return try files.map { parsedFile in
            ParsedSourceFile(
                path: parsedFile.path,
                sourceFile: try expand(
                    sourceFile: parsedFile.sourceFile,
                    macros: registry,
                    protocols: protocols,
                    parameterMacroSignatures: context.macroRealizationView.parameterMacroSignatures,
                    literalBridges: context.macroRealizationView.realizedLiteralBridges,
                    context: context
                )
            )
        }
    }
}
