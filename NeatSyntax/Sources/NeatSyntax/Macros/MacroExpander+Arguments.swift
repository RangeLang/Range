import Foundation

extension MacroExpander {
    static func expressionMacroArgumentBindings(
        for macro: MacroDeclaration,
        arguments: [CallArgument]
    ) throws -> [String: Expression] {
        let parameters = macro.parameters
        guard arguments.count == parameters.count else {
            throw ParseError(
                "Macro #\(macro.name) expects \(parameters.count) argument(s), got \(arguments.count)."
            )
        }

        var bindings: [String: Expression] = [:]
        for (parameter, argument) in zip(parameters, arguments) {
            let expectedLabel = macroArgumentLabel(for: parameter)
            let actualLabel = argument.label

            if actualLabel == nil {
                // Macro arguments can be passed positionally.
            } else if let expectedLabel, let actualLabel, expectedLabel == actualLabel {
                // Label matched.
            } else if let expectedLabel, let actualLabel {
                throw ParseError(
                    "Macro #\(macro.name) expects argument label \(expectedLabel), got \(actualLabel)."
                )
            } else if let actualLabel {
                throw ParseError(
                    "Macro #\(macro.name) argument for \(parameter.localName) should not use label \(actualLabel)."
                )
            }

            bindings[parameter.localName] = argument.value
        }

        return bindings
    }

    static func parseMacroArgumentBindings(
        for macro: MacroDeclaration,
        argumentClause: String?
    ) throws -> [String: Expression] {
        let parameters = macro.parameters
        guard !parameters.isEmpty || argumentClause == nil else {
            throw ParseError("Macro #\(macro.name) requires arguments.")
        }
        guard !parameters.isEmpty else {
            return [:]
        }
        guard let argumentClause else {
            throw ParseError("Macro #\(macro.name) requires arguments.")
        }

        var parser = try Parser(source: "macro(\(argumentClause))")
        _ = try parser.consumeCallableName()
        let arguments = try parser.parseInvocationArgumentsIfPresent()
        try parser.consume(Token.eof)

        guard arguments.count == parameters.count else {
            throw ParseError(
                "Macro #\(macro.name) expects \(parameters.count) argument(s), got \(arguments.count)."
            )
        }

        var bindings: [String: Expression] = [:]
        for (parameter, argument) in zip(parameters, arguments) {
            let expectedLabel = macroArgumentLabel(for: parameter)
            let actualLabel = argument.label

            if actualLabel == nil {
                // Macro arguments can be passed positionally.
            } else if let expectedLabel, let actualLabel, expectedLabel == actualLabel {
                // Label matched.
            } else if let expectedLabel, let actualLabel {
                throw ParseError(
                    "Macro #\(macro.name) expects argument label \(expectedLabel), got \(actualLabel)."
                )
            } else if let actualLabel {
                throw ParseError(
                    "Macro #\(macro.name) argument for \(parameter.localName) should not use label \(actualLabel)."
                )
            }
            bindings[parameter.localName] = argument.value
        }
        return bindings
    }

    static func macroArgumentLabel(for parameter: NeatFunctionParameter) -> String? {
        parameter.externalLabel ?? parameter.localName
    }
}
