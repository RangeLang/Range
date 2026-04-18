import Foundation

extension DeclarationGraph {
    func macroRealizationView(macrosByName: [String: MacroDeclaration]) -> MacroRealizationView {
        MacroRealizationView(
            parameterMacroSignatures: parameterMacroSignatures(macrosByName: macrosByName),
            functionMacroSignatures: functionMacroSignatures(macrosByName: macrosByName),
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
        macrosByName: [String: MacroDeclaration]
    ) -> [ParameterMacroSignature] {
        callablesByName.values
            .flatMap { $0 }
            .compactMap { callable in
                parameterMacroSignature(
                    for: callable,
                    macrosByName: macrosByName
                )
            }
    }

    private func functionMacroSignatures(
        macrosByName: [String: MacroDeclaration]
    ) -> [FunctionMacroSignature] {
        callablesByName.values
            .flatMap { $0 }
            .compactMap { callable in
                functionMacroSignature(
                    for: callable,
                    macrosByName: macrosByName
                )
            }
    }

    private func parameterMacroSignature(
        for callable: CallableDeclaration,
        macrosByName: [String: MacroDeclaration]
    ) -> ParameterMacroSignature? {
        guard callable.targetType == nil else {
            return nil
        }

        let parameterMacrosByIndex: [Int: MacroDeclaration] = Dictionary(
            uniqueKeysWithValues: callable.parameters.enumerated().compactMap {
                index, parameter -> (Int, MacroDeclaration)? in
                guard
                    let macro = parameter.macros.lazy.compactMap({ macrosByName[$0.name] }).first(where: {
                        MacroExpander.macroTargetKind(for: $0) == .parameter
                    })
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
        macrosByName: [String: MacroDeclaration]
    ) -> FunctionMacroSignature? {
        guard callable.targetType == nil else {
            return nil
        }

        let functionMacros: [MacroDeclaration] = callable.macros.compactMap { macroApplication in
            guard
                let macro = macrosByName[macroApplication.name],
                MacroExpander.macroTargetKind(for: macro) == .function
            else {
                return nil
            }

            return macro
        }

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
