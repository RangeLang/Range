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
        if parameters.count == 1, parameters[0].capturesSyntax {
            return [parameters[0].localName: .string(normalizedArgumentClause)]
        }

        do {
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
        } catch {
            if parameters.count == 1, parameters[0].capturesSyntax {
                return [parameters[0].localName: .identifier(normalizedArgumentClause)]
            }
            throw error
        }
    }

    static func parseMarkerArgumentBindings(
        for marker: MarkerDeclaration,
        argumentClause: String?,
        rawBody: String? = nil
    ) throws -> [String: Expression] {
        let parameters = marker.parameters
        let normalizedArgumentClause = argumentClause?.trimmingCharacters(in: .whitespacesAndNewlines)

        if let rawBody {
            guard normalizedArgumentClause == nil || normalizedArgumentClause == "" else {
                throw ParseError("Marker #\(marker.name) cannot mix arguments with a raw body.")
            }
            guard marker.foreignBodyLanguage != nil else {
                throw ParseError("Marker #\(marker.name) does not accept a foreign body.")
            }
            let parameter = parameters[0]
            return [parameter.localName: .string(rawBody)]
        }

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
        if let firstParameter = parameters.first, firstParameter.capturesSyntax {
            return try capturedMarkerArgumentBindings(
                kind: "Marker",
                name: marker.name,
                parameters: parameters,
                argumentClause: normalizedArgumentClause
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

    private static func capturedMarkerArgumentBindings(
        kind: String,
        name: String,
        parameters: [RangeFunctionParameter],
        argumentClause: String
    ) throws -> [String: Expression] {
        let firstParameter = parameters[0]
        let remainingParameters = Array(parameters.dropFirst())
        let (capturedSource, remainingSource) = splitCapturedArgument(argumentClause)
        var bindings = [
            firstParameter.localName: capturedSyntaxValue(capturedSource, for: firstParameter)
        ]

        if !remainingParameters.isEmpty {
            let remainingArguments: [CallArgument]
            if let remainingSource, !remainingSource.isEmpty {
                var parser = try Parser(source: "marker(\(remainingSource))")
                _ = try parser.consumeCallableName()
                remainingArguments = try parser.parseInvocationArgumentsIfPresent()
                try parser.consume(Token.eof)
            } else {
                remainingArguments = []
            }

            let remainingBindings = try argumentBindings(
                kind: kind,
                name: name,
                parameters: remainingParameters,
                arguments: remainingArguments
            )
            for (key, value) in remainingBindings {
                bindings[key] = value
            }
        }

        return bindings
    }

    private static func capturedSyntaxValue(
        _ source: String,
        for parameter: RangeFunctionParameter
    ) -> Expression {
        let captureType = parameter.captureMetadataType ?? parameter.typeReference
        guard captureType?.displayName == "Expression" else {
            return .string(source)
        }

        return .call(
            name: "WrittenExpression",
            arguments: [
                CallArgument(label: "type", value: .nilLiteral),
                CallArgument(
                    label: "written",
                    value: .call(
                        name: "WrittenSyntax",
                        arguments: [
                            CallArgument(label: "text", value: .string(source)),
                            CallArgument(label: "range", value: .nilLiteral)
                        ]
                    )
                )
            ]
        )
    }

    private static func splitCapturedArgument(_ source: String) -> (captured: String, remaining: String?) {
        var depth = 0
        var inString = false
        var previousWasEscape = false

        for (offset, character) in source.enumerated() {
            if inString {
                if character == "\"" && !previousWasEscape {
                    inString = false
                }
                previousWasEscape = character == "\\" && !previousWasEscape
                continue
            }

            switch character {
            case "\"":
                inString = true
                previousWasEscape = false
            case "(", "[", "{":
                depth += 1
            case ")", "]", "}":
                depth = max(0, depth - 1)
            case "," where depth == 0:
                let index = source.index(source.startIndex, offsetBy: offset)
                let captured = source[..<index].trimmingCharacters(in: .whitespacesAndNewlines)
                let remainingStart = source.index(after: index)
                let remaining = source[remainingStart...].trimmingCharacters(in: .whitespacesAndNewlines)
                return (captured, remaining.isEmpty ? nil : String(remaining))
            default:
                break
            }
        }

        return (source.trimmingCharacters(in: .whitespacesAndNewlines), nil)
    }

    private static func argumentBindings(
        kind: String,
        name: String,
        parameters: [RangeFunctionParameter],
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
            bindings[parameter.localName] = normalizedArgumentValue(
                argument.value,
                for: parameter,
                kind: kind
            )
        }

        for parameter in parameters.dropFirst(arguments.count) {
            if let defaultValue = parameter.defaultValue {
                bindings[parameter.localName] = defaultValue
                continue
            }
            if parameter.typeReference?.isOptionalReference == true {
                bindings[parameter.localName] = .nilLiteral
                continue
            }
            throw ParseError("\(kind) #\(name) requires argument \(parameter.localName).")
        }

        return bindings
    }

    private static func normalizedArgumentValue(
        _ value: Expression,
        for parameter: RangeFunctionParameter,
        kind: String
    ) -> Expression {
        guard kind == "Marker" else {
            return value
        }
        guard case .named("Identifier") = parameter.typeReference,
            case .identifier(let name) = value
        else {
            return value
        }

        return .call(
            name: "Identifier",
            arguments: [CallArgument(label: "name", value: .string(name))]
        )
    }

    static func macroArgumentLabel(for parameter: RangeFunctionParameter) -> String? {
        parameter.externalLabel
    }
}

private extension TypeReference {
    var isOptionalReference: Bool {
        guard case .optional = self else {
            return false
        }
        return true
    }
}
