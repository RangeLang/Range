import Foundation
@testable import CLI
import Testing

@Suite("Range LSP semantic tokens")
struct RangeLanguageServerSemanticTokenTests {
    @Test("Explicit macro applications emit semantic tokens")
    func explicitMacroApplicationsEmitSemanticTokens() {
        let source = """
        @construct(name: "Panel") {
            @let(name: "enabled") {
                @value(type: "Bool", current: "Bool(false)")
            }
            @state(name: "count", value: "Int(0)")
        }
        """

        let tokens = RangeLanguageServer.debugSemanticTokenSnapshots(in: source)

        #expect(containsExactToken(tokens, text: "@construct", type: .macro, modifiers: []))
        #expect(containsExactToken(tokens, text: "@let", type: .macro, modifiers: []))
        #expect(containsExactToken(tokens, text: "@value", type: .macro, modifiers: []))
        #expect(containsExactToken(tokens, text: "@state", type: .macro, modifiers: []))
        #expect(!containsExactToken(tokens, text: "Bool", type: .type, modifiers: []))
        #expect(!containsExactToken(tokens, text: "Int", type: .type, modifiers: []))
    }

    @Test("Type reference argument labels emit type application tokens")
    func typeReferenceArgumentLabelsEmitTypeApplicationTokens() {
        let source = """
        @main {
            @return(value: ArrayTypeReference(element: target))
        }
        """

        let tokens = RangeLanguageServer.debugSemanticTokenSnapshots(in: source)

        #expect(containsExactToken(tokens, text: "ArrayTypeReference", type: .type, modifiers: []))
        #expect(containsExactToken(tokens, text: "element", type: .type, modifiers: [.application]))
    }

    @Test("Definition ignores argument labels")
    func definitionIgnoresArgumentLabels() {
        let source = """
        @main {
            @return(value: Math.clamp(value: Int(1), min: Int(0), max: Int(2)))
        }
        """
        let support = """
        @construct(name: "Math") {
        }
        """

        let definition = RangeLanguageServer.debugDefinitionSnapshot(
            in: source,
            line: 1,
            character: 31,
            supportDocuments: [(uri: "file:///Math.range", text: support)]
        )

        #expect(definition == nil)
    }

    @Test("Definition ignores type names inside macro string payloads")
    func definitionIgnoresTypeNamesInsideMacroStringPayloads() {
        let source = """
        @construct(name: "Panel") {
            @let(name: "enabled") {
                @value(type: "Bool", current: "Bool(true)")
            }
        }
        """
        let support = """
        @construct(name: "Bool") {
        }
        """

        let definition = RangeLanguageServer.debugDefinitionSnapshot(
            in: source,
            line: 2,
            character: 27,
            supportDocuments: [(uri: "file:///Bool.range", text: support)]
        )

        #expect(definition == nil)
    }

    @Test("Macro applications, including parameter macros, emit semantic tokens")
    func macroApplicationsEmitSemanticTokens() {
        let source = """
        @parameter(name: "values") {
            @variadic
            @value(type: "Array<Int>")
        }
        @stringify(value: "Int(1) + Int(2)")
        """

        let tokens = RangeLanguageServer.debugSemanticTokenSnapshots(in: source)

        #expect(containsToken(tokens, text: "@variadic", type: .macro, modifiers: []))
        #expect(containsToken(tokens, text: "@stringify", type: .macro, modifiers: []))
    }

    @Test("String interpolation contents stay plain text")
    func stringInterpolationContentsStayPlainText() {
        let source = #"""
        @macro(name: "stringify", result: "String") {
            @return(value: "\(value)")
        }
        """#

        let tokens = RangeLanguageServer.debugSemanticTokenSnapshots(in: source)
        let interpolationIdentifierHasSemanticToken = tokens.contains(where: { token in
            token.line == 1
                && token.text == "value"
                && (token.type == .parameter || token.type == .variable)
        })

        #expect(!containsExactToken(tokens, text: #""\(value)""#, type: .string, modifiers: []))
        #expect(!interpolationIdentifierHasSemanticToken)
    }

    @Test("Macro declarations emit semantic tokens")
    func macroDeclarationsEmitSemanticTokens() {
        let source = """
        @macro(name: "codingKey", result: "String") {
            @parameter(name: "value") {
                @value(type: "String")
            }
            @return(value: value)
        }
        """

        let tokens = RangeLanguageServer.debugSemanticTokenSnapshots(in: source)

        #expect(containsExactToken(tokens, text: "@macro", type: .macro, modifiers: []))
        #expect(containsExactToken(tokens, text: "@parameter", type: .macro, modifiers: []))
        #expect(containsExactToken(tokens, text: "@return", type: .macro, modifiers: []))
        #expect(!containsToken(tokens, text: "codingKey", type: .macro, modifiers: [.declaration]))
    }

    @Test("Documented package syntax emits semantic tokens")
    func documentedPackageSyntaxEmitsSemanticTokens() {
        let source = """
        @construct(name: "Project") {
            @let(name: "name") {
                @value(type: "Title", current: "Title(\\"Example\\")")
            }
            @let(name: "version") {
                @value(type: "Version", current: "Version(0.1.0)")
            }
        }

        @construct(name: "Language") {
            @let(name: "defaultLocale") {
                @value(type: "String", current: "String(\\"en\\")")
            }
        }

        @construct(name: "Panel") {
            @let(name: "count") {
                @value(type: "Optional<Int>", current: "Optional<Int>(5)")
            }
            @let(name: "value") {
                @value(type: "Optional<Int>")
            }
        }
        """

        let tokens = RangeLanguageServer.debugSemanticTokenSnapshots(in: source)

        #expect(containsExactToken(tokens, text: "@construct", type: .macro, modifiers: []))
        #expect(containsExactToken(tokens, text: "@let", type: .macro, modifiers: []))
        #expect(containsExactToken(tokens, text: "@value", type: .macro, modifiers: []))
        #expect(!containsExactToken(tokens, text: "Title", type: .type, modifiers: []))
        #expect(!containsExactToken(tokens, text: "Version", type: .type, modifiers: []))
        #expect(!containsExactToken(tokens, text: "Optional", type: .type, modifiers: []))
        #expect(!containsExactToken(tokens, text: "Int", type: .type, modifiers: []))
    }

    @Test("Member call receivers do not emit plain variable read tokens")
    func memberCallReceiversDoNotEmitVariableReadTokens() {
        let source = """
        @main {
            @return(value: output.send(String("george")))
        }
        """

        let tokens = RangeLanguageServer.debugSemanticTokenSnapshots(in: source)

        #expect(containsExactToken(tokens, text: "send", type: .method, modifiers: []))
        #expect(!containsExactToken(tokens, text: "output", type: .variable, modifiers: []))
    }

    @Test("Formatting indents documented metadata syntax without counting string braces")
    func formattingIndentsDocumentedMetadataSyntaxWithoutCountingStringBraces() {
        let source = """
        @construct(name: "Project") {
        @let(name: "name") {
        @value(type: "Title", current: "Title(\\"Example {\\")")
        }
        @let(name: "version") {
        @value(type: "Version", current: "Version(0.1.0)") // )
        }
        }
        @construct(name: "Panel") {
        @let(name: "title") {
        @value(type: "String")
        }
        }
        """

        let formatted = RangeLanguageServer.debugFormattedDocument(source)

        #expect(formatted == """
        @construct(name: "Project") {
          @let(name: "name") {
            @value(type: "Title", current: "Title(\\"Example {\\")")
          }
          @let(name: "version") {
            @value(type: "Version", current: "Version(0.1.0)") // )
          }
        }
        @construct(name: "Panel") {
          @let(name: "title") {
            @value(type: "String")
          }
        }
        """)
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
