import Foundation

public indirect enum RangeRuntimeValue: CustomStringConvertible, Equatable {
    case string(String)
    case integer(Int)
    case double(Double)
    case boolean(Bool)
    case nilValue
    case array([RangeRuntimeValue])
    case object(typeName: String, fields: [String: RangeRuntimeValue])

    public var description: String {
        switch self {
        case .string(let value):
            return value.debugDescription
        case .integer(let value):
            return String(value)
        case .double(let value):
            return String(value)
        case .boolean(let value):
            return value ? "true" : "false"
        case .nilValue:
            return "nil"
        case .array(let values):
            return "[" + values.map(\.description).joined(separator: ", ") + "]"
        case .object(let typeName, let fields):
            let renderedFields = fields.keys.sorted().map { key in
                "\(key): \(fields[key]!.description)"
            }
            return "\(typeName)(" + renderedFields.joined(separator: ", ") + ")"
        }
    }
}

public struct RangeRuntimeExecutor {
    public init() {}

    public func execute(function name: String, in program: CompiledProgram) throws -> RangeRuntimeValue {
        let callable = try findZeroArgumentCallable(named: name, in: program.expandedFiles)
        return try execute(callable: callable)
    }

    func execute(function name: String, in context: CompilerPipelineRuntimeContext) throws -> RangeRuntimeValue {
        let files = context.expandedFiles.isEmpty ? context.parsedFiles : context.expandedFiles
        let callable = try findZeroArgumentCallable(named: name, in: files)
        return try execute(callable: callable)
    }

    private func execute(callable: CallableDeclaration) throws -> RangeRuntimeValue {
        guard callable.parameters.isEmpty else {
            throw RangeRuntimeExecutionError.unsupportedCallable("Range runtime execution only supports zero-argument functions today: \(callable.name).")
        }
        guard let body = callable.body else {
            throw RangeRuntimeExecutionError.unsupportedCallable("Range runtime execution requires a function body: \(callable.name).")
        }

        var locals: [String: Expression] = [:]
        let evaluator = CompileTimeValueEvaluator(
            targetBinding: "target",
            targetValue: .object(typeName: "Runtime.Target", fields: [:]),
            localBindings: locals
        )

        for statement in body {
            switch statement {
            case .localBinding(let declaration):
                locals[declaration.name] = declaration.expression
            case .return(let expression?):
                guard let value = evaluator.evaluate(expression, with: locals) else {
                    throw RangeRuntimeExecutionError.unsupportedExpression("Range runtime could not evaluate return expression in \(callable.name).")
                }
                return RangeRuntimeValue(value)
            case .expression(let expression):
                _ = evaluator.evaluate(expression, with: locals)
            default:
                throw RangeRuntimeExecutionError.unsupportedStatement("Range runtime execution does not support this statement in \(callable.name).")
            }
        }

        throw RangeRuntimeExecutionError.missingReturn("Range runtime function \(callable.name) did not return a value.")
    }

    private func findZeroArgumentCallable(
        named name: String,
        in files: [ParsedSourceFile]
    ) throws -> CallableDeclaration {
        let matches = files.flatMap { callables(in: $0.sourceFile) }
            .filter { $0.name == name && $0.parameters.isEmpty }
        guard let callable = matches.first else {
            throw RangeRuntimeExecutionError.missingCallable("Range runtime function not found: \(name).")
        }
        return callable
    }

    private func callables(in sourceFile: SourceFileNode) -> [CallableDeclaration] {
        switch sourceFile {
        case .module(let module):
            return module.callables + module.packageSpaces.flatMap(\.callables)
        case .namespace(let namespace):
            return namespace.callables
        case .construct(let construct):
            return construct.callables
        case .extensions(let extensions):
            return extensions.flatMap(\.callables)
        default:
            return []
        }
    }
}

public struct RangeFunctionRuntimeHook: CompilerPipelineRuntimeHook {
    public let name: String
    public let functionName: String
    public let stage: CompilerPipelineRuntimeStage

    public init(
        name: String? = nil,
        functionName: String,
        stage: CompilerPipelineRuntimeStage = .declarationGraphBuilt
    ) {
        self.name = name ?? "range.function.\(functionName)"
        self.functionName = functionName
        self.stage = stage
    }

    public func run(context: CompilerPipelineRuntimeContext) throws -> CompilerPipelineRuntimeResult? {
        guard context.stage == stage else {
            return nil
        }

        let value = try RangeRuntimeExecutor().execute(function: functionName, in: context)
        return CompilerPipelineRuntimeResult(
            hookName: name,
            stage: context.stage,
            artifacts: [functionName: value.description]
        )
    }
}

public enum RangeRuntimeExecutionError: Error, CustomStringConvertible {
    case missingCallable(String)
    case missingReturn(String)
    case unsupportedCallable(String)
    case unsupportedStatement(String)
    case unsupportedExpression(String)

    public var description: String {
        switch self {
        case .missingCallable(let message),
            .missingReturn(let message),
            .unsupportedCallable(let message),
            .unsupportedStatement(let message),
            .unsupportedExpression(let message):
            return message
        }
    }
}

private extension RangeRuntimeValue {
    init(_ value: CompileTimeValue) {
        switch value {
        case .string(let value):
            self = .string(value)
        case .integer(let value):
            self = .integer(value)
        case .double(let value):
            self = .double(value)
        case .boolean(let value):
            self = .boolean(value)
        case .nilValue:
            self = .nilValue
        case .array(let values):
            self = .array(values.map(RangeRuntimeValue.init))
        case .object(let typeName, let fields):
            self = .object(typeName: typeName, fields: fields.mapValues(RangeRuntimeValue.init))
        }
    }
}
