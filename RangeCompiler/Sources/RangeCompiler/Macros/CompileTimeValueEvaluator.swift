import Foundation

struct CompileTimeValueEvaluator {
    let targetBinding: String
    let targetValue: CompileTimeValue
    let graphBinding: String?
    let selfValue: CompileTimeValue?
    let localBindings: [String: Expression]
    let macroDeclarationsByName: [String: MacroDeclaration]
    let callableDeclarationsByName: [String: [CallableDeclaration]]
    let knownObjectTypeNames: Set<String>
    let context: MacroExpansionContext?

    init(
        targetBinding: String,
        targetValue: CompileTimeValue,
        graphBinding: String? = nil,
        selfValue: CompileTimeValue? = nil,
        localBindings: [String: Expression],
        macroDeclarationsByName: [String: MacroDeclaration] = [:],
        callableDeclarationsByName: [String: [CallableDeclaration]] = [:],
        knownObjectTypeNames: Set<String> = [],
        context: MacroExpansionContext? = nil
    ) {
        self.targetBinding = targetBinding
        self.targetValue = targetValue
        self.graphBinding = graphBinding
        self.selfValue = selfValue
        self.localBindings = localBindings
        self.macroDeclarationsByName = macroDeclarationsByName
        self.callableDeclarationsByName = callableDeclarationsByName
        self.knownObjectTypeNames = knownObjectTypeNames
        self.context = context
    }

    func evaluate(_ expression: Expression) -> CompileTimeValue? {
        evaluate(expression, locals: localBindings)
    }

    func evaluate(_ expression: Expression, with locals: [String: Expression]) -> CompileTimeValue? {
        evaluate(expression, locals: locals)
    }

    // Unified statement-sequence evaluator. A macro body or a closure body is
    // ordinary Range syntax: bindings, assignments, conditionals, loops, returns,
    // expressions. This is the single place statements are executed at compile
    // time so macro bodies and closures don't each re-implement control flow.
    // Returns the produced value (from a `return` or value-producing expression),
    // or nil if the body produced none. `locals` is threaded mutably so
    // assignments and loop accumulation persist across statements.
    func evaluateStatements(
        _ statements: [Statement],
        locals: inout [String: Expression]
    ) -> CompileTimeValue? {
        for statement in statements {
            switch statement {
            case .localBinding(let declaration):
                locals[declaration.name] = boundExpression(declaration.expression, locals: locals)
            case .assignment(let target, let expression):
                if let name = Self.assignmentTargetName(target) {
                    locals[name] = boundExpression(expression, locals: locals)
                }
            case .return(let expression?):
                return evaluate(expression, locals: locals)
            case .macroApplication(let name, let arguments) where name == "return":
                guard let valueArgument = arguments.first(where: { $0.label == "value" }) else {
                    return .object(typeName: "Void", fields: [:])
                }
                return evaluate(valueArgument.value, locals: locals)
            case .macroApplication(let name, let arguments) where name == "state" || name == "let":
                guard let binding = macroLocalBinding(arguments: arguments, locals: locals) else {
                    continue
                }
                locals[binding.name] = binding.expression
            case .macroInvocation(let name, let argumentClause, let body) where name == "while":
                guard let condition = macroConditionExpression(argumentClause: argumentClause) else {
                    continue
                }
                while case .boolean(true) = evaluate(condition, locals: locals) {
                    if let value = evaluateStatements(body, locals: &locals) {
                        return value
                    }
                }
            case .macroInvocation(let name, let argumentClause, let body) where name == "if":
                guard let condition = macroConditionExpression(argumentClause: argumentClause),
                    case .boolean(true) = evaluate(condition, locals: locals)
                else {
                    continue
                }
                if let value = evaluateStatements(body, locals: &locals) {
                    return value
                }
            case .expression(let expression):
                if let value = evaluate(expression, locals: locals) {
                    return value
                }
            case .switchStatement:
                if let value = try? MacroExpander.statementSyntaxValue(statement) {
                    return value
                }
            case .conditional(let branches):
                for branch in branches {
                    if let condition = branch.condition {
                        guard case .boolean(true) = evaluate(condition, locals: locals) else {
                            continue
                        }
                    }
                    if let value = evaluateStatements(branch.body, locals: &locals) {
                        return value
                    }
                    break
                }
            case .forEach(let name, let sequence, let body):
                guard case .array(let elements)? = evaluate(sequence, locals: locals) else {
                    continue
                }
                for element in elements {
                    guard let elementExpression = element.expression else { continue }
                    locals[name] = elementExpression
                    if let value = evaluateStatements(body, locals: &locals) {
                        return value
                    }
                }
            default:
                continue
            }
        }
        return nil
    }

    private func macroLocalBinding(
        arguments: [CallArgument],
        locals: [String: Expression]
    ) -> (name: String, expression: Expression)? {
        guard let nameArgument = arguments.first(where: { $0.label == "name" }),
            let valueArgument = arguments.first(where: { $0.label == "value" }),
            case .string(let name) = evaluate(nameArgument.value, locals: locals)
        else {
            return nil
        }
        return (name, macroLocalValueExpression(valueArgument.value, locals: locals))
    }

    private func macroLocalValueExpression(
        _ expression: Expression,
        locals: [String: Expression]
    ) -> Expression {
        if case .string(let source) = expression,
            let parsed = try? parseMacroLocalValueSource(source)
        {
            return boundExpression(parsed, locals: locals)
        }
        return boundExpression(expression, locals: locals)
    }

    private func parseMacroLocalValueSource(_ source: String) throws -> Expression {
        var parser = try Parser(source: StringLiteral.decodeEscapes(source))
        let expression = try parser.parseExpression()
        try parser.consume(.eof)
        return expression
    }

    private func macroConditionExpression(argumentClause: String?) -> Expression? {
        guard let argumentClause = argumentClause?.trimmingCharacters(in: .whitespacesAndNewlines),
            !argumentClause.isEmpty,
            let arguments = try? MacroExpander.parsedMacroArguments(argumentClause: argumentClause)
        else {
            return .boolean(true)
        }

        if let condition = arguments.first(where: { $0.label == "condition" }) {
            return condition.value
        }

        return arguments.first?.value
    }

    // Resolves an expression to a bound expression: if it evaluates to a concrete
    // value, store that value's expression so later statements/iterations read the
    // updated result; otherwise keep the raw expression.
    private func boundExpression(
        _ expression: Expression,
        locals: [String: Expression]
    ) -> Expression {
        if let value = evaluate(expression, locals: locals), let resolved = value.expression {
            return resolved
        }
        return expression
    }

    static func assignmentTargetName(_ target: AssignmentTarget) -> String? {
        switch target {
        case .state(let name), .binding(let name), .local(let name):
            return name
        case .member:
            return nil
        }
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
            if let functionValue = evaluateUserFunctionCall(
                name: name,
                arguments: arguments,
                locals: locals
            ) {
                return functionValue
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
            if let llvmValue = evaluateLLVMCall(
                name: name,
                arguments: arguments,
                locals: locals
            ) {
                return llvmValue
            }
            if let projectValue = evaluateRangeProjectCall(
                name: name,
                arguments: arguments,
                locals: locals
            ) {
                return projectValue
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

    private func evaluateUserFunctionCall(
        name: String,
        arguments: [CallArgument],
        locals: [String: Expression]
    ) -> CompileTimeValue? {
        guard let callable = callableDeclarationsByName[name]?.first(where: { callable in
            callable.parameters.count == arguments.count
        }), let body = callable.body else {
            return nil
        }

        var nestedLocals: [String: Expression] = [:]
        for (parameter, argument) in zip(callable.parameters, arguments) {
            if let label = argument.label,
                label != parameter.name,
                label != parameter.slotName
            {
                return nil
            }
            guard let value = evaluate(argument.value, locals: locals),
                let expression = value.expression
            else {
                return nil
            }
            nestedLocals[parameter.name] = expression
        }

        let evaluator = CompileTimeValueEvaluator(
            targetBinding: targetBinding,
            targetValue: targetValue,
            graphBinding: graphBinding,
            selfValue: selfValue,
            localBindings: nestedLocals,
            macroDeclarationsByName: macroDeclarationsByName,
            callableDeclarationsByName: callableDeclarationsByName,
            knownObjectTypeNames: knownObjectTypeNames,
            context: context
        )
        return evaluator.evaluateStatements(body, locals: &nestedLocals)
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

    private func enumCaseValue(
        named name: String,
        associatedValues: [String: CompileTimeValue] = [:]
    ) -> CompileTimeValue {
        .object(
            typeName: "Enum.Case",
            fields: [
                "identifier": .object(typeName: "Identifier", fields: ["name": .string(name)]),
                "associatedValues": .array(
                    associatedValues.map { label, value in
                        .object(
                            typeName: "Enum.AssociatedValue",
                            fields: [
                                "name": .string(label),
                                "value": value,
                            ]
                        )
                    }
                ),
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
                case "snakeCase":
                    current = .string(snakeCase(value))
                    continue
                case "obfuscated":
                    current = .string(obfuscated(value))
                    continue
                case "lastComponent":
                    current = .string(value.split(separator: ".").last.map(String.init) ?? value)
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
        let supportedSuffixes = [
            ".count", ".contains", ".hasPrefix", ".hasSuffix", ".containsRepeated", ".segment",
            ".replacingOccurrences",
        ]
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
        case ".contains":
            guard arguments.count == 1 else { return nil }
            let argument = arguments[0]
            guard case .string(let needle) = evaluate(argument.value, locals: locals) else {
                return nil
            }
            guard argument.label == "value" else { return nil }
            return .boolean(value.contains(needle))
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
        case ".replacingOccurrences":
            guard arguments.count == 2,
                let ofArgument = arguments.first(where: { $0.label == "of" }),
                let withArgument = arguments.first(where: { $0.label == "with" }),
                case .string(let needle) = evaluate(ofArgument.value, locals: locals),
                case .string(let replacement) = evaluate(withArgument.value, locals: locals)
            else {
                return nil
            }
            return .string(value.replacingOccurrences(of: needle, with: replacement))
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
        "ProgramSourceFile", "ProgramArtifact", "ProgramResult", "RangeProgram", "RangeGraph", "RangeProject",
        "WrittenExpression",
        "ArrayExpression", "EnumCaseExpression", "CompilerPipelineRuntimeContext", "CompilerPipelineRuntimeResult", "CompilerPipelineRuntimeHook",
    ]

    private func evaluatePrimitiveConstruction(
        name: String,
        arguments: [CallArgument],
        locals: [String: Expression]
    ) -> CompileTimeValue? {
        if arguments.isEmpty {
            switch name {
            case "String":
                return .string("")
            default:
                return nil
            }
        }

        guard arguments.count == 1,
            arguments[0].label == nil
        else {
            return nil
        }

        if name == "String" {
            return evaluateStringConstructionArgument(arguments[0].value, locals: locals)
        }

        guard let value = evaluate(arguments[0].value, locals: locals) else {
            return nil
        }

        switch (name, value) {
        case ("Int", .integer), ("Bool", .boolean), ("Float", .double):
            return value
        default:
            return nil
        }
    }

    private func evaluateStringConstructionArgument(
        _ expression: Expression,
        locals: [String: Expression]
    ) -> CompileTimeValue? {
        if case .binary(let lhs, .addition, let rhs) = expression,
            case .string(let left)? = evaluateStringConstructionArgument(lhs, locals: locals),
            case .string(let right)? = evaluateStringConstructionArgument(rhs, locals: locals)
        {
            return .string(left + right)
        }

        guard case .string = evaluate(expression, locals: locals) else {
            return nil
        }
        return evaluate(expression, locals: locals)
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
        if name == "FileManager.createFile" {
            guard arguments.count == 2,
                let pathArgument = arguments.first(where: { $0.label == "path" }),
                let textArgument = arguments.first(where: { $0.label == "text" }),
                case .string(let path) = evaluate(pathArgument.value, locals: locals),
                case .string(let text) = evaluate(textArgument.value, locals: locals)
            else {
                return nil
            }
            return createFileResult(path: path, text: text)
        }

        guard arguments.count == 1,
            arguments[0].label == "path",
            case .string(let path) = evaluate(arguments[0].value, locals: locals)
        else {
            return nil
        }

        if name == "FileManager.readFile" {
            return readFileResult(path: path)
        }

        guard name == "FileTree.rangeFiles" || name == "FileTree.sourceFiles" else {
            return nil
        }

        let files = rangeFileURLs(in: path)
        if name == "FileTree.rangeFiles" {
            return .array(files.map { .string($0.path) })
        }

        return .array(
            files.compactMap { url in
                guard let text = try? String(contentsOf: url, encoding: .utf8) else {
                    return nil
                }
                return .object(
                    typeName: "ProgramSourceFile",
                    fields: [
                        "path": .string(url.path),
                        "text": .string(text),
                    ]
                )
            }
        )
    }

    private func evaluateLLVMCall(
        name: String,
        arguments: [CallArgument],
        locals: [String: Expression]
    ) -> CompileTimeValue? {
        guard name == "llvmMain" || name == "LLVM.main",
            arguments.count == 1,
            arguments[0].label == "body",
            case .array(let statements) = evaluate(arguments[0].value, locals: locals)
        else {
            return nil
        }

        return .string(renderLLVMMain(statements: statements))
    }

    private func evaluateRangeProjectCall(
        name: String,
        arguments: [CallArgument],
        locals: [String: Expression]
    ) -> CompileTimeValue? {
        guard arguments.isEmpty else {
            return nil
        }

        let rangeFilesSuffix = ".rangeFiles"
        let sourceFilesSuffix = ".sourceFiles"
        let suffix: String
        if name.hasSuffix(rangeFilesSuffix) {
            suffix = rangeFilesSuffix
        } else if name.hasSuffix(sourceFilesSuffix) {
            suffix = sourceFilesSuffix
        } else {
            return nil
        }

        guard let source = evaluatePath(String(name.dropLast(suffix.count)), locals: locals),
            case .object("RangeProject", let fields) = source,
            case .string(let path)? = fields["path"]
        else {
            return nil
        }

        let files = rangeFileURLs(in: path)
        if suffix == rangeFilesSuffix {
            return .array(files.map { .string($0.path) })
        }

        return .array(
            files.compactMap { url in
                guard let text = try? String(contentsOf: url, encoding: .utf8) else {
                    return nil
                }
                return .object(
                    typeName: "ProgramSourceFile",
                    fields: [
                        "path": .string(url.path),
                        "text": .string(text),
                    ]
                )
            }
        )
    }

    private func renderLLVMMain(statements: [CompileTimeValue]) -> String {
        var builder = LLVMMainBuilder()
        for statement in statements {
            builder.emit(statement: statement)
        }
        return builder.module()
    }

    private func rangeFileURLs(in path: String) -> [URL] {
        let root = URL(fileURLWithPath: path, isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var files: [URL] = []
        for case let url as URL in enumerator {
            guard url.pathExtension == "range" else { continue }
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
            guard values?.isRegularFile == true else { continue }
            files.append(url)
        }

        return files.sorted { $0.path < $1.path }
    }

    private func readFileResult(path: String) -> CompileTimeValue {
        guard let text = try? String(contentsOf: URL(fileURLWithPath: path), encoding: .utf8) else {
            return enumCaseValue(named: "failure", associatedValues: [
                "cause": enumCaseValue(named: "unreadable")
            ])
        }
        return enumCaseValue(named: "success", associatedValues: ["result": .string(text)])
    }

    private func createFileResult(path: String, text: String) -> CompileTimeValue {
        do {
            let url = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try text.write(to: url, atomically: true, encoding: .utf8)
            return enumCaseValue(named: "success", associatedValues: [
                "result": .object(typeName: "Void", fields: [:])
            ])
        } catch {
            return enumCaseValue(named: "failure", associatedValues: [
                "cause": enumCaseValue(named: "unwritable")
            ])
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
            case .macroApplication(let name, let arguments) where name == "return":
                guard let valueArgument = arguments.first(where: { $0.label == "value" }) else {
                    return .object(typeName: "Void", fields: [:])
                }
                return evaluate(valueArgument.value, locals: nestedLocals)
            case .macroApplication(let name, let arguments):
                guard let macro = macroDeclarationsByName[name], let context else {
                    return nil
                }
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

private struct LLVMMainBuilder {
    private var lines: [String] = []
    private var locals: [String: String] = [:]
    private var nextTemporary = 1
    private var didReturn = false

    mutating func emit(statement: CompileTimeValue) {
        guard !didReturn,
            case .object(let typeName, let fields) = statement
        else {
            return
        }

        switch typeName {
        case "LocalBinding":
            guard let name = stringField("name", in: fields),
                let expression = fields["expression"],
                let operand = emitExpression(expression)
            else {
                return
            }
            let register = "%\(name)"
            lines.append("  \(register) = add i64 0, \(operand)")
            locals[name] = register
        case "Return":
            guard let expression = fields["expression"],
                let operand = emitExpression(expression)
            else {
                lines.append("  ret i3 0")
                didReturn = true
                return
            }
            let truncated = temporary()
            lines.append("  \(truncated) = trunc i64 \(operand) to i3")
            lines.append("  ret i3 \(truncated)")
            didReturn = true
        case "ExpressionStatement":
            if let expression = fields["expression"] {
                _ = emitExpression(expression)
            }
        default:
            return
        }
    }

    mutating func module() -> String {
        if !didReturn {
            lines.append("  ret i3 0")
            didReturn = true
        }
        return (
            [
                "; ModuleID = 'RangeScalar'",
                "source_filename = \"RangeScalar.range\"",
                "",
                "define i3 @main() {",
                "entry:",
            ] + lines + [
                "}",
                "",
            ]
        ).joined(separator: "\n")
    }

    private mutating func emitExpression(_ expression: CompileTimeValue) -> String? {
        guard case .object(let typeName, let fields) = expression else {
            switch expression {
            case .integer(let value):
                return "\(value)"
            default:
                return nil
            }
        }

        switch typeName {
        case "IntegerLiteralExpression":
            guard case .integer(let value)? = fields["value"] else { return nil }
            return "\(value)"
        case "IdentifierExpression":
            guard let name = stringField("name", in: fields) else { return nil }
            return locals[name] ?? "%\(name)"
        case "CallExpression":
            guard let name = stringField("name", in: fields),
                name == "Int",
                case .array(let arguments)? = fields["arguments"],
                arguments.count == 1,
                case .object(_, let argumentFields) = arguments[0],
                let value = argumentFields["value"]
            else {
                return nil
            }
            return emitExpression(value)
        case "BinaryExpression":
            guard stringField("operator", in: fields) == "+",
                let lhs = fields["lhs"],
                let rhs = fields["rhs"],
                let left = emitExpression(lhs),
                let right = emitExpression(rhs)
            else {
                return nil
            }
            let register = temporary()
            lines.append("  \(register) = add i64 \(left), \(right)")
            return register
        default:
            return nil
        }
    }

    private mutating func temporary() -> String {
        let register = "%\(nextTemporary)"
        nextTemporary += 1
        return register
    }

    private func stringField(_ name: String, in fields: [String: CompileTimeValue]) -> String? {
        guard case .string(let value)? = fields[name] else {
            return nil
        }
        return value
    }
}
