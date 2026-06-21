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
        return try execute(callable: callable, in: program.expandedFiles)
    }

    func execute(function name: String, in context: CompilerPipelineRuntimeContext) throws -> RangeRuntimeValue {
        let files = context.expandedFiles.isEmpty ? context.parsedFiles : context.expandedFiles
        let callable = try findZeroArgumentCallable(named: name, in: files)
        return try execute(callable: callable, in: files)
    }

    private func execute(callable: CallableDeclaration, in files: [ParsedSourceFile]) throws -> RangeRuntimeValue {
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
            localBindings: locals,
            callableDeclarationsByName: Dictionary(grouping: files.flatMap { callables(in: $0.sourceFile) }, by: \.name),
            knownObjectTypeNames: knownObjectTypeNames(in: files)
        )

        guard let value = evaluator.evaluateStatements(body, locals: &locals) else {
            throw RangeRuntimeExecutionError.missingReturn("Range runtime function \(callable.name) did not return a value.")
        }
        return RangeRuntimeValue(value)
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
            return module.callables + module.constructs.flatMap { callables(in: .construct($0)) }
        case .construct(let construct):
            return construct.callables + construct.constructs.flatMap { callables(in: .construct($0)) }
        case .extensions(let extensions):
            return extensions.flatMap { $0.callables + $0.constructs.flatMap { callables(in: .construct($0)) } }
        default:
            return []
        }
    }

    private func knownObjectTypeNames(in files: [ParsedSourceFile]) -> Set<String> {
        Set(files.flatMap { constructNames(in: $0.sourceFile) })
    }

    private func constructNames(in sourceFile: SourceFileNode) -> [String] {
        switch sourceFile {
        case .module(let module):
            return module.constructs.flatMap { constructNames(in: $0) }
        case .construct(let construct):
            return constructNames(in: construct)
        case .extensions(let extensions):
            return extensions.flatMap { $0.constructs.flatMap(constructNames(in:)) }
        case .enumeration, .macro, .mainBlock:
            return []
        }
    }

    private func constructNames(in construct: ConstructDeclaration) -> [String] {
        [construct.name] + construct.constructs.flatMap(constructNames(in:))
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
