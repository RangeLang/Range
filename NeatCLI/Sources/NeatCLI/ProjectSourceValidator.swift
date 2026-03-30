import ArgumentParser
import Foundation
import NeatSyntax

enum ProjectSourceValidator {
    struct ParsedFile {
        let url: URL
        let sourceFile: SourceFileNode
    }

    static func semanticProgram(
        for files: [URL],
        includeCore: Bool = true
    ) throws -> SemanticProgram {
        try CompilerPipeline().build(inputs: sourceInputs(for: files, includeCore: includeCore))
    }

    static func validatedSemanticProgram(
        for files: [URL],
        includeCore: Bool = true
    ) throws -> SemanticProgram {
        let program = try semanticProgram(for: files, includeCore: includeCore)
        try SemanticProgramValidator().validate(program)
        return program
    }

    static func expandedParsedFiles(
        for files: [URL],
        includeCore: Bool = true
    ) throws -> [ParsedFile] {
        let program = try semanticProgram(for: files, includeCore: includeCore)
        return parsedFiles(from: program.expandedFiles)
    }

    static func expandedParsedFile(at fileURL: URL) throws -> ParsedFile {
        let program = try semanticProgram(for: [fileURL], includeCore: true)
        guard
            let match = parsedFiles(from: program.projectExpandedFiles).first(where: {
                $0.url.standardizedFileURL == fileURL.standardizedFileURL
            })
        else {
            throw ValidationError("Failed to expand \(fileURL.lastPathComponent).")
        }
        return match
    }

    static func validateFiles(_ files: [URL]) throws {
        _ = try validatedSemanticProgram(for: files)
    }

    static func validatePrimaryDeclarations(in files: [URL]) throws {
        let program = try semanticProgram(for: files)
        try SemanticProgramValidator().validatePrimaryDeclarations(in: program)
    }

    private static func sourceInputs(
        for files: [URL],
        includeCore: Bool
    ) throws -> [SourceInput] {
        let coreInputs = includeCore ? try NeatCoreLoader.sourceInputs() : []
        let projectInputs = try files.map { fileURL in
            do {
                return SourceInput(
                    path: fileURL.path,
                    source: try String(contentsOf: fileURL, encoding: .utf8),
                    role: .project
                )
            } catch {
                throw ValidationError("Failed to read \(fileURL.path): \(error)")
            }
        }
        return coreInputs + projectInputs
    }

    private static func parsedFiles(from files: [ParsedSourceFile]) -> [ParsedFile] {
        files.map { ParsedFile(url: URL(fileURLWithPath: $0.path), sourceFile: $0.sourceFile) }
    }
}
