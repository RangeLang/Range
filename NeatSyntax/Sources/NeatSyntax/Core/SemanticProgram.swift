import Foundation

public enum SourceInputRole {
    case core
    case project
}

public struct SourceInput {
    public let path: String
    public let source: String
    public let role: SourceInputRole

    public init(path: String, source: String, role: SourceInputRole) {
        self.path = path
        self.source = source
        self.role = role
    }
}

public struct SemanticProgram {
    public let inputs: [SourceInput]
    public let parsedFiles: [ParsedSourceFile]
    public let expandedFiles: [ParsedSourceFile]
    public let declarationGraph: DeclarationGraph

    private let inputRoleByPath: [String: SourceInputRole]

    public init(
        inputs: [SourceInput],
        parsedFiles: [ParsedSourceFile],
        expandedFiles: [ParsedSourceFile],
        declarationGraph: DeclarationGraph
    ) {
        self.inputs = inputs
        self.parsedFiles = parsedFiles
        self.expandedFiles = expandedFiles
        self.declarationGraph = declarationGraph
        self.inputRoleByPath = Dictionary(
            uniqueKeysWithValues: inputs.map { ($0.path, $0.role) }
        )
    }

    public var literalBridgeResolver: LiteralBridgeResolver {
        declarationGraph.literalBridgeResolver
    }

    public var projectParsedFiles: [ParsedSourceFile] {
        parsedFiles.filter { inputRoleByPath[$0.path] == .project }
    }

    public var projectExpandedFiles: [ParsedSourceFile] {
        expandedFiles.filter { inputRoleByPath[$0.path] == .project }
    }

    public func sourceRole(forPath path: String) -> SourceInputRole? {
        inputRoleByPath[path]
    }
}

public struct CompilerPipeline {
    public init() {}

    public func build(inputs: [SourceInput]) throws -> SemanticProgram {
        let orderedInputs = inputs.sorted { lhs, rhs in
            if lhs.role != rhs.role {
                return lhs.role == .core
            }
            return lhs.path < rhs.path
        }

        let coreInputs = orderedInputs.filter { $0.role == .core }
        let projectInputs = orderedInputs.filter { $0.role == .project }

        let parsedCoreFiles = try parse(
            inputs: coreInputs,
            literalBridgeResolver: .empty,
            declarationMemberResolver: .empty
        )
        let coreGraph = DeclarationGraph(files: parsedCoreFiles)
        let coreResolver = coreGraph.literalBridgeResolver
        let coreMemberResolver = coreGraph.memberResolver
        let parsedProjectFiles = try parse(
            inputs: projectInputs,
            literalBridgeResolver: coreResolver,
            declarationMemberResolver: coreMemberResolver
        )

        let parsedFiles = parsedCoreFiles + parsedProjectFiles
        let expandedFiles = try MacroExpander.expand(files: parsedFiles)
        let declarationGraph = DeclarationGraph(files: expandedFiles)

        return SemanticProgram(
            inputs: orderedInputs,
            parsedFiles: parsedFiles,
            expandedFiles: expandedFiles,
            declarationGraph: declarationGraph
        )
    }

    public func buildValidated(inputs: [SourceInput]) throws -> SemanticProgram {
        let program = try build(inputs: inputs)
        try SemanticProgramValidator().validate(program)
        return program
    }

    public func validatePrimaryDeclarations(inputs: [SourceInput]) throws {
        let program = try build(inputs: inputs)
        try SemanticProgramValidator().validatePrimaryDeclarations(in: program)
    }

    private func parse(
        inputs: [SourceInput],
        literalBridgeResolver: LiteralBridgeResolver,
        declarationMemberResolver: DeclarationMemberResolver
    ) throws -> [ParsedSourceFile] {
        try inputs.map { input in
            var parser = try Parser(
                source: input.source,
                literalBridgeResolver: literalBridgeResolver,
                declarationMemberResolver: declarationMemberResolver
            )
            return ParsedSourceFile(
                path: input.path,
                sourceFile: try parser.parseSourceFile()
            )
        }
    }
}
