import Foundation
@testable import NeatCLI
import Testing

@Suite("Neat LSP semantic tokens")
struct NeatLanguageServerSemanticTokenTests {
    @Test("Type declarations and usages are split semantically")
    func typeDeclarationsAndUsagesSplit() {
        let source = """
        construct Something {
            let number: Int
        }

        @main {
            let item = Something()
        }
        """

        let tokens = NeatLanguageServer.debugSemanticTokenSnapshots(in: source)

        #expect(containsExactToken(tokens, text: "@main", type: .keyword, modifiers: []))
        #expect(containsToken(tokens, text: "Something", type: .type, modifiers: [.declaration]))
        #expect(containsToken(tokens, text: "Int", type: .type, modifiers: []))
        #expect(containsExactToken(tokens, text: "Something", type: .type, modifiers: []))
    }

    @Test("Functions, variables, parameters, and member semantics are emitted")
    func declarationsAndMembersEmitSemanticTokens() {
        let source = """
        function identity(value _: Int) -> Int {
            let number: Int = 0
            Logger.info(number)
            return value
        }

        function fetchUsername(id _: Int) -> String {
            return ""
        }

        function refreshUser(id _: Int) {
            let username = fetchUsername(id: id)
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
        #expect(containsToken(tokens, text: "number", type: .variable, modifiers: [.declaration]))
        #expect(containsToken(tokens, text: "number", type: .variable, modifiers: [.argument]))
        #expect(containsToken(tokens, text: "id", type: .parameter, modifiers: [.argument]))
        #expect(containsToken(tokens, text: "username", type: .variable, modifiers: [.argument]))
        #expect(containsToken(tokens, text: "arrayifyParameter", type: .macro, modifiers: [.declaration]))
        #expect(containsToken(tokens, text: "declaration", type: .property, modifiers: []))
        #expect(containsToken(tokens, text: "rewrite", type: .method, modifiers: []))
    }

    @Test("Constructor argument labels are method-style tokens, not parameter declarations")
    func constructorArgumentLabelsEmitMethodTokens() {
        let source = """
        construct FixtureConstruct {
            let number: Int
        }

        @main {
            let result: FixtureConstruct = FixtureConstruct(number: 1)
        }
        """

        let tokens = NeatLanguageServer.debugSemanticTokenSnapshots(in: source)

        #expect(containsExactToken(tokens, text: "number", type: .method, modifiers: []))
        #expect(!containsToken(tokens, text: "number", type: .parameter, modifiers: [.declaration]))
    }

    @Test("Type reference argument labels emit type application tokens")
    func typeReferenceArgumentLabelsEmitTypeApplicationTokens() {
        let source = """
        macro arrayifyParameter(): Parameter { target, diagnostics in
            target.declaration.type.rewrite(
                ArrayTypeReference(
                    element: target.declaration.type
                )
            )
        }
        """

        let tokens = NeatLanguageServer.debugSemanticTokenSnapshots(in: source)

        #expect(containsExactToken(tokens, text: "ArrayTypeReference", type: .type, modifiers: []))
        #expect(containsExactToken(tokens, text: "element", type: .type, modifiers: [.application]))
    }

    @Test("Generic function declarations emit function and parameter declaration tokens")
    func genericFunctionDeclarationsEmitDeclarationTokens() {
        let source = """
        function load<Value, Failure>(
            target _: binding Promise<Value, Failure>,
            #autoclosure task: Result<Value, Failure>
        ) {
            switch task() {
            case .success(let item):
                target = .success(result: item)
            }
        }
        """

        let tokens = NeatLanguageServer.debugSemanticTokenSnapshots(in: source)

        #expect(containsToken(tokens, text: "load", type: .function, modifiers: [.declaration]))
        #expect(containsToken(tokens, text: "target", type: .parameter, modifiers: [.declaration]))
        #expect(containsToken(tokens, text: "task", type: .parameter, modifiers: [.declaration]))
        #expect(!containsExactToken(tokens, text: "target", type: .method, modifiers: []))
        #expect(!containsExactToken(tokens, text: "task", type: .method, modifiers: []))
    }

    @Test("Macro applications, including parameter macros, emit semantic tokens")
    func macroApplicationsEmitSemanticTokens() {
        let source = """
        function takeMany(#variadic values: Int) -> [Int] {
            return values
        }

        @main {
            let text = #stringify(1 + 2)
        }
        """

        let tokens = NeatLanguageServer.debugSemanticTokenSnapshots(in: source)

        #expect(containsToken(tokens, text: "#variadic", type: .macro, modifiers: []))
        #expect(containsToken(tokens, text: "#stringify", type: .macro, modifiers: []))
    }

    @Test("Nil emits a keyword semantic token")
    func nilEmitsKeywordToken() {
        let source = """
        function fallback() -> String? {
            return nil
        }
        """

        let tokens = NeatLanguageServer.debugSemanticTokenSnapshots(in: source)

        #expect(containsExactToken(tokens, text: "nil", type: .keyword, modifiers: []))
    }

    @Test("Member call receivers do not emit plain variable read tokens")
    func memberCallReceiversDoNotEmitVariableReadTokens() {
        let source = """
        @main {
            let output = Channel<String>()
            output.send("george")
            state received = output.receive()
        }
        """

        let tokens = NeatLanguageServer.debugSemanticTokenSnapshots(in: source)

        #expect(containsExactToken(tokens, text: "send", type: .method, modifiers: []))
        #expect(containsExactToken(tokens, text: "receive", type: .method, modifiers: []))
        #expect(!containsExactToken(tokens, text: "output", type: .variable, modifiers: []))
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
