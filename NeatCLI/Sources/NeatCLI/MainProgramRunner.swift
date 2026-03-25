import ArgumentParser
import Foundation
import NeatSyntax

struct MainProgramRunner {
    private let path: String
    private let showSummary: Bool

    init(path: String, showSummary: Bool = true) {
        self.path = path
        self.showSummary = showSummary
    }

    func run() throws {
        let startedAt = Date()
        let inputURL = URL(fileURLWithPath: path).standardizedFileURL

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: inputURL.path, isDirectory: &isDirectory)
        else {
            throw ValidationError("Missing input at \(inputURL.path)")
        }

        let entryFile: URL
        let packageName: String

        if isDirectory.boolValue {
            let packageFile = inputURL.appendingPathComponent("Package.neat", isDirectory: false)
            guard FileManager.default.fileExists(atPath: packageFile.path) else {
                throw ValidationError("Missing Package.neat in \(inputURL.path)")
            }

            let manifest = try PackageManifestLoader.load(from: packageFile)
            packageName = manifest.name
            let files = try neatFiles(in: inputURL, excludingManifestAt: packageFile)
            try ProjectSourceValidator.validatePrimaryDeclarations(in: files)
            entryFile = try discoverEntryFile(in: inputURL)
        } else {
            guard inputURL.pathExtension.lowercased() == "neat" else {
                throw ValidationError("Expected a .neat file or project directory.")
            }
            if inputURL.lastPathComponent == "Package.neat" {
                throw ValidationError(
                    "Package.neat cannot be run directly. Use a file or project with @main.")
            }

            packageName = inputURL.deletingPathExtension().lastPathComponent
            entryFile = inputURL
        }

        let source = try String(contentsOf: entryFile, encoding: .utf8)
        var parser = try Parser(source: source)

        let sourceFile = try parser.parseSourceFile()
        let mainBlock: MainBlockNode
        switch sourceFile {
        case .mainBlock(let block):
            mainBlock = block
        case .extensions:
            throw ValidationError(
                "Main entry file '\(entryFile.lastPathComponent)' must use @main { ... }."
            )
        case .construct, .enumeration, .protocolDefinition, .macro:
            throw ValidationError(
                "Main entry file '\(entryFile.lastPathComponent)' must use @main { ... }."
            )
        case .module:
            throw ValidationError(
                "Main entry file '\(entryFile.lastPathComponent)' must use @main { ... }."
            )
        }

        if showSummary {
            let startupMS = Int((Date().timeIntervalSince(startedAt) * 1000.0).rounded())
            TerminalLog.timedOut("Running \(packageName)", milliseconds: startupMS, level: .warning)
        }

        var interpreter = MainProgramInterpreter(fileName: entryFile.lastPathComponent)
        try interpreter.execute(mainBlock)

        if showSummary {
            let elapsedMS = Int((Date().timeIntervalSince(startedAt) * 1000.0).rounded())
            TerminalLog.timedOut(
                "Finished \(packageName)", milliseconds: elapsedMS, level: .success)
        }
    }

    private func discoverEntryFile(in root: URL) throws -> URL {
        let packageFile = root.appendingPathComponent("Package.neat", isDirectory: false)
        let files = try neatFiles(in: root, excludingManifestAt: packageFile)

        let mainBlocks = try files.compactMap { fileURL -> URL? in
            let sourceFile = try ProjectSourceValidator.parseSourceFile(at: fileURL)
            guard case .mainBlock = sourceFile else {
                return nil
            }
            return fileURL
        }

        if mainBlocks.isEmpty {
            throw ValidationError("Missing @main block in \(root.path)")
        }
        if mainBlocks.count > 1 {
            let names = mainBlocks.map(\.lastPathComponent).sorted().joined(separator: ", ")
            throw ValidationError("Found multiple @main modules: \(names)")
        }
        return mainBlocks[0]
    }

    private func neatFiles(in root: URL, excludingManifestAt manifestURL: URL) throws -> [URL] {
        let fileManager = FileManager.default
        guard
            let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: []
            )
        else {
            throw ValidationError("Could not inspect project files in \(root.path)")
        }

        var matches: [URL] = []

        while let fileURL = enumerator.nextObject() as? URL {
            let path = fileURL.path
            let isDirectory =
                (try? fileURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory)
                ?? false

            if path.contains("/.git/") || path.contains("/.build/")
                || path.contains("/.neat/Build/") || path.contains("/.neat/Packages/")
            {
                if isDirectory {
                    enumerator.skipDescendants()
                }
                continue
            }

            if isDirectory || fileURL.pathExtension.lowercased() != "neat" {
                continue
            }

            let fileName = fileURL.lastPathComponent
            if fileURL.standardizedFileURL == manifestURL.standardizedFileURL
                || fileName == "Fonts.neat"
            {
                continue
            }
            matches.append(fileURL)
        }

        return matches.sorted { $0.path < $1.path }
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
        case none
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

    private mutating func executeStatement(_ statement: Statement) throws -> ControlFlow {
        switch statement {
        case .declaration(let kind, let name, let expression):
            let value = try evaluate(expression)
            try declare(name: name, kind: kind, value: value)
            return .none

        case .environmentProvision:
            throw ValidationError(
                "Environment branching is not supported in the main program interpreter yet."
            )

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
            case .none:
                elements = []
            default:
                throw ValidationError(
                    "For-in sequence in \(fileName) must evaluate to an array or none."
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
                let caseValue = try evaluate(switchCase.value)
                if valuesEqual(subject, caseValue) {
                    pushScope()
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

    private mutating func executeExpressionStatement(_ expression: NeatSyntax.Expression) throws {
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

    private mutating func evaluate(_ expression: NeatSyntax.Expression) throws -> RuntimeValue {
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

        case .none:
            return .none

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

            case .nilCoalescing:
                let left = try evaluate(lhs)
                if case .none = left {
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

    private func evaluateForInterpolation(_ expression: NeatSyntax.Expression) throws
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
        case .none:
            return "none"
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
        case (.none, .none):
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
                throw ValidationError("Cannot assign to immutable value '\(name)'.")
            }
            slot.value = value

        case .state(let name):
            throw ValidationError(
                "State assignment is not supported in the main-program interpreter yet (\(name)).")

        case .binding(let name):
            throw ValidationError(
                "Binding assignment is not supported in the main-program interpreter yet (\(name))."
            )

        case .environment(let name):
            throw ValidationError(
                "Environment-state assignment is not supported in the main-program interpreter yet (\(name))."
            )

        case .member(let name):
            throw ValidationError(
                "Member assignment is not supported in the main-program interpreter yet (self.\(name))."
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

        case .environment(let name):
            throw ValidationError(
                "Environment-state reads are not supported in the main-program interpreter yet (\(name))."
            )

        case .member(let name):
            throw ValidationError(
                "Member reads are not supported in the main-program interpreter yet (self.\(name))."
            )
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
