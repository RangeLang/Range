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
        function identity(_ value: Int) -> Int {
            let number: Int = 0
            Logger.info(number)
            return value
        }

        function fetchUsername(_ id: Int) -> String {
            return ""
        }

        function refreshUser(_ id: Int) {
            let username = fetchUsername(id)
            Logger.info(username)
        }

        macro arrayifyParameter(): Parameter { target, diagnostics in
            target.declaration.type.replace(with:
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
        #expect(containsToken(tokens, text: "username", type: .variable, modifiers: [.argument]))
        #expect(containsToken(tokens, text: "arrayifyParameter", type: .macro, modifiers: [.declaration]))
        #expect(containsToken(tokens, text: "declaration", type: .property, modifiers: []))
        #expect(containsToken(tokens, text: "replace", type: .method, modifiers: []))
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
            target.declaration.type.replace(with:
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
            target target: binding Promise<Value, Failure>,
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
        #expect(containsToken(tokens, text: "task", type: .parameter, modifiers: [.declaration]))
        #expect(!containsExactToken(tokens, text: "task", type: .method, modifiers: []))
    }

    @Test("Operator function declarations emit declaration tokens")
    func operatorFunctionDeclarationsEmitDeclarationTokens() {
        let source = """
        protocol Comparable: Equatable {
            function <(lhs: Self, rhs: Self) -> Bool
        }
        """

        let tokens = NeatLanguageServer.debugSemanticTokenSnapshots(in: source)

        #expect(containsExactToken(tokens, text: "function", type: .keyword, modifiers: []))
        #expect(containsExactToken(tokens, text: "<", type: .function, modifiers: [.declaration]))
        #expect(containsExactToken(tokens, text: "lhs", type: .parameter, modifiers: [.declaration]))
        #expect(containsExactToken(tokens, text: "rhs", type: .parameter, modifiers: [.declaration]))
        #expect(!containsExactToken(tokens, text: "lhs", type: .method, modifiers: []))
        #expect(!containsExactToken(tokens, text: "rhs", type: .method, modifiers: []))
    }

    @Test("Switch pattern bindings stay plain text")
    func switchPatternBindingsStayPlainText() {
        let source = """
        function encode() -> Result<Void, EncodingError> {
            switch container.encode(id, forKey: "id") {
            case .success:
                break
            case .failure(let error):
                return .failure(cause: error)
            }
        }
        """

        let tokens = NeatLanguageServer.debugSemanticTokenSnapshots(in: source)

        #expect(!containsExactToken(tokens, text: "error", type: .variable, modifiers: [.declaration]))
        #expect(!containsExactToken(tokens, text: "error", type: .variable, modifiers: [.argument]))
        #expect(!containsExactToken(tokens, text: "error", type: .variable, modifiers: []))
    }

    @Test("Parameter references stay plain text")
    func parameterReferencesStayPlainText() {
        let source = """
        macro clamped<T: Comparable>(min: T, max: T): State<T> { target, diagnostics in
            target.initializer { value in
                Math.clamp(value: value, min: min, max: max)
            }
        }
        """

        let tokens = NeatLanguageServer.debugSemanticTokenSnapshots(in: source)
        let highlightedParameterReferences = tokens.filter { token in
            token.line == 2
                && (token.text == "min" || token.text == "max")
                && (token.type == .parameter || token.type == .variable)
        }

        #expect(containsExactToken(tokens, text: "min", type: .parameter, modifiers: [.declaration]))
        #expect(containsExactToken(tokens, text: "max", type: .parameter, modifiers: [.declaration]))
        #expect(highlightedParameterReferences.isEmpty)
    }

    @Test("Definition ignores argument labels")
    func definitionIgnoresArgumentLabels() {
        let source = """
        macro clamped<T: Comparable>(min: T, max: T): State<T> { target, diagnostics in
            target.initializer { value in
                Math.clamp(value: value, min: min, max: max)
            }
        }
        """
        let support = """
        construct Let<T> {
            let value: Expression?
        }
        """

        let definition = NeatLanguageServer.debugDefinitionSnapshot(
            in: source,
            line: 2,
            character: 20,
            supportDocuments: [(uri: "file:///Let.neat", text: support)]
        )

        #expect(definition == nil)
    }

    @Test("Definition resolves core types through graph")
    func definitionResolvesCoreTypesThroughGraph() {
        let source = """
        @main {
            let enabled: Bool = true
        }
        """
        let support = """
        construct Bool {
        }
        """

        let definition = NeatLanguageServer.debugDefinitionSnapshot(
            in: source,
            line: 1,
            character: 17,
            supportDocuments: [(uri: "file:///Bool.neat", text: support)]
        )

        #expect(definition?.uri == "file:///Bool.neat")
        #expect(definition?.name == "Bool")
    }

    @Test("External parameter labels emit plain label semantic tokens")
    func externalParameterLabelsEmitLabelTokens() {
        let source = """
        protocol KeyedDecodingContainer {
            function decode(_ type: Bool.Type, forKey key: String) -> Result<Bool, DecodingError>
        }
        """

        let tokens = NeatLanguageServer.debugSemanticTokenSnapshots(in: source)

        #expect(containsExactToken(tokens, text: "forKey", type: .label, modifiers: [.declaration]))
        #expect(containsExactToken(tokens, text: "_", type: .label, modifiers: [.declaration]))
        #expect(!containsExactToken(tokens, text: "type", type: .parameter, modifiers: [.declaration]))
        #expect(!containsExactToken(tokens, text: "key", type: .parameter, modifiers: [.declaration]))
        #expect(!containsExactToken(tokens, text: "forKey", type: .property, modifiers: []))
    }

    @Test("Two-name parameters keep internal names plain")
    func twoNameParametersKeepInternalNamesPlain() {
        let source = """
        extension User: Encodable {
            function encode(to encoder: Encoder) -> Result<Void, EncodingError> {
                let container: KeyedEncodingContainer = encoder.keyedContainer()
                return .success(result: Void())
            }
        }
        """

        let tokens = NeatLanguageServer.debugSemanticTokenSnapshots(in: source)

        #expect(containsExactToken(tokens, text: "to", type: .label, modifiers: [.declaration]))
        #expect(!containsExactToken(tokens, text: "encoder", type: .parameter, modifiers: [.declaration]))
    }

    @Test("Underscore external labels are declaration tokens")
    func underscoreExternalLabelsAreDeclarationTokens() {
        let source = """
        macro codable(_ strategy: CodingKeyStrategy = .identity): Construct { target, diagnostics in
            target.declaration.expand {
            }
        }
        """

        let tokens = NeatLanguageServer.debugSemanticTokenSnapshots(in: source)

        #expect(containsExactToken(tokens, text: "_", type: .label, modifiers: [.declaration]))
        #expect(!containsExactToken(tokens, text: "strategy", type: .parameter, modifiers: [.declaration]))
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

    @Test("String interpolation contents stay plain text")
    func stringInterpolationContentsStayPlainText() {
        let source = #"""
        macro stringify(_ value: capture Expression): Expression -> String { target, diagnostics in
            target.replace(with: "\(value)")
        }
        """#

        let tokens = NeatLanguageServer.debugSemanticTokenSnapshots(in: source)
        let interpolationIdentifierHasSemanticToken = tokens.contains(where: { token in
            token.line == 1
                && token.text == "value"
                && (token.type == .parameter || token.type == .variable)
        })

        #expect(!containsExactToken(tokens, text: #""\(value)""#, type: .string, modifiers: []))
        #expect(!interpolationIdentifierHasSemanticToken)
    }

    @Test("Marker declarations emit semantic tokens")
    func markerDeclarationsEmitSemanticTokens() {
        let source = """
        marker codingKey<T>(_ value: String): Let<T> -> String {
            return value
        }
        """

        let tokens = NeatLanguageServer.debugSemanticTokenSnapshots(in: source)

        #expect(containsExactToken(tokens, text: "marker", type: .keyword, modifiers: []))
        #expect(containsToken(tokens, text: "codingKey", type: .macro, modifiers: [.declaration]))
        #expect(containsExactToken(tokens, text: "_", type: .label, modifiers: [.declaration]))
        #expect(!containsExactToken(tokens, text: "value", type: .parameter, modifiers: [.declaration]))
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

    @Test("Enum case declarations emit enum member semantic tokens")
    func enumCaseDeclarationsEmitEnumMemberTokens() {
        let source = """
        enum EncodingError {
            case failed
        }
        """

        let tokens = NeatLanguageServer.debugSemanticTokenSnapshots(in: source)

        #expect(containsExactToken(tokens, text: "failed", type: .enumMember, modifiers: [.declaration]))
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
