import Foundation

final class CompileTimeLLVMContext {
    var bindings: [String: String] = [:]
    var bindingConstructs: [String: String] = [:]
    var bindingReturnCasts: [String: String] = [:]
    private var temporaryIndex = 0

    func nextTemporary(prefix: String) -> String {
        let current = temporaryIndex
        temporaryIndex += 1
        return "\(prefix).\(current)"
    }
}

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
    let llvmContext: CompileTimeLLVMContext?

    init(
        targetBinding: String,
        targetValue: CompileTimeValue,
        graphBinding: String? = nil,
        selfValue: CompileTimeValue? = nil,
        localBindings: [String: Expression],
        macroDeclarationsByName: [String: MacroDeclaration] = [:],
        callableDeclarationsByName: [String: [CallableDeclaration]] = [:],
        knownObjectTypeNames: Set<String> = [],
        context: MacroExpansionContext? = nil,
        llvmContext: CompileTimeLLVMContext? = nil
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
        self.llvmContext = llvmContext
    }

    func evaluate(_ expression: Expression) -> CompileTimeValue? {
        evaluate(expression, locals: localBindings)
    }

    func evaluate(_ expression: Expression, with locals: [String: Expression]) -> CompileTimeValue? {
        evaluate(expression, locals: locals)
    }

    // Macro bodies execute through the explicit statement macro surface.
    // Returns the produced value from @return.
    // `locals` is threaded mutably so @assignment and loop accumulation persist.
    func evaluateStatements(
        _ statements: [Statement],
        locals: inout [String: Expression]
    ) -> CompileTimeValue? {
        for statement in statements {
            switch statement {
            case .macroApplication(let name, let arguments) where name == "return":
                guard let valueArgument = arguments.first(where: { $0.label == "value" }) else {
                    return .object(typeName: "Void", fields: [:])
                }
                return macroReturnValue(valueArgument.value, locals: locals)
            case .macroApplication(let name, let arguments):
                _ = evaluateStatementMacroEffect(name: name, arguments: arguments, locals: &locals)
            case .macroInvocation(let name, let argumentClause, let body):
                guard
                    let control = evaluateControlMacroEffect(
                        name: name,
                        argumentClause: argumentClause,
                        locals: locals
                    )
                else {
                    continue
                }
                switch control.kind {
                case "branch":
                    guard let condition = controlConditionExpression(control.condition, locals: locals),
                        case .boolean(true) = evaluate(condition, locals: locals)
                    else {
                        continue
                    }
                    if let value = evaluateStatements(body, locals: &locals) {
                        return value
                    }
                case "loop":
                    guard let condition = controlConditionExpression(control.condition, locals: locals) else {
                        continue
                    }
                    var iterationCount = 0
                    while case .boolean(true) = evaluate(condition, locals: locals) {
                        guard iterationCount < 10_000 else {
                            return nil
                        }
                        if let value = evaluateStatements(body, locals: &locals) {
                            return value
                        }
                        iterationCount += 1
                    }
                default:
                    continue
                }
            default:
                continue
            }
        }
        return nil
    }

    func evaluateControlMacroEffect(
        name: String,
        argumentClause: String?,
        locals: [String: Expression]
    ) -> (kind: String, condition: String)? {
        guard let macro = macroDeclarationsByName[name],
            let context
        else {
            return nil
        }

        let arguments: [CallArgument]
        do {
            arguments = try argumentClause.map(MacroExpander.parsedMacroArguments) ?? []
        } catch {
            return nil
        }

        let argumentBindings: [String: Expression]
        do {
            argumentBindings = try MacroExpander.parseMacroArgumentBindings(
                for: macro,
                arguments: arguments
            )
        } catch {
            guard macro.parameters.count == 1,
                let parameter = macro.parameters.first,
                arguments.count == 1,
                arguments[0].label == nil
            else {
                return nil
            }
            argumentBindings = [parameter.localName: arguments[0].value]
        }

        var macroLocals = locals
        for (key, value) in argumentBindings {
            macroLocals[key] = value
        }

        let evaluator = CompileTimeValueEvaluator(
            targetBinding: targetBinding,
            targetValue: targetValue,
            graphBinding: graphBinding,
            selfValue: selfValue,
            localBindings: macroLocals,
            macroDeclarationsByName: macroDeclarationsByName,
            callableDeclarationsByName: callableDeclarationsByName,
            knownObjectTypeNames: knownObjectTypeNames,
            context: context,
            llvmContext: llvmContext
        )
        guard case .string(let effect)? = evaluator.evaluateStatements(macro.body, locals: &macroLocals)
        else {
            return nil
        }
        return controlEffect(effect)
    }

    private func controlEffect(_ effect: String) -> (kind: String, condition: String)? {
        let prefix = "effect|kind="
        guard effect.hasPrefix(prefix) else {
            return nil
        }
        let remainder = effect.dropFirst(prefix.count)
        guard let conditionSeparator = remainder.range(of: "|condition=") else {
            return nil
        }
        let kind = String(remainder[..<conditionSeparator.lowerBound])
        guard !kind.isEmpty else {
            return nil
        }
        let conditionStart = conditionSeparator.upperBound
        return (kind, String(remainder[conditionStart...]))
    }

    func controlConditionExpression(_ source: String, locals: [String: Expression]) -> Expression? {
        macroLocalValueExpression(.string(source), locals: [:])
    }

    private func evaluateStatementMacroEffect(
        name: String,
        arguments: [CallArgument],
        locals: inout [String: Expression]
    ) -> Bool {
        guard let macro = macroDeclarationsByName[name],
            let context
        else {
            return false
        }

        let argumentBindings: [String: Expression]
        do {
            argumentBindings = try MacroExpander.parseMacroArgumentBindings(
                for: macro,
                arguments: arguments
            )
        } catch {
            return false
        }

        var macroLocals = locals
        for (key, value) in argumentBindings {
            macroLocals[key] = value
        }

        let evaluator = CompileTimeValueEvaluator(
            targetBinding: targetBinding,
            targetValue: targetValue,
            graphBinding: graphBinding,
            selfValue: selfValue,
            localBindings: macroLocals,
            macroDeclarationsByName: macroDeclarationsByName,
            callableDeclarationsByName: callableDeclarationsByName,
            knownObjectTypeNames: knownObjectTypeNames,
            context: context,
            llvmContext: llvmContext
        )
        guard case .string(let effect)? = evaluator.evaluateStatements(macro.body, locals: &macroLocals),
            let environmentSet = environmentSetEffect(effect)
        else {
            return false
        }

        locals[environmentSet.name] = macroLocalValueExpression(
            .string(environmentSet.value),
            locals: locals
        )
        return true
    }

    private func environmentSetEffect(_ effect: String) -> (name: String, value: String)? {
        let prefix = "effect|kind=environment-set|name="
        guard effect.hasPrefix(prefix) else {
            return nil
        }
        let remainder = effect.dropFirst(prefix.count)
        guard let valueSeparator = remainder.range(of: "|value=") else {
            return nil
        }
        let name = String(remainder[..<valueSeparator.lowerBound])
        guard !name.isEmpty else {
            return nil
        }
        let valueStart = valueSeparator.upperBound
        return (name, String(remainder[valueStart...]))
    }

    private func macroLocalValueExpression(
        _ expression: Expression,
        locals: [String: Expression]
    ) -> Expression {
        if case .string(let source) = expression,
            let parsed = try? parseMacroLocalValueSource(source)
        {
            if case .identifier = parsed,
                evaluate(parsed, locals: locals) == nil
            {
                return .string(source)
            }
            return boundExpression(parsed, locals: locals)
        }
        return boundExpression(expression, locals: locals)
    }

    private func macroReturnValue(
        _ expression: Expression,
        locals: [String: Expression]
    ) -> CompileTimeValue? {
        if case .string(let source) = expression,
            let parsed = try? parseMacroLocalValueSource(source),
            let value = evaluate(parsed, locals: locals)
        {
            return value
        }
        return evaluate(expression, locals: locals)
    }

    private func parseMacroLocalValueSource(_ source: String) throws -> Expression {
        var parser = try Parser(source: StringLiteral.decodeEscapes(source))
        let expression = try parser.parseExpression()
        try parser.consume(.eof)
        return expression
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

    private func evaluate(
        _ expression: Expression,
        locals: [String: Expression]
    ) -> CompileTimeValue? {
        switch expression {
        case .string(let value):
            return .string(StringLiteral.decodeEscapes(value))
        case .integer(let value):
            return .integer(value)
        case .double(let value):
            return .double(value)
        case .boolean(let value):
            return .boolean(value)
        case .nilLiteral:
            return .nilValue
        case .macroInvocation(let name, let arguments):
            if name == "string",
                let value = stringMacroValue(arguments: arguments, locals: locals)
            {
                return .string(value)
            }
            if name == "llvmField",
                let value = llvmFieldMacroValue(arguments: arguments, locals: locals)
            {
                return .string(value)
            }
            if name == "temporary",
                let value = temporaryMacroValue(arguments: arguments, locals: locals)
            {
                return .string(value)
            }
            if name == "llvmBinding",
                let value = llvmBindingMacroValue(arguments: arguments, locals: locals)
            {
                return .string(value)
            }
            if name == "generic",
                let value = genericMacroValue(arguments: arguments, locals: locals)
            {
                return .string(value)
            }
            guard let macro = macroDeclarationsByName[name],
                macro.target == nil,
                let context,
                let value = try? MacroExpander.evaluateFreestandingSyntaxMacro(
                    macro,
                    arguments: arguments,
                    callerLocals: locals,
                    callerTargetBinding: targetBinding,
                    callerTargetValue: targetValue,
                    callerSelfValue: selfValue,
                    callerLLVMContext: llvmContext,
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
            if let graphValue = evaluateGraphCall(
                name: name,
                arguments: arguments,
                locals: locals
            ) {
                return graphValue
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

    private func stringMacroValue(
        arguments: [CallArgument],
        locals: [String: Expression]
    ) -> String? {
        let valueExpression = arguments.first(where: { $0.label == "value" })?.value
            ?? arguments.first?.value
        guard let valueExpression else {
            return ""
        }
        guard case .string(let value) = evaluate(valueExpression, locals: locals) else {
            return nil
        }
        return value
    }

    private func llvmFieldMacroValue(
        arguments: [CallArgument],
        locals: [String: Expression]
    ) -> String? {
        let valueExpression = arguments.first(where: { $0.label == "value" })?.value
            ?? arguments.first?.value
        let nameExpression = arguments.first(where: { $0.label == "name" })?.value
        guard let valueExpression,
            let nameExpression,
            case .string(let value) = evaluate(valueExpression, locals: locals),
            case .string(let name) = evaluate(nameExpression, locals: locals)
        else {
            return nil
        }
        guard let field = llvmPayloadField(value, name: name) else {
            return ""
        }
        if name == "prelude", !field.isEmpty {
            return field + "\n"
        }
        return field
    }

    private func temporaryMacroValue(
        arguments: [CallArgument],
        locals: [String: Expression]
    ) -> String? {
        let prefixExpression = arguments.first(where: { $0.label == "prefix" })?.value
            ?? arguments.first?.value
        guard let llvmContext,
            let prefixExpression,
            case .string(let prefix) = evaluate(prefixExpression, locals: locals),
            !prefix.isEmpty
        else {
            return nil
        }
        return "%\(llvmContext.nextTemporary(prefix: prefix))"
    }

    private func llvmBindingMacroValue(
        arguments: [CallArgument],
        locals: [String: Expression]
    ) -> String? {
        let nameExpression = arguments.first(where: { $0.label == "name" })?.value
            ?? arguments.first?.value
        guard let llvmContext,
            let nameExpression,
            case .string(let name) = evaluate(nameExpression, locals: locals),
            let type = llvmContext.bindings[name]
        else {
            return nil
        }
        let construct = llvmContext.bindingConstructs[name] ?? ""
        let returnCast = llvmContext.bindingReturnCasts[name] ?? ""
        return "llvm-binding|construct=\(construct)|type=\(type)|returnCast=\(returnCast)|pointer=%\(name)"
    }

    private func genericMacroValue(
        arguments: [CallArgument],
        locals: [String: Expression]
    ) -> String? {
        let valueExpression = arguments.first(where: { $0.label == "value" })?.value
            ?? arguments.first?.value
        guard let valueExpression else {
            return ""
        }
        if case .macroInvocation(_, let arguments) = valueExpression,
            let nestedValueExpression = arguments.first(where: { $0.label == "value" })?.value
                ?? arguments.first?.value
        {
            return genericMacroValue(
                arguments: [CallArgument(label: "value", value: nestedValueExpression)],
                locals: locals
            )
        }
        if case .identifier(let name) = valueExpression {
            return name
        }
        guard let value = evaluate(valueExpression, locals: locals) else {
            return nil
        }
        switch value {
        case .string(let value):
            return value
        case .integer(let value):
            return String(value)
        case .double(let value):
            return String(value)
        case .boolean(let value):
            return value ? "true" : "false"
        default:
            return nil
        }
    }

    private func llvmPayloadField(_ payload: String, name: String) -> String? {
        let parts = payload.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard parts.first == "value" || parts.first == "llvm-value" || parts.first == "llvm-binding" else {
            return nil
        }
        var fields: [String: String] = [:]
        for part in parts.dropFirst() {
            let pair = part.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard pair.count == 2 else {
                continue
            }
            fields[String(pair[0])] = String(pair[1])
        }
        if let field = fields[name] {
            return field
        }
        if parts.first == "value",
            let field = fields["llvm.\(name)"]
        {
            return field
        }
        return nil
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
        } else if let contextValue = targetValue.field(root) {
            value = contextValue
        } else if root == "context" {
            value = macroContextValue()
        } else if root == graphBinding || (graphBinding == nil && root == "graph") {
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

    private func macroContextValue() -> CompileTimeValue {
        .object(
            typeName: "MacroContext",
            fields: [
                "current": currentGraphIdentity() ?? .nilValue,
                "graph": graphContextValue(),
            ]
        )
    }

    private func graphContextValue() -> CompileTimeValue {
        .object(
            typeName: "GraphContext",
            fields: [
                "main": context?.graphContext.mainMacro() ?? .nilValue,
                "macros": context?.graphContext.macros() ?? .array([]),
            ]
        )
    }

    private func currentGraphIdentity() -> CompileTimeValue? {
        if let identity = targetValue.field("identity") {
            return identity
        }
        if let identity = targetValue.field("declaration")?.field("identity") {
            return identity
        }
        if let identity = selfValue?.field("identity") {
            return identity
        }
        return nil
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
        "Void", "Identity", "RangeGraphIdentity", "GraphRole", "GraphEntry", "WrittenSyntax", "Parsed", "Block", "LocalBinding",
        "Return", "Break", "Assignment",
        "ProgramSourceFile", "ProgramArtifact", "ProgramResult", "RangeProgram", "RangeGraph", "RangeProject",
        "WrittenExpression",
        "ArrayExpression", "EnumCaseExpression",
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

        guard let value = evaluate(expression, locals: locals) else {
            return nil
        }
        switch value {
        case .string(let string):
            return .string(string)
        case .integer(let integer):
            return .string(String(integer))
        case .double(let double):
            return .string(String(double))
        case .boolean(let boolean):
            return .string(boolean ? "true" : "false")
        default:
            return nil
        }
    }

    private func evaluateGraphCall(
        name: String,
        arguments: [CallArgument],
        locals: [String: Expression]
    ) -> CompileTimeValue? {
        let graphRoot = graphBinding ?? "graph"
        guard let context,
            name.hasPrefix("\(graphRoot).")
        else {
            return nil
        }

        switch name {
        case "\(graphRoot).declaration":
            guard arguments.count == 1,
                let identity = evaluate(arguments[0].value, locals: locals)
            else {
                return nil
            }
            return context.graphContext.declaration(for: identity)
        case "\(graphRoot).parent":
            guard arguments.count == 1,
                arguments[0].label == "of",
                let identity = evaluate(arguments[0].value, locals: locals)
            else {
                return nil
            }
            return context.graphContext.parent(of: identity)
        case "\(graphRoot).members":
            guard arguments.count == 1,
                arguments[0].label == "of",
                let identity = evaluate(arguments[0].value, locals: locals)
            else {
                return nil
            }
            return context.graphContext.members(of: identity)
        case "\(graphRoot).sourcePath":
            guard arguments.count == 1,
                arguments[0].label == "of",
                let identity = evaluate(arguments[0].value, locals: locals)
            else {
                return nil
            }
            return context.graphContext.sourcePath(of: identity) ?? .nilValue
        case "\(graphRoot).sourceDirectory":
            guard arguments.count == 1,
                arguments[0].label == "of",
                let identity = evaluate(arguments[0].value, locals: locals)
            else {
                return nil
            }
            return context.graphContext.sourceDirectory(of: identity) ?? .nilValue
        case "\(graphRoot).macros":
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
            return context.graphContext.unknownCall(
                name: String(name.dropFirst(graphRoot.count + 1)),
                arguments: arguments
            )
        }
    }

    private func evaluateFileSystemCall(
        name: String,
        arguments: [CallArgument],
        locals: [String: Expression]
    ) -> CompileTimeValue? {
        guard arguments.count == 1,
            arguments[0].label == "path",
            case .string(let path) = evaluate(arguments[0].value, locals: locals)
        else {
            return nil
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

        if let first = elements.first {
            return first
        }

        guard let defaultExpression = argument("default", in: arguments) else {
            return nil
        }
        return evaluate(defaultExpression, locals: locals)
    }

    private func argument(_ label: String, in arguments: [CallArgument]) -> Expression? {
        arguments.first(where: { $0.label == label })?.value
    }
}
