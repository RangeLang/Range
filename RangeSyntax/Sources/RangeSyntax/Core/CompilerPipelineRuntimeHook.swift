import Foundation

public enum CompilerPipelineRuntimeStage: String, Sendable {
    case coreDeclarationsDiscovered
    case coreParsed
    case projectDeclarationsDiscovered
    case projectParsed
    case macrosExpanded
    case declarationGraphBuilt
}

public struct CompilerPipelineRuntimeContext {
    public let stage: CompilerPipelineRuntimeStage
    public let inputs: [SourceInput]
    public let parsedFiles: [ParsedSourceFile]
    public let expandedFiles: [ParsedSourceFile]
    public let declarationGraph: DeclarationGraph?

    public init(
        stage: CompilerPipelineRuntimeStage,
        inputs: [SourceInput],
        parsedFiles: [ParsedSourceFile] = [],
        expandedFiles: [ParsedSourceFile] = [],
        declarationGraph: DeclarationGraph? = nil
    ) {
        self.stage = stage
        self.inputs = inputs
        self.parsedFiles = parsedFiles
        self.expandedFiles = expandedFiles
        self.declarationGraph = declarationGraph
    }
}

public struct CompilerPipelineRuntimeResult {
    public let hookName: String
    public let stage: CompilerPipelineRuntimeStage
    public let diagnostics: [RangeDiagnostic]
    public let artifacts: [String: String]

    public init(
        hookName: String,
        stage: CompilerPipelineRuntimeStage,
        diagnostics: [RangeDiagnostic] = [],
        artifacts: [String: String] = [:]
    ) {
        self.hookName = hookName
        self.stage = stage
        self.diagnostics = diagnostics
        self.artifacts = artifacts
    }
}

public protocol CompilerPipelineRuntimeHook {
    var name: String { get }

    func run(context: CompilerPipelineRuntimeContext) throws -> CompilerPipelineRuntimeResult?
}
