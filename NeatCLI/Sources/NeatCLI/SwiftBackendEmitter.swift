import ArgumentParser
import Foundation
import NeatSyntax

struct SwiftBackendEmitter {
    private typealias NeatExpression = NeatSyntax.Expression
    private typealias NeatStatement = NeatSyntax.Statement

    struct SourceUnit {
        let swiftFileName: String
        let callables: [CallableDeclaration]
        let mainBlock: MainBlockNode?
    }

    struct Program {
        let callables: [CallableDeclaration]
        let declarations: [ConstructDeclaration]
        let mainBlock: MainBlockNode
        let units: [SourceUnit]
    }

    func emit(program: Program) throws -> String {
        let allCallables = program.callables + program.declarations.flatMap(\.callables)
        let functions =
            try allCallables
            .filter { $0.targetType == nil }
            .map(emitFunction)
            .joined(separator: "\n\n")

        let main = try emitMain(program.mainBlock)

        let sections = [
            "import Foundation",
            functions,
            main,
        ].filter { !$0.isEmpty }

        return sections.joined(separator: "\n\n") + "\n"
    }

    func emitWorkspace(program: Program, at root: URL) throws {
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
                to: sourcesDirectory.appendingPathComponent(unit.swiftFileName),
                atomically: true,
                encoding: .utf8
            )
        }
    }

    private func emitSourceUnit(_ unit: SourceUnit) throws -> String {
        var sections: [String] = ["import Foundation"]

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
            throw ValidationError(
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

    private func emitParameter(_ parameter: NeatFunctionParameter) throws -> String {
        guard let typeReference = parameter.typeReference else {
            throw ValidationError("Swift backend requires explicit parameter types.")
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
        case "Data":
            return "Data"
        default:
            return typeName
        }
    }

    private func emitStatements(_ statements: [NeatStatement], indent: Int) throws -> String {
        try statements
            .map { try emitStatement($0, indent: indent) }
            .joined(separator: "\n")
    }

    private func emitStatement(_ statement: NeatStatement, indent: Int) throws -> String {
        let prefix = String(repeating: "    ", count: indent)

        switch statement {
        case .declaration(let kind, let name, _, let expression):
            let keyword = kind == .constant ? "let" : "var"
            return "\(prefix)\(keyword) \(name) = \(try emitExpression(expression))"
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
            throw ValidationError(
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
        case .identifier(let name):
            return name
        case .call(let name, let arguments):
            let rendered = try arguments.map(emitCallArgument).joined(separator: ", ")
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
