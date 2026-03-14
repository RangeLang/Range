import ArgumentParser
import Foundation
import NeatSyntax

enum ProjectSourceValidator {
    static func parseSourceFile(at fileURL: URL) throws -> SourceFileNode {
        let source = try String(contentsOf: fileURL, encoding: .utf8)
        var parser = try Parser(source: source)
        return try parser.parseSourceFile()
    }

    static func validatePrimaryDeclarations(in files: [URL]) throws {
        var firstDeclarationByName: [String: URL] = [:]

        for fileURL in files {
            let sourceFile = try parseSourceFile(at: fileURL)
            guard case .declaration(let declaration) = sourceFile else {
                continue
            }

            if let firstFile = firstDeclarationByName[declaration.name] {
                throw ValidationError(
                    "Duplicate primary declaration #\(declaration.name) in \(fileURL.lastPathComponent). First declared in \(firstFile.lastPathComponent). Use extension \(declaration.name) to augment an existing declaration."
                )
            }

            firstDeclarationByName[declaration.name] = fileURL
        }
    }
}
