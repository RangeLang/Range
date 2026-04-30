import Foundation

extension ApplicationGraphValidator {
    func validateControlFlow(in parsedFiles: [ParsedSourceFile]) throws {
        for parsedFile in parsedFiles {
            let fileName = lastPathComponent(of: parsedFile.path)

            switch parsedFile.sourceFile {
            case .construct(let declaration):
                try validateControlFlow(in: declaration, fileName: fileName)
            case .namespace(let declaration):
                try validateControlFlow(in: declaration, fileName: fileName)
            case .module(let module):
                if let mainBlock = module.mainBlock {
                    try validateControlFlow(
                        in: mainBlock.body,
                        context: .root,
                        fileName: fileName
                    )
                }

                for callable in module.callables {
                    guard let body = callable.body else {
                        continue
                    }

                    try validateControlFlow(
                        in: body,
                        context: .root,
                        fileName: fileName
                    )
                }

                for declaration in module.constructs {
                    try validateControlFlow(in: declaration, fileName: fileName)
                }
                for declaration in module.namespaces {
                    try validateControlFlow(in: declaration, fileName: fileName)
                }
            case .mainBlock(let mainBlock):
                try validateControlFlow(
                    in: mainBlock.body,
                    context: .root,
                    fileName: fileName
                )
            case .enumeration, .protocolDefinition, .macro, .marker, .extensions:
                break
            }
        }
    }

    func validateControlFlow(
        in declaration: NamespaceDeclaration,
        fileName: String
    ) throws {
        for callable in declaration.callables {
            guard let body = callable.body else { continue }
            try validateControlFlow(
                in: body,
                context: .root,
                fileName: fileName
            )
        }

        for nestedDeclaration in declaration.constructs {
            try validateControlFlow(in: nestedDeclaration, fileName: fileName)
        }
        for nestedNamespace in declaration.namespaces {
            try validateControlFlow(in: nestedNamespace, fileName: fileName)
        }
    }

    func validateControlFlow(
        in declaration: ConstructDeclaration,
        fileName: String
    ) throws {
        for derived in declaration.deriveds {
            guard let body = derived.body else {
                continue
            }

            try validateControlFlow(
                in: body,
                context: .root,
                fileName: fileName
            )
        }

        for initializer in declaration.initializers {
            guard let body = initializer.body else {
                continue
            }

            try validateControlFlow(
                in: body,
                context: .root,
                fileName: fileName
            )
        }

        for callable in declaration.callables {
            guard let body = callable.body else {
                continue
            }

            try validateControlFlow(
                in: body,
                context: .root,
                fileName: fileName
            )
        }

        for nestedDeclaration in declaration.constructs {
            try validateControlFlow(in: nestedDeclaration, fileName: fileName)
        }
    }

    func validateControlFlow(
        in statements: [Statement],
        context: ControlFlowContext,
        fileName: String
    ) throws {
        for statement in statements {
            switch statement {
            case .expand:
                continue
            case .macroInvocation(_, _, let body):
                try validateControlFlow(
                    in: body,
                    context: context,
                    fileName: fileName
                )
            case .background(let background):
                try validateControlFlow(
                    in: background.body,
                    context: context.enteringBackground(),
                    fileName: fileName
                )
            case .deferBlock(let deferred):
                try validateControlFlow(
                    in: deferred.body,
                    context: context,
                    fileName: fileName
                )
            case .localCallable(let declaration):
                try validateControlFlow(
                    in: declaration.body,
                    context: .root,
                    fileName: fileName
                )
            case .derived(_, _, let body):
                try validateControlFlow(
                    in: body,
                    context: context,
                    fileName: fileName
                )
            case .forEach(_, _, let body):
                try validateControlFlow(
                    in: body,
                    context: context.enteringLoop(),
                    fileName: fileName
                )
            case .whileLoop(_, let body):
                try validateControlFlow(
                    in: body,
                    context: context.enteringLoop(),
                    fileName: fileName
                )
            case .conditional(let branches):
                for branch in branches {
                    try validateControlFlow(
                        in: branch.body,
                        context: context,
                        fileName: fileName
                    )
                }
            case .switchStatement(_, let cases, let defaultBody):
                let switchContext = context.enteringSwitch()

                for switchCase in cases {
                    try validateControlFlow(
                        in: switchCase.body,
                        context: switchContext,
                        fileName: fileName
                    )
                }

                if let defaultBody {
                    try validateControlFlow(
                        in: defaultBody,
                        context: switchContext,
                        fileName: fileName
                    )
                }
            case .return(let expression):
                if context.insideAnonymousBackground, expression != nil {
                    throw SemanticValidationError(
                        "Anonymous @background block in \(fileName) cannot return a value. Use bare return to exit early."
                    )
                }
            case .break:
                guard context.loopDepth > 0 || context.switchDepth > 0 else {
                    throw SemanticValidationError(
                        "'break' in \(fileName) can only be used inside a loop or switch."
                    )
                }
            case .continue:
                guard context.loopDepth > 0 else {
                    throw SemanticValidationError(
                        "'continue' in \(fileName) can only be used inside a loop."
                    )
                }
            case .localBinding, .environmentProvision, .assignment, .compoundAssignment,
                .expression:
                continue
            }
        }
    }
}
