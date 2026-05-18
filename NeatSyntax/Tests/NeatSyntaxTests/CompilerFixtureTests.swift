import Foundation
@testable import NeatSyntax
import Testing

@Suite("Compiler fixtures")
struct CompilerFixtureTests {
    @Test("CompilePass fixtures validate")
    func compilePassFixturesValidate() throws {
        for fixture in try fixtureFiles(in: "CompilePass") {
            do {
                _ = try compile(fixture: fixture, expectedRole: .pass)
            } catch {
                Issue.record("Expected \(fixture.path) to validate, got \(error).")
            }
        }
    }

    @Test("CompileFail fixtures fail")
    func compileFailFixturesFail() throws {
        for fixture in try fixtureFiles(in: "CompileFail") {
            do {
                _ = try compile(fixture: fixture, expectedRole: .fail)
                Issue.record("Expected \(fixture.path) to fail validation.")
            } catch {
                // Expected.
            }
        }
    }

    @Test("Compiler diagnostics include macro warnings")
    func compilerDiagnosticsIncludeMacroWarnings() throws {
        let fixture = try fixtureFile(
            in: "CompilePass",
            path: "Macros/SyntaxProducingMacroIdentifierMemberAccess.neat"
        )
        var inputs = try neatCoreInputs()
        inputs.append(
            SourceInput(
                path: fixture.path,
                source: try String(contentsOf: fixture, encoding: .utf8),
                role: .project
            )
        )

        let diagnostics = CompilerPipeline().diagnostics(inputs: inputs)

        #expect(
            diagnostics.contains {
                $0.severity == .warning
                    && $0.code == "macro.identifier-member-splice"
                    && $0.path == fixture.path
            }
        )
    }

    @Test("User macro diagnostics feed compiler diagnostics")
    func userMacroDiagnosticsFeedCompilerDiagnostics() throws {
        let fixture = try fixtureFile(
            in: "CompilePass",
            path: "Macros/MacroDiagnosticsWarning.neat"
        )
        var inputs = try neatCoreInputs()
        inputs.append(
            SourceInput(
                path: fixture.path,
                source: try String(contentsOf: fixture, encoding: .utf8),
                role: .project
            )
        )

        let diagnostics = CompilerPipeline().diagnostics(inputs: inputs)

        #expect(
            diagnostics.contains {
                $0.severity == .warning
                    && $0.source == "neat-macro"
                    && $0.code == "macro.diagnostic.warning"
                    && $0.message == "custom macro warning"
                    && $0.path == fixture.path
            }
        )
        #expect(
            diagnostics.contains {
                $0.severity == .information
                    && $0.source == "neat-macro"
                    && $0.code == "macro.diagnostic.information"
                    && $0.message == "custom macro information"
                    && $0.path == fixture.path
            }
        )
        #expect(
            diagnostics.contains {
                $0.severity == .hint
                    && $0.source == "neat-macro"
                    && $0.code == "macro.diagnostic.hint"
                    && $0.message == "custom macro hint"
                    && $0.path == fixture.path
            }
        )
    }

    @Test("Parser diagnostics point at invalid hash syntax")
    func parserDiagnosticsPointAtInvalidHashSyntax() throws {
        let projectPath = "/tmp/InvalidHashMacro.neat"
        var inputs = try neatCoreInputs()
        inputs.append(
            SourceInput(
                path: projectPath,
                source: """
                macro bad(): Parameter { target, diagnostics in
                    parameters: #[]
                }
                """,
                role: .project
            )
        )

        let diagnostics = CompilerPipeline().diagnostics(inputs: inputs)
        let diagnostic = try #require(
            diagnostics.first {
                $0.message == "Expected identifier after #."
                    && $0.source == "neat-parser"
                    && $0.path == projectPath
            }
        )

        #expect(diagnostic.range?.start.line == 1)
        #expect(diagnostic.range?.start.character == 16)
        #expect(diagnostic.range?.end.line == 1)
        #expect(diagnostic.range?.end.character == 17)
    }

    @Test("Project source cannot declare initializers")
    func projectSourceCannotDeclareInitializers() throws {
        let projectPath = "/tmp/InitializerSyntax.neat"
        var inputs = try neatCoreInputs()
        inputs.append(
            SourceInput(
                path: projectPath,
                source: """
                construct Version {
                    let value: String

                    init(value: String) {
                        self.value = value
                    }
                }
                """,
                role: .project
            )
        )

        let diagnostics = CompilerPipeline().diagnostics(inputs: inputs)
        #expect(
            diagnostics.contains {
                $0.source == "neat-parser"
                    && $0.path == projectPath
                    && $0.message.contains("Initializer declarations are no longer source syntax")
            }
        )
    }

    @Test("Construct applications bind directly to stored declarations")
    func constructApplicationsBindDirectlyToStoredDeclarations() throws {
        var inputs = try neatCoreInputs()
        inputs.append(
            SourceInput(
                path: "/tmp/DirectConstructApplication.neat",
                source: """
                construct User {
                    let id: Int
                    let name: String
                }

                @main {
                    let user = User(id: 1, name: "George")
                }
                """,
                role: .project
            )
        )

        _ = try CompilerPipeline().buildValidated(inputs: inputs)
    }

    @Test("Typed construction annotations can be optional")
    func typedConstructionAnnotationsCanBeOptional() throws {
        let source = """
        construct WidgetCount {
            let value: Double
        }

        construct Counter {
            let count: Int(5)?
            let widgetCount: WidgetCount(value: 0.1)?
            state current: Int(5)?
        }

        @main {
            let local: Int(5)?
        }
        """

        var parser = try Parser(source: source)
        let file = try parser.parseSourceFile()

        guard case .module(let module) = file else {
            Issue.record("Expected module.")
            return
        }
        let counter = try #require(module.constructs.first(where: { $0.name == "Counter" }))

        var inputs = try neatCoreInputs()
        inputs.append(
            SourceInput(
                path: "/tmp/TypedConstructionOptional.neat",
                source: source,
                role: .project
            )
        )
        _ = try CompilerPipeline().buildValidated(inputs: inputs)

        let count = try #require(counter.values.first(where: { $0.name == "count" }))
        #expect(count.typeName == "Int?")
        guard case .integer(5)? = count.value else {
            Issue.record("Expected typed construction literal value.")
            return
        }

        let widgetCount = try #require(counter.values.first(where: { $0.name == "widgetCount" }))
        #expect(widgetCount.typeName == "WidgetCount?")
        guard case .call(let widgetCountInitializer, let widgetCountArguments)? = widgetCount.value
        else {
            Issue.record("Expected typed construction value call.")
            return
        }
        #expect(widgetCountInitializer == "WidgetCount")
        #expect(widgetCountArguments.map(\.label) == ["value"])

        let current = try #require(counter.states.first(where: { $0.name == "current" }))
        #expect(current.type == .optional(.named("Int")))
        guard case .stored(.integer(5)) = current.storage else {
            Issue.record("Expected typed construction state initializer.")
            return
        }

        let local = try #require(module.mainBlock?.body.first)
        guard case .localBinding(let declaration) = local else {
            Issue.record("Expected local typed construction binding.")
            return
        }
        #expect(declaration.type == .optional(.named("Int")))
        guard case .integer(5) = declaration.expression else {
            Issue.record("Expected typed construction local initializer.")
            return
        }
    }

    @Test("Local typed declarations replace assignment-shaped type construction")
    func localTypedDeclarationsReplaceAssignmentShapedTypeConstruction() throws {
        let validSource = """
        @main {
            let input: Channel<Int>
        }
        """

        var validInputs = try neatCoreInputs()
        validInputs.append(
            SourceInput(
                path: "/tmp/TypedChannelDeclaration.neat",
                source: validSource,
                role: .project
            )
        )
        _ = try CompilerPipeline().buildValidated(inputs: validInputs)

        let invalidPath = "/tmp/AssignmentShapedTypeConstruction.neat"
        var invalidInputs = try neatCoreInputs()
        invalidInputs.append(
            SourceInput(
                path: invalidPath,
                source: """
                @main {
                    let input = Channel<Int>
                }
                """,
                role: .project
            )
        )

        let diagnostics = CompilerPipeline().diagnostics(inputs: invalidInputs)
        #expect(
            diagnostics.contains {
                $0.path == invalidPath
                    && $0.message.contains("Use `let input: Channel<Int>`")
            }
        )
    }

    @Test("Construct applications reject labels with no stored declaration")
    func constructApplicationsRejectLabelsWithNoStoredDeclaration() throws {
        let projectPath = "/tmp/DirectConstructApplicationBadLabel.neat"
        var inputs = try neatCoreInputs()
        inputs.append(
            SourceInput(
                path: projectPath,
                source: """
                construct User {
                    let id: Int
                    let name: String
                }

                @main {
                    let user = User(identifier: 1, name: "George")
                }
                """,
                role: .project
            )
        )

        let diagnostics = CompilerPipeline().diagnostics(inputs: inputs)
        #expect(
            diagnostics.contains {
                $0.path == projectPath
                    && $0.message.contains("does not match any available parameter labels")
            }
        )
    }

    @Test("Namespace declarations provide attribute names")
    func namespaceDeclarationsProvideAttributeNames() throws {
        var inputs = try neatCoreInputs()
        inputs.append(
            SourceInput(
                path: "/tmp/NamespaceAttribute.neat",
                source: """
                namespace Styling {}

                @Styling
                construct Panel {
                    let title: String
                }
                """,
                role: .project
            )
        )

        let program = try CompilerPipeline().buildValidated(inputs: inputs)
        #expect(program.declarationGraph.hasNamespaceAttribute(named: "Styling"))
    }

    @Test("Unknown attributes require matching namespaces")
    func unknownAttributesRequireMatchingNamespaces() throws {
        var inputs = try neatCoreInputs()
        inputs.append(
            SourceInput(
                path: "/tmp/UnknownAttribute.neat",
                source: """
                @Missing
                construct Panel {
                    let title: String
                }
                """,
                role: .project
            )
        )

        do {
            _ = try CompilerPipeline().buildValidated(inputs: inputs)
            Issue.record("Expected @Missing to require a matching namespace.")
        } catch {
            #expect(String(describing: error).contains("Declare namespace Missing"))
        }
    }

    @Test("Project macros infer across project files")
    func projectMacrosInferAcrossProjectFiles() throws {
        var inputs = try neatCoreInputs()
        inputs.append(
            SourceInput(
                path: "/tmp/ProjectMacros.neat",
                source: """
                macro captureText(_ value: capture Expression): Expression -> String { target, diagnostics in
                    target.replace(with: "captured: \\(value)")
                }
                """,
                role: .project
            )
        )
        inputs.append(
            SourceInput(
                path: "/tmp/ProjectMain.neat",
                source: """
                @main {
                    let text = #captureText(1 + 2)
                }
                """,
                role: .project
            )
        )

        _ = try CompilerPipeline().buildValidated(inputs: inputs)
    }

    @Test("Project callables and macros infer before later declarations")
    func projectDeclarationsInferBeforeLaterDeclarations() throws {
        var inputs = try neatCoreInputs()
        inputs.append(
            SourceInput(
                path: "/tmp/ForwardDeclarations.neat",
                source: """
                @main {
                    let messageText = message()
                    let captured = #captureText(1 + 2)
                }

                function message() -> String {
                    return "Hello"
                }

                macro captureText(_ value: capture Expression): Expression -> String { target, diagnostics in
                    target.replace(with: "captured: \\(value)")
                }
                """,
                role: .project
            )
        )

        _ = try CompilerPipeline().buildValidated(inputs: inputs)
    }

    @Test("Init rewrite expression uses canonical initializer labels")
    func initRewriteExpressionUsesCanonicalInitializerLabels() throws {
        let expression = Expression.call(
            name: "target.declaration.expression",
            arguments: [
                CallArgument(
                    label: "arguments",
                    value: .array([
                        .identifier("target.application.arguments[0]"),
                        .identifier("target.application.arguments[1]"),
                    ])
                )
            ]
        )

        let rewritten = MacroExpander.executeInitRewriteExpression(
            expression,
            targetBinding: "target",
            applicationArguments: [
                CallArgument(label: nil, value: .string("Hello")),
                CallArgument(label: nil, value: .integer(27)),
            ],
            initTarget: RealizedInitTarget(
                constructName: "Greeting",
                parameterLabels: ["text", "number"],
                isCore: false
            )
        )

        #expect(rewritten != nil)

        guard case .call(let name, let arguments)? = rewritten else {
            Issue.record("Expected rewritten init expression to be a call.")
            return
        }

        #expect(name == "Greeting")
        #expect(arguments.count == 2)
        #expect(arguments[0].label == "text")
        #expect(arguments[1].label == "number")
    }

    @Test("Construct application surface is present in declaration graph")
    func constructApplicationSurfaceIsPresentInDeclarationGraph() throws {
        let program = try CompilerPipeline().build(inputs: neatCoreInputs())
        let graph = program.declarationGraph

        #expect(graph.constructsByName["Construct"] != nil)
        #expect(graph.constructsByName["Construct.Application"] != nil)
        #expect(graph.syntaxResolver.declaration(named: "Construct.Application", conformsTo: "SyntaxReplaceable"))
    }

    @Test("Declaration graph carries source locations")
    func declarationGraphCarriesSourceLocations() throws {
        let source = """
        macro codable(): Construct { target, diagnostics in
        }

        marker codingKey<T>(_ value: String): Let<T> -> String {
            return value
        }

        construct User {
        }

        function makeUser() -> User {
            return User()
        }
        """
        let program = try CompilerPipeline().build(inputs: [
            SourceInput(path: "/tmp/GraphLocations.neat", source: source, role: .project)
        ])
        let graph = program.declarationGraph

        let construct = graph.sourceLocation(named: "User", kinds: [.type])
        let macro = graph.sourceLocation(named: "codable", kinds: [.macro])
        let marker = graph.sourceLocation(named: "codingKey", kinds: [.marker])
        let function = graph.sourceLocation(named: "makeUser", kinds: [.function])

        #expect(construct?.path == "/tmp/GraphLocations.neat")
        #expect(construct?.range.start.line == 7)
        #expect(construct?.range.start.character == 10)
        #expect(macro?.range.start.line == 0)
        #expect(marker?.range.start.line == 3)
        #expect(function?.range.start.line == 10)
    }

    @Test("Rewrite site decoding uses declaration-backed descriptors")
    func rewriteSiteDecodingUsesDeclarationBackedDescriptors() throws {
        let program = try CompilerPipeline().build(inputs: neatCoreInputs())
        let context = program.declarationGraph.macroExpansionContext(macrosByName: [:])

        let direct = context.resolvedRewriteCall(
            from: .call(
                name: "target.replace",
                arguments: [CallArgument(label: "with", value: .string("value"))]
            ),
            targetBinding: "target",
            targetType: .named("Expression")
        )
        #expect(direct?.site == .targetDirect)

        let parameter = context.resolvedRewriteCall(
            from: .call(
                name: "target.application.expression.replace",
                arguments: [CallArgument(label: "with", value: .string("value"))]
            ),
            targetBinding: "target",
            targetType: .named("Parameter")
        )
        #expect(parameter?.site == .parameterApplicationArgument)

        let functionArgument = context.resolvedRewriteCall(
            from: .call(
                name: "target.application.arguments[0].expression.replace",
                arguments: [CallArgument(label: "with", value: .string("value"))]
            ),
            targetBinding: "target",
            targetType: .named("Function")
        )
        #expect(functionArgument?.site == .functionArgumentExpression)

        let functionApplication = context.resolvedRewriteCall(
            from: .call(
                name: "target.application.replace",
                arguments: [CallArgument(label: "with", value: .string("value"))]
            ),
            targetBinding: "target",
            targetType: .named("Function")
        )
        #expect(functionApplication?.site == .functionApplication)
    }

    @Test("Namespaces qualify nested callables and constructs")
    func namespacesQualifyNestedCallablesAndConstructs() throws {
        var inputs = try neatCoreInputs()
        inputs.append(
            SourceInput(
                path: "/tmp/Namespaces.neat",
                source: """
                namespace System {
                    namespace Math {
                        function zero() -> Int {
                            return 0
                        }

                        construct Box {
                            let number: Int
                        }
                    }
                }

                @main {
                    let result = System.Math.zero()
                }
                """,
                role: .project
            )
        )

        let program = try CompilerPipeline().buildValidated(inputs: inputs)

        #expect(program.declarationGraph.callablesByName["System.Math.zero"] != nil)
        #expect(program.declarationGraph.constructsByName["System.Math.Box"] != nil)
    }

    @Test("Core Math namespace is available")
    func coreMathNamespaceIsAvailable() throws {
        let program = try CompilerPipeline().buildValidated(inputs: neatCoreInputs())

        #expect(program.declarationGraph.callablesByName["Math.abs"] != nil)
        #expect(program.declarationGraph.callablesByName["Math.min"] != nil)
        #expect(program.declarationGraph.callablesByName["Math.max"] != nil)
        #expect(program.declarationGraph.callablesByName["Math.clamp"] != nil)
    }

    @Test("Namespace extensions reopen namespace members")
    func namespaceExtensionsReopenNamespaceMembers() throws {
        var inputs = try neatCoreInputs()
        inputs.append(
            SourceInput(
                path: "/tmp/NamespaceExtension.neat",
                source: """
                extension Math {
                    function twice(value: Int) -> Int {
                        return value + value
                    }

                    construct Box {
                        let number: Int
                    }
                }
                """,
                role: .project
            )
        )

        let program = try CompilerPipeline().buildValidated(inputs: inputs)

        #expect(program.declarationGraph.callablesByName["Math.twice"] != nil)
        #expect(program.declarationGraph.constructsByName["Math.Box"] != nil)
    }

    @Test("Construct conformances require nominal type references")
    func constructConformancesRequireNominalTypeReferences() throws {
        let source = """
        construct Box: [Int] { }
        """

        do {
            var parser = try Parser(source: source)
            _ = try parser.parseSourceFile()
            Issue.record("Expected non-nominal construct conformance to fail parsing.")
        } catch {
            let description = String(describing: error)
            #expect(description.contains("Conformance must be a nominal type reference"))
        }
    }

    @Test("Extension targets require nominal type references")
    func extensionTargetsRequireNominalTypeReferences() throws {
        let source = """
        extension [Int] { }
        """

        do {
            var parser = try Parser(source: source)
            _ = try parser.parseSourceFile()
            Issue.record("Expected non-nominal extension target to fail parsing.")
        } catch {
            let description = String(describing: error)
            #expect(description.contains("Extension target must be a nominal type reference"))
        }
    }

    @Test("Clamped state macro rewrites initializer and assignments")
    func clampedStateMacroRewritesInitializerAndAssignments() throws {
        let fixture = try fixtureFile(in: "CompilePass", path: "Macros/ClampedState.neat")
        let program = try compile(fixture: fixture, expectedRole: .pass)
        let expandedFile = try #require(
            program.projectExpandedFiles.first(where: { $0.path == fixture.path })
        )

        let construct: ConstructDeclaration
        switch expandedFile.sourceFile {
        case .construct(let declaration):
            construct = declaration
        case .module(let module):
            construct = try #require(module.constructs.first(where: { $0.name == "Person" }))
        default:
            Issue.record("Expected expanded project file to contain the Person construct.")
            return
        }

        let state = try #require(construct.states.first(where: { $0.name == "age" }))

        guard case .stored(let initializerExpression) = state.storage else {
            Issue.record("Expected clamped state to keep stored initializer.")
            return
        }

        guard case .call(let initializerName, _) = initializerExpression else {
            Issue.record("Expected clamped initializer to become a call.")
            return
        }

        #expect(initializerName == "Math.clamp")

        let update = try #require(construct.callables.first(where: { $0.name == "update" }))
        let assignment = try #require(update.body?.first)

        guard case .assignment(_, let assignmentExpression) = assignment else {
            Issue.record("Expected update body to contain a rewritten assignment.")
            return
        }

        guard case .call(let assignmentName, _) = assignmentExpression else {
            Issue.record("Expected clamped assignment to become a call.")
            return
        }

        #expect(assignmentName == "Math.clamp")

        let compoundAssignment = try #require(update.body?[1])

        guard case .assignment(_, let compoundAssignmentExpression) = compoundAssignment else {
            Issue.record("Expected compound assignment to lower into a rewritten assignment.")
            return
        }

        guard case .call(let compoundAssignmentName, _) = compoundAssignmentExpression else {
            Issue.record("Expected lowered compound assignment to become a call.")
            return
        }

        #expect(compoundAssignmentName == "Math.clamp")
    }

    @Test("State getter macro rewrites reads in expressions")
    func stateGetterMacroRewritesReadsInExpressions() throws {
        let fixture = try fixtureFile(in: "CompilePass", path: "Macros/GetterState.neat")
        let program = try compile(fixture: fixture, expectedRole: .pass)
        let expandedFile = try #require(
            program.projectExpandedFiles.first(where: { $0.path == fixture.path })
        )

        let construct: ConstructDeclaration
        switch expandedFile.sourceFile {
        case .construct(let declaration):
            construct = declaration
        case .module(let module):
            construct = try #require(module.constructs.first(where: { $0.name == "Reader" }))
        default:
            Issue.record("Expected expanded project file to contain the Reader construct.")
            return
        }

        let current = try #require(construct.callables.first(where: { $0.name == "current" }))
        let currentReturn = try #require(current.body?.first)
        guard case .return(let currentExpression?) = currentReturn,
            case .binary(let currentLHS, .addition, let currentRHS) = currentExpression,
            case .identifier(let currentName) = currentLHS,
            case .integer(let currentAmount) = currentRHS
        else {
            Issue.record("Expected current() to return the getter-rewritten age expression.")
            return
        }

        #expect(currentName == "age")
        #expect(currentAmount == 1)

        let total = try #require(construct.callables.first(where: { $0.name == "total" }))
        let totalReturn = try #require(total.body?.first)
        guard case .return(let totalExpression?) = totalReturn,
            case .binary(let totalLHS, .addition, let totalRHS) = totalExpression,
            case .binary(let nestedLHS, .addition, let nestedRHS) = totalLHS,
            case .identifier(let nestedName) = nestedLHS,
            case .integer(let nestedAmount) = nestedRHS,
            case .identifier(let totalValueName) = totalRHS
        else {
            Issue.record("Expected total() to rewrite the age read inside the larger expression.")
            return
        }

        #expect(nestedName == "age")
        #expect(nestedAmount == 1)
        #expect(totalValueName == "value")
    }

    @Test("Let property macro rewrites initializer and reads")
    func letPropertyMacroRewritesInitializerAndReads() throws {
        let fixture = try fixtureFile(in: "CompilePass", path: "Macros/LetProperty.neat")
        let program = try compile(fixture: fixture, expectedRole: .pass)
        let expandedFile = try #require(
            program.projectExpandedFiles.first(where: { $0.path == fixture.path })
        )

        let construct: ConstructDeclaration
        switch expandedFile.sourceFile {
        case .construct(let declaration):
            construct = declaration
        case .module(let module):
            construct = try #require(module.constructs.first(where: { $0.name == "Holder" }))
        default:
            Issue.record("Expected expanded project file to contain the Holder construct.")
            return
        }

        let value = try #require(construct.values.first(where: { $0.name == "count" }))
        guard case .binary(let initializerLHS, .addition, let initializerRHS)? = value.value,
            case .integer(let initializerBase) = initializerLHS,
            case .integer(let initializerAmount) = initializerRHS
        else {
            Issue.record("Expected let initializer to be rewritten through the initializer hook.")
            return
        }

        #expect(initializerBase == 10)
        #expect(initializerAmount == 2)

        let current = try #require(construct.callables.first(where: { $0.name == "current" }))
        let currentReturn = try #require(current.body?.first)
        guard case .return(let expression?) = currentReturn,
            case .binary(let lhs, .addition, let rhs) = expression,
            case .identifier(let name) = lhs,
            case .integer(let amount) = rhs
        else {
            Issue.record("Expected let getter to rewrite reads.")
            return
        }

        #expect(name == "count")
        #expect(amount == 2)
    }

    @Test("Binding property macro rewrites reads and assignments")
    func bindingPropertyMacroRewritesReadsAndAssignments() throws {
        let fixture = try fixtureFile(in: "CompilePass", path: "Macros/BindingProperty.neat")
        let program = try compile(fixture: fixture, expectedRole: .pass)
        let expandedFile = try #require(
            program.projectExpandedFiles.first(where: { $0.path == fixture.path })
        )

        let construct: ConstructDeclaration
        switch expandedFile.sourceFile {
        case .construct(let declaration):
            construct = declaration
        case .module(let module):
            construct = try #require(module.constructs.first(where: { $0.name == "Box" }))
        default:
            Issue.record("Expected expanded project file to contain the Box construct.")
            return
        }

        let current = try #require(construct.callables.first(where: { $0.name == "current" }))
        let currentReturn = try #require(current.body?.first)
        guard case .return(let expression?) = currentReturn,
            case .binary(let lhs, .addition, let rhs) = expression,
            case .identifier(let name) = lhs,
            case .integer(let amount) = rhs
        else {
            Issue.record("Expected binding getter to rewrite reads.")
            return
        }

        #expect(name == "score")
        #expect(amount == 1)

        let update = try #require(construct.callables.first(where: { $0.name == "update" }))
        let directAssignment = try #require(update.body?.first)
        guard case .assignment(_, let directExpression) = directAssignment,
            case .binary(let directLHS, .addition, let directRHS) = directExpression,
            case .identifier(let directName) = directLHS,
            case .integer(let directAmount) = directRHS
        else {
            Issue.record("Expected binding setter to rewrite direct assignments.")
            return
        }

        #expect(directName == "value")
        #expect(directAmount == 1)

        let compoundAssignment = try #require(update.body?[1])
        guard case .assignment(_, let compoundExpression) = compoundAssignment,
            case .binary(_, .addition, let outerRHS) = compoundExpression,
            case .integer(let compoundAmount) = outerRHS
        else {
            Issue.record("Expected binding setter to rewrite compound assignments.")
            return
        }

        #expect(compoundAmount == 1)
    }

    @Test("Construct macro expand emits extension declarations")
    func constructMacroExpandEmitsExtensionDeclarations() throws {
        let fixture = try fixtureFile(in: "CompilePass", path: "Macros/ConstructAddExtensionSurface.neat")
        let program = try compile(fixture: fixture, expectedRole: .pass)
        let expandedFile = try #require(
            program.projectExpandedFiles.first(where: { $0.path == fixture.path })
        )

        let module: ModuleFileNode
        switch expandedFile.sourceFile {
        case .module(let expandedModule):
            module = expandedModule
        default:
            Issue.record("Expected expanded construct macro fixture to become a module.")
            return
        }

        let extensionDeclaration = try #require(module.extensions.first)
        #expect(extensionDeclaration.targetType.displayName == "ExtendableFixture")
        #expect(extensionDeclaration.conformances.map(\.displayName) == ["Greetable"])
        #expect(extensionDeclaration.callables.contains(where: { $0.name == "greet" }))
        #expect(
            extensionDeclaration.callables.first(where: { $0.name == "clone" })?.returnType?
                .displayName == "ExtendableFixture"
        )
        #expect(module.constructs.contains(where: { $0.name == "SiblingConstruct" }))
    }

    @Test("Codable macro synthesizes string keyed encode and decode")
    func codableMacroSynthesizesStringKeyedEncodeAndDecode() throws {
        let fixture = try fixtureFile(in: "CompilePass", path: "Macros/CodableMacroSynthesis.neat")
        let program = try compile(fixture: fixture, expectedRole: .pass)
        let expandedFile = try #require(
            program.projectExpandedFiles.first(where: { $0.path == fixture.path })
        )

        let module: ModuleFileNode
        switch expandedFile.sourceFile {
        case .module(let expandedModule):
            module = expandedModule
        default:
            Issue.record("Expected expanded Codable macro fixture to become a module.")
            return
        }

        #expect(module.enumerations.contains(where: { $0.name == "CodingKeys" }) == false)
        #expect(
            module.extensions.allSatisfy { extensionDeclaration in
                extensionDeclaration.enumerations.contains(where: { $0.name == "CodingKeys" }) == false
            }
        )

        let snakeCase = try #require(
            module.extensions.first(where: { $0.targetName == "SnakeCaseCodableMacroFixture" })
        )
        #expect(snakeCase.conformances.map(\.displayName) == ["Codable"])
        #expect(encodeKeys(in: snakeCase) == ["userId": "user_id", "displayName": "display_name"])
        #expect(decodeKeys(in: snakeCase) == ["userId": "user_id", "displayName": "display_name"])

        let identity = try #require(
            module.extensions.first(where: { $0.targetName == "IdentityCodableMacroFixture" })
        )
        #expect(encodeKeys(in: identity) == ["displayName": "displayName"])
        #expect(decodeKeys(in: identity) == ["displayName": "displayName"])

        let markerOverride = try #require(
            module.extensions.first(where: { $0.targetName == "MarkerOverrideCodableMacroFixture" })
        )
        #expect(encodeKeys(in: markerOverride) == ["userId": "id"])
        #expect(decodeKeys(in: markerOverride) == ["userId": "id"])
    }

    @Test("Equatable macro synthesizes field comparisons")
    func equatableMacroSynthesizesFieldComparisons() throws {
        let fixture = try fixtureFile(in: "CompilePass", path: "Macros/EquatableMacroSynthesis.neat")
        let program = try compile(fixture: fixture, expectedRole: .pass)
        let expandedFile = try #require(
            program.projectExpandedFiles.first(where: { $0.path == fixture.path })
        )

        let module: ModuleFileNode
        switch expandedFile.sourceFile {
        case .module(let expandedModule):
            module = expandedModule
        default:
            Issue.record("Expected expanded Equatable macro fixture to become a module.")
            return
        }

        let fixtureExtension = try #require(
            module.extensions.first(where: { $0.targetName == "EquatableMacroFixture" })
        )
        #expect(fixtureExtension.conformances.map(\.displayName) == ["Equatable"])
        #expect(equalityComparisons(in: fixtureExtension) == ["id", "name", "active"])
        #expect(equalityReturnsTrue(in: fixtureExtension))

        let emptyExtension = try #require(
            module.extensions.first(where: { $0.targetName == "EmptyEquatableMacroFixture" })
        )
        #expect(equalityComparisons(in: emptyExtension).isEmpty)
        #expect(equalityReturnsTrue(in: emptyExtension))
    }

    @Test("Hashable macro synthesizes field combines")
    func hashableMacroSynthesizesFieldCombines() throws {
        let fixture = try fixtureFile(in: "CompilePass", path: "Macros/HashableMacroSynthesis.neat")
        let program = try compile(fixture: fixture, expectedRole: .pass)
        let expandedFile = try #require(
            program.projectExpandedFiles.first(where: { $0.path == fixture.path })
        )

        let module: ModuleFileNode
        switch expandedFile.sourceFile {
        case .module(let expandedModule):
            module = expandedModule
        default:
            Issue.record("Expected expanded Hashable macro fixture to become a module.")
            return
        }

        let fixtureExtension = try #require(
            module.extensions.first(where: { $0.targetName == "HashableMacroFixture" })
        )
        #expect(fixtureExtension.conformances.map(\.displayName) == ["Hashable"])
        #expect(hashCombines(in: fixtureExtension) == ["id", "name", "active"])

        let emptyExtension = try #require(
            module.extensions.first(where: { $0.targetName == "EmptyHashableMacroFixture" })
        )
        #expect(hashCombines(in: emptyExtension).isEmpty)
    }

    @Test("Comparable macro synthesizes lexicographic ordering")
    func comparableMacroSynthesizesLexicographicOrdering() throws {
        let fixture = try fixtureFile(in: "CompilePass", path: "Macros/ComparableMacroSynthesis.neat")
        let program = try compile(fixture: fixture, expectedRole: .pass)
        let expandedFile = try #require(
            program.projectExpandedFiles.first(where: { $0.path == fixture.path })
        )

        let module: ModuleFileNode
        switch expandedFile.sourceFile {
        case .module(let expandedModule):
            module = expandedModule
        default:
            Issue.record("Expected expanded Comparable macro fixture to become a module.")
            return
        }

        let fixtureExtension = try #require(
            module.extensions.first(where: { $0.targetName == "ComparableMacroFixture" })
        )
        #expect(fixtureExtension.conformances.map(\.displayName) == ["Comparable"])
        #expect(equalityComparisons(in: fixtureExtension) == ["major", "minor", "patch"])
        #expect(comparisonChecks(in: fixtureExtension) == [
            ComparisonCheck(property: "major", returns: true),
            ComparisonCheck(property: "major", returns: false),
            ComparisonCheck(property: "minor", returns: true),
            ComparisonCheck(property: "minor", returns: false),
            ComparisonCheck(property: "patch", returns: true),
            ComparisonCheck(property: "patch", returns: false),
        ])
        #expect(comparisonReturnsFalse(in: fixtureExtension))

        let emptyExtension = try #require(
            module.extensions.first(where: { $0.targetName == "EmptyComparableMacroFixture" })
        )
        #expect(comparisonChecks(in: emptyExtension).isEmpty)
        #expect(comparisonReturnsFalse(in: emptyExtension))
    }

    @Test("CaseIterable macro synthesizes allCases function")
    func caseIterableMacroSynthesizesAllCasesFunction() throws {
        let fixture = try fixtureFile(in: "CompilePass", path: "Macros/CaseIterableMacroSynthesis.neat")
        let program = try compile(fixture: fixture, expectedRole: .pass)
        let expandedFile = try #require(
            program.projectExpandedFiles.first(where: { $0.path == fixture.path })
        )

        let module: ModuleFileNode
        switch expandedFile.sourceFile {
        case .module(let expandedModule):
            module = expandedModule
        default:
            Issue.record("Expected expanded CaseIterable macro fixture to become a module.")
            return
        }

        let fixtureExtension = try #require(
            module.extensions.first(where: { $0.targetName == "CaseIterableMacroFixture" })
        )
        #expect(fixtureExtension.conformances.map(\.displayName) == ["CaseIterable"])
        #expect(allCasesReturnValues(in: fixtureExtension) == [".loading", ".ready", ".failed"])

        let emptyExtension = try #require(
            module.extensions.first(where: { $0.targetName == "EmptyCaseIterableMacroFixture" })
        )
        #expect(allCasesReturnValues(in: emptyExtension).isEmpty)
    }

    @Test("Derived property macro rewrites reads")
    func derivedPropertyMacroRewritesReads() throws {
        let fixture = try fixtureFile(in: "CompilePass", path: "Macros/DerivedProperty.neat")
        let program = try compile(fixture: fixture, expectedRole: .pass)
        let expandedFile = try #require(
            program.projectExpandedFiles.first(where: { $0.path == fixture.path })
        )

        let construct: ConstructDeclaration
        switch expandedFile.sourceFile {
        case .construct(let declaration):
            construct = declaration
        case .module(let module):
            construct = try #require(module.constructs.first(where: { $0.name == "Reader" }))
        default:
            Issue.record("Expected expanded project file to contain the Reader construct.")
            return
        }

        let current = try #require(construct.callables.first(where: { $0.name == "current" }))
        let currentReturn = try #require(current.body?.first)
        guard case .return(let expression?) = currentReturn,
            case .binary(let lhs, .addition, let rhs) = expression,
            case .identifier(let name) = lhs,
            case .integer(let amount) = rhs
        else {
            Issue.record("Expected derived getter to rewrite reads.")
            return
        }

        #expect(name == "next")
        #expect(amount == 1)
    }

    @Test("Generic parameter clauses are shared across declarations")
    func genericParameterClausesAreSharedAcrossDeclarations() throws {
        let source = """
        construct Box<T: Comparable, let count: Int = 3> { }

        enum Maybe<T: Comparable, let count: Int = 3> {
            case value(T)
        }

        protocol Cache<T: Comparable, let capacity: Int = 1> {
            function get(value: T) -> T
        }

        function identity<T: Comparable, let count: Int = 3>(value: T) -> T {
            return value
        }

        macro clamped<T: Comparable, let count: Int = 3>(_ value: T): State<T> { target, diagnostics in
            target.replace(with: value)
        }
        """

        var parser = try Parser(source: source)
        let file = try parser.parseSourceFile()

        guard case .module(let module) = file else {
            Issue.record("Expected a module source file.")
            return
        }

        #expect(module.constructs.count == 1)
        #expect(module.enumerations.count == 1)
        #expect(module.protocols.count == 1)
        #expect(module.callables.count == 1)
        #expect(module.macros.count == 1)

        expectSharedGenericShape(module.constructs[0].genericParameters)
        expectSharedGenericShape(module.enumerations[0].genericParameters)
        expectSharedGenericShape(module.protocols[0].genericParameters)
        expectSharedGenericShape(module.callables[0].genericParameters)
        expectSharedGenericShape(module.macros[0].genericParameters)
    }

}

private enum FixtureRole {
    case pass
    case fail
}

private func expectSharedGenericShape(_ parameters: [GenericParameter]) {
    #expect(parameters.count == 2)

    guard case .type(let typeName, let constraint?, let defaultArgument) = parameters[0] else {
        Issue.record("Expected first generic parameter to be a constrained type parameter.")
        return
    }

    #expect(typeName == "T")
    #expect(constraint.displayName == "Comparable")
    #expect(defaultArgument == nil)

    guard case .value(let valueName, let typeReference, let defaultValue?) = parameters[1] else {
        Issue.record("Expected second generic parameter to be a value parameter with a default.")
        return
    }

    #expect(valueName == "count" || valueName == "capacity")
    #expect(typeReference.displayName == "Int")

    guard case .integer(let value) = defaultValue else {
        Issue.record("Expected generic value default to parse as an integer literal.")
        return
    }

    #expect(value == 3 || value == 1)
}


private func encodeKeys(in extensionDeclaration: ExtensionDeclaration) -> [String: String] {
    guard let encode = extensionDeclaration.callables.first(where: { $0.name == "encode" }),
        let body = encode.body
    else {
        return [:]
    }

    return body.reduce(into: [:]) { keys, statement in
        guard case .switchStatement(let expression, _, _) = statement,
            case .call(let name, let arguments) = expression,
            name == "container.encode",
            case .identifier(let propertyName)? = arguments.first(where: { $0.label == nil })?.value,
            case .string(let key)? = arguments.first(where: { $0.label == "forKey" })?.value
        else {
            return
        }

        keys[propertyName] = key
    }
}

private func decodeKeys(in extensionDeclaration: ExtensionDeclaration) -> [String: String] {
    guard let decode = extensionDeclaration.callables.first(where: { $0.name == "decode" }),
        let body = decode.body
    else {
        return [:]
    }

    return body.reduce(into: [:]) { keys, statement in
        guard case .switchStatement(let expression, let cases, _) = statement,
            case .call(let name, let arguments) = expression,
            name == "container.decode",
            case .string(let key)? = arguments.first(where: { $0.label == "forKey" })?.value,
            let successCase = cases.first(where: { switchCase in
                guard case .enumCase(let name, _) = switchCase.pattern else {
                    return false
                }
                return name == ".success"
            }),
            case .enumCase(_, let binding?) = successCase.pattern
        else {
            return
        }

        keys[binding.name] = key
    }
}

private func equalityComparisons(in extensionDeclaration: ExtensionDeclaration) -> [String] {
    guard let equality = extensionDeclaration.callables.first(where: { $0.name == "==" }),
        let body = equality.body
    else {
        return []
    }

    return body.compactMap { statement in
        guard case .conditional(let branches) = statement,
            branches.count == 1,
            case .binary(let lhs, let operatorSymbol, let rhs)? = branches.first?.condition,
            operatorSymbol == .notEqual,
            case .identifier(let lhsPath) = lhs,
            case .identifier(let rhsPath) = rhs,
            lhsPath.hasPrefix("lhs."),
            rhsPath.hasPrefix("rhs."),
            lhsPath.dropFirst(4) == rhsPath.dropFirst(4)
        else {
            return nil
        }

        return String(lhsPath.dropFirst(4))
    }
}

private func equalityReturnsTrue(in extensionDeclaration: ExtensionDeclaration) -> Bool {
    guard let equality = extensionDeclaration.callables.first(where: { $0.name == "==" }),
        let body = equality.body,
        case .return(.boolean(true))? = body.last
    else {
        return false
    }

    return true
}

private func hashCombines(in extensionDeclaration: ExtensionDeclaration) -> [String] {
    guard let hash = extensionDeclaration.callables.first(where: { $0.name == "hash" }),
        let body = hash.body
    else {
        return []
    }

    return body.compactMap { statement in
        guard case .expression(.call(let name, let arguments)) = statement,
            name == "hasher.combine",
            arguments.count == 1,
            arguments[0].label == nil,
            case .identifier(let value) = arguments[0].value
        else {
            return nil
        }

        return value
    }
}

private struct ComparisonCheck: Equatable {
    let property: String
    let returns: Bool
}

private func comparisonChecks(in extensionDeclaration: ExtensionDeclaration) -> [ComparisonCheck] {
    guard let comparison = extensionDeclaration.callables.first(where: { $0.name == "<" }),
        let body = comparison.body
    else {
        return []
    }

    return body.compactMap { statement in
        guard case .conditional(let branches) = statement,
            branches.count == 1,
            case .binary(let lhs, let operatorSymbol, let rhs)? = branches.first?.condition,
            operatorSymbol == .less,
            case .identifier(let lhsPath) = lhs,
            case .identifier(let rhsPath) = rhs
        else {
            return nil
        }

        if lhsPath.hasPrefix("lhs."), rhsPath.hasPrefix("rhs."),
            lhsPath.dropFirst(4) == rhsPath.dropFirst(4),
            branchReturns(branches[0], value: true)
        {
            return ComparisonCheck(property: String(lhsPath.dropFirst(4)), returns: true)
        }

        if lhsPath.hasPrefix("rhs."), rhsPath.hasPrefix("lhs."),
            lhsPath.dropFirst(4) == rhsPath.dropFirst(4),
            branchReturns(branches[0], value: false)
        {
            return ComparisonCheck(property: String(lhsPath.dropFirst(4)), returns: false)
        }

        return nil
    }
}

private func comparisonReturnsFalse(in extensionDeclaration: ExtensionDeclaration) -> Bool {
    guard let comparison = extensionDeclaration.callables.first(where: { $0.name == "<" }),
        let body = comparison.body,
        case .return(.boolean(false))? = body.last
    else {
        return false
    }

    return true
}

private func branchReturns(_ branch: StatementConditionalBranch, value: Bool) -> Bool {
    guard case .return(.boolean(value))? = branch.body.first else {
        return false
    }

    return true
}

private func allCasesReturnValues(in extensionDeclaration: ExtensionDeclaration) -> [String] {
    guard let allCases = extensionDeclaration.callables.first(where: { $0.name == "allCases" }),
        let body = allCases.body,
        case .return(.array(let cases))? = body.first
    else {
        return []
    }

    return cases.compactMap { expression in
        guard case .identifier(let name) = expression else {
            return nil
        }
        return name
    }
}

private func compile(fixture: URL, expectedRole: FixtureRole) throws -> CompiledProgram {
    var inputs = try neatCoreInputs()
    inputs.append(
        SourceInput(
            path: fixture.path,
            source: try String(contentsOf: fixture, encoding: .utf8),
            role: .project
        )
    )
    return try CompilerPipeline().buildValidated(inputs: inputs)
}

private func fixtureFiles(in suite: String) throws -> [URL] {
    let root = try repositoryRoot()
        .appendingPathComponent("NeatCompilerFixtures", isDirectory: true)
        .appendingPathComponent(suite, isDirectory: true)
    return try neatFiles(in: root, excludingExploration: false)
}

private func fixtureFile(in suite: String, path: String) throws -> URL {
    try repositoryRoot()
        .appendingPathComponent("NeatCompilerFixtures", isDirectory: true)
        .appendingPathComponent(suite, isDirectory: true)
        .appendingPathComponent(path)
}

private func neatCoreInputs() throws -> [SourceInput] {
    try neatFiles(
        in: try repositoryRoot().appendingPathComponent("NeatCore", isDirectory: true),
        excludingExploration: true
    )
    .map { file in
        SourceInput(
            path: file.path,
            source: try String(contentsOf: file, encoding: .utf8),
            role: .core
        )
    }
}

private func neatFiles(in root: URL, excludingExploration: Bool) throws -> [URL] {
    guard
        let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
    else {
        throw FixtureError.missingDirectory(root.path)
    }

    var files: [URL] = []
    while let url = enumerator.nextObject() as? URL {
        let isDirectory =
            (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        if excludingExploration,
            isDirectory,
            url.lastPathComponent == "Exploration",
            url.path.contains("/NeatCore/")
        {
            enumerator.skipDescendants()
            continue
        }

        guard !isDirectory, url.pathExtension.lowercased() == "neat" else {
            continue
        }
        files.append(url)
    }

    return files.sorted { $0.path < $1.path }
}

private func repositoryRoot() throws -> URL {
    var current = URL(fileURLWithPath: #filePath)
    while current.path != "/" {
        let candidateCore = current.appendingPathComponent("NeatCore", isDirectory: true)
        let candidateFixtures = current.appendingPathComponent(
            "NeatCompilerFixtures",
            isDirectory: true
        )
        var isCoreDirectory: ObjCBool = false
        var isFixturesDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: candidateCore.path, isDirectory: &isCoreDirectory),
            isCoreDirectory.boolValue,
            FileManager.default.fileExists(
                atPath: candidateFixtures.path,
                isDirectory: &isFixturesDirectory
            ),
            isFixturesDirectory.boolValue
        {
            return current
        }
        current.deleteLastPathComponent()
    }
    throw FixtureError.repositoryRootNotFound
}

private enum FixtureError: Error, CustomStringConvertible {
    case missingDirectory(String)
    case repositoryRootNotFound

    var description: String {
        switch self {
        case .missingDirectory(let path):
            return "Missing fixture directory at \(path)."
        case .repositoryRootNotFound:
            return "Could not find repository root."
        }
    }
}
