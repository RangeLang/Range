import Foundation

extension Parser {
    mutating func parseDerivedDeclaration() throws -> DerivedDeclaration {
        let builderName = try parseBuilderDirectiveIfPresent()
        try consumeKeyword(.derived)
        let name = try consumeIdentifier()
        try consume(.colon)
        let typeName = try consumeTypeReference()
        let body = peek() == .leftBrace ? try parseStatementBlock(baseLocalBindings: [:]) : nil
        return DerivedDeclaration(
            builderName: builderName,
            name: name,
            typeName: typeName,
            body: body
        )
    }

    func validateDerivedDeclarations(_ deriveds: [DerivedDeclaration]) throws {
        for derived in deriveds {
            guard let body = derived.body else { continue }

            if derived.builderName != nil {
                continue
            }

            if derived.isVariadic {
                for statement in body {
                    guard case .expression = statement else {
                        throw ParseError(
                            "Variadic derived \(derived.name): \(derived.typeName) can only contain top-level expression statements."
                        )
                    }
                }
                continue
            }

            let topLevelExpressions = body.compactMap { statement -> Expression? in
                guard case .expression(let expression) = statement else { return nil }
                return expression
            }

            if topLevelExpressions.count > 1 && topLevelExpressions.count == body.count {
                throw ParseError(
                    "Derived \(derived.name): \(derived.typeName) must produce a single value. Use \(derived.typeName)... if you want to collect multiple sibling expressions."
                )
            }
        }
    }

    func validateBuilderDeclarations(in declarations: [ConstructDeclaration]) throws {
        let declarationsByName = Dictionary(
            uniqueKeysWithValues: declarations.map { ($0.name, $0) })

        for declaration in declarations {
            for derived in declaration.deriveds {
                guard let builderName = derived.builderName else { continue }
                guard let builder = declarationsByName[builderName] else {
                    throw ParseError(
                        "Derived \(derived.name): \(derived.typeName) references unknown builder \(builderName)."
                    )
                }
                guard builder.kind == .builder else {
                    throw ParseError(
                        "Derived \(derived.name): \(derived.typeName) references \(builderName), but it is not declared as a builder."
                    )
                }

                let availableHooks = Set(builder.callables.map(\.name))
                let requiredHooks = requiredBuilderHooks(for: derived)

                let missingHooks = requiredHooks.subtracting(availableHooks).sorted()
                if !missingHooks.isEmpty {
                    throw ParseError(
                        "Builder \(builderName) is missing required hook functions for derived \(derived.name): \(missingHooks.joined(separator: ", "))."
                    )
                }
            }
        }
    }

    func requiredBuilderHooks(for derived: DerivedDeclaration) -> Set<String> {
        guard let body = derived.body else {
            return []
        }

        var hooks: Set<String> = ["buildExpression", "buildBlock"]
        collectBuilderHooks(from: body, into: &hooks)
        return hooks
    }

    func collectBuilderHooks(from statements: [Statement], into hooks: inout Set<String>) {
        for statement in statements {
            switch statement {
            case .expression:
                continue
            case .declaration:
                continue
            case .assignment, .compoundAssignment:
                continue
            case .environmentProvision:
                continue
            case .return, .break, .continue:
                continue
            case .forEach(_, _, let body):
                hooks.insert("buildArray")
                collectBuilderHooks(from: body, into: &hooks)
            case .whileLoop(_, let body):
                hooks.insert("buildArray")
                collectBuilderHooks(from: body, into: &hooks)
            case .conditional(let branches):
                if branches.contains(where: { $0.condition == nil }) {
                    hooks.insert("buildEither")
                } else {
                    hooks.insert("buildOptional")
                }

                for branch in branches {
                    collectBuilderHooks(from: branch.body, into: &hooks)
                }
            case .switchStatement(_, let cases, let defaultBody):
                hooks.insert("buildEither")
                for `case` in cases {
                    collectBuilderHooks(from: `case`.body, into: &hooks)
                }
                if let defaultBody {
                    collectBuilderHooks(from: defaultBody, into: &hooks)
                }
            }
        }
    }

    func isBuilderDirectiveStart() -> Bool {
        guard peek() == .asterisk else { return false }

        switch peek(offset: 1) {
        case .identifier(let name), .keyword(let name):
            guard name != "environment", name != "builder" else { return false }
        default:
            return false
        }
        return true
    }

    mutating func parseBuilderDirectiveIfPresent() throws -> String? {
        guard isBuilderDirectiveStart() else {
            return nil
        }

        try consume(.asterisk)
        switch peek() {
        case .identifier(let name), .keyword(let name):
            advance()
            return name
        default:
            throw ParseError("Expected *BuilderName directive.")
        }
    }

    func isDerivedDeclarationStart() -> Bool {
        if isBuilderDirectiveStart() {
            return true
        }
        guard peek() == .keyword(NeatSyntax.Keyword.derived.rawValue) else {
            return false
        }
        guard case .identifier = peek(offset: 1) else { return false }
        return peek(offset: 2) == .colon
    }
}
