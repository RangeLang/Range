import Foundation

public struct DeclarationGraphValidator: CompiledProgramValidationPass {
    public let name = "DeclarationGraph"

    public init() {}

    public func validate(_ program: CompiledProgram) throws {
        try validateCoreAttributeUsage(in: program.projectParsedFiles)
        try validatePrimaryDeclarations(in: program.parsedFiles)
        try validateTopLevelStates(in: program.parsedFiles)
    }

    public func validatePrimaryDeclarations(in program: CompiledProgram) throws {
        try validatePrimaryDeclarations(in: program.expandedFiles)
    }

    private func validatePrimaryDeclarations(in parsedFiles: [ParsedSourceFile]) throws {
        var firstDeclarationByName: [String: String] = [:]

        for parsedFile in parsedFiles {
            for declaration in declarations(in: parsedFile.sourceFile) {
                if let firstPath = firstDeclarationByName[declaration.name] {
                    throw SemanticValidationError(
                        "Duplicate primary declaration #\(declaration.name) in \(lastPathComponent(of: parsedFile.path)). First declared in \(lastPathComponent(of: firstPath)). Use extension \(declaration.name) to augment an existing declaration."
                    )
                }

                firstDeclarationByName[declaration.name] = parsedFile.path
            }
        }
    }

    private func validateTopLevelStates(in parsedFiles: [ParsedSourceFile]) throws {
        var firstStateByName: [String: String] = [:]

        for parsedFile in parsedFiles {
            for state in topLevelStates(in: parsedFile.sourceFile) {
                if let firstPath = firstStateByName[state.name] {
                    throw SemanticValidationError(
                        "Duplicate top-level state \(state.name) in \(lastPathComponent(of: parsedFile.path)). First declared in \(lastPathComponent(of: firstPath))."
                    )
                }

                firstStateByName[state.name] = parsedFile.path
            }
        }
    }

    private func validateCoreAttributeUsage(in parsedFiles: [ParsedSourceFile]) throws {
        for parsedFile in parsedFiles {
            for declaration in declarations(in: parsedFile.sourceFile) where declaration.isCore {
                throw SemanticValidationError(
                    "@core can only be used in NeatCore. Remove @core from \(declaration.name) in \(lastPathComponent(of: parsedFile.path))."
                )
            }
            for callable in callables(in: parsedFile.sourceFile) where callable.isCore {
                throw SemanticValidationError(
                    "@core can only be used in NeatCore. Remove @core from \(callable.name) in \(lastPathComponent(of: parsedFile.path))."
                )
            }
            for declaration in protocols(in: parsedFile.sourceFile) where declaration.isCore {
                throw SemanticValidationError(
                    "@core can only be used in NeatCore. Remove @core from \(declaration.name) in \(lastPathComponent(of: parsedFile.path))."
                )
            }
            for declaration in enumerations(in: parsedFile.sourceFile) where declaration.isCore {
                throw SemanticValidationError(
                    "@core can only be used in NeatCore. Remove @core from \(declaration.name) in \(lastPathComponent(of: parsedFile.path))."
                )
            }
        }
    }

    private func declarations(in sourceFile: SourceFileNode) -> [ConstructDeclaration] {
        switch sourceFile {
        case .construct(let declaration):
            return [declaration]
        case .module(let module):
            return module.constructs
        case .mainBlock, .extensions, .enumeration, .protocolDefinition, .macro:
            return []
        }
    }

    private func topLevelStates(in sourceFile: SourceFileNode) -> [StateDeclaration] {
        switch sourceFile {
        case .module(let module):
            return module.states
        case .construct, .mainBlock, .extensions, .enumeration, .protocolDefinition, .macro:
            return []
        }
    }

    private func callables(in sourceFile: SourceFileNode) -> [CallableDeclaration] {
        switch sourceFile {
        case .module(let module):
            return module.callables
        case .construct, .mainBlock, .extensions, .enumeration, .protocolDefinition, .macro:
            return []
        }
    }

    private func protocols(in sourceFile: SourceFileNode) -> [ProtocolDeclaration] {
        switch sourceFile {
        case .protocolDefinition(let declaration):
            return [declaration]
        case .module(let module):
            return module.protocols
        case .construct, .mainBlock, .extensions, .enumeration, .macro:
            return []
        }
    }

    private func enumerations(in sourceFile: SourceFileNode) -> [EnumDeclaration] {
        switch sourceFile {
        case .enumeration(let declaration):
            return [declaration]
        case .module(let module):
            return module.enumerations
        case .construct, .mainBlock, .extensions, .protocolDefinition, .macro:
            return []
        }
    }

    private func lastPathComponent(of path: String) -> String {
        URL(fileURLWithPath: path).lastPathComponent
    }
}
