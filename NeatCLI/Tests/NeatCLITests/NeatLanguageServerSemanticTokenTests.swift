import Foundation
@testable import NeatCLI
import Testing

@Suite("Neat LSP semantic tokens")
struct NeatLanguageServerSemanticTokenTests {
    @Test("Type declarations and usages are split semantically")
    func typeDeclarationsAndUsagesSplit() {
        let source = """
        construct Something {
            value number: Int
        }

        @main {
            value item = Something()
        }
        """

        let tokens = NeatLanguageServer.debugSemanticTokenSnapshots(in: source)

        #expect(containsToken(tokens, text: "Something", type: .type, modifiers: [.declaration]))
        #expect(containsToken(tokens, text: "Int", type: .type, modifiers: [.defaultLibrary]))
        #expect(containsToken(tokens, text: "Something", type: .type, modifiers: [.application]))
    }

    @Test("Functions, variables, parameters, and member semantics are emitted")
    func declarationsAndMembersEmitSemanticTokens() {
        let source = """
        function identity(value _: Int) -> Int {
            value number: Int = 0
            Logger.info(number)
            return value
        }

        function fetchUsername(id _: Int) -> String {
            return ""
        }

        function refreshUser(id _: Int) {
            value username = fetchUsername(id: id)
            Logger.info(username)
        }

        macro arrayifyParameter(): Parameter { target, diagnostics in
            target.declaration.type.rewrite(
                ArrayTypeReference(
                    element: target.declaration.type
                )
            )
        }
        """

        let tokens = NeatLanguageServer.debugSemanticTokenSnapshots(in: source)

        #expect(containsToken(tokens, text: "identity", type: .function, modifiers: [.declaration]))
        #expect(containsToken(tokens, text: "value", type: .parameter, modifiers: [.declaration]))
        #expect(containsToken(tokens, text: "number", type: .variable, modifiers: [.declaration]))
        #expect(containsToken(tokens, text: "number", type: .variable, modifiers: [.argument]))
        #expect(containsExactToken(tokens, text: "value", type: .parameter, modifiers: []))
        #expect(containsToken(tokens, text: "id", type: .parameter, modifiers: [.argument]))
        #expect(containsToken(tokens, text: "username", type: .variable, modifiers: [.argument]))
        #expect(containsToken(tokens, text: "arrayifyParameter", type: .macro, modifiers: [.declaration]))
        #expect(containsToken(tokens, text: "declaration", type: .property, modifiers: []))
        #expect(containsToken(tokens, text: "rewrite", type: .method, modifiers: []))
    }

    @Test("Macro applications, including parameter macros, emit semantic tokens")
    func macroApplicationsEmitSemanticTokens() {
        let source = """
        function takeMany(#variadic values: Int) -> [Int] {
            return values
        }

        @main {
            value text = #stringify(1 + 2)
        }
        """

        let tokens = NeatLanguageServer.debugSemanticTokenSnapshots(in: source)

        #expect(containsToken(tokens, text: "variadic", type: .macro, modifiers: [.defaultLibrary]))
        #expect(containsToken(tokens, text: "stringify", type: .macro, modifiers: [.defaultLibrary]))
    }
}

private func containsToken(
    _ tokens: [SemanticTokenSnapshot],
    text: String,
    type: SemanticTokenType,
    modifiers: Set<SemanticTokenModifier>
) -> Bool {
    tokens.contains(where: {
        $0.text == text && $0.type == type && modifiers.isSubset(of: $0.modifiers)
    })
}

private func containsExactToken(
    _ tokens: [SemanticTokenSnapshot],
    text: String,
    type: SemanticTokenType,
    modifiers: Set<SemanticTokenModifier>
) -> Bool {
    tokens.contains(where: {
        $0.text == text && $0.type == type && $0.modifiers == modifiers
    })
}
