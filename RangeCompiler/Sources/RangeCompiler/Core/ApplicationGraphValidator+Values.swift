import Foundation

extension ApplicationGraphValidator {
    func validateValueBindings(
        in parsedFiles: [ParsedSourceFile],
        declarationGraph: DeclarationGraph
    ) throws {
        let bindingConstructNames = Set(
            parsedFiles
                .flatMap { declarations(in: $0.sourceFile) }
                .filter {
                    declarationGraph.bindings(onConstruct: $0.name).contains(where: {
                        !isMetadataBinding($0)
                    })
                }
                .map(\.name)
        )

        guard !bindingConstructNames.isEmpty else { return }

        for parsedFile in parsedFiles {
            let fileName = lastPathComponent(of: parsedFile.path)

            switch parsedFile.sourceFile {
            case .construct:
                break
            case .module(let module):
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
            case .enumeration, .macro, .extensions:
                break
            }
        }
    }
    func validateValueBindings(
        in declaration: ConstructDeclaration,
        declarationGraph: DeclarationGraph,
        bindingConstructNames: Set<String>,
        fileName: String
    ) throws {
        for value in declarationGraph.values(onConstruct: declaration.name) {
            if let constructName = normalizedTypeName(value.typeName),
                bindingConstructNames.contains(constructName)
            {
                throw SemanticValidationError(
                    "let \(value.name): \(constructName) in construct \(declaration.name) (\(fileName)) is not allowed because \(constructName) declares binding members. Use state or a snapshot construct."
                )
            }
        }

        for derived in declarationGraph.deriveds(onConstruct: declaration.name) {
            if let body = derived.body {
                try validateValueDeclarations(
                    in: body,
                    bindingConstructNames: bindingConstructNames,
                    fileName: fileName
                )
            }
        }

        for initializer in declarationGraph.initializers(onConstruct: declaration.name) {
            if let body = initializer.body {
                try validateValueDeclarations(
                    in: body,
                    bindingConstructNames: bindingConstructNames,
                    fileName: fileName
                )
            }
        }

        for callable in declarationGraph.callables(onConstruct: declaration.name) {
            if let body = callable.body {
                try validateValueDeclarations(
                    in: body,
                    bindingConstructNames: bindingConstructNames,
                    fileName: fileName
                )
            }
        }
    }

    func validateValueDeclarations(
        in statements: [Statement],
        bindingConstructNames: Set<String>,
        fileName: String
    ) throws {
        for statement in statements {
            switch statement {
            case .macroApplication, .expand, .replace:
                continue
            case .macroInvocation(_, _, let body):
                try validateValueDeclarations(
                    in: body,
                    bindingConstructNames: bindingConstructNames,
                    fileName: fileName
                )
            case .localBinding(let declaration):
                guard declaration.kind == .constant else { continue }
                let explicitType = normalizedTypeName(declaration.type.displayName)
                let inferredType = inferredConstructName(from: declaration.expression)
                let constructName = explicitType ?? inferredType
                if let constructName, bindingConstructNames.contains(constructName) {
                    throw SemanticValidationError(
                        "let \(declaration.name): \(constructName) in \(fileName) is not allowed because \(constructName) declares binding members. Use state or a snapshot construct."
                    )
                }
            case .derived(_, _, let body):
                try validateValueDeclarations(
                    in: body,
                    bindingConstructNames: bindingConstructNames,
                    fileName: fileName
                )
            case .localCallable(let declaration):
                try validateValueDeclarations(
                    in: declaration.body,
                    bindingConstructNames: bindingConstructNames,
                    fileName: fileName
                )
            case .background(let background):
                try validateValueDeclarations(
                    in: background.body,
                    bindingConstructNames: bindingConstructNames,
                    fileName: fileName
                )
            case .deferBlock(let deferred):
                try validateValueDeclarations(
                    in: deferred.body,
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
            case .assignment, .compoundAssignment, .expression, .return,
                .break, .continue:
                continue
            }
        }
    }

    func inferredConstructName(from expression: Expression) -> String? {
        guard case .call(let name, _) = expression else { return nil }
        return normalizedTypeName(name)
    }

    func normalizedTypeName(_ raw: String) -> String? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        if text.hasSuffix("...") {
            text.removeLast(3)
        }

        if let genericStart = text.firstIndex(of: "<") {
            text = String(text[..<genericStart])
        }

        if text.hasPrefix("(") {
            return nil
        }

        if let lastDot = text.lastIndex(of: ".") {
            text = String(text[text.index(after: lastDot)...])
        }

        return text.isEmpty ? nil : text
    }
}

private func isMetadataBinding(_ binding: BindingDeclaration) -> Bool {
    binding.typeName.contains("@")
}
