import ArgumentParser
import Foundation
import NeatSyntax

enum ProjectSourceValidator {
    struct ParsedFile {
        let url: URL
        let sourceFile: SourceFileNode
    }

    static func parseSourceFile(
        at fileURL: URL,
        literalBridgeResolver: LiteralBridgeResolver? = nil
    ) throws -> SourceFileNode {
        let source = try String(contentsOf: fileURL, encoding: .utf8)
        do {
            var parser = try Parser(
                source: source,
                literalBridgeResolver: literalBridgeResolver ?? .empty
            )
            return try parser.parseSourceFile()
        } catch {
            throw ValidationError("Failed to parse \(fileURL.path): \(error)")
        }
    }

    static func expandedParsedFiles(
        for files: [URL],
        includeCore: Bool = true
    ) throws -> [ParsedFile] {
        let coreFiles = includeCore ? try NeatCoreLoader.parsedValidationFiles() : []
        let coreLiteralBridgeResolver =
            includeCore
            ? DeclarationGraph(
                files: coreFiles.map {
                    ParsedSourceFile(path: $0.url.path, sourceFile: $0.sourceFile)
                }
            ).literalBridgeResolver
            : nil
        let projectFiles = try files.map {
            ParsedFile(
                url: $0,
                sourceFile: try parseSourceFile(
                    at: $0,
                    literalBridgeResolver: coreLiteralBridgeResolver
                )
            )
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
        try validateLiteralBridgeCompatibility(in: parsedFiles)
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

    private static func validateLiteralBridgeCompatibility(in parsedFiles: [ParsedFile]) throws {
        let declarationGraph = DeclarationGraph(
            files: parsedFiles.map {
                ParsedSourceFile(path: $0.url.path, sourceFile: $0.sourceFile)
            }
        )
        let resolver = declarationGraph.literalBridgeResolver

        for parsedFile in parsedFiles {
            let fileName = parsedFile.url.lastPathComponent

            switch parsedFile.sourceFile {
            case .construct(let declaration):
                try validateLiteralBridgeCompatibility(
                    in: declaration,
                    resolver: resolver,
                    fileName: fileName
                )
            case .module(let module):
                try validateLiteralBridgeCompatibility(
                    in: module.states,
                    accessibleTypes: [:],
                    resolver: resolver,
                    fileName: fileName
                )

                let topLevelStateTypes = Dictionary(
                    uniqueKeysWithValues: module.states.map {
                        ($0.name, BootstrapLiteralType.typed($0.type))
                    }
                )

                for callable in module.callables {
                    try validateLiteralBridgeCompatibility(
                        in: callable,
                        accessibleTypes: topLevelStateTypes,
                        resolver: resolver,
                        fileName: fileName
                    )
                }

                for declaration in module.constructs {
                    try validateLiteralBridgeCompatibility(
                        in: declaration,
                        resolver: resolver,
                        fileName: fileName
                    )
                }
            case .mainBlock, .enumeration, .protocolDefinition, .macro, .extensions:
                break
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

    private static func validateLiteralBridgeCompatibility(
        in declaration: ConstructDeclaration,
        resolver: LiteralBridgeResolver,
        fileName: String
    ) throws {
        let environmentTypes = Dictionary(
            uniqueKeysWithValues: declaration.environments.map {
                ($0.name, BootstrapLiteralType.typed($0.type))
            }
        )

        try validateLiteralBridgeCompatibility(
            in: declaration.states,
            accessibleTypes: environmentTypes,
            resolver: resolver,
            fileName: fileName
        )

        let stateTypes = Dictionary(
            uniqueKeysWithValues: declaration.states.map {
                ($0.name, BootstrapLiteralType.typed($0.type))
            }
        )
        let accessibleTypes = stateTypes.merging(environmentTypes) { current, _ in current }

        for callable in declaration.callables {
            try validateLiteralBridgeCompatibility(
                in: callable,
                accessibleTypes: accessibleTypes,
                resolver: resolver,
                fileName: fileName
            )
        }
    }

    private static func validateLiteralBridgeCompatibility(
        in states: [StateDeclaration],
        accessibleTypes initialAccessibleTypes: [String: BootstrapLiteralType],
        resolver: LiteralBridgeResolver,
        fileName: String
    ) throws {
        var accessibleTypes = initialAccessibleTypes

        for state in states {
            if state.hasExplicitTypeAnnotation,
                case .stored(let expression) = state.storage,
                let inferred = try? BootstrapExpressionSemantics.inferType(
                    of: expression,
                    accessibleTypes: accessibleTypes,
                    resolver: resolver
                ),
                inferred.isLiteralLike,
                !BootstrapExpressionSemantics.isCompatible(
                    actual: inferred,
                    expected: state.type,
                    resolver: resolver
                )
            {
                throw ValidationError(
                    "state '\(state.name)' in \(fileName) expects \(state.type.displayName), got \(inferred.displayName)."
                )
            }

            accessibleTypes[state.name] = .typed(state.type)
        }
    }

    private static func validateLiteralBridgeCompatibility(
        in callable: CallableDeclaration,
        accessibleTypes: [String: BootstrapLiteralType],
        resolver: LiteralBridgeResolver,
        fileName: String
    ) throws {
        guard let explicitReturnType = callable.returnType,
            explicitReturnType.displayName != "Void",
            let body = callable.body
        else {
            return
        }

        let parameterTypes: [String: BootstrapLiteralType] = Dictionary(
            uniqueKeysWithValues: callable.parameters.compactMap { parameter in
                guard let typeReference = parameter.typeReference else {
                    return nil
                }
                return (parameter.localName, BootstrapLiteralType.typed(typeReference))
            }
        )
        let visibleTypes = accessibleTypes.merging(parameterTypes) { current, _ in current }

        for expression in collectReturnExpressions(in: body).compactMap({ $0 }) {
            guard
                let inferred = try? BootstrapExpressionSemantics.inferType(
                    of: expression,
                    accessibleTypes: visibleTypes,
                    resolver: resolver
                ),
                inferred.isLiteralLike
            else {
                continue
            }

            guard
                BootstrapExpressionSemantics.isCompatible(
                    actual: inferred,
                    expected: explicitReturnType,
                    resolver: resolver
                )
            else {
                throw ValidationError(
                    "Callable \(callable.name) in \(fileName) expects return type \(explicitReturnType.displayName), got \(inferred.displayName)."
                )
            }
        }
    }

    private static func collectReturnExpressions(in statements: [Statement]) -> [NeatSyntax
        .Expression?]
    {
        var expressions: [NeatSyntax.Expression?] = []

        for statement in statements {
            switch statement {
            case .freestandingMacro(_, _, let body):
                expressions.append(contentsOf: collectReturnExpressions(in: body))
            case .return(let expression):
                expressions.append(expression)
            case .forEach(_, _, let body):
                expressions.append(contentsOf: collectReturnExpressions(in: body))
            case .whileLoop(_, let body):
                expressions.append(contentsOf: collectReturnExpressions(in: body))
            case .conditional(let branches):
                for branch in branches {
                    expressions.append(contentsOf: collectReturnExpressions(in: branch.body))
                }
            case .switchStatement(_, let cases, let defaultBody):
                for switchCase in cases {
                    expressions.append(contentsOf: collectReturnExpressions(in: switchCase.body))
                }
                if let defaultBody {
                    expressions.append(contentsOf: collectReturnExpressions(in: defaultBody))
                }
            case .declaration, .derived, .environmentProvision, .assignment, .compoundAssignment,
                .expression, .break, .continue:
                continue
            }
        }

        return expressions
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
