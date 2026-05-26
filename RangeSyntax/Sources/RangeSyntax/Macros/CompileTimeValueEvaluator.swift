import Foundation

struct CompileTimeValueEvaluator {
    let targetBinding: String
    let targetValue: CompileTimeValue
    let graphBinding: String?
    let localBindings: [String: Expression]
    let macroDeclarationsByName: [String: MacroDeclaration]
    let context: MacroExpansionContext?

    init(
        targetBinding: String,
        targetValue: CompileTimeValue,
        graphBinding: String? = nil,
        localBindings: [String: Expression],
        macroDeclarationsByName: [String: MacroDeclaration] = [:],
        context: MacroExpansionContext? = nil
    ) {
        self.targetBinding = targetBinding
        self.targetValue = targetValue
        self.graphBinding = graphBinding
        self.localBindings = localBindings
        self.macroDeclarationsByName = macroDeclarationsByName
        self.context = context
    }

    func evaluate(_ expression: Expression) -> CompileTimeValue? {
        evaluate(expression, locals: localBindings)
    }

    func evaluate(_ expression: Expression, with locals: [String: Expression]) -> CompileTimeValue? {
        evaluate(expression, locals: locals)
    }

    private func evaluate(
        _ expression: Expression,
        locals: [String: Expression]
    ) -> CompileTimeValue? {
        switch expression {
        case .string(let value):
            return .string(StringLiteral.decodeEscapes(value))
        case .interpolatedString(let string):
            return evaluateInterpolatedString(string, locals: locals)
        case .integer(let value):
            return .integer(value)
        case .double(let value):
            return .double(value)
        case .boolean(let value):
            return .boolean(value)
        case .macroInvocation(let name, let arguments):
            guard let macro = macroDeclarationsByName[name],
                macro.target == nil,
                let context,
                let value = try? MacroExpander.evaluateFreestandingSyntaxMacro(
                    macro,
                    arguments: arguments,
                    callerLocals: locals,
                    context: context
                )
            else {
                return nil
            }
            return value
        case .identifier(let path):
            if let bound = locals[path] {
                if case .identifier(path) = bound {
                    return evaluatePath(path, locals: locals)
                }
                return evaluate(bound, locals: locals)
            }
            if path.hasPrefix(".") {
                return enumCaseValue(named: String(path.dropFirst()))
            }
            let components = path.split(separator: ".").map(String.init)
            if components.count == 2,
                let root = components.first,
                root.first?.isUppercase == true
            {
                return enumCaseValue(named: components[1])
            }
            return evaluatePath(path, locals: locals)
        case .array(let elements):
            let values = elements.compactMap { evaluate($0, locals: locals) }
            guard values.count == elements.count else {
                return nil
            }
            return .array(values)
        case .call(let name, let arguments):
            if arguments.isEmpty,
                let dot = name.lastIndex(of: "."),
                dot < name.index(before: name.endIndex)
            {
                return enumCaseValue(named: String(name[name.index(after: dot)...]))
            }
            if let graphValue = evaluateGraphCall(
                name: name,
                arguments: arguments,
                locals: locals
            ) {
                return graphValue
            }
            if let stringValue = evaluateStringTransform(
                name: name,
                arguments: arguments,
                locals: locals
            ) {
                return stringValue
            }
            if let transformed = evaluateArrayTransform(
                name: name,
                arguments: arguments,
                locals: locals
            ) {
                return transformed
            }
            if let element = evaluateArrayElementAccess(
                name: name,
                arguments: arguments,
                locals: locals
            ) {
                return element
            }
            return evaluateObjectConstruction(name: name, arguments: arguments, locals: locals)
        case .ternary(let condition, let trueExpression, let falseExpression):
            guard case .boolean(let conditionValue) = evaluate(condition, locals: locals) else {
                return nil
            }
            return evaluate(conditionValue ? trueExpression : falseExpression, locals: locals)
        case .binary(let lhs, .addition, let rhs):
            guard case .string(let left) = evaluate(lhs, locals: locals),
                case .string(let right) = evaluate(rhs, locals: locals)
            else {
                return nil
            }
            return .string(left + right)
        case .binary(let lhs, .subtraction, let rhs):
            guard case .integer(let left) = evaluate(lhs, locals: locals),
                case .integer(let right) = evaluate(rhs, locals: locals)
            else {
                return nil
            }
            return .integer(left - right)
        case .binary(let lhs, .equal, let rhs):
            guard let left = evaluate(lhs, locals: locals),
                let right = evaluate(rhs, locals: locals)
            else {
                return nil
            }
            return .boolean(valuesEqual(left, right))
        case .binary(let lhs, .notEqual, let rhs):
            guard let left = evaluate(lhs, locals: locals),
                let right = evaluate(rhs, locals: locals)
            else {
                return nil
            }
            return .boolean(!valuesEqual(left, right))
        default:
            return nil
        }
    }

    private func enumCaseValue(named name: String) -> CompileTimeValue {
        .object(
            typeName: "Enum.Case",
            fields: [
                "identifier": .object(typeName: "Identifier", fields: ["name": .string(name)]),
                "associatedValues": .array([]),
            ]
        )
    }

    private func valuesEqual(_ lhs: CompileTimeValue, _ rhs: CompileTimeValue) -> Bool {
        switch (lhs, rhs) {
        case (.string(let left), .string(let right)):
            return left == right
        case (.integer(let left), .integer(let right)):
            return left == right
        case (.double(let left), .double(let right)):
            return left == right
        case (.boolean(let left), .boolean(let right)):
            return left == right
        case (.object("Enum.Case", let left), .object("Enum.Case", let right)):
            guard let leftName = enumCaseName(left),
                let rightName = enumCaseName(right)
            else {
                return false
            }
            return leftName == rightName
        default:
            return false
        }
    }

    private func enumCaseName(_ fields: [String: CompileTimeValue]) -> String? {
        if case .string(let name)? = fields["name"] {
            return name
        }
        guard case .object("Identifier", let identifierFields)? = fields["identifier"],
            case .string(let name)? = identifierFields["name"]
        else {
            return nil
        }
        return name
    }

    private func evaluatePath(_ path: String, locals: [String: Expression]) -> CompileTimeValue? {
        let components = path.split(separator: ".").map(String.init)
        guard !components.isEmpty else {
            return nil
        }

        let root = components[0]
        let value: CompileTimeValue?
        if root == targetBinding {
            value = targetValue
        } else if root == graphBinding {
            value = .object(typeName: "GraphContext", fields: [:])
        } else if let local = locals[root] {
            if case .identifier(root) = local {
                return nil
            }
            value = evaluate(local, locals: locals)
        } else {
            value = nil
        }

        guard var current = value else {
            return nil
        }

        for component in components.dropFirst() {
            if case .array(let values) = current {
                switch component {
                case "count":
                    current = .integer(values.count)
                    continue
                case "isEmpty":
                    current = .boolean(values.isEmpty)
                    continue
                default:
                    break
                }
            }

            guard let next = current.field(component) else {
                return nil
            }
            current = next
        }

        return current
    }

    private func evaluateObjectConstruction(
        name: String,
        arguments: [CallArgument],
        locals: [String: Expression]
    ) -> CompileTimeValue? {
        switch name {
        case "Enum", "Enum.Declaration", "Enum.Case", "Enum.AssociatedValue", "Identifier", "NamedTypeReference",
            "MemberTypeReference", "ArrayTypeReference", "Let", "State", "Binding", "Derived", "Init.Declaration",
            "Function.Declaration", "Construct.Declaration", "Extension", "TypeGeneric",
            "ValueGeneric", "GraphIdentity", "Macro.Application", "Macro.Declaration", "Macro.Target",
            "Marker.Application", "WrittenSyntax", "Parsed", "Block", "LocalBinding", "Switch",
            "SwitchCase", "Return", "Break", "Assignment", "ExpressionStatement",
            "ArrayExpression", "EnumCaseExpression", "Lexer", "LexerRule", "LexerRepresentation", "LexicalToken", "TokenKind", "Token", "Delimiter", "OperatorBindingRange", "OperatorBindingMetric", "OperatorBinding", "SourceLocation", "SourceRange", "ASCIILiteral", "ASCII", "CompilerPipelineRuntimeContext", "CompilerPipelineRuntimeResult", "CompilerPipelineRuntimeHook":
            var fields: [String: CompileTimeValue] = [:]
            for argument in arguments {
                guard let label = argument.label,
                    let value = evaluate(argument.value, locals: locals)
                else {
                    return nil
                }
                fields[label] = value
            }
            return .object(typeName: name, fields: fields)
        default:
            return nil
        }
    }

    private func evaluateGraphCall(
        name: String,
        arguments: [CallArgument],
        locals: [String: Expression]
    ) -> CompileTimeValue? {
        guard let graphBinding,
            let context,
            name.hasPrefix("\(graphBinding).")
        else {
            return nil
        }

        switch name {
        case "\(graphBinding).declaration":
            guard arguments.count == 1,
                let identity = evaluate(arguments[0].value, locals: locals)
            else {
                return nil
            }
            return context.graphContext.declaration(for: identity)
        case "\(graphBinding).parent":
            guard arguments.count == 1,
                arguments[0].label == "of",
                let identity = evaluate(arguments[0].value, locals: locals)
            else {
                return nil
            }
            return context.graphContext.parent(of: identity)
        case "\(graphBinding).members":
            guard arguments.count == 1,
                arguments[0].label == "of",
                let identity = evaluate(arguments[0].value, locals: locals)
            else {
                return nil
            }
            return context.graphContext.members(of: identity)
        case "\(graphBinding).markers":
            guard arguments.count == 1,
                arguments[0].label == "on",
                let identity = evaluate(arguments[0].value, locals: locals)
            else {
                return nil
            }
            return context.graphContext.markers(on: identity)
        case "\(graphBinding).macros":
            guard arguments.count == 1 else {
                return nil
            }
            if arguments[0].label == "on",
                let identity = evaluate(arguments[0].value, locals: locals)
            {
                return context.graphContext.macros(on: identity)
            }
            if arguments[0].label == "named",
                case .string(let name)? = evaluate(arguments[0].value, locals: locals)
            {
                return context.graphContext.macros(named: name)
            }
            return nil
        default:
            return nil
        }
    }

    private func evaluateStringTransform(
        name: String,
        arguments: [CallArgument],
        locals: [String: Expression]
    ) -> CompileTimeValue? {
        let supportedSuffixes = [".snakeCase", ".obfuscated", ".lastComponent"]
        guard let suffix = supportedSuffixes.first(where: { name.hasSuffix($0) }),
            arguments.isEmpty,
            let source = evaluatePath(String(name.dropLast(suffix.count)), locals: locals),
            case .string(let value) = source
        else {
            return nil
        }

        switch suffix {
        case ".snakeCase":
            return .string(snakeCase(value))
        case ".obfuscated":
            return .string(obfuscated(value))
        case ".lastComponent":
            return .string(value.split(separator: ".").last.map(String.init) ?? value)
        default:
            return nil
        }
    }

    private func obfuscated(_ name: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in name.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return "r_" + String(hash, radix: 16)
    }

    private func snakeCase(_ name: String) -> String {
        var result = ""
        var previousWasLowercaseOrDigit = false

        for scalar in name.unicodeScalars {
            let character = Character(scalar)
            let string = String(character)
            let isUppercase = string.uppercased() == string && string.lowercased() != string
            let isLowercase = string.lowercased() == string && string.uppercased() != string
            let isDigit = CharacterSet.decimalDigits.contains(scalar)

            if isUppercase && previousWasLowercaseOrDigit && !result.isEmpty {
                result.append("_")
            }

            result.append(string.lowercased())
            previousWasLowercaseOrDigit = isLowercase || isDigit
        }

        return result
    }

    private func evaluateInterpolatedString(
        _ string: InterpolatedString,
        locals: [String: Expression]
    ) -> CompileTimeValue? {
        var result = ""

        for segment in string.segments {
            switch segment {
            case .text(let text):
                result.append(StringLiteral.decodeEscapes(text))
            case .expression(let expression):
                guard let value = evaluate(expression, locals: locals),
                    let string = interpolatedStringValue(value)
                else {
                    return nil
                }
                result.append(string)
            }
        }

        return .string(result)
    }

    private func interpolatedStringValue(_ value: CompileTimeValue) -> String? {
        switch value {
        case .string(let string):
            return string
        case .integer(let integer):
            return String(integer)
        case .double(let double):
            return String(double)
        case .boolean(let boolean):
            return boolean ? "true" : "false"
        default:
            return nil
        }
    }

    private func evaluateArrayElementAccess(
        name: String,
        arguments: [CallArgument],
        locals: [String: Expression]
    ) -> CompileTimeValue? {
        let suffix = ".first"
        guard name.hasSuffix(suffix),
            let source = evaluatePath(String(name.dropLast(suffix.count)), locals: locals),
            case .array(let elements) = source
        else {
            return nil
        }

        let candidates: [CompileTimeValue]
        if let predicate = argument("where", in: arguments) {
            candidates = elements.filter { element in
                guard case .call("Closure", let closureArguments) = predicate else {
                    return false
                }
                guard case .boolean(true) = evaluateSingleParameterClosure(
                    closureArguments,
                    element: element,
                    locals: locals
                ) else {
                    return false
                }
                return true
            }
        } else {
            candidates = elements
        }

        if let first = candidates.first {
            return first
        }

        guard let defaultExpression = argument("default", in: arguments) else {
            return nil
        }
        return evaluate(defaultExpression, locals: locals)
    }

    private func evaluateArrayTransform(
        name: String,
        arguments: [CallArgument],
        locals: [String: Expression]
    ) -> CompileTimeValue? {
        let supportedSuffixes = [".map", ".compactMap", ".flatMap", ".filter"]
        guard let suffix = supportedSuffixes.first(where: { name.hasSuffix($0) }),
            arguments.count == 1,
            arguments[0].label == nil,
            case .call("Closure", let closureArguments) = arguments[0].value,
            let source = evaluatePath(String(name.dropLast(suffix.count)), locals: locals),
            case .array(let elements) = source
        else {
            return nil
        }

        let transformed = elements.compactMap { element -> CompileTimeValue? in
            evaluateSingleParameterClosure(
                closureArguments,
                element: element,
                locals: locals
            )
        }

        switch suffix {
        case ".map":
            guard transformed.count == elements.count else {
                return nil
            }
            return .array(transformed)
        case ".compactMap":
            return .array(transformed)
        case ".flatMap":
            var flattened: [CompileTimeValue] = []
            for value in transformed {
                guard case .array(let nested) = value else {
                    return nil
                }
                flattened.append(contentsOf: nested)
            }
            return .array(flattened)
        case ".filter":
            var filtered: [CompileTimeValue] = []
            for (element, value) in zip(elements, transformed) {
                guard case .boolean(let include) = value else {
                    return nil
                }
                if include {
                    filtered.append(element)
                }
            }
            return .array(filtered)
        default:
            return nil
        }
    }

    private func evaluateSingleParameterClosure(
        _ closureArguments: [CallArgument],
        element: CompileTimeValue,
        locals: [String: Expression]
    ) -> CompileTimeValue? {
        guard let parameterExpression = argument("parameters", in: closureArguments),
            case .array(let parameterExpressions) = parameterExpression,
            parameterExpressions.count == 1,
            case .identifier(let parameterName) = parameterExpressions[0],
            let bodyExpression = argument("body", in: closureArguments),
            case .block(let body) = bodyExpression
        else {
            return nil
        }

        var nestedLocals = locals
        nestedLocals[parameterName] = element.expression

        for statement in body {
            switch statement {
            case .localBinding(let declaration):
                nestedLocals[declaration.name] = declaration.expression
            case .expression(let expression):
                return evaluate(expression, locals: nestedLocals)
            case .return(let expression?):
                return evaluate(expression, locals: nestedLocals)
            default:
                return nil
            }
        }

        return nil
    }

    private func argument(_ label: String, in arguments: [CallArgument]) -> Expression? {
        arguments.first(where: { $0.label == label })?.value
    }
}
