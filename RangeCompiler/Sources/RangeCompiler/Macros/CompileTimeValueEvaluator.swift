import Foundation

struct CompileTimeValueEvaluator {
    let targetBinding: String
    let targetValue: CompileTimeValue
    let graphBinding: String?
    let selfValue: CompileTimeValue?
    let localBindings: [String: Expression]
    let macroDeclarationsByName: [String: MacroDeclaration]
    let knownObjectTypeNames: Set<String>
    let context: MacroExpansionContext?

    init(
        targetBinding: String,
        targetValue: CompileTimeValue,
        graphBinding: String? = nil,
        selfValue: CompileTimeValue? = nil,
        localBindings: [String: Expression],
        macroDeclarationsByName: [String: MacroDeclaration] = [:],
        knownObjectTypeNames: Set<String> = [],
        context: MacroExpansionContext? = nil
    ) {
        self.targetBinding = targetBinding
        self.targetValue = targetValue
        self.graphBinding = graphBinding
        self.selfValue = selfValue
        self.localBindings = localBindings
        self.macroDeclarationsByName = macroDeclarationsByName
        self.knownObjectTypeNames = knownObjectTypeNames
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
        case .nilLiteral:
            return .nilValue
        case .macroInvocation(let name, let arguments):
            guard let macro = macroDeclarationsByName[name],
                macro.target == nil,
                let context,
                let value = try? MacroExpander.evaluateFreestandingSyntaxMacro(
                    macro,
                    arguments: arguments,
                    callerLocals: locals,
                    callerSelfValue: selfValue,
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
                let local = locals[name],
                let value = evaluate(local, locals: locals)
            {
                return value
            }
            if let context,
                let rewritten = try? MacroExpander.applyInitMacroRewritesIfNeeded(
                    callName: name,
                    callArguments: arguments,
                    macros: macroDeclarationsByName,
                    context: context
                )
            {
                return evaluate(rewritten, locals: locals)
            }
            if let graphValue = evaluateGraphCall(
                name: name,
                arguments: arguments,
                locals: locals
            ) {
                return graphValue
            }
            if let fileSystemValue = evaluateFileSystemCall(
                name: name,
                arguments: arguments,
                locals: locals
            ) {
                return fileSystemValue
            }
            if let stringValue = evaluateStringTransform(
                name: name,
                arguments: arguments,
                locals: locals
            ) {
                return stringValue
            }
            if let stringValue = evaluateStringCall(
                name: name,
                arguments: arguments,
                locals: locals
            ) {
                return stringValue
            }
            if arguments.isEmpty,
                let dot = name.lastIndex(of: "."),
                dot < name.index(before: name.endIndex)
            {
                return enumCaseValue(named: String(name[name.index(after: dot)...]))
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
        case .unary(.not, let expression):
            guard case .boolean(let value) = evaluate(expression, locals: locals) else {
                return nil
            }
            return .boolean(!value)
        case .binary(let lhs, .addition, let rhs):
            let leftValue = evaluate(lhs, locals: locals)
            let rightValue = evaluate(rhs, locals: locals)
            switch (leftValue, rightValue) {
            case (.integer(let left)?, .integer(let right)?):
                return .integer(left + right)
            case (.string(let left)?, .string(let right)?):
                return .string(left + right)
            default:
                return nil
            }
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
        case .binary(let lhs, .nilCoalescing, let rhs):
            guard let left = evaluate(lhs, locals: locals) else {
                return nil
            }
            if case .nilValue = left {
                return evaluate(rhs, locals: locals)
            }
            return left
        case .binary(let lhs, .less, let rhs):
            return evaluateIntegerComparison(lhs, rhs, locals: locals, <)
        case .binary(let lhs, .lessEqual, let rhs):
            return evaluateIntegerComparison(lhs, rhs, locals: locals, <=)
        case .binary(let lhs, .greater, let rhs):
            return evaluateIntegerComparison(lhs, rhs, locals: locals, >)
        case .binary(let lhs, .greaterEqual, let rhs):
            return evaluateIntegerComparison(lhs, rhs, locals: locals, >=)
        default:
            return nil
        }
    }

    private func evaluateIntegerComparison(
        _ lhs: Expression,
        _ rhs: Expression,
        locals: [String: Expression],
        _ compare: (Int, Int) -> Bool
    ) -> CompileTimeValue? {
        guard case .integer(let left) = evaluate(lhs, locals: locals),
            case .integer(let right) = evaluate(rhs, locals: locals)
        else {
            return nil
        }
        return .boolean(compare(left, right))
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
        case (.nilValue, .nilValue):
            return true
        case (.array(let left), .array(let right)):
            guard left.count == right.count else {
                return false
            }
            return zip(left, right).allSatisfy(valuesEqual)
        case (.object("Enum.Case", let left), .object("Enum.Case", let right)):
            guard let leftName = enumCaseName(left),
                let rightName = enumCaseName(right)
            else {
                return false
            }
            return leftName == rightName
        case (.object(let leftType, let leftFields), .object(let rightType, let rightFields)):
            guard leftType == rightType, Set(leftFields.keys) == Set(rightFields.keys) else {
                return false
            }
            return leftFields.allSatisfy { key, leftValue in
                guard let rightValue = rightFields[key] else {
                    return false
                }
                return valuesEqual(leftValue, rightValue)
            }
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
        } else if root == "self" {
            value = selfValue
        } else if root == graphBinding {
            value = .object(
                typeName: "GraphContext",
                fields: [
                    "main": context?.graphContext.mainMacro() ?? .nilValue,
                    "macros": context?.graphContext.macros() ?? .array([])
                ]
            )
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

            if case .string(let value) = current {
                switch component {
                case "count":
                    current = .integer(value.count)
                    continue
                case "isEmpty":
                    current = .boolean(value.isEmpty)
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

    private func evaluateStringCall(
        name: String,
        arguments: [CallArgument],
        locals: [String: Expression]
    ) -> CompileTimeValue? {
        if let value = evaluateStringSourceCall(
            name: name,
            arguments: arguments,
            locals: locals
        ) {
            return value
        }

        let suffix = ".character"
        guard name.hasSuffix(suffix),
            let source = evaluatePath(String(name.dropLast(suffix.count)), locals: locals),
            case .string(let value) = source,
            arguments.count == 1,
            arguments[0].label == "index",
            case .integer(let index) = evaluate(arguments[0].value, locals: locals),
            index >= 0,
            index < value.count
        else {
            return nil
        }

        let stringIndex = value.index(value.startIndex, offsetBy: index)
        return .string(String(value[stringIndex]))
    }

    private func evaluateStringSourceCall(
        name: String,
        arguments: [CallArgument],
        locals: [String: Expression]
    ) -> CompileTimeValue? {
        let supportedSuffixes = [".count", ".hasPrefix", ".hasSuffix", ".containsRepeated", ".segment"]
        guard let suffix = supportedSuffixes.first(where: { name.hasSuffix($0) }),
            let source = evaluatePath(String(name.dropLast(suffix.count)), locals: locals),
            case .string(let value) = source
        else {
            return nil
        }

        switch suffix {
        case ".count":
            guard arguments.count == 1 else { return nil }
            let argument = arguments[0]
            guard case .string(let needle) = evaluate(argument.value, locals: locals) else {
                return nil
            }
            guard argument.label == "of" else { return nil }
            guard !needle.isEmpty else { return .integer(0) }
            var count = 0
            var searchStart = value.startIndex
            while searchStart < value.endIndex,
                let range = value.range(of: needle, range: searchStart..<value.endIndex)
            {
                count += 1
                searchStart = range.upperBound
            }
            return .integer(count)
        case ".hasPrefix":
            guard arguments.count == 1 else { return nil }
            let argument = arguments[0]
            guard case .string(let needle) = evaluate(argument.value, locals: locals) else {
                return nil
            }
            guard argument.label == nil else { return nil }
            return .boolean(value.hasPrefix(needle))
        case ".hasSuffix":
            guard arguments.count == 1 else { return nil }
            let argument = arguments[0]
            guard case .string(let needle) = evaluate(argument.value, locals: locals) else {
                return nil
            }
            guard argument.label == nil else { return nil }
            return .boolean(value.hasSuffix(needle))
        case ".containsRepeated":
            guard arguments.count == 1 else { return nil }
            let argument = arguments[0]
            guard case .string(let needle) = evaluate(argument.value, locals: locals) else {
                return nil
            }
            guard argument.label == "delimiter" else { return nil }
            guard !needle.isEmpty else { return .boolean(false) }
            return .boolean(value.contains("\(needle)\(needle)"))
        case ".segment":
            guard arguments.count == 2,
                let indexArgument = arguments.first(where: { $0.label == "index" }),
                let delimiterArgument = arguments.first(where: { $0.label == "delimiter" }),
                case .integer(let index) = evaluate(indexArgument.value, locals: locals),
                case .string(let delimiter) = evaluate(delimiterArgument.value, locals: locals),
                index >= 0,
                !delimiter.isEmpty
            else {
                return nil
            }
            let segments = value.components(separatedBy: delimiter)
            guard index < segments.count else {
                return nil
            }
            return .string(segments[index])
        default:
            return nil
        }
    }

    private func evaluateObjectConstruction(
        name: String,
        arguments: [CallArgument],
        locals: [String: Expression]
    ) -> CompileTimeValue? {
        if let primitive = evaluatePrimitiveConstruction(
            name: name,
            arguments: arguments,
            locals: locals
        ) {
            return primitive
        }

        if name == "Array" || name.hasPrefix("Array<") {
            guard arguments.count == 1,
                arguments[0].label == nil,
                case .array = evaluate(arguments[0].value, locals: locals)
            else {
                return nil
            }
            return evaluate(arguments[0].value, locals: locals)
        }

        if arguments.count == 1,
            arguments[0].label == nil,
            let value = evaluate(arguments[0].value, locals: locals),
            case .object(let typeName, _) = value
        {
            if typeName == name {
                return value
            }
        }

        if isKnownObjectType(name) {
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
        }

        return nil
    }

    private func isKnownObjectType(_ name: String) -> Bool {
        Self.builtInObjectTypeNames.contains(name)
            || knownObjectTypeNames.contains(name)
            || context?.graphContext.knownObjectTypeNames.contains(name) == true
    }

    private static let builtInObjectTypeNames: Set<String> = [
        "Enum", "Enum.Declaration", "Enum.Case", "Enum.AssociatedValue", "Identifier", "NamedTypeReference",
        "MemberTypeReference", "ArrayTypeReference", "Let", "State", "Binding", "Derived", "Init.Declaration",
        "Function.Declaration", "Construct.Declaration", "Extension", "TypeGeneric",
        "Macro.Application", "Macro.Declaration", "Macro.Target", "CodingBehavior",
        "ValueGeneric", "Parameter.Declaration",
        "Void", "Identity", "UUID", "UUIDStorage", "RangeGraphIdentity", "GraphRole", "GraphEntry", "WrittenSyntax", "Parsed", "Block", "LocalBinding", "Switch",
        "SwitchCase", "Return", "Break", "Assignment", "ExpressionStatement",
        "WrittenExpression",
        "ArrayExpression", "EnumCaseExpression", "CompilerPipelineRuntimeContext", "CompilerPipelineRuntimeResult", "CompilerPipelineRuntimeHook",
    ]

    private func evaluatePrimitiveConstruction(
        name: String,
        arguments: [CallArgument],
        locals: [String: Expression]
    ) -> CompileTimeValue? {
        guard arguments.count == 1,
            arguments[0].label == nil,
            let value = evaluate(arguments[0].value, locals: locals)
        else {
            return nil
        }

        switch (name, value) {
        case ("String", .string), ("Int", .integer), ("Bool", .boolean), ("Float", .double):
            return value
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
        case "\(graphBinding).sourcePath":
            guard arguments.count == 1,
                arguments[0].label == "of",
                let identity = evaluate(arguments[0].value, locals: locals)
            else {
                return nil
            }
            return context.graphContext.sourcePath(of: identity)
        case "\(graphBinding).sourceDirectory":
            guard arguments.count == 1,
                arguments[0].label == "of",
                let identity = evaluate(arguments[0].value, locals: locals)
            else {
                return nil
            }
            return context.graphContext.sourceDirectory(of: identity)
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

    private func evaluateFileSystemCall(
        name: String,
        arguments: [CallArgument],
        locals: [String: Expression]
    ) -> CompileTimeValue? {
        guard name == "FileTree.rangeFiles",
            arguments.count == 1,
            arguments[0].label == "path",
            case .string(let path) = evaluate(arguments[0].value, locals: locals)
        else {
            return nil
        }

        let root = URL(fileURLWithPath: path, isDirectory: true)
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return .array([])
        }

        var files: [CompileTimeValue] = []
        for case let url as URL in enumerator {
            guard url.pathExtension == "range" else { continue }
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
            guard values?.isRegularFile == true else { continue }
            files.append(.string(url.path))
        }

        return .array(files.sorted {
            guard case .string(let left) = $0, case .string(let right) = $1 else {
                return false
            }
            return left < right
        })
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
        if name.hasSuffix(".element"),
            let source = evaluatePath(String(name.dropLast(".element".count)), locals: locals),
            case .array(let elements) = source,
            arguments.count == 1,
            arguments[0].label == "index",
            case .integer(let index) = evaluate(arguments[0].value, locals: locals),
            index >= 0,
            index < elements.count
        {
            return elements[index]
        }

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
        let supportedSuffixes = [".map", ".compactMap", ".flatMap", ".filter", ".where"]
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
        case ".filter", ".where":
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
            case .macroInvocation(let name, let argumentClause, _):
                guard let macro = macroDeclarationsByName[name] else {
                    return nil
                }
                let arguments: [CallArgument]
                if let argumentClause = argumentClause?.trimmingCharacters(in: .whitespacesAndNewlines),
                    !argumentClause.isEmpty
                {
                    var parser = try? Parser(source: "macro(\(argumentClause))")
                    guard parser != nil else {
                        return nil
                    }
                    _ = try? parser?.consumeCallableName()
                    guard let parsedArguments = try? parser?.parseInvocationArgumentsIfPresent() else {
                        return nil
                    }
                    arguments = parsedArguments
                } else {
                    arguments = []
                }
                guard let context,
                    let value = try? MacroExpander.evaluateFreestandingSyntaxMacro(
                        macro,
                        arguments: arguments,
                        callerLocals: nestedLocals,
                        callerSelfValue: selfValue,
                        context: context
                    )
                else {
                    return nil
                }
                return value
            case .expression(let expression):
                if case .macroInvocation(let name, let arguments) = expression,
                    let macro = macroDeclarationsByName[name],
                    let context
                {
                    let resolvedArguments = arguments.map { argument in
                        if let value = evaluate(argument.value, locals: nestedLocals),
                            let expression = value.expression
                        {
                            return CallArgument(label: argument.label, value: expression)
                        }
                        return argument
                    }
                    return try? MacroExpander.evaluateFreestandingSyntaxMacro(
                        macro,
                        arguments: resolvedArguments,
                        callerLocals: nestedLocals,
                        callerSelfValue: selfValue,
                        context: context
                    )
                }
                let value = evaluate(expression, locals: nestedLocals)
                return value
            case .return(let expression?):
                return evaluate(expression, locals: nestedLocals)
            case .switchStatement:
                return try? MacroExpander.statementSyntaxValue(statement)
            case .conditional(let branches):
                for branch in branches {
                    if let condition = branch.condition {
                        guard case .boolean(true) = evaluate(condition, locals: nestedLocals) else {
                            continue
                        }
                    }
                    return evaluateSingleParameterClosure(
                        [
                            CallArgument(label: "parameters", value: .array([.identifier(parameterName)])),
                            CallArgument(label: "body", value: .block(branch.body)),
                        ],
                        element: element,
                        locals: nestedLocals
                    )
                }
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
