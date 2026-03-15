import ArgumentParser
import Foundation
import NeatSyntax

enum ProjectSourceValidator {
    struct ParsedFile {
        let url: URL
        let sourceFile: SourceFileNode
    }

    static func parseSourceFile(at fileURL: URL) throws -> SourceFileNode {
        let source = try String(contentsOf: fileURL, encoding: .utf8)
        var parser = try Parser(source: source)
        return try parser.parseSourceFile()
    }

    static func validateFiles(_ files: [URL]) throws {
        let parsedFiles = try files.map {
            ParsedFile(url: $0, sourceFile: try parseSourceFile(at: $0))
        }
        try validatePrimaryDeclarations(in: parsedFiles)
        try validateTopLevelStates(in: parsedFiles)
        try validateEnvironmentStateResolution(in: parsedFiles)
    }

    static func validatePrimaryDeclarations(in files: [URL]) throws {
        let parsedFiles = try files.map {
            ParsedFile(url: $0, sourceFile: try parseSourceFile(at: $0))
        }
        try validatePrimaryDeclarations(in: parsedFiles)
    }

    private static func validatePrimaryDeclarations(in parsedFiles: [ParsedFile]) throws {
        var firstDeclarationByName: [String: URL] = [:]

        for parsedFile in parsedFiles {
            for declaration in declarations(in: parsedFile.sourceFile) {
                if let firstFile = firstDeclarationByName[declaration.name] {
                    throw ValidationError(
                        "Duplicate primary declaration #\(declaration.name) in \(parsedFile.url.lastPathComponent). First declared in \(firstFile.lastPathComponent). Use extension \(declaration.name) to augment an existing declaration."
                    )
                }

                firstDeclarationByName[declaration.name] = parsedFile.url
            }
        }
    }

    private static func validateTopLevelStates(in parsedFiles: [ParsedFile]) throws {
        var firstStateByName: [String: URL] = [:]

        for parsedFile in parsedFiles {
            for state in topLevelStates(in: parsedFile.sourceFile) {
                if let firstFile = firstStateByName[state.name] {
                    throw ValidationError(
                        "Duplicate top-level state \(state.name) in \(parsedFile.url.lastPathComponent). First declared in \(firstFile.lastPathComponent)."
                    )
                }

                firstStateByName[state.name] = parsedFile.url
            }
        }
    }

    private static func validateEnvironmentStateResolution(in parsedFiles: [ParsedFile]) throws {
        let topLevelStateNames = Set(
            parsedFiles.flatMap { parsedFile in
                topLevelStates(in: parsedFile.sourceFile).map(\.name)
            }
        )

        for parsedFile in parsedFiles {
            for declaration in declarations(in: parsedFile.sourceFile) {
                let localStateNames = Set(declaration.states.map(\.name))

                for environment in declaration.environments where environment.isState {
                    if localStateNames.contains(environment.name) {
                        continue
                    }

                    guard topLevelStateNames.contains(environment.name) else {
                        throw ValidationError(
                            "environment state \(environment.name): \(environment.typeName) in \(parsedFile.url.lastPathComponent) could not be resolved from lexical outer scope."
                        )
                    }
                }
            }
        }
    }

    private static func declarations(in sourceFile: SourceFileNode) -> [DeclarationNode] {
        switch sourceFile {
        case .declaration(let declaration):
            return [declaration]
        case .module(let module):
            return module.declarations
        case .mainBlock, .extensions:
            return []
        }
    }

    private static func topLevelStates(in sourceFile: SourceFileNode) -> [StateDeclaration] {
        switch sourceFile {
        case .module(let module):
            return module.states
        case .declaration, .mainBlock, .extensions:
            return []
        }
    }
}
