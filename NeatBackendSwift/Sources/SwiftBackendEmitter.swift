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
            // Backend implementation for NeatCore's Promise and Logger surface.
            // NeatCore declares the language-visible API; Swift runtime support lives here.
            enum PromiseRuntimeState<Success, Failure> {
                case loading
                case success(Success)
                case failure(Failure)
            }

            final class Promise<Success: Sendable, Failure>: @unchecked Sendable {
                private let lock = NSLock()
                private var state: PromiseRuntimeState<Success, Failure>

                private init(state: PromiseRuntimeState<Success, Failure>) {
                    self.state = state
                }

                static func loading() -> Promise<Success, Failure> {
                    Promise(state: .loading)
                }

                static func success(_ value: Success) -> Promise<Success, Failure> {
                    Promise(state: .success(value))
                }

                static func failure(_ error: Failure) -> Promise<Success, Failure> {
                    Promise(state: .failure(error))
                }

                func snapshot() -> PromiseRuntimeState<Success, Failure> {
                    lock.lock()
                    defer { lock.unlock() }
                    return state
                }

                func isLoading() -> Bool {
                    lock.lock()
                    defer { lock.unlock() }
                    if case .loading = state {
                        return true
                    }
                    return false
                }

                func value() -> Success? {
                    lock.lock()
                    defer { lock.unlock() }
                    if case .success(let value) = state {
                        return value
                    }
                    return nil
                }

                func error() -> Failure? {
                    lock.lock()
                    defer { lock.unlock() }
                    if case .failure(let error) = state {
                        return error
                    }
                    return nil
                }

                func resolveSuccess(_ value: Success) {
                    lock.lock()
                    state = .success(value)
                    lock.unlock()
                }

                func resolveFailure(_ error: Failure) {
                    lock.lock()
                    state = .failure(error)
                    lock.unlock()
                }
            }

            func settle<Success, Failure>(_ result: Result<Success, Failure>) -> Result<Success, Failure> {
                result
            }

            func settle<Success: Sendable, Failure>(_ promise: Promise<Success, Failure>) -> Result<Success, Failure> {
                while true {
                    switch promise.snapshot() {
                    case .loading:
                        Thread.sleep(forTimeInterval: 0.001)
                    case .success(let value):
                        return .success(value)
                    case .failure(let error):
                        return .failure(error)
                    }
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

        if callable.isBackground {
            return try emitBackgroundFunction(callable, parameters: parameters, body: body)
        }

        let returnClause = try emitReturnClause(callable.returnType)
        let functionBody = try emitStatements(body, indent: 1)

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

    private func emitBackgroundFunction(
        _ callable: CallableDeclaration,
        parameters: String,
        body: [NeatStatement]
    ) throws -> String {
        guard
            let declaredReturnType = callable.returnType,
            let successType = callable.backgroundPromiseSuccessType,
            let failureType = callable.backgroundPromiseFailureType
        else {
            throw SwiftBackendError(
                "Background worker \(callable.name) must declare return type Promise<Success, Failure>."
            )
        }

        let returnClause = try emitReturnClause(declaredReturnType)
        let successTypeName = emitTypeName(successType)
        let failureTypeName = emitTypeName(failureType)
        let functionBody = try emitStatements(body, indent: 4)

        return """
            func \(callable.name)(\(parameters))\(returnClause) {
                let promise = Promise<\(successTypeName), \(failureTypeName)>.loading()
                Task {
                    let value: \(successTypeName) = {
            \(functionBody)
                    }()
                    promise.resolveSuccess(value)
                }
                return promise
            }
            """
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

    private func emitLocalBindingExpression(_ declaration: LocalBindingDeclaration) throws -> String
    {
        let expression = try emitExpression(declaration.expression)

        guard declaration.kind == .constant, isResultType(declaration.type) else {
            return expression
        }

        return "settle(\(expression))"
    }

    private func isResultType(_ typeReference: TypeReference) -> Bool {
        guard case .generic(let base, let arguments) = typeReference,
            arguments.count == 2
        else {
            return false
        }

        guard case .named(let baseName) = base else {
            return false
        }

        return baseName == "Result"
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
                .background(let body),
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
        case .background(let body):
            let bodyText = try emitStatements(body, indent: indent + 1)
            return """
                \(prefix)Task {
                \(bodyText)
                \(prefix)}
                """
        case .localCallable(let declaration):
            return try emitLocalCallableDeclaration(declaration, indent: indent)
        case .localBinding(let declaration):
            let keyword = declaration.kind == .constant ? "let" : "var"
            let typeAnnotation =
                declaration.hasExplicitTypeAnnotation ? ": \(emitTypeName(declaration.type))" : ""
            return
                "\(prefix)\(keyword) \(declaration.name)\(typeAnnotation) = \(try emitLocalBindingExpression(declaration))"
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
        case .freestandingMacro(let name, _):
            throw SwiftBackendError(
                "Freestanding expression macro #\(name) must be expanded before Swift emission.")
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

    private func emitKnownCollectionCall(name: String, arguments: [CallArgument]) throws -> String?
    {
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
