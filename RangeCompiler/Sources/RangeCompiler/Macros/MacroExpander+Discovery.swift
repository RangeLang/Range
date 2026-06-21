import Foundation

extension MacroExpander {
    public static func collectMacros(from files: [ParsedSourceFile]) -> [String: MacroDeclaration] {
        var registry: [String: MacroDeclaration] = [:]
        for parsedFile in files {
            for macro in self.macros(in: parsedFile.sourceFile) {
                if metadataDeclaration(from: macro) != nil {
                    continue
                }
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

    static func macros(in sourceFile: SourceFileNode) -> [MacroDeclaration] {
        switch sourceFile {
        case .macro(let declaration):
            return [declaration]
        case .module(let module):
            return module.macros
        case .construct, .enumeration, .mainBlock, .extensions:
            return []
        }
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
        if case .macroSurface("block") = firstTarget {
            return nil
        }
        guard macro.expansionType != nil else {
            return nil
        }
        guard !macro.body.contains(where: containsMacroRewrite) else {
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
            bindings: macro.bindings,
            body: macro.body
        )
    }

    private static func containsMacroRewrite(_ statement: Statement) -> Bool {
        switch statement {
        case .expand, .replace:
            return true
        case .expression(let expression), .return(let expression?):
            return expressionContainsMacroRewrite(expression)
        case .macroInvocation(_, _, let body),
            .derived(_, _, let body),
            .forEach(_, _, let body),
            .whileLoop(_, let body):
            return body.contains(where: containsMacroRewrite)
        case .background(let block):
            return block.body.contains(where: containsMacroRewrite)
        case .deferBlock(let block):
            return block.body.contains(where: containsMacroRewrite)
        case .localCallable(let declaration):
            return declaration.body.contains(where: containsMacroRewrite)
        case .conditional(let branches):
            return branches.contains { $0.body.contains(where: containsMacroRewrite) }
        case .switchStatement(_, let cases, let defaultBody):
            return cases.contains { $0.body.contains(where: containsMacroRewrite) }
                || (defaultBody?.contains(where: containsMacroRewrite) ?? false)
        case .macroApplication(_, let arguments):
            return arguments.contains { expressionContainsMacroRewrite($0.value) }
        case .localBinding, .assignment, .compoundAssignment, .return, .break, .continue:
            return false
        }
    }

    private static func expressionContainsMacroRewrite(_ expression: Expression) -> Bool {
        switch expression {
        case .call(let name, let arguments):
            return name.hasSuffix(".replace")
                || arguments.contains { expressionContainsMacroRewrite($0.value) }
        case .macroInvocation(_, let arguments):
            return arguments.contains { expressionContainsMacroRewrite($0.value) }
        case .block(let statements):
            return statements.contains(where: containsMacroRewrite)
        case .interpolatedString(let string):
            return string.segments.contains { segment in
                if case .expression(let expression) = segment {
                    return expressionContainsMacroRewrite(expression)
                }
                return false
            }
        case .array(let values):
            return values.contains(where: expressionContainsMacroRewrite)
        case .dictionary(let elements):
            return elements.contains {
                expressionContainsMacroRewrite($0.key) || expressionContainsMacroRewrite($0.value)
            }
        case .ternary(let condition, let trueExpression, let falseExpression):
            return expressionContainsMacroRewrite(condition)
                || expressionContainsMacroRewrite(trueExpression)
                || expressionContainsMacroRewrite(falseExpression)
        case .unary(_, let expression):
            return expressionContainsMacroRewrite(expression)
        case .binary(let lhs, _, let rhs):
            return expressionContainsMacroRewrite(lhs) || expressionContainsMacroRewrite(rhs)
        case .integer, .double, .string, .boolean, .nilLiteral, .identifier, .bindingReference:
            return false
        }
    }

}
