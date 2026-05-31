import Foundation

extension DeclarationGraph {
    func macroExpansionContext(
        macrosByName: [String: MacroDeclaration],
        macroMetadataDeclarationsByName: [String: MacroMetadataDeclaration] = [:],
        diagnosticEngine: RangeDiagnosticEngine? = nil
    ) -> MacroExpansionContext {
        MacroExpansionContext(
            macroRealizationView: macroRealizationView(macrosByName: macrosByName),
            rewriteSurfaceView: rewriteSurfaceView,
            graphContext: MacroGraphContext(
                declarationGraph: self,
                macroDeclarationsByName: macrosByName,
                macroMetadataDeclarationsByName: macroMetadataDeclarationsByName
            ),
            macroDeclarationsByName: macrosByName,
            macroMetadataByName: macroMetadataDeclarationsByName,
            diagnosticEngine: diagnosticEngine,
            currentPath: nil
        )
    }

    func macroRealizationView(macrosByName: [String: MacroDeclaration]) -> MacroRealizationView {
        let registryView = MacroRegistryView(macrosByName: macrosByName)
        return MacroRealizationView(
            parameterMacroSignatures: parameterMacroSignatures(registryView: registryView),
            functionMacroSignatures: functionMacroSignatures(registryView: registryView),
            realizedLiteralBridges: realizedLiteralBridges,
            realizedInitMacroTargets: realizedInitMacroTargets
        )
    }

    var rewriteSurfaceView: RewriteSurfaceView {
        RewriteSurfaceView(
            syntaxResolver: syntaxResolver,
            constructsByName: constructsByName
        )
    }

    private func parameterMacroSignatures(
        registryView: MacroRegistryView
    ) -> [ParameterMacroSignature] {
        callablesByName.values
            .flatMap { $0 }
            .compactMap { callable in
                parameterMacroSignature(
                    for: callable,
                    registryView: registryView
                )
            }
    }

    private func functionMacroSignatures(
        registryView: MacroRegistryView
    ) -> [FunctionMacroSignature] {
        callablesByName.values
            .flatMap { $0 }
            .compactMap { callable in
                functionMacroSignature(
                    for: callable,
                    registryView: registryView
                )
            }
    }

    private func parameterMacroSignature(
        for callable: CallableDeclaration,
        registryView: MacroRegistryView
    ) -> ParameterMacroSignature? {
        guard callable.targetType == nil else {
            return nil
        }

        let parameterMacrosByIndex: [Int: MacroDeclaration] = Dictionary(
            uniqueKeysWithValues: callable.parameters.enumerated().compactMap {
                index, parameter -> (Int, MacroDeclaration)? in
                guard
                    let macro = registryView.firstMacro(
                        in: parameter.macros,
                        targetKind: .parameter
                    )
                else {
                    return nil
                }

                return (index, macro)
            }
        )

        guard !parameterMacrosByIndex.isEmpty else {
            return nil
        }

        return ParameterMacroSignature(
            name: callable.name,
            labels: callable.parameters.map(\.externalLabel),
            parameterMacrosByIndex: parameterMacrosByIndex
        )
    }

    private func functionMacroSignature(
        for callable: CallableDeclaration,
        registryView: MacroRegistryView
    ) -> FunctionMacroSignature? {
        guard callable.targetType == nil else {
            return nil
        }

        let functionMacros = registryView.macros(
            in: callable.macros,
            targetKind: .function
        )

        guard !functionMacros.isEmpty else {
            return nil
        }

        return FunctionMacroSignature(
            name: callable.name,
            labels: callable.parameters.map(\.externalLabel),
            functionMacros: functionMacros
        )
    }
}
