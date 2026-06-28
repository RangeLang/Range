import Foundation

public enum MacroExpander {
    private static let expansionLock = NSLock()

    public static func expand(
        files: [ParsedSourceFile],
        diagnosticEngine: RangeDiagnosticEngine? = nil
    ) throws -> [ParsedSourceFile] {
        expansionLock.lock()
        defer { expansionLock.unlock() }

        let registry = collectMacros(from: files)
        let macroMetadataRegistry = collectMacroMetadata(from: files)
        let declarationGraph = DeclarationGraph(files: files)
        let graphViews = declarationGraph.views
        try validateMacroSyntaxCaptures(
            macros: Array(registry.values),
            syntaxResolver: graphViews.syntaxResolver
        )
        let context = declarationGraph.macroExpansionContext(
            macrosByName: registry,
            macroMetadataDeclarationsByName: macroMetadataRegistry,
            diagnosticEngine: diagnosticEngine
        )
        return try files.map { parsedFile in
            ParsedSourceFile(
                path: parsedFile.path,
                source: parsedFile.source,
                sourceFile: try expand(
                    sourceFile: parsedFile.sourceFile,
                    macros: registry,
                    context: context.withCurrentPath(parsedFile.path)
                )
            )
        }
    }
}
