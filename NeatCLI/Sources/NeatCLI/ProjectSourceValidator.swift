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

    static func expandedParsedFiles(
        for files: [URL],
        includeCore: Bool = true
    ) throws -> [ParsedFile] {
        let coreFiles = includeCore ? try NeatCoreLoader.parsedValidationFiles() : []
        let projectFiles = try files.map {
            ParsedFile(url: $0, sourceFile: try parseSourceFile(at: $0))
        }
        return try expandParsedFiles(coreFiles + projectFiles)
    }

    static func expandedParsedFile(at fileURL: URL) throws -> ParsedFile {
        let files = try expandedParsedFiles(for: [fileURL], includeCore: true)
        guard
            let match = files.first(where: {
                $0.url.standardizedFileURL == fileURL.standardizedFileURL
            })
        else {
            throw ValidationError("Failed to expand \(fileURL.lastPathComponent).")
        }
        return match
    }

    static func expandParsedFiles(_ parsedFiles: [ParsedFile]) throws -> [ParsedFile] {
        let expanded = try MacroExpander.expand(
            files: parsedFiles.map {
                ParsedSourceFile(path: $0.url.path, sourceFile: $0.sourceFile)
            }
        )
        let expandedByPath = Dictionary(
            uniqueKeysWithValues: expanded.map { ($0.path, $0.sourceFile) })
        return try parsedFiles.map { parsedFile in
            guard let sourceFile = expandedByPath[parsedFile.url.path] else {
                throw ValidationError("Failed to expand \(parsedFile.url.lastPathComponent).")
            }
            return ParsedFile(url: parsedFile.url, sourceFile: sourceFile)
        }
    }

    static func validateFiles(_ files: [URL]) throws {
        let parsedFiles = try expandedParsedFiles(for: files)
        try validatePrimaryDeclarations(in: parsedFiles)
        try validateTopLevelStates(in: parsedFiles)
        try validateEnvironmentStateResolution(in: parsedFiles)
        try validateValueBindings(in: parsedFiles)
    }

    static func validatePrimaryDeclarations(in files: [URL]) throws {
        let parsedFiles = try expandedParsedFiles(for: files)
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

    private static func declarations(in sourceFile: SourceFileNode) -> [ConstructDeclaration] {
        switch sourceFile {
        case .construct(let declaration):
            return [declaration]
        case .module(let module):
            return module.constructs
        case .mainBlock, .extensions, .enumeration, .protocolDefinition, .macro:
            return []
        }
    }

    private static func topLevelStates(in sourceFile: SourceFileNode) -> [StateDeclaration] {
        switch sourceFile {
        case .module(let module):
            return module.states
        case .construct, .mainBlock, .extensions, .enumeration, .protocolDefinition, .macro:
            return []
        }
    }

    private static func validateValueBindings(in parsedFiles: [ParsedFile]) throws {
        let bindingConstructNames = Set(
            parsedFiles
                .flatMap { declarations(in: $0.sourceFile) }
                .filter { !$0.bindings.isEmpty }
                .map(\.name)
        )

        guard !bindingConstructNames.isEmpty else { return }

        for parsedFile in parsedFiles {
            let fileName = parsedFile.url.lastPathComponent

            switch parsedFile.sourceFile {
            case .construct(let declaration):
                try validateValueBindings(
                    in: declaration,
                    bindingConstructNames: bindingConstructNames,
                    fileName: fileName
                )
            case .module(let module):
                for declaration in module.constructs {
                    try validateValueBindings(
                        in: declaration,
                        bindingConstructNames: bindingConstructNames,
                        fileName: fileName
                    )
                }
                if let mainBlock = module.mainBlock {
                    try validateValueDeclarations(
                        in: mainBlock.body,
                        bindingConstructNames: bindingConstructNames,
                        fileName: fileName
                    )
                }
                for callable in module.callables {
                    if let body = callable.body {
                        try validateValueDeclarations(
                            in: body,
                            bindingConstructNames: bindingConstructNames,
                            fileName: fileName
                        )
                    }
                }
            case .mainBlock(let mainBlock):
                try validateValueDeclarations(
                    in: mainBlock.body,
                    bindingConstructNames: bindingConstructNames,
                    fileName: fileName
                )
            case .enumeration, .protocolDefinition, .macro, .extensions:
                break
            }
        }
    }

    private static func validateValueBindings(
        in declaration: ConstructDeclaration,
        bindingConstructNames: Set<String>,
        fileName: String
    ) throws {
        for value in declaration.values {
            if let constructName = normalizedTypeName(value.typeName),
                bindingConstructNames.contains(constructName)
            {
                throw ValidationError(
                    "value \(value.name): \(constructName) in construct \(declaration.name) (\(fileName)) is not allowed because \(constructName) declares binding members. Use state or a snapshot construct."
                )
            }
        }

        for derived in declaration.deriveds {
            if let body = derived.body {
                try validateValueDeclarations(
                    in: body,
                    bindingConstructNames: bindingConstructNames,
                    fileName: fileName
                )
            }
        }

        for initializer in declaration.initializers {
            if let body = initializer.body {
                try validateValueDeclarations(
                    in: body,
                    bindingConstructNames: bindingConstructNames,
                    fileName: fileName
                )
            }
        }

        for callable in declaration.callables {
            if let body = callable.body {
                try validateValueDeclarations(
                    in: body,
                    bindingConstructNames: bindingConstructNames,
                    fileName: fileName
                )
            }
        }
    }

    private static func validateValueDeclarations(
        in statements: [Statement],
        bindingConstructNames: Set<String>,
        fileName: String
    ) throws {
        for statement in statements {
            switch statement {
            case .freestandingMacro(_, _, let body):
                try validateValueDeclarations(
                    in: body,
                    bindingConstructNames: bindingConstructNames,
                    fileName: fileName
                )
            case .declaration(let kind, let name, let typeName, let expression):
                guard kind == .constant else { continue }
                let explicitType = typeName.flatMap(normalizedTypeName)
                let inferredType = inferredConstructName(from: expression)
                let constructName = explicitType ?? inferredType
                if let constructName, bindingConstructNames.contains(constructName) {
                    throw ValidationError(
                        "value \(name): \(constructName) in \(fileName) is not allowed because \(constructName) declares binding members. Use state or a snapshot construct."
                    )
                }
            case .derived(_, _, let body):
                try validateValueDeclarations(
                    in: body,
                    bindingConstructNames: bindingConstructNames,
                    fileName: fileName
                )
            case .forEach(_, _, let body):
                try validateValueDeclarations(
                    in: body,
                    bindingConstructNames: bindingConstructNames,
                    fileName: fileName
                )
            case .whileLoop(_, let body):
                try validateValueDeclarations(
                    in: body,
                    bindingConstructNames: bindingConstructNames,
                    fileName: fileName
                )
            case .conditional(let branches):
                for branch in branches {
                    try validateValueDeclarations(
                        in: branch.body,
                        bindingConstructNames: bindingConstructNames,
                        fileName: fileName
                    )
                }
            case .switchStatement(_, let cases, let defaultBody):
                for switchCase in cases {
                    try validateValueDeclarations(
                        in: switchCase.body,
                        bindingConstructNames: bindingConstructNames,
                        fileName: fileName
                    )
                }
                if let defaultBody {
                    try validateValueDeclarations(
                        in: defaultBody,
                        bindingConstructNames: bindingConstructNames,
                        fileName: fileName
                    )
                }
            case .environmentProvision, .assignment, .compoundAssignment, .expression, .return,
                .break, .continue:
                continue
            }
        }
    }

    private static func inferredConstructName(from expression: NeatSyntax.Expression) -> String? {
        guard case .call(let name, _) = expression else { return nil }
        return normalizedTypeName(name)
    }

    private static func normalizedTypeName(_ raw: String) -> String? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        while text.hasSuffix("?") {
            text.removeLast()
        }
        if text.hasSuffix("...") {
            text.removeLast(3)
        }

        if let genericStart = text.firstIndex(of: "<") {
            text = String(text[..<genericStart])
        }

        if text.hasPrefix("[") || text.hasPrefix("(") {
            return nil
        }

        if let lastDot = text.lastIndex(of: ".") {
            text = String(text[text.index(after: lastDot)...])
        }

        return text.isEmpty ? nil : text
    }
}
