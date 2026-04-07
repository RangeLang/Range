import Foundation
import NeatSyntax

struct SwiftBackendEmitter {
    private typealias NeatExpression = NeatSyntax.Expression
    private typealias NeatStatement = NeatSyntax.Statement

    func emit(program: LoweredProgram) throws -> String {
        let allCallables = program.callables + program.declarations.flatMap(\.callables)
        let functions =
            try allCallables
            .filter { $0.targetType == nil }
            .map(emitFunction)
            .joined(separator: "\n\n")
        let declarations = try program.declarations.map(emitConstruct).joined(separator: "\n\n")

        let main = try emitMain(program.mainBlock)

        let sections = [
            "import Foundation",
            declarations,
            functions,
            main,
        ].filter { !$0.isEmpty }

        return sections.joined(separator: "\n\n") + "\n"
    }

    func emitWorkspace(program: LoweredProgram, at root: URL) throws {
        let sourcesDirectory = root.appendingPathComponent("Sources", isDirectory: true)
        try FileManager.default.createDirectory(
            at: sourcesDirectory, withIntermediateDirectories: true)

        let packageSwift = """
            // swift-tools-version: 6.2
            import PackageDescription

            let package = Package(
                name: "NeatGenerated",
                platforms: [
                    .macOS(.v13)
                ],
                targets: [
                    .executableTarget(
                        name: "NeatGenerated"
                    )
                ]
            )
            """

        try packageSwift.write(
            to: root.appendingPathComponent("Package.swift"),
            atomically: true,
            encoding: .utf8
        )

        let runtimeSwift = """
            import Foundation

            enum Logger {
                static func log(_ value: Any) {
                    print(String(describing: value))
                }

                static func debug(_ value: Any) {
                    print(String(describing: value))
                }

                static func info(_ value: Any) {
                    print(String(describing: value))
                }

                static func success(_ value: Any) {
                    print(String(describing: value))
                }

                static func warning(_ value: Any) {
                    print(String(describing: value))
                }

                static func error(_ value: Any) {
                    fputs("\\(String(describing: value))\\n", stderr)
                }
            }
            """

        try runtimeSwift.write(
            to: sourcesDirectory.appendingPathComponent("Runtime.swift"),
            atomically: true,
            encoding: .utf8
        )

        for unit in program.units {
            let content = try emitSourceUnit(unit)
            try content.write(
                to: sourcesDirectory.appendingPathComponent(unit.outputFileName),
                atomically: true,
                encoding: .utf8
            )
        }
    }

    private func emitSourceUnit(_ unit: LoweredSourceUnit) throws -> String {
        var sections: [String] = ["import Foundation"]

        let declarations = try unit.declarations.map(emitConstruct).joined(separator: "\n\n")
        if !declarations.isEmpty {
            sections.append(declarations)
        }

        let functions = try unit.callables
            .filter { $0.targetType == nil }
            .map(emitFunction)
            .joined(separator: "\n\n")

        if !functions.isEmpty {
            sections.append(functions)
        }

        if let mainBlock = unit.mainBlock {
            sections.append(try emitMain(mainBlock))
        }

        return sections.joined(separator: "\n\n") + "\n"
    }

    private func emitMain(_ mainBlock: MainBlockNode) throws -> String {
        let body = try emitStatements(mainBlock.body, indent: 2)

        return """
            @main
            struct NeatMain {
                static func main() throws {
            \(body)
                }
            }
            """
    }

    private func emitFunction(_ callable: CallableDeclaration) throws -> String {
        guard let body = callable.body else {
            throw SwiftBackendError(
                "Swift backend requires function \(callable.name) to have a body.")
        }

        let parameters = try callable.parameters.map(emitParameter).joined(separator: ", ")
        let returnClause = try emitReturnClause(callable.returnType)
        let functionBody = try emitStatements(body, indent: 1)

        return """
            func \(callable.name)(\(parameters))\(returnClause) {
            \(functionBody)
            }
            """
    }

    private func emitConstruct(_ declaration: ConstructDeclaration) throws -> String {
        let genericClause = emitConstructGenericClause(declaration.genericParameters)
        let storedValues = try declaration.values.map(emitStoredValue).joined(separator: "\n")
        let storedStates = try declaration.states.map(emitStoredState).joined(separator: "\n")
        let storedBindings = try declaration.bindings.map(emitStoredBinding).joined(separator: "\n")
        let deriveds = try declaration.deriveds.map(emitDerivedMember).joined(separator: "\n\n")
        let initializers = try declaration.initializers.map(emitInitializer).joined(
            separator: "\n\n")
        let methods = try declaration.callables
            .filter { $0.targetType == nil }
            .map(emitMethod)
            .joined(separator: "\n\n")

        let memberSections = [
            storedValues,
            storedStates,
            storedBindings,
            deriveds,
            initializers,
            methods,
        ].filter { !$0.isEmpty }

        if memberSections.isEmpty {
            return "struct \(declaration.name)\(genericClause) {\n}"
        }

        let body = memberSections.joined(separator: "\n\n")
        return """
            struct \(declaration.name)\(genericClause) {
            \(indentBlock(body, level: 1))
            }
            """
    }

    private func emitParameter(_ parameter: NeatFunctionParameter) throws -> String {
        guard let typeReference = parameter.typeReference else {
            throw SwiftBackendError("Swift backend requires explicit parameter types.")
        }

        let local = parameter.localName
        switch parameter.externalLabel {
        case .none:
            return "_ \(local): \(emitTypeName(typeReference))"
        case .some(let external) where external == local:
            return "\(local): \(emitTypeName(typeReference))"
        case .some(let external):
            return "\(external) \(local): \(emitTypeName(typeReference))"
        }
    }

    private func emitReturnClause(_ typeReference: TypeReference?) throws -> String {
        guard let typeReference else {
            return ""
        }
        return " -> \(emitTypeName(typeReference))"
    }

    private func emitTypeName(_ typeReference: TypeReference) -> String {
        let typeName = typeReference.displayName
        switch typeName {
        case "Int", "Double", "Float", "String", "Bool", "Void":
            return typeName
        default:
            return typeName
        }
    }

    private func emitConstructGenericClause(_ parameters: [GenericParameter]) -> String {
        guard !parameters.isEmpty else { return "" }

        let rendered = parameters.compactMap { parameter -> String? in
            switch parameter {
            case .type(let name, _, _):
                return name
            case .value:
                return nil
            }
        }

        guard !rendered.isEmpty else { return "" }
        return "<\(rendered.joined(separator: ", "))>"
    }

    private func emitStoredValue(_ value: ValueDeclaration) throws -> String {
        if let expression = value.value {
            return "let \(value.name): \(value.typeName) = \(try emitExpression(expression))"
        }
        return "let \(value.name): \(value.typeName)"
    }

    private func emitStoredState(_ state: StateDeclaration) throws -> String {
        switch state.storage {
        case .stored(let expression):
            return
                "var \(state.name): \(emitTypeName(state.type)) = \(try emitExpression(expression))"
        case .declared:
            return "var \(state.name): \(emitTypeName(state.type))"
        }
    }

    private func emitStoredBinding(_ binding: BindingDeclaration) throws -> String {
        switch binding.storage {
        case .plain:
            return "var \(binding.name): \(binding.typeName)"
        case .derived:
            throw SwiftBackendError("Swift backend does not support derived binding storage yet.")
        }
    }

    private func emitDerivedMember(_ derived: DerivedDeclaration) throws -> String {
        guard let body = derived.body else {
            return "var \(derived.name): \(derived.typeName)"
        }

        if body.count == 1, case .expression(let expression) = body[0] {
            return
                "var \(derived.name): \(derived.typeName) { \(try emitExpression(expression)) }"
        }

        let bodyText = try emitStatements(body, indent: 2)
        return """
            var \(derived.name): \(derived.typeName) {
            \(bodyText)
            }
            """
    }

    private func emitInitializer(_ initializer: InitializerDeclaration) throws -> String {
        let parameters = try initializer.parameters.map(emitParameter).joined(separator: ", ")
        guard let body = initializer.body else {
            return "init(\(parameters)) {}"
        }

        let functionBody = try emitStatements(body, indent: 2)
        return """
            init(\(parameters)) {
            \(functionBody)
            }
            """
    }

    private func emitMethod(_ callable: CallableDeclaration) throws -> String {
        guard let body = callable.body else {
            throw SwiftBackendError(
                "Swift backend requires function \(callable.name) to have a body.")
        }

        let parameters = try callable.parameters.map(emitParameter).joined(separator: ", ")
        let returnClause = try emitReturnClause(callable.returnType)
        let functionBody = try emitStatements(body, indent: 2)
        let mutatingPrefix = methodNeedsMutation(callable) ? "mutating " : ""

        return """
            \(mutatingPrefix)func \(callable.name)(\(parameters))\(returnClause) {
            \(functionBody)
            }
            """
    }

    private func methodNeedsMutation(_ callable: CallableDeclaration) -> Bool {
        guard let body = callable.body else { return false }
        return statementsContainMutation(body)
    }

    private func statementsContainMutation(_ statements: [NeatStatement]) -> Bool {
        for statement in statements {
            switch statement {
            case .assignment, .compoundAssignment:
                return true
            case .freestandingMacro(_, _, let body),
                .forEach(_, _, let body),
                .whileLoop(_, let body),
                .derived(_, _, let body):
                if statementsContainMutation(body) {
                    return true
                }
            case .conditional(let branches):
                if branches.contains(where: { statementsContainMutation($0.body) }) {
                    return true
                }
            case .switchStatement(_, let cases, let defaultBody):
                if cases.contains(where: { statementsContainMutation($0.body) }) {
                    return true
                }
                if let defaultBody, statementsContainMutation(defaultBody) {
                    return true
                }
            case .localBinding, .environmentProvision, .expression, .return, .break, .continue:
                continue
            }
        }

        return false
    }

    private func indentBlock(_ text: String, level: Int) -> String {
        let prefix = String(repeating: "    ", count: level)
        return
            text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { prefix + $0 }
            .joined(separator: "\n")
    }

    private func emitStatements(_ statements: [NeatStatement], indent: Int) throws -> String {
        try statements
            .map { try emitStatement($0, indent: indent) }
            .joined(separator: "\n")
    }

    private func emitStatement(_ statement: NeatStatement, indent: Int) throws -> String {
        let prefix = String(repeating: "    ", count: indent)

        switch statement {
        case .freestandingMacro:
            throw SwiftBackendError("Freestanding macros must be expanded before Swift emission.")
        case .localBinding(let declaration):
            let keyword = declaration.kind == .constant ? "let" : "var"
            let typeAnnotation =
                declaration.hasExplicitTypeAnnotation ? ": \(emitTypeName(declaration.type))" : ""
            return
                "\(prefix)\(keyword) \(declaration.name)\(typeAnnotation) = \(try emitExpression(declaration.expression))"
        case .derived(let name, let typeName, let body):
            let bodyText = try emitStatements(body, indent: indent + 2)
            return """
                \(prefix)let \(name): \(typeName) = {
                \(bodyText)
                \(prefix)}()
                """
        case .assignment(let target, let expression):
            return
                "\(prefix)\(try emitAssignmentTarget(target)) = \(try emitExpression(expression))"
        case .compoundAssignment(let target, .plusEquals, let expression):
            return
                "\(prefix)\(try emitAssignmentTarget(target)) += \(try emitExpression(expression))"
        case .expression(let expression):
            return "\(prefix)\(try emitExpression(expression))"
        case .return(let expression):
            if let expression {
                return "\(prefix)return \(try emitExpression(expression))"
            }
            return "\(prefix)return"
        case .conditional(let branches):
            return try emitConditional(branches, indent: indent)
        case .forEach(let name, let sequence, let body):
            let header = "\(prefix)for \(name) in \(try emitExpression(sequence)) {"
            let bodyText = try emitStatements(body, indent: indent + 1)
            return "\(header)\n\(bodyText)\n\(prefix)}"
        case .whileLoop(let condition, let body):
            let header = "\(prefix)while \(try emitExpression(condition)) {"
            let bodyText = try emitStatements(body, indent: indent + 1)
            return "\(header)\n\(bodyText)\n\(prefix)}"
        case .break:
            return "\(prefix)break"
        case .continue:
            return "\(prefix)continue"
        case .switchStatement(let expression, let cases, let defaultBody):
            return try emitSwitch(
                subject: expression,
                cases: cases,
                defaultBody: defaultBody,
                indent: indent
            )
        case .environmentProvision:
            throw SwiftBackendError(
                "Swift backend does not support environment provision statements yet.")
        }
    }

    private func emitConditional(_ branches: [StatementConditionalBranch], indent: Int) throws
        -> String
    {
        let prefix = String(repeating: "    ", count: indent)
        var rendered: [String] = []

        for (index, branch) in branches.enumerated() {
            let bodyText = try emitStatements(branch.body, indent: indent + 1)
            if let condition = branch.condition {
                let keyword = index == 0 ? "if" : "else if"
                rendered.append(
                    "\(prefix)\(keyword) \(try emitExpression(condition)) {\n\(bodyText)\n\(prefix)}"
                )
            } else {
                rendered.append("\(prefix)else {\n\(bodyText)\n\(prefix)}")
            }
        }

        return rendered.joined(separator: " ")
    }

    private func emitSwitch(
        subject: NeatExpression,
        cases: [SwitchCase],
        defaultBody: [NeatStatement]?,
        indent: Int
    ) throws -> String {
        let prefix = String(repeating: "    ", count: indent)
        var lines: [String] = ["\(prefix)switch \(try emitExpression(subject)) {"]

        for switchCase in cases {
            lines.append("\(prefix)case \(try emitExpression(switchCase.value)):")
            lines.append(try emitStatements(switchCase.body, indent: indent + 1))
        }

        if let defaultBody {
            lines.append("\(prefix)default:")
            lines.append(try emitStatements(defaultBody, indent: indent + 1))
        }

        lines.append("\(prefix)}")
        return lines.joined(separator: "\n")
    }

    private func emitAssignmentTarget(_ target: AssignmentTarget) throws -> String {
        switch target {
        case .state(let name), .binding(let name), .environment(let name), .local(let name):
            return name
        case .member(let base, let name):
            return "\(try emitAssignmentTarget(base)).\(name)"
        }
    }

    private func emitExpression(_ expression: NeatExpression) throws -> String {
        switch expression {
        case .integer(let value):
            return "\(value)"
        case .double(let value):
            return "\(value)"
        case .string(let value):
            return "\"\(escapeString(value))\""
        case .interpolatedString(let value):
            return "\"\(try emitInterpolatedString(value))\""
        case .boolean(let value):
            return value ? "true" : "false"
        case .nilLiteral:
            return "nil"
        case .block(let body):
            return try emitClosureExpression(body)
        case .identifier(let name):
            return name
        case .call(let name, let arguments):
            if let lowered = try emitKnownCollectionCall(name: name, arguments: arguments) {
                return lowered
            }
            let rendered = try emitCallArguments(arguments, for: name)
            return "\(name)(\(rendered))"
        case .bindingReference(let name):
            return name
        case .array(let elements):
            let rendered = try elements.map(emitExpression).joined(separator: ", ")
            return "[\(rendered)]"
        case .dictionary(let elements):
            let rendered = try elements.map { element in
                "\(try emitExpression(element.key)): \(try emitExpression(element.value))"
            }.joined(separator: ", ")
            return "[\(rendered)]"
        case .ternary(let condition, let trueExpression, let falseExpression):
            return
                "\(try emitExpression(condition)) ? \(try emitExpression(trueExpression)) : \(try emitExpression(falseExpression))"
        case .unary(let operatorSymbol, let nested):
            return "\(operatorSymbol.rawValue)\(try emitExpression(nested))"
        case .binary(let lhs, let operatorSymbol, let rhs):
            return
                "\(try emitExpression(lhs)) \(operatorSymbol.rawValue) \(try emitExpression(rhs))"
        }
    }

    private func emitCallArgument(_ argument: CallArgument) throws -> String {
        if let label = argument.label {
            return "\(label): \(try emitExpression(argument.value))"
        }
        return try emitExpression(argument.value)
    }

    private func emitCallArguments(_ arguments: [CallArgument], for callee: String) throws -> String
    {
        return try arguments.map(emitCallArgument).joined(separator: ", ")
    }

    private func emitKnownCollectionCall(name: String, arguments: [CallArgument]) throws -> String? {
        guard let dot = name.lastIndex(of: ".") else {
            return nil
        }

        let base = String(name[..<dot])
        let member = String(name[name.index(after: dot)...])

        func argument(_ label: String) -> NeatSyntax.Expression? {
            arguments.first(where: { $0.label == label })?.value
        }

        switch member {
        case "append":
            guard let element = argument("element") else { return nil }
            return "\(base).append(\(try emitExpression(element)))"
        case "element":
            guard let index = argument("index") else { return nil }
            return "\(base)[\(try emitExpression(index))]"
        case "update":
            guard let element = argument("element"), let index = argument("index") else {
                return nil
            }
            return "\(base)[\(try emitExpression(index))] = \(try emitExpression(element))"
        case "insert":
            guard let element = argument("element") else { return nil }
            if let index = argument("index") {
                return "\(base).insert(\(try emitExpression(element)), at: \(try emitExpression(index)))"
            }
            return "\(base).insert(\(try emitExpression(element)))"
        case "remove":
            if let index = argument("index") {
                return "\(base).remove(at: \(try emitExpression(index)))"
            }
            guard let element = argument("element") else { return nil }
            return "\(base).remove(\(try emitExpression(element)))"
        case "removeLast":
            guard arguments.isEmpty else { return nil }
            return "\(base).popLast()"
        case "clear":
            guard arguments.isEmpty else { return nil }
            return "\(base).removeAll()"
        case "first":
            guard arguments.isEmpty else { return nil }
            return "\(base).first"
        case "last":
            guard arguments.isEmpty else { return nil }
            return "\(base).last"
        case "filter":
            guard let include = argument("include") else { return nil }
            return "\(base).filter(\(try emitExpression(include)))"
        case "value":
            guard let key = argument("key") else { return nil }
            return "\(base)[\(try emitExpression(key))]"
        case "updateValue":
            guard let value = argument("value"), let key = argument("key") else { return nil }
            return
                "\(base).updateValue(\(try emitExpression(value)), forKey: \(try emitExpression(key)))"
        case "removeValue":
            guard let key = argument("key") else { return nil }
            return "\(base).removeValue(forKey: \(try emitExpression(key)))"
        case "contains":
            if let key = argument("key") {
                return "\(base).keys.contains(\(try emitExpression(key)))"
            }
            guard let element = argument("element") else { return nil }
            return "\(base).contains(\(try emitExpression(element)))"
        default:
            return nil
        }
    }

    private func emitClosureExpression(_ body: [NeatStatement]) throws -> String {
        if body.count == 1, case .expression(let expression) = body[0] {
            return "{ \(try emitExpression(expression)) }"
        }

        let bodyText = try emitStatements(body, indent: 1)
        return "{\n\(bodyText)\n}"
    }

    private func emitInterpolatedString(_ string: InterpolatedString) throws -> String {
        var result = ""

        for segment in string.segments {
            switch segment {
            case .text(let text):
                result += escapeString(text)
            case .expression(let expression):
                result += "\\(\(try emitExpression(expression)))"
            }
        }

        return result
    }

    private func escapeString(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
    }
}
