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
        let enumerations = try program.enumerations.map(emitEnum).joined(separator: "\n\n")
        let declarations = try program.declarations.map(emitConstruct).joined(separator: "\n\n")

        let main = try emitMain(program.mainBlock)

        let sections = [
            "import Foundation",
            emitRuntimeSupport(includeFoundationImport: false),
            enumerations,
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

        let runtimeSwift = emitRuntimeSupport(includeFoundationImport: true)

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

    private func emitRuntimeSupport(includeFoundationImport: Bool) -> String {
        let support = """
            // Backend implementation for NeatCore's Promise, Result, ChannelStorage, and Logger surface.
            // NeatCore declares the language-visible API; Swift runtime support lives here.
            enum Promise<Success, Failure> {
                case loading
                case success(result: Success)
                case failure(cause: Failure)
            }

            enum Result<Success, Failure> {
                case success(result: Success)
                case failure(cause: Failure)
            }

            final class ChannelStorage<Element>: @unchecked Sendable {
                private let condition = NSCondition()
                private var buffer: [Element] = []
                private let capacity: Int
                private var closed = false

                init() {
                    self.capacity = 0
                }

                init(capacity: Int) {
                    self.capacity = max(0, capacity)
                }

                func send(element: Element) {
                    condition.lock()
                    defer { condition.unlock() }

                    precondition(!closed, "Cannot send to a closed channel.")

                    if capacity == 0 {
                        while !closed && !buffer.isEmpty {
                            condition.wait()
                        }

                        precondition(!closed, "Cannot send to a closed channel.")

                        buffer.append(element)
                        condition.broadcast()

                        while !closed && !buffer.isEmpty {
                            condition.wait()
                        }
                        return
                    }

                    while !closed && buffer.count >= capacity {
                        condition.wait()
                    }

                    precondition(!closed, "Cannot send to a closed channel.")

                    buffer.append(element)
                    condition.broadcast()
                }

                func receive() -> Element {
                    condition.lock()
                    defer { condition.unlock() }

                    while buffer.isEmpty {
                        if closed {
                            preconditionFailure(
                                "Cannot receive from a closed channel with no remaining elements."
                            )
                        }
                        condition.wait()
                    }

                    let element = buffer.removeFirst()
                    condition.broadcast()
                    return element
                }

                func close() {
                    condition.lock()
                    closed = true
                    condition.broadcast()
                    condition.unlock()
                }
            }

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

            enum __NeatDeferredControlFlow: Error {
                case returnValue(Any)
                case returnVoid
                case breakLoop
                case continueLoop
            }
            """

        guard includeFoundationImport else {
            return support
        }

        return "import Foundation\n\n\(support)"
    }

    private func emitSourceUnit(_ unit: LoweredSourceUnit) throws -> String {
        var sections: [String] = ["import Foundation"]

        let enumerations = try unit.enumerations.map(emitEnum).joined(separator: "\n\n")
        if !enumerations.isEmpty {
            sections.append(enumerations)
        }

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
        let body = try emitStatements(mainBlock.body, indent: 2, enclosingReturnType: .named("Void"))

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
        let functionBody = try emitStatements(
            body,
            indent: 1,
            enclosingReturnType: callable.returnType ?? .named("Void")
        )

        return """
            func \(callable.name)(\(parameters))\(returnClause) {
            \(functionBody)
            }
            """
    }

    private func emitLocalCallableDeclaration(
        _ declaration: LocalCallableDeclaration,
        indent: Int
    ) throws -> String {
        let callable = CallableDeclaration(
            macros: declaration.macros,
            attribute: declaration.attribute,
            targetType: nil,
            name: declaration.name,
            genericParameters: declaration.genericParameters,
            hasExplicitParameterClause: declaration.hasExplicitParameterClause,
            parameters: declaration.parameters,
            returnType: declaration.returnType,
            body: declaration.body
        )

        return indentBlock(try emitFunction(callable), level: indent)
    }



    private func emitEnum(_ declaration: EnumDeclaration) throws -> String {
        let genericClause = emitConstructGenericClause(declaration.genericParameters)
        let renderedCases = try declaration.cases.map(emitEnumCase).joined(separator: "\n")

        if renderedCases.isEmpty {
            return "enum \(declaration.name)\(genericClause) {}"
        }

        return """
            enum \(declaration.name)\(genericClause) {
            \(indentBlock(renderedCases, level: 1))
            }
            """
    }

    private func emitEnumCase(_ declaration: EnumCaseDeclaration) throws -> String {
        guard !declaration.associatedValues.isEmpty else {
            return "case \(declaration.name)"
        }

        let associatedValues = declaration.associatedValues.map { associatedValue in
            if let label = associatedValue.label {
                return "\(label): \(emitTypeName(associatedValue.typeReference))"
            }
            return emitTypeName(associatedValue.typeReference)
        }.joined(separator: ", ")

        return "case \(declaration.name)(\(associatedValues))"
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
        let typeName = normalizedSwiftTypeName(typeReference.displayName)
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

    private func emitLocalBindingExpression(_ declaration: LocalBindingDeclaration) throws -> String
    {
        try emitExpression(declaration.expression)
    }

    private func emitDerivedMember(_ derived: DerivedDeclaration) throws -> String {
        guard let body = derived.body else {
            return "var \(derived.name): \(derived.typeName)"
        }

        if body.count == 1, case .expression(let expression) = body[0] {
            return
                "var \(derived.name): \(derived.typeName) { \(try emitExpression(expression)) }"
        }

        let bodyText = try emitStatements(
            body,
            indent: 2,
            enclosingReturnType: .named(derived.typeName)
        )
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

        let functionBody = try emitStatements(body, indent: 2, enclosingReturnType: .named("Void"))
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
        let functionBody = try emitStatements(
            body,
            indent: 2,
            enclosingReturnType: callable.returnType ?? .named("Void")
        )
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
            case .expand:
                continue
            case .macroInvocation(_, _, let body),
                .forEach(_, _, let body),
                .whileLoop(_, let body),
                .derived(_, _, let body):
                if statementsContainMutation(body) {
                    return true
                }
            case .background(let background):
                if statementsContainMutation(background.body) {
                    return true
                }
            case .deferBlock(let deferred):
                if statementsContainMutation(deferred.body) {
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
            case .localBinding, .localCallable, .environmentProvision, .expression, .return, .break, .continue:
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

    private func emitStatements(
        _ statements: [NeatStatement],
        indent: Int,
        enclosingReturnType: TypeReference? = nil
    ) throws -> String {
        try statements
            .map { try emitStatement($0, indent: indent, enclosingReturnType: enclosingReturnType) }
            .joined(separator: "\n")
    }

    private func emitStatement(
        _ statement: NeatStatement,
        indent: Int,
        enclosingReturnType: TypeReference? = nil
    ) throws -> String {
        let prefix = String(repeating: "    ", count: indent)

        switch statement {
        case .macroInvocation:
            throw SwiftBackendError("Macro invocations must be expanded before Swift emission.")
        case .expand:
            throw SwiftBackendError("Macro expansion statements must be expanded before Swift emission.")
        case .background(let background):
            let bodyText = try emitStatements(
                background.body,
                indent: indent + 1,
                enclosingReturnType: enclosingReturnType
            )
            return """
                \(prefix)Task.detached {
                \(bodyText)
                \(prefix)}
                """
        case .deferBlock(let deferred):
            return try emitDeferredBlock(
                deferred.body,
                indent: indent,
                enclosingReturnType: enclosingReturnType
            )
        case .localCallable(let declaration):
            return try emitLocalCallableDeclaration(declaration, indent: indent)
        case .localBinding(let declaration):
            let keyword = declaration.kind == .constant ? "let" : "var"
            let typeAnnotation =
                declaration.hasExplicitTypeAnnotation ? ": \(emitTypeName(declaration.type))" : ""
            return
                "\(prefix)\(keyword) \(declaration.name)\(typeAnnotation) = \(try emitLocalBindingExpression(declaration))"
        case .derived(let name, let typeName, let body):
            let bodyText = try emitStatements(
                body,
                indent: indent + 2,
                enclosingReturnType: .named(typeName)
            )
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
            return try emitConditional(
                branches,
                indent: indent,
                enclosingReturnType: enclosingReturnType
            )
        case .forEach(let name, let sequence, let body):
            let header = "\(prefix)for \(name) in \(try emitExpression(sequence)) {"
            let bodyText = try emitStatements(
                body,
                indent: indent + 1,
                enclosingReturnType: enclosingReturnType
            )
            return "\(header)\n\(bodyText)\n\(prefix)}"
        case .whileLoop(let condition, let body):
            let header = "\(prefix)while \(try emitExpression(condition)) {"
            let bodyText = try emitStatements(
                body,
                indent: indent + 1,
                enclosingReturnType: enclosingReturnType
            )
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
                indent: indent,
                enclosingReturnType: enclosingReturnType
            )
        case .environmentProvision:
            throw SwiftBackendError(
                "Swift backend does not support environment provision statements yet.")
        }
    }

    private func emitConditional(
        _ branches: [StatementConditionalBranch],
        indent: Int,
        enclosingReturnType: TypeReference? = nil
    ) throws
        -> String
    {
        let prefix = String(repeating: "    ", count: indent)
        var rendered: [String] = []

        for (index, branch) in branches.enumerated() {
            let bodyText = try emitStatements(
                branch.body,
                indent: indent + 1,
                enclosingReturnType: enclosingReturnType
            )
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
        indent: Int,
        enclosingReturnType: TypeReference? = nil
    ) throws -> String {
        let prefix = String(repeating: "    ", count: indent)
        var lines: [String] = ["\(prefix)switch \(try emitExpression(subject)) {"]

        for switchCase in cases {
            lines.append("\(prefix)case \(try emitSwitchCasePattern(switchCase.pattern)):")
            lines.append(
                try emitStatements(
                    switchCase.body,
                    indent: indent + 1,
                    enclosingReturnType: enclosingReturnType
                )
            )
        }

        if let defaultBody {
            lines.append("\(prefix)default:")
            lines.append(
                try emitStatements(
                    defaultBody,
                    indent: indent + 1,
                    enclosingReturnType: enclosingReturnType
                )
            )
        }

        lines.append("\(prefix)}")
        return lines.joined(separator: "\n")
    }

    private func emitSwitchCasePattern(_ pattern: SwitchCasePattern) throws -> String {
        switch pattern {
        case .expression(let expression):
            return try emitExpression(expression)
        case .enumCase(let name, let binding):
            if let binding {
                let bindingKeyword = binding.kind == .constant ? "let" : "state"
                return ".\(name)(\(bindingKeyword) \(binding.name))"
            }
            return ".\(name)"
        }
    }

    private func emitAssignmentTarget(_ target: AssignmentTarget) throws -> String {
        switch target {
        case .state(let name), .binding(let name), .environment(let name), .local(let name):
            return name
        case .member(let base, let name):
            return "\(try emitAssignmentTarget(base)).\(name)"
        }
    }

    private func emitExpression(
        _ expression: NeatExpression
    ) throws -> String {
        return try emitRawExpression(expression)
    }

    private func emitRawExpression(
        _ expression: NeatExpression
    ) throws -> String {
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
        case .macroInvocation(let name, _):
            throw SwiftBackendError(
                "Expression macro invocation #\(name) must be expanded before Swift emission.")
        case .block(let body):
            return try emitClosureExpression(body)
        case .identifier(let name):
            return name
        case .call(let name, let arguments):
            if let closure = try emitCoreClosureCall(name: name, arguments: arguments) {
                return closure
            }
            if let lowered = try emitKnownCollectionCall(
                name: name,
                arguments: arguments
            ) {
                return lowered
            }
            return try emitRawCall(name: name, arguments: arguments)
        case .bindingReference(let name):
            return name
        case .array(let elements):
            let rendered = try elements.map { try emitExpression($0) }.joined(separator: ", ")
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

    private func normalizedSwiftTypeName(_ rawName: String) -> String {
        guard rawName.hasPrefix("Channel<"), rawName.hasSuffix(">") else {
            return rawName
        }

        let start = rawName.index(rawName.startIndex, offsetBy: "Channel<".count)
        let end = rawName.index(before: rawName.endIndex)
        let argumentsText = String(rawName[start..<end])

        var depth = 0
        for character in argumentsText {
            switch character {
            case "<":
                depth += 1
            case ">":
                depth -= 1
            case "," where depth == 0:
                return rawName
            default:
                break
            }
        }

        return rawName
    }

    private func emitCoreClosureCall(
        name: String,
        arguments: [CallArgument]
    ) throws -> String? {
        guard name == "Closure",
            let parameters = arguments.first(where: { $0.label == "parameters" })?.value,
            let body = arguments.first(where: { $0.label == "body" })?.value
        else {
            return nil
        }

        guard case .array(let parameterExpressions) = parameters else {
            return nil
        }

        let parameterNames = parameterExpressions.compactMap { expression -> String? in
            guard case .identifier(let name) = expression else {
                return nil
            }
            return name
        }

        guard parameterNames.count == parameterExpressions.count,
            case .block(let statements) = body
        else {
            return nil
        }

        if statements.count == 1, case .expression(let expression) = statements[0] {
            return "{ \(parameterNames.joined(separator: ", ")) in \(try emitExpression(expression)) }"
        }

        let bodyText = try emitStatements(statements, indent: 1, enclosingReturnType: nil)
        return """
            { \(parameterNames.joined(separator: ", ")) in
            \(bodyText)
            }
            """
    }

    private func emitCallArgument(
        _ argument: CallArgument
    ) throws -> String {
        if let label = argument.label {
            return "\(label): \(try emitExpression(argument.value))"
        }
        return try emitExpression(argument.value)
    }

    private func emitCallArguments(
        _ arguments: [CallArgument],
        for callee: String
    ) throws -> String {
        _ = callee
        return try arguments.map { try emitCallArgument($0) }.joined(separator: ", ")
    }

    private func emitKnownCollectionCall(
        name: String,
        arguments: [CallArgument]
    ) throws -> String? {
        guard let dot = name.lastIndex(of: ".") else {
            return nil
        }

        let base = String(name[..<dot])
        let member = String(name[name.index(after: dot)...])

        func argument(_ label: String) -> NeatSyntax.Expression? {
            arguments.first(where: { $0.label == label })?.value
        }

        func unlabeledArgument() -> NeatSyntax.Expression? {
            guard arguments.count == 1, arguments[0].label == nil else {
                return nil
            }
            return arguments[0].value
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
            return
                "\(base)[\(try emitExpression(index))] = \(try emitExpression(element))"
        case "insert":
            guard let element = argument("element") else { return nil }
            if let index = argument("index") {
                return
                    "\(base).insert(\(try emitExpression(element)), at: \(try emitExpression(index)))"
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
        case "map", "compactMap", "flatMap", "forEach":
            guard let transform = unlabeledArgument() else { return nil }
            return "\(base).\(member)(\(try emitExpression(transform)))"
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

        let bodyText = try emitStatements(body, indent: 1, enclosingReturnType: nil)
        return "{\n\(bodyText)\n}"
    }

    private func emitDeferredBlock(
        _ statements: [NeatStatement],
        indent: Int,
        enclosingReturnType: TypeReference?
    ) throws -> String {
        let prefix = String(repeating: "    ", count: indent)
        let bodyPrefix = String(repeating: "    ", count: indent + 1)
        var lines: [String] = [
            "\(prefix)do {",
            "\(bodyPrefix)var __neatDeferredControlFlow: __NeatDeferredControlFlow?",
        ]

        for statement in statements {
            lines.append(
                try emitDeferredProtectedStatement(
                    statement,
                    indent: indent + 1,
                    enclosingReturnType: enclosingReturnType
                )
            )
        }

        lines.append(
            try emitDeferredFlowResume(
                indent: indent + 1,
                enclosingReturnType: enclosingReturnType
            )
        )
        lines.append("\(prefix)}")
        return lines.joined(separator: "\n")
    }

    private func emitDeferredProtectedStatement(
        _ statement: NeatStatement,
        indent: Int,
        enclosingReturnType: TypeReference?
    ) throws -> String {
        let prefix = String(repeating: "    ", count: indent)
        let bodyText = try emitDeferredInnerStatement(
            statement,
            indent: indent + 2,
            enclosingReturnType: enclosingReturnType
        )

        return """
            \(prefix)do {
            \(prefix)    try ({ () throws in
            \(bodyText)
            \(prefix)    })()
            \(prefix)} catch let flow as __NeatDeferredControlFlow {
            \(prefix)    if __neatDeferredControlFlow == nil {
            \(prefix)        __neatDeferredControlFlow = flow
            \(prefix)    }
            \(prefix)}
            """
    }

    private func emitDeferredInnerStatement(
        _ statement: NeatStatement,
        indent: Int,
        enclosingReturnType: TypeReference?
    ) throws -> String {
        let prefix = String(repeating: "    ", count: indent)

        switch statement {
        case .macroInvocation:
            throw SwiftBackendError("Macro invocations must be expanded before Swift emission.")
        case .expand:
            throw SwiftBackendError("Macro expansion statements must be expanded before Swift emission.")
        case .background(let background):
            let bodyText = try emitStatements(
                background.body,
                indent: indent + 1,
                enclosingReturnType: enclosingReturnType
            )
            return """
                \(prefix)Task.detached {
                \(bodyText)
                \(prefix)}
                """
        case .deferBlock(let deferred):
            return try emitDeferredBlock(
                deferred.body,
                indent: indent,
                enclosingReturnType: enclosingReturnType
            )
        case .localCallable(let declaration):
            return try emitLocalCallableDeclaration(declaration, indent: indent)
        case .localBinding(let declaration):
            let keyword = declaration.kind == .constant ? "let" : "var"
            let typeAnnotation =
                declaration.hasExplicitTypeAnnotation ? ": \(emitTypeName(declaration.type))" : ""
            return
                "\(prefix)\(keyword) \(declaration.name)\(typeAnnotation) = \(try emitLocalBindingExpression(declaration))"
        case .derived(let name, let typeName, let body):
            let bodyText = try emitStatements(
                body,
                indent: indent + 2,
                enclosingReturnType: .named(typeName)
            )
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
                return "\(prefix)throw __NeatDeferredControlFlow.returnValue(\(try emitExpression(expression)))"
            }
            return "\(prefix)throw __NeatDeferredControlFlow.returnVoid"
        case .conditional(let branches):
            return try emitDeferredConditional(
                branches,
                indent: indent,
                enclosingReturnType: enclosingReturnType
            )
        case .forEach(let name, let sequence, let body):
            let header = "\(prefix)for \(name) in \(try emitExpression(sequence)) {"
            let bodyText = try emitDeferredInnerStatements(
                body,
                indent: indent + 1,
                enclosingReturnType: enclosingReturnType
            )
            return "\(header)\n\(bodyText)\n\(prefix)}"
        case .whileLoop(let condition, let body):
            let header = "\(prefix)while \(try emitExpression(condition)) {"
            let bodyText = try emitDeferredInnerStatements(
                body,
                indent: indent + 1,
                enclosingReturnType: enclosingReturnType
            )
            return "\(header)\n\(bodyText)\n\(prefix)}"
        case .break:
            return "\(prefix)throw __NeatDeferredControlFlow.breakLoop"
        case .continue:
            return "\(prefix)throw __NeatDeferredControlFlow.continueLoop"
        case .switchStatement(let expression, let cases, let defaultBody):
            return try emitDeferredSwitch(
                subject: expression,
                cases: cases,
                defaultBody: defaultBody,
                indent: indent,
                enclosingReturnType: enclosingReturnType
            )
        case .environmentProvision:
            throw SwiftBackendError(
                "Swift backend does not support environment provision statements yet.")
        }
    }

    private func emitDeferredInnerStatements(
        _ statements: [NeatStatement],
        indent: Int,
        enclosingReturnType: TypeReference?
    ) throws -> String {
        try statements
            .map { try emitDeferredInnerStatement($0, indent: indent, enclosingReturnType: enclosingReturnType) }
            .joined(separator: "\n")
    }

    private func emitDeferredConditional(
        _ branches: [StatementConditionalBranch],
        indent: Int,
        enclosingReturnType: TypeReference?
    ) throws -> String {
        let prefix = String(repeating: "    ", count: indent)
        var rendered: [String] = []

        for (index, branch) in branches.enumerated() {
            let bodyText = try emitDeferredInnerStatements(
                branch.body,
                indent: indent + 1,
                enclosingReturnType: enclosingReturnType
            )
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

    private func emitDeferredSwitch(
        subject: NeatExpression,
        cases: [SwitchCase],
        defaultBody: [NeatStatement]?,
        indent: Int,
        enclosingReturnType: TypeReference?
    ) throws -> String {
        let prefix = String(repeating: "    ", count: indent)
        var lines: [String] = ["\(prefix)switch \(try emitExpression(subject)) {"]

        for switchCase in cases {
            lines.append("\(prefix)case \(try emitSwitchCasePattern(switchCase.pattern)):")
            lines.append(
                try emitDeferredInnerStatements(
                    switchCase.body,
                    indent: indent + 1,
                    enclosingReturnType: enclosingReturnType
                )
            )
        }

        if let defaultBody {
            lines.append("\(prefix)default:")
            lines.append(
                try emitDeferredInnerStatements(
                    defaultBody,
                    indent: indent + 1,
                    enclosingReturnType: enclosingReturnType
                )
            )
        }

        lines.append("\(prefix)}")
        return lines.joined(separator: "\n")
    }

    private func emitDeferredFlowResume(
        indent: Int,
        enclosingReturnType: TypeReference?
    ) throws -> String {
        let prefix = String(repeating: "    ", count: indent)
        var lines: [String] = [
            "\(prefix)if let __neatDeferredControlFlow {",
            "\(prefix)    switch __neatDeferredControlFlow {",
        ]

        if let enclosingReturnType, emitTypeName(enclosingReturnType) != "Void" {
            lines.append(
                "\(prefix)    case .returnValue(let value): return value as! \(emitTypeName(enclosingReturnType))"
            )
            lines.append("\(prefix)    case .returnVoid: return")
        } else {
            lines.append("\(prefix)    case .returnValue: return")
            lines.append("\(prefix)    case .returnVoid: return")
        }

        lines.append("\(prefix)    case .breakLoop: break")
        lines.append("\(prefix)    case .continueLoop: continue")
        lines.append("\(prefix)    }")
        lines.append("\(prefix)}")
        return lines.joined(separator: "\n")
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

    private func emitRawCall(
        name: String,
        arguments: [CallArgument]
    ) throws -> String {
        let rendered = try emitCallArguments(arguments, for: name)
        return "\(normalizedSwiftTypeName(name))(\(rendered))"
    }
}
