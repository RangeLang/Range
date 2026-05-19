import ArgumentParser
import Foundation
import GradientSyntax

struct MainProgramRunner {
    private let project: LoadedProject
    private let compiledProgram: CompiledProgram
    private let showSummary: Bool

    init(project: LoadedProject, compiledProgram: CompiledProgram, showSummary: Bool = true) {
        self.project = project
        self.compiledProgram = compiledProgram
        self.showSummary = showSummary
    }

    func run() throws {
        let startedAt = Date()
        let entryFile = try discoverEntryFile()
        let sourceFile = try expandedProjectSourceFile(at: entryFile)
        let mainBlock: MainBlockNode
        switch sourceFile {
        case .mainBlock(let block):
            mainBlock = block
        case .module(let module):
            guard let block = module.mainBlock else {
                throw ValidationError(
                    "Main entry file '\(entryFile.lastPathComponent)' must use #main { ... }."
                )
            }
            mainBlock = block
        case .extensions:
            throw ValidationError(
                "Main entry file '\(entryFile.lastPathComponent)' must use #main { ... }."
            )
        case .construct, .namespace, .enumeration, .protocolDefinition, .macro, .marker:
            throw ValidationError(
                "Main entry file '\(entryFile.lastPathComponent)' must use #main { ... }."
            )
        }

        if showSummary {
            let startupMS = Int((Date().timeIntervalSince(startedAt) * 1000.0).rounded())
            TerminalLog.timedOut(
                "Running \(project.packageName)",
                milliseconds: startupMS,
                level: .warning
            )
        }

        var interpreter = MainProgramInterpreter(fileName: entryFile.lastPathComponent)
        try interpreter.execute(mainBlock)

        if showSummary {
            let elapsedMS = Int((Date().timeIntervalSince(startedAt) * 1000.0).rounded())
            TerminalLog.timedOut(
                "Finished \(project.packageName)",
                milliseconds: elapsedMS,
                level: .success
            )
        }
    }

    private func discoverEntryFile() throws -> URL {
        if project.isSingleFile {
            return project.projectFiles[0]
        }

        let mainBlocks = try project.projectFiles.compactMap { fileURL -> URL? in
            let sourceFile = try expandedProjectSourceFile(at: fileURL)
            switch sourceFile {
            case .mainBlock:
                return fileURL
            case .module(let module):
                return module.mainBlock == nil ? nil : fileURL
            default:
                return nil
            }
        }

        if mainBlocks.isEmpty {
            throw ValidationError("Missing #main block in \(project.projectRoot.path)")
        }
        if mainBlocks.count > 1 {
            let names = mainBlocks.map(\.lastPathComponent).sorted().joined(separator: ", ")
            throw ValidationError("Found multiple #main modules: \(names)")
        }
        return mainBlocks[0]
    }

    private func expandedProjectSourceFile(at fileURL: URL) throws -> SourceFileNode {
        guard
            let parsedFile = compiledProgram.projectExpandedFiles.first(where: {
                URL(fileURLWithPath: $0.path).standardizedFileURL == fileURL.standardizedFileURL
            })
        else {
            throw ValidationError("Failed to expand \(fileURL.lastPathComponent).")
        }
        return parsedFile.sourceFile
    }
}

private struct MainProgramInterpreter {
    private final class VariableSlot {
        let kind: LocalBindingKind
        var value: RuntimeValue

        init(kind: LocalBindingKind, value: RuntimeValue) {
            self.kind = kind
            self.value = value
        }
    }

    private enum RuntimeValue {
        case int(Int)
        case double(Double)
        case string(String)
        case bool(Bool)
        case nilLiteral
        case array([RuntimeValue])
        case dictionary([String: RuntimeValue])
    }

    private enum ControlFlow {
        case none
        case returned(RuntimeValue?)
        case broke
        case continued
    }

    private var scopes: [[String: VariableSlot]] = [[:]]
    private let fileName: String

    init(fileName: String) {
        self.fileName = fileName
    }

    mutating func execute(_ mainBlock: MainBlockNode) throws {
        let flow = try executeStatements(mainBlock.body)
        switch flow {
        case .none, .returned:
            return
        case .broke:
            throw ValidationError("'break' can only be used inside a loop or switch.")
        case .continued:
            throw ValidationError("'continue' can only be used inside a loop.")
        }
    }

    private mutating func executeStatements(_ statements: [Statement]) throws -> ControlFlow {
        for statement in statements {
            let flow = try executeStatement(statement)
            switch flow {
            case .none:
                continue
            case .returned, .broke, .continued:
                return flow
            }
        }
        return .none
    }

    private mutating func executeDeferredStatements(_ statements: [Statement]) throws -> ControlFlow {
        var pendingFlow: ControlFlow = .none

        for statement in statements {
            let flow = try executeStatement(statement)

            switch flow {
            case .none:
                continue
            case .returned, .broke, .continued:
                if case .none = pendingFlow {
                    pendingFlow = flow
                }
            }
        }

        return pendingFlow
    }

    private mutating func executeStatement(_ statement: Statement) throws -> ControlFlow {
        switch statement {
        case .macroInvocation:
            throw ValidationError("Macro invocations must be expanded before interpretation.")
        case .expand:
            throw ValidationError("Macro expansion statements must be expanded before interpretation.")
        case .background:
            throw ValidationError(
                "@background blocks are not supported in the main program interpreter yet.")
        case .deferBlock(let deferred):
            return try executeDeferredStatements(deferred.body)
        case .localCallable:
            throw ValidationError(
                "Local callable declarations are not supported in the main program interpreter yet.")
        case .localBinding(let declaration):
            let value = try evaluate(declaration.expression)
            try declare(name: declaration.name, kind: declaration.kind, value: value)
            return .none

        case .derived(let name, _, let body):
            let value = try evaluateDerivedBody(body, name: name)
            try declare(name: name, kind: .constant, value: value)
            return .none

        case .assignment(let target, let expression):
            let value = try evaluate(expression)
            try assign(target: target, value: value)
            return .none

        case .compoundAssignment(let target, .plusEquals, let expression):
            let current = try read(target: target)
            let rhs = try evaluate(expression)
            try assign(target: target, value: try add(current, rhs))
            return .none

        case .forEach(let name, let sequence, let body):
            let value = try evaluate(sequence)
            let elements: [RuntimeValue]
            switch value {
            case .array(let array):
                elements = array
            case .nilLiteral:
                elements = []
            default:
                throw ValidationError(
                    "For-in sequence in \(fileName) must evaluate to an array or nil."
                )
            }

            for element in elements {
                pushScope(bindings: [name: VariableSlot(kind: .constant, value: element)])
                defer { popScope() }

                let flow = try executeStatements(body)
                switch flow {
                case .none:
                    break
                case .continued:
                    continue
                case .broke:
                    return .none
                case .returned:
                    return flow
                }
            }

            return .none

        case .whileLoop(let condition, let body):
            while try expectBool(evaluate(condition), context: "While condition") {
                pushScope()
                let flow = try executeStatements(body)
                popScope()

                switch flow {
                case .none:
                    continue
                case .continued:
                    continue
                case .broke:
                    return .none
                case .returned:
                    return flow
                }
            }
            return .none

        case .conditional(let branches):
            for branch in branches {
                let matches: Bool
                if let condition = branch.condition {
                    matches = try expectBool(evaluate(condition), context: "If condition")
                } else {
                    matches = true
                }

                guard matches else { continue }

                pushScope()
                let flow = try executeStatements(branch.body)
                popScope()
                return flow
            }
            return .none

        case .return(let expression):
            let value: RuntimeValue?
            if let expression {
                value = try evaluate(expression)
            } else {
                value = nil
            }
            return .returned(value)

        case .break:
            return .broke

        case .continue:
            return .continued

        case .switchStatement(let expression, let cases, let defaultBody):
            let subject = try evaluate(expression)

            for switchCase in cases {
                if try switchCaseMatches(subject: subject, switchCase.pattern) {
                    pushScope()
                    try bindSwitchCasePattern(switchCase.pattern, subject: subject)
                    let flow = try executeStatements(switchCase.body)
                    popScope()

                    switch flow {
                    case .broke:
                        return .none
                    default:
                        return flow
                    }
                }
            }

            if let defaultBody {
                pushScope()
                let flow = try executeStatements(defaultBody)
                popScope()

                switch flow {
                case .broke:
                    return .none
                default:
                    return flow
                }
            }

            return .none

        case .expression(let expression):
            try executeExpressionStatement(expression)
            return .none

        }
    }

    private mutating func switchCaseMatches(
        subject: RuntimeValue,
        _ pattern: SwitchCasePattern
    ) throws -> Bool {
        switch pattern {
        case .expression(let expression):
            return valuesEqual(subject, try evaluate(expression))
        case .enumCase:
            throw ValidationError(
                "Enum switch case patterns are not supported in the main program interpreter yet."
            )
        }
    }

    private mutating func bindSwitchCasePattern(
        _ pattern: SwitchCasePattern,
        subject: RuntimeValue
    ) throws {
        switch pattern {
        case .expression:
            return
        case .enumCase(_, let binding):
            if let binding {
                try declare(name: binding.name, kind: binding.kind, value: subject)
            }
        }
    }

    private enum LoggerOutputMode {
        case log
        case debug
        case info
        case success
        case warning
        case error

        var runtimeLevel: RuntimeLogLevel {
            switch self {
            case .log:
                return .log
            case .debug:
                return .debug
            case .info:
                return .info
            case .success:
                return .success
            case .warning:
                return .warning
            case .error:
                return .error
            }
        }

        var usesStderr: Bool {
            switch self {
            case .error:
                return true
            default:
                return false
            }
        }
    }

    private mutating func executeExpressionStatement(_ expression: GradientSyntax.Expression) throws {
        guard case .call(let name, let arguments) = expression else {
            throw ValidationError("Standalone expression statements must be callable.")
        }

        switch name {
        case "Logger.log":
            try emitLoggerMessage(arguments, mode: .log)
        case "Logger.debug":
            try emitLoggerMessage(arguments, mode: .debug)
        case "Logger.info":
            try emitLoggerMessage(arguments, mode: .info)
        case "Logger.success":
            try emitLoggerMessage(arguments, mode: .success)
        case "Logger.warning":
            try emitLoggerMessage(arguments, mode: .warning)
        case "Logger.error":
            try emitLoggerMessage(arguments, mode: .error)
        default:
            throw ValidationError(
                "Running standalone callable expressions is not supported in the main-program interpreter yet (\(name))."
            )
        }
    }

    private mutating func emitLoggerMessage(
        _ arguments: [CallArgument],
        mode: LoggerOutputMode
    ) throws {
        guard arguments.count == 1 else {
            throw ValidationError("Logger runtime calls currently require exactly one argument.")
        }

        let message = stringify(try evaluate(arguments[0].value))

        if mode.usesStderr {
            TerminalLog.runtimeLogErr(message, level: mode.runtimeLevel)
        } else {
            TerminalLog.runtimeLogOut(message, level: mode.runtimeLevel)
        }
    }

    private mutating func evaluate(_ expression: GradientSyntax.Expression) throws -> RuntimeValue {
        switch expression {
        case .integer(let value):
            return .int(value)

        case .double(let value):
            return .double(value)

        case .string(let value):
            return .string(value)

        case .interpolatedString(let value):
            return .string(render(value))

        case .boolean(let value):
            return .bool(value)

        case .nilLiteral:
            return .nilLiteral

        case .macroInvocation(let name, _):
            throw ValidationError(
                "Expression macro invocation @\(name) must be expanded before interpretation."
            )

        case .block:
            throw ValidationError(
                "Block expressions are not supported in the main-program interpreter yet."
            )

        case .identifier(let name):
            return try lookup(name: name)?.value
                ?? {
                    throw ValidationError("Unknown identifier '\(name)' in \(fileName).")
                }()

        case .call(let name, _):
            throw ValidationError(
                "Running callable expressions is not supported in the main-program interpreter yet (\(name))."
            )

        case .bindingReference(let name):
            throw ValidationError(
                "Binding references are not supported in the main-program interpreter yet ($\(name))."
            )

        case .array(let values):
            var evaluated: [RuntimeValue] = []
            evaluated.reserveCapacity(values.count)
            for value in values {
                evaluated.append(try evaluate(value))
            }
            return .array(evaluated)

        case .dictionary(let elements):
            var evaluated: [String: RuntimeValue] = [:]
            for element in elements {
                let keyValue = try evaluate(element.key)
                guard case .string(let key) = keyValue else {
                    throw ValidationError(
                        "Dictionary literal keys must evaluate to String in \(fileName)."
                    )
                }
                evaluated[key] = try evaluate(element.value)
            }
            return .dictionary(evaluated)

        case .ternary(let condition, let trueExpression, let falseExpression):
            let result = try expectBool(evaluate(condition), context: "Ternary condition")
            return try evaluate(result ? trueExpression : falseExpression)

        case .unary(let operatorSymbol, let nested):
            switch operatorSymbol {
            case .not:
                let negated = try expectBool(try evaluate(nested), context: "Negation operand")
                return .bool(!negated)
            }

        case .binary(let lhs, let operatorSymbol, let rhs):
            switch operatorSymbol {
            case .addition:
                return try add(evaluate(lhs), evaluate(rhs))
            case .subtraction:
                return try subtract(evaluate(lhs), evaluate(rhs))
            case .multiplication:
                return try multiply(evaluate(lhs), evaluate(rhs))
            case .division:
                return try divide(evaluate(lhs), evaluate(rhs))
            case .remainder:
                return try remainder(evaluate(lhs), evaluate(rhs))

            case .nilCoalescing:
                let left = try evaluate(lhs)
                if case .nilLiteral = left {
                    return try evaluate(rhs)
                }
                return left

            case .equal:
                return .bool(valuesEqual(try evaluate(lhs), try evaluate(rhs)))

            case .notEqual:
                let areEqual = valuesEqual(try evaluate(lhs), try evaluate(rhs))
                return .bool(!areEqual)

            case .less:
                return .bool(try compare(evaluate(lhs), evaluate(rhs), operator: "<"))

            case .lessEqual:
                return .bool(try compare(evaluate(lhs), evaluate(rhs), operator: "<="))

            case .greater:
                return .bool(try compare(evaluate(lhs), evaluate(rhs), operator: ">"))

            case .greaterEqual:
                return .bool(try compare(evaluate(lhs), evaluate(rhs), operator: ">="))

            case .and:
                let left = try expectBool(evaluate(lhs), context: "Logical && left operand")
                if !left {
                    return .bool(false)
                }
                return .bool(try expectBool(evaluate(rhs), context: "Logical && right operand"))

            case .or:
                let left = try expectBool(evaluate(lhs), context: "Logical || left operand")
                if left {
                    return .bool(true)
                }
                return .bool(try expectBool(evaluate(rhs), context: "Logical || right operand"))
            }
        }
    }

    private func render(_ string: InterpolatedString) -> String {
        string.segments.map { segment in
            switch segment {
            case .text(let text):
                return text
            case .expression(let expression):
                return (try? stringify(evaluateForInterpolation(expression))) ?? "<error>"
            }
        }.joined()
    }

    private func evaluateForInterpolation(_ expression: GradientSyntax.Expression) throws
        -> RuntimeValue
    {
        var copy = self
        return try copy.evaluate(expression)
    }

    private func stringify(_ value: RuntimeValue) -> String {
        switch value {
        case .int(let value):
            return String(value)
        case .double(let value):
            let rounded = value.rounded()
            if rounded == value {
                return String(Int(rounded))
            }
            return String(value)
        case .string(let value):
            return value
        case .bool(let value):
            return value ? "true" : "false"
        case .nilLiteral:
            return "nil"
        case .array(let values):
            return "[" + values.map(stringify).joined(separator: ", ") + "]"
        case .dictionary(let values):
            let rendered = values.keys.sorted().map { key in
                "\"\(key)\": \(stringify(values[key]!))"
            }
            return "{\(rendered.joined(separator: ", "))}"
        }
    }

    private func expectBool(_ value: RuntimeValue, context: String) throws -> Bool {
        guard case .bool(let result) = value else {
            throw ValidationError("\(context) must evaluate to Bool.")
        }
        return result
    }

    private func add(_ lhs: RuntimeValue, _ rhs: RuntimeValue) throws -> RuntimeValue {
        switch (lhs, rhs) {
        case (.int(let left), .int(let right)):
            return .int(left + right)
        case (.double(let left), .double(let right)):
            return .double(left + right)
        case (.int(let left), .double(let right)):
            return .double(Double(left) + right)
        case (.double(let left), .int(let right)):
            return .double(left + Double(right))
        case (.string(let left), .string(let right)):
            return .string(left + right)
        case (.string(let left), let right):
            return .string(left + stringify(right))
        case (let left, .string(let right)):
            return .string(stringify(left) + right)
        default:
            throw ValidationError("Operator '+' is only supported for numbers and strings.")
        }
    }

    private func subtract(_ lhs: RuntimeValue, _ rhs: RuntimeValue) throws -> RuntimeValue {
        switch (lhs, rhs) {
        case (.int(let left), .int(let right)):
            return .int(left - right)
        case (.double(let left), .double(let right)):
            return .double(left - right)
        case (.int(let left), .double(let right)):
            return .double(Double(left) - right)
        case (.double(let left), .int(let right)):
            return .double(left - Double(right))
        default:
            throw ValidationError("Operator '-' is only supported for numbers.")
        }
    }

    private func multiply(_ lhs: RuntimeValue, _ rhs: RuntimeValue) throws -> RuntimeValue {
        switch (lhs, rhs) {
        case (.int(let left), .int(let right)):
            return .int(left * right)
        case (.double(let left), .double(let right)):
            return .double(left * right)
        case (.int(let left), .double(let right)):
            return .double(Double(left) * right)
        case (.double(let left), .int(let right)):
            return .double(left * Double(right))
        default:
            throw ValidationError("Operator '*' is only supported for numbers.")
        }
    }

    private func divide(_ lhs: RuntimeValue, _ rhs: RuntimeValue) throws -> RuntimeValue {
        switch (lhs, rhs) {
        case (.int(let left), .int(let right)):
            return .int(left / right)
        case (.double(let left), .double(let right)):
            return .double(left / right)
        case (.int(let left), .double(let right)):
            return .double(Double(left) / right)
        case (.double(let left), .int(let right)):
            return .double(left / Double(right))
        default:
            throw ValidationError("Operator '/' is only supported for numbers.")
        }
    }

    private func remainder(_ lhs: RuntimeValue, _ rhs: RuntimeValue) throws -> RuntimeValue {
        switch (lhs, rhs) {
        case (.int(let left), .int(let right)):
            return .int(left % right)
        default:
            throw ValidationError("Operator '%' is only supported for Int values.")
        }
    }

    private func compare(
        _ lhs: RuntimeValue,
        _ rhs: RuntimeValue,
        operator: String
    ) throws -> Bool {
        switch (lhs, rhs) {
        case (.int(let left), .int(let right)):
            return applyComparison(Double(left), Double(right), operator: `operator`)
        case (.double(let left), .double(let right)):
            return applyComparison(left, right, operator: `operator`)
        case (.int(let left), .double(let right)):
            return applyComparison(Double(left), right, operator: `operator`)
        case (.double(let left), .int(let right)):
            return applyComparison(left, Double(right), operator: `operator`)
        case (.string(let left), .string(let right)):
            switch `operator` {
            case "<": return left < right
            case "<=": return left <= right
            case ">": return left > right
            case ">=": return left >= right
            default:
                throw ValidationError("Unsupported comparison operator '\(`operator`)'")
            }
        default:
            throw ValidationError(
                "Comparison operator '\(`operator`)' requires matching numeric or string values."
            )
        }
    }

    private func applyComparison(_ lhs: Double, _ rhs: Double, operator: String) -> Bool {
        switch `operator` {
        case "<": return lhs < rhs
        case "<=": return lhs <= rhs
        case ">": return lhs > rhs
        case ">=": return lhs >= rhs
        default: return false
        }
    }

    private func valuesEqual(_ lhs: RuntimeValue, _ rhs: RuntimeValue) -> Bool {
        switch (lhs, rhs) {
        case (.int(let left), .int(let right)):
            return left == right
        case (.double(let left), .double(let right)):
            return left == right
        case (.int(let left), .double(let right)):
            return Double(left) == right
        case (.double(let left), .int(let right)):
            return left == Double(right)
        case (.string(let left), .string(let right)):
            return left == right
        case (.bool(let left), .bool(let right)):
            return left == right
        case (.nilLiteral, .nilLiteral):
            return true
        case (.array(let left), .array(let right)):
            guard left.count == right.count else { return false }
            return zip(left, right).allSatisfy(valuesEqual)
        case (.dictionary(let left), .dictionary(let right)):
            guard left.count == right.count else { return false }
            for (key, leftValue) in left {
                guard let rightValue = right[key], valuesEqual(leftValue, rightValue) else {
                    return false
                }
            }
            return true
        default:
            return false
        }
    }

    private mutating func declare(name: String, kind: LocalBindingKind, value: RuntimeValue) throws
    {
        guard scopes.indices.contains(scopes.count - 1) else {
            throw ValidationError("Internal scope error while declaring '\(name)'.")
        }
        if scopes[scopes.count - 1][name] != nil {
            throw ValidationError("'\(name)' is already declared in this scope.")
        }
        scopes[scopes.count - 1][name] = VariableSlot(kind: kind, value: value)
    }

    private mutating func assign(target: AssignmentTarget, value: RuntimeValue) throws {
        switch target {
        case .local(let name):
            guard let slot = try lookup(name: name) else {
                throw ValidationError("Unknown mutable symbol '\(name)'.")
            }
            guard slot.kind == .mutable else {
                throw ValidationError("Cannot assign to immutable binding '\(name)'.")
            }
            slot.value = value

        case .state(let name):
            throw ValidationError(
                "State assignment is not supported in the main-program interpreter yet (\(name)).")

        case .binding(let name):
            throw ValidationError(
                "Binding assignment is not supported in the main-program interpreter yet (\(name))."
            )

        case .member(let base, let name):
            throw ValidationError(
                "Member assignment is not supported in the main-program interpreter yet (\(try renderAssignmentTarget(base)).\(name))."
            )
        }
    }

    private func read(target: AssignmentTarget) throws -> RuntimeValue {
        switch target {
        case .local(let name):
            guard let slot = try lookup(name: name) else {
                throw ValidationError("Unknown mutable symbol '\(name)'.")
            }
            return slot.value

        case .state(let name):
            throw ValidationError(
                "State reads are not supported in the main-program interpreter yet (\(name)).")

        case .binding(let name):
            throw ValidationError(
                "Binding reads are not supported in the main-program interpreter yet (\(name)).")

        case .member(let base, let name):
            throw ValidationError(
                "Member reads are not supported in the main-program interpreter yet (\(try renderAssignmentTarget(base)).\(name))."
            )
        }
    }

    private mutating func evaluateDerivedBody(_ body: [Statement], name: String) throws
        -> RuntimeValue
    {
        guard body.count == 1, case .expression(let expression) = body[0] else {
            throw ValidationError(
                "Local derived '\(name)' in \(fileName) currently requires a single top-level expression."
            )
        }
        return try evaluate(expression)
    }

    private func renderAssignmentTarget(_ target: AssignmentTarget) throws -> String {
        switch target {
        case .local(let name), .state(let name), .binding(let name):
            return name
        case .member(let base, let name):
            return "\(try renderAssignmentTarget(base)).\(name)"
        }
    }

    private func lookup(name: String) throws -> VariableSlot? {
        for scope in scopes.reversed() {
            if let slot = scope[name] {
                return slot
            }
        }
        return nil
    }

    private mutating func pushScope(bindings: [String: VariableSlot] = [:]) {
        scopes.append(bindings)
    }

    private mutating func popScope() {
        if scopes.count > 1 {
            scopes.removeLast()
        }
    }
}
