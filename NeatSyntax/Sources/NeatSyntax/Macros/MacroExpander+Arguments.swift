import Foundation

extension MacroExpander {
    static func expressionMacroArgumentBindings(
        for macro: MacroDeclaration,
        arguments: [CallArgument]
    ) throws -> [String: Expression] {
        let parameters = macro.parameters
        return try argumentBindings(
            kind: "Macro",
            name: macro.name,
            parameters: parameters,
            arguments: arguments
        )
    }

    static func parseMacroArgumentBindings(
        for macro: MacroDeclaration,
        argumentClause: String?
    ) throws -> [String: Expression] {
        let parameters = macro.parameters
        let normalizedArgumentClause = argumentClause?.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !parameters.isEmpty || normalizedArgumentClause == nil || normalizedArgumentClause == "" else {
            throw ParseError("Macro #\(macro.name) requires arguments.")
        }
        guard !parameters.isEmpty else {
            return [:]
        }
        guard let normalizedArgumentClause, !normalizedArgumentClause.isEmpty else {
            return try argumentBindings(
                kind: "Macro",
                name: macro.name,
                parameters: parameters,
                arguments: []
            )
        }

        var parser = try Parser(source: "macro(\(normalizedArgumentClause))")
        _ = try parser.consumeCallableName()
        let arguments = try parser.parseInvocationArgumentsIfPresent()
        try parser.consume(Token.eof)

        return try argumentBindings(
            kind: "Macro",
            name: macro.name,
            parameters: parameters,
            arguments: arguments
        )
    }

    static func parseMarkerArgumentBindings(
        for marker: MarkerDeclaration,
        argumentClause: String?
    ) throws -> [String: Expression] {
        let parameters = marker.parameters
        let normalizedArgumentClause = argumentClause?.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !parameters.isEmpty || normalizedArgumentClause == nil || normalizedArgumentClause == "" else {
            throw ParseError("Marker #\(marker.name) requires arguments.")
        }
        guard !parameters.isEmpty else {
            return [:]
        }
        guard let normalizedArgumentClause, !normalizedArgumentClause.isEmpty else {
            return try argumentBindings(
                kind: "Marker",
                name: marker.name,
                parameters: parameters,
                arguments: []
            )
        }

        var parser = try Parser(source: "marker(\(normalizedArgumentClause))")
        _ = try parser.consumeCallableName()
        let arguments = try parser.parseInvocationArgumentsIfPresent()
        try parser.consume(Token.eof)

        return try argumentBindings(
            kind: "Marker",
            name: marker.name,
            parameters: parameters,
            arguments: arguments
        )
    }

    private static func argumentBindings(
        kind: String,
        name: String,
        parameters: [NeatFunctionParameter],
        arguments: [CallArgument]
    ) throws -> [String: Expression] {
        guard arguments.count <= parameters.count else {
            throw ParseError(
                "\(kind) #\(name) expects \(parameters.count) argument(s), got \(arguments.count)."
            )
        }

        var bindings: [String: Expression] = [:]
        for (parameter, argument) in zip(parameters, arguments) {
            let expectedLabel = macroArgumentLabel(for: parameter)
            let actualLabel = argument.label

            if actualLabel == nil, expectedLabel == nil {
                // Unlabeled macro and marker arguments require an explicit `_` label erasure.
            } else if let expectedLabel, let actualLabel, expectedLabel == actualLabel {
                // Label matched.
            } else if let expectedLabel, actualLabel == nil {
                throw ParseError(
                    "\(kind) #\(name) expects argument label \(expectedLabel)."
                )
            } else if let expectedLabel, let actualLabel {
                throw ParseError(
                    "\(kind) #\(name) expects argument label \(expectedLabel), got \(actualLabel)."
                )
            } else if let actualLabel {
                throw ParseError(
                    "\(kind) #\(name) argument for \(parameter.localName) should not use label \(actualLabel)."
                )
            }
            bindings[parameter.localName] = argument.value
        }

        for parameter in parameters.dropFirst(arguments.count) {
            guard let defaultValue = parameter.defaultValue else {
                throw ParseError("\(kind) #\(name) requires argument \(parameter.localName).")
            }
            bindings[parameter.localName] = defaultValue
        }

        return bindings
    }

    static func macroArgumentLabel(for parameter: NeatFunctionParameter) -> String? {
        parameter.externalLabel
    }
}
