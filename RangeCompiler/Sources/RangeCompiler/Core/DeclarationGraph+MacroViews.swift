import Foundation

extension DeclarationGraph {
    func macroExpansionContext(
        macrosByName: [String: MacroDeclaration],
        macroMetadataDeclarationsByName: [String: MacroMetadataDeclaration] = [:],
        diagnosticEngine: RangeDiagnosticEngine? = nil
    ) -> MacroExpansionContext {
        MacroExpansionContext(
            syntaxResolver: syntaxResolver,
            graphContext: MacroGraphContext(
                declarationGraph: self,
                macroDeclarationsByName: macrosByName,
                macroMetadataDeclarationsByName: macroMetadataDeclarationsByName
            ),
            macroDeclarationsByName: macrosByName,
            macroMetadataByName: macroMetadataDeclarationsByName,
            callableDeclarationsByName: callablesByName,
            diagnosticEngine: diagnosticEngine,
            currentPath: nil
        )
    }
}
