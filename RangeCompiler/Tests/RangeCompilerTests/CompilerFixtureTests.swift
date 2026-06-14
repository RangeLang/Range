import Foundation
import Testing

@testable import RangeCompiler

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
            path: "Macros/SyntaxProducingMacroIdentifierMemberAccess.range"
        )
        var inputs = try rangeCoreInputs()
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

    @Test("Open enum extension cases validate")
    func openEnumExtensionCasesValidate() throws {
        let fixture = try fixtureFile(
            in: "CompilePass", path: "System/OpenEnumExtensionCases.range")
        let program = try compile(fixture: fixture, expectedRole: .pass)

        let cases = program.declarationGraph.enumCases(onEnum: "EncodingFormat").map(\.name)
        #expect(cases == ["json", "binary", "urlForm"])
    }

    @Test("Closed enum extension cases fail")
    func closedEnumExtensionCasesFail() throws {
        let fixtures = [
            ("System/ClosedEnumExtensionCases.range", "Closed enum ClosedEncodingFormat"),
            (
                "System/ExplicitClosedEnumExtensionCases.range",
                "Closed enum ExplicitClosedEncodingFormat"
            ),
        ]

        for (path, expectedMessage) in fixtures {
            let fixture = try fixtureFile(in: "CompileFail", path: path)

            do {
                _ = try compile(fixture: fixture, expectedRole: .fail)
                Issue.record("Expected closed enum extension cases to fail validation.")
            } catch {
                #expect(String(describing: error).contains(expectedMessage))
            }
        }
    }

    @Test("Identifier init macro stringifies bare syntax")
    func identifierInitMacroStringifiesBareSyntax() throws {
        let fixture = try fixtureFile(in: "CompilePass", path: "Macros/IdentifierInitMacro.range")
        _ = try compile(fixture: fixture, expectedRole: .pass)
    }

    @Test("@Project macro requires a single project declaration")
    func projectMacroRequiresSingleProjectDeclaration() throws {
        let inputs = [
            SourceInput(
                path: "/tmp/DuplicateProjects.range",
                source: """
                    open macro Project(): Construct -> Void { target, diagnostics, graph in
                        let projectMacros: Array<Macro.Application>(
                            graph.macros.where { entry in
                                entry.identifier.name == "Project"
                            }
                        )
                        if projectMacros.count > 1 {
                            diagnostics.error("A second @Project conflicts with the project already declared in this Range project.")
                        }
                    }

                    construct Identifier {
                        let name: String
                    }

                    @Project
                    construct FirstProject {
                    }

                    @Project
                    construct SecondProject {
                    }
                    """,
                role: .project
            )
        ]
        let diagnostics = CompilerPipeline().diagnostics(inputs: inputs)
        #expect(
            diagnostics.contains {
                $0.severity == .error
                    && $0.source == "range-macro"
                    && $0.message.contains("A second @Project conflicts")
            }
        )
    }

    @Test("Construct macro target carries localized syntax body")
    func constructMacroTargetCarriesLocalizedSyntaxBody() throws {
        let projectPath = "/tmp/MacroTargetWrittenSource.range"
        var inputs = try rangeCoreInputs()
        inputs.append(
            SourceInput(
                path: projectPath,
                source: """
                    macro reportBody(): Construct { target, diagnostics in
                        diagnostics.warning(target.body.text)
                    }

                    @reportBody
                    construct SourceReadable {
                        let value: Int
                    }
                    """,
                role: .project
            )
        )

        let diagnostics = CompilerPipeline().diagnostics(inputs: inputs)
        let diagnostic = try #require(
            diagnostics.first {
                $0.severity == .warning
                    && $0.source == "range-macro"
                    && $0.code == "macro.diagnostic.warning"
                    && $0.message.contains("@reportBody")
                    && $0.message.contains("construct SourceReadable")
                    && $0.message.contains("let value: Int")
                    && $0.path == projectPath
            }
        )
        #expect(diagnostic.message.contains("target.body") == false)
    }

    @Test("User macro diagnostics feed compiler diagnostics")
    func userMacroDiagnosticsFeedCompilerDiagnostics() throws {
        let fixture = try fixtureFile(
            in: "CompilePass",
            path: "Macros/MacroDiagnosticsWarning.range"
        )
        var inputs = try rangeCoreInputs()
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
                    && $0.source == "range-macro"
                    && $0.code == "macro.diagnostic.warning"
                    && $0.message == "custom macro warning"
                    && $0.path == fixture.path
            }
        )
        #expect(
            diagnostics.contains {
                $0.severity == .information
                    && $0.source == "range-macro"
                    && $0.code == "macro.diagnostic.information"
                    && $0.message == "custom macro information"
                    && $0.path == fixture.path
            }
        )
        #expect(
            diagnostics.contains {
                $0.severity == .hint
                    && $0.source == "range-macro"
                    && $0.code == "macro.diagnostic.hint"
                    && $0.message == "custom macro hint"
                    && $0.path == fixture.path
            }
        )
    }

    @Test("Init forwarded property macro exposes nested initializer")
    func initForwardedPropertyMacroExposesNestedInitializer() throws {
        let fixture = try fixtureFile(in: "CompilePass", path: "Macros/InitForwarded.range")
        _ = try compile(fixture: fixture, expectedRole: .pass)
    }

    @Test("Macro metadata queries graph through identities")
    func macroMetadataQueriesGraphThroughIdentities() throws {
        let source = """
            @tracked("root")
            construct User {
                @tracked("name")
                let name: String
                let age: Int

                function displayName(): String {
                    return name
                }

                construct Nested {
                    let value: Int
                }
            }
            """
        var parser = try Parser(source: source)
        let sourceFile = try parser.parseSourceFile()
        guard case .construct(let construct) = sourceFile else {
            Issue.record("Expected construct.")
            return
        }
        let graph = DeclarationGraph(
            files: [
                ParsedSourceFile(
                    path: "/tmp/MacroGraphIdentity.range",
                    source: source,
                    sourceFile: sourceFile
                )
            ]
        )
        let trackedMacro = MacroDeclaration(
            packageVisibility: .open,
            name: "tracked",
            genericParameters: [],
            parameters: [],
            target: .macroSurface("syntax"),
            expansionType: nil,
            bindings: nil,
            body: [.return(.string("macro body"))],
            syntaxBody: nil
        )
        let context = graph.macroExpansionContext(macrosByName: ["tracked": trackedMacro])
        let propertyTargetKinds = macroTargetKinds(
            for: .macroSurface("property"),
            syntaxResolver: context.rewriteSurfaceView.syntaxResolver
        )
        #expect(propertyTargetKinds == [.property])
        let target = MacroTargetValueBuilder().targetValue(for: construct)
        let evaluator = CompileTimeValueEvaluator(
            targetBinding: "target",
            targetValue: target,
            graphBinding: "graph",
            localBindings: [:],
            context: context
        )

        guard
            case .string("User")? = evaluator.evaluate(
                Expression.identifier("target.identity.name")
            )
        else {
            Issue.record("Expected target.identity.name to resolve.")
            return
        }

        let members = try #require(
            evaluator.evaluate(
                Expression.call(
                    name: "graph.members",
                    arguments: [
                        CallArgument(label: "of", value: .identifier("target.identity"))
                    ]
                )
            )
        )
        guard case .array(let memberIdentities) = members else {
            Issue.record("Expected graph.members(of:) to return identity array.")
            return
        }
        #expect(memberIdentities.count == 4)
        guard case .object("GraphIdentity", let firstMemberFields)? = memberIdentities.first,
            case .string("let:User.name")? = firstMemberFields["id"]
        else {
            Issue.record("Expected first member identity to describe User.name.")
            return
        }

        let parent = try #require(
            evaluator.evaluate(
                Expression.call(
                    name: "graph.parent",
                    arguments: [
                        CallArgument(label: "of", value: memberIdentities[0].expression!)
                    ]
                )
            )
        )
        guard case .object("GraphIdentity", let parentFields) = parent,
            case .string("construct:User")? = parentFields["id"],
            case .string("User")? = parentFields["name"]
        else {
            Issue.record("Expected graph.parent(of:) to resolve User.name back to User.")
            return
        }

        let attachedMacros = try #require(
            evaluator.evaluate(
                Expression.call(
                    name: "graph.macros",
                    arguments: [
                        CallArgument(label: "on", value: .identifier("target.identity"))
                    ]
                )
            )
        )
        guard case .array(let targetMacros) = attachedMacros else {
            Issue.record("Expected graph.macros(on:) to return macro application array.")
            return
        }
        #expect(targetMacros.count == 1)
        guard let macroDeclaration = targetMacros.first?.field("declaration") else {
            Issue.record("Expected attached macro to carry declaration metadata.")
            return
        }
        guard case .string("return \"macro body\"")? = macroDeclaration.field("body") else {
            Issue.record("Expected attached macro declaration body to be readable.")
            return
        }
        guard
            case .object("Macro.Target", let targetFields)? = macroDeclaration.field("target"),
            case .string("macroSurface")? = targetFields["kind"],
            case .string("syntax")? = targetFields["name"]
        else {
            Issue.record("Expected attached macro declaration target to be a metaobject.")
            return
        }
        guard
            case .object("WrittenSyntax", let writtenFields)? = macroDeclaration.field(
                "writtenBody"),
            case .string("return \"macro body\"")? = writtenFields["text"]
        else {
            Issue.record("Expected attached macro written body to carry authored text.")
            return
        }
        guard case .object("Parsed", let parsedFields)? = macroDeclaration.field("parsedBody"),
            case .object("Block", let blockFields)? = parsedFields["value"],
            case .array(let statements)? = blockFields["statements"]
        else {
            Issue.record("Expected attached macro parsed body to carry a block metaobject.")
            return
        }
        #expect(statements.count == 1)

        let targetDeclaration = try #require(target.field("declaration"))
        guard case .array(let memberIdentities)? = targetDeclaration.field("members") else {
            Issue.record("Expected construct declaration to expose unified members.")
            return
        }
        #expect(memberIdentities.count == 4)
        let memberIDs: [String] = memberIdentities.compactMap {
            guard case .object("GraphIdentity", let fields) = $0,
                case .string(let id)? = fields["id"]
            else {
                return nil
            }
            return id
        }
        #expect(
            memberIDs == [
                "let:User.name",
                "let:User.age",
                "function:User.displayName",
                "construct:User.Nested",
            ])

        let functionDeclaration = try #require(
            evaluator.evaluate(
                Expression.call(
                    name: "graph.declaration",
                    arguments: [CallArgument(label: nil, value: memberIdentities[2].expression!)]
                )
            )
        )
        #expect(functionDeclaration.field("identifier") != nil)
        #expect(functionDeclaration.field("parent") != nil)

        let nestedParent = try #require(
            evaluator.evaluate(
                Expression.call(
                    name: "graph.parent",
                    arguments: [CallArgument(label: "of", value: memberIdentities[3].expression!)]
                )
            )
        )
        guard case .object("GraphIdentity", let nestedParentFields) = nestedParent,
            case .string("construct:User")? = nestedParentFields["id"]
        else {
            Issue.record("Expected graph.parent(of:) to resolve nested construct members.")
            return
        }

        let namedMacros = try #require(
            evaluator.evaluate(
                Expression.call(
                    name: "graph.macros",
                    arguments: [
                        CallArgument(label: "named", value: .string("tracked"))
                    ]
                )
            )
        )
        guard case .array(let trackedMacros) = namedMacros else {
            Issue.record("Expected graph.macros(named:) to return macro application array.")
            return
        }
        #expect(trackedMacros.count == 2)

        let declaration = try #require(
            evaluator.evaluate(
                Expression.call(
                    name: "graph.declaration",
                    arguments: [CallArgument(label: nil, value: memberIdentities[0].expression!)]
                )
            )
        )
        #expect(declaration.field("identifier") != nil)
        #expect(declaration.field("parent") != nil)

        var inputs = try rangeCoreInputs()
        inputs.append(
            SourceInput(
                path: "/tmp/MacroGraphExpansion.range",
                source: """
                    macro graphNamed(): Construct { target, diagnostics, graph in
                        let declaration: Construct.Declaration(graph.declaration(target.identity))
                        target.declaration.expand {
                            extension #(declaration.self) {
                                function graphName(): String {
                                    return "User"
                                }
                            }
                        }
                    }

                    @graphNamed
                    construct User {
                        let name: String
                    }
                    """,
                role: .project
            )
        )

        let program = try CompilerPipeline().buildValidated(inputs: inputs)
        #expect(
            program.declarationGraph.extensionsByTargetName["User"]?.contains {
                $0.callables.contains { $0.name == "graphName" }
            } == true
        )
    }

    @Test("WrittenSyntax macro isolates raw ASCII body")
    func writtenSyntaxMacroIsolatesRawASCIIBody() throws {
        var inputs = try rangeCoreInputs()
        inputs.append(
            SourceInput(
                path: "/tmp/WrittenSyntaxMacro.range",
                source: """
                    @WrittenSyntax {
                    function this is not parsed -> nope
                    @@@ raw ascii stays isolated
                    }
                    construct User {
                        let name: String
                    }
                    """,
                role: .project
            )
        )

        let program = try CompilerPipeline().buildValidated(inputs: inputs)
        let construct = try #require(program.declarationGraph.constructsByName["User"])
        #expect(construct.macros.map(\.name) == ["WrittenSyntax"])
    }

    @Test("Macros query graph through identities")
    func macrosQueryGraphThroughIdentities() throws {
        var inputs = try rangeCoreInputs()
        inputs.append(
            SourceInput(
                path: "/tmp/MacroGraphIdentity.range",
                source: """
                    macro graphName(): Construct -> String { target, diagnostics, graph in
                        let declaration: Construct.Declaration(graph.declaration(target.identity))
                        return declaration.self.name
                    }

                    @graphName
                    construct User {
                        let name: String
                    }
                    """,
                role: .project
            )
        )

        _ = try CompilerPipeline().buildValidated(inputs: inputs)
    }

    @Test("Extension macros evaluate against extension target")
    func extensionMacrosEvaluateAgainstExtensionTarget() throws {
        var inputs = try rangeCoreInputs()
        inputs.append(
            SourceInput(
                path: "/tmp/ExtensionMacro.range",
                source: """
                    macro extensionTargetName(): Extension -> String { target, diagnostics in
                        return target.target.name
                    }

                    construct User {
                        let name: String
                    }

                    @extensionTargetName
                    extension User {
                        function displayName(): String {
                            return name
                        }
                    }
                    """,
                role: .project
            )
        )

        let program = try CompilerPipeline().buildValidated(inputs: inputs)
        let extensionDeclaration = try #require(
            program.declarationGraph.extensionsByTargetName["User"]?.first
        )
        #expect(extensionDeclaration.macros.map(\.name) == ["extensionTargetName"])
    }

    @Test("Extension macros reject non-extension targets")
    func extensionMacrosRejectNonExtensionTargets() throws {
        var inputs = try rangeCoreInputs()
        inputs.append(
            SourceInput(
                path: "/tmp/InvalidExtensionMacro.range",
                source: """
                    macro constructOnly(): Construct -> String { target, diagnostics in
                        return target.declaration.self.name
                    }

                    construct User {
                        let name: String
                    }

                    @constructOnly
                    extension User {
                        function displayName(): String {
                            return name
                        }
                    }
                    """,
                role: .project
            )
        )

        do {
            _ = try CompilerPipeline().buildValidated(inputs: inputs)
            Issue.record("Expected construct macro on extension to fail validation.")
        } catch {
            #expect(
                String(describing: error).contains("used on an extension but targets Construct"))
        }
    }

    @Test("Parser diagnostics point at invalid hash syntax")
    func parserDiagnosticsPointAtInvalidHashSyntax() throws {
        let projectPath = "/tmp/InvalidHashMacro.range"
        var inputs = try rangeCoreInputs()
        inputs.append(
            SourceInput(
                path: projectPath,
                source: """
                    function bad(): Int {
                        return #(]
                    }
                    """,
                role: .project
            )
        )

        let diagnostics = CompilerPipeline().diagnostics(inputs: inputs)
        _ = try #require(
            diagnostics.first {
                String(describing: $0).contains("Expected expression.")
            }
        )
    }

    @Test("Function declarations reject arrow return syntax")
    func functionDeclarationsRejectArrowReturnSyntax() throws {
        let projectPath = "/tmp/FunctionArrowReturn.range"
        var inputs = try rangeCoreInputs()
        inputs.append(
            SourceInput(
                path: projectPath,
                source: """
                    function passthrough(value: Int) -> Int {
                        return value
                    }
                    """,
                role: .project
            )
        )

        let diagnostics = CompilerPipeline().diagnostics(inputs: inputs)
        let diagnostic = try #require(
            diagnostics.first {
                $0.message == "Function return type clause must be ': ReturnType'."
                    && $0.source == "range-parser"
                    && $0.path == projectPath
            }
        )

        #expect(diagnostic.range?.start.line == 0)
        #expect(diagnostic.range?.start.character == 33)
    }

    @Test("Project source cannot declare initializers")
    func projectSourceCannotDeclareInitializers() throws {
        let projectPath = "/tmp/InitializerSyntax.range"
        var inputs = try rangeCoreInputs()
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
                $0.source == "range-parser"
                    && $0.path == projectPath
                    && $0.message.contains("Initializer declarations are no longer source syntax")
            }
        )
    }

    @Test("Construct applications bind directly to stored declarations")
    func constructApplicationsBindDirectlyToStoredDeclarations() throws {
        var inputs = try rangeCoreInputs()
        inputs.append(
            SourceInput(
                path: "/tmp/DirectConstructApplication.range",
                source: """
                    construct User {
                        let id: Int
                        let name: String
                    }

                    @main {
                        let user: User(id: 1, name: "George")
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
                let count: Optional<Int>(5)
                let widgetCount: Optional<WidgetCount>(value: 0.1)
                state current: Optional<Int>(5)
            }

            @main {
                let local: Optional<Int>(5)
            }
            """

        var parser = try Parser(source: source)
        let file = try parser.parseSourceFile()

        guard case .module(let module) = file else {
            Issue.record("Expected module.")
            return
        }
        let counter = try #require(module.constructs.first(where: { $0.name == "Counter" }))

        var inputs = try rangeCoreInputs()
        inputs.append(
            SourceInput(
                path: "/tmp/TypedConstructionOptional.range",
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

        var validInputs = try rangeCoreInputs()
        validInputs.append(
            SourceInput(
                path: "/tmp/TypedChannelDeclaration.range",
                source: validSource,
                role: .project
            )
        )
        _ = try CompilerPipeline().buildValidated(inputs: validInputs)

        let invalidPath = "/tmp/AssignmentShapedTypeConstruction.range"
        var invalidInputs = try rangeCoreInputs()
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
                    && $0.message.contains("expects declaration initialization after ':'")
            }
        )
    }

    @Test("Local declarations require colon before initializer")
    func localDeclarationsRequireColonBeforeInitializer() throws {
        let projectPath = "/tmp/LocalDeclarationMissingColon.range"
        var inputs = try rangeCoreInputs()
        inputs.append(
            SourceInput(
                path: projectPath,
                source: """
                    @main {
                        state cursor   LexerCursor(source: "", foreignBodies: [], rules: [])
                    }
                    """,
                role: .project
            )
        )

        let diagnostics = CompilerPipeline().diagnostics(inputs: inputs)
        #expect(
            diagnostics.contains {
                $0.path == projectPath
                    && $0.message.contains("state 'cursor' expects typed construction")
            }
        )
    }

    @Test("Construct applications reject labels with no stored declaration")
    func constructApplicationsRejectLabelsWithNoStoredDeclaration() throws {
        let projectPath = "/tmp/DirectConstructApplicationBadLabel.range"
        var inputs = try rangeCoreInputs()
        inputs.append(
            SourceInput(
                path: projectPath,
                source: """
                    construct User {
                        let id: Int
                        let name: String
                    }

                    @main {
                        let user: User(identifier: 1, name: "George")
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

    @Test("Metadata slot macros declare semantic slots")
    func metadataSlotMacrosDeclareSemanticSlots() throws {
        var inputs = try rangeCoreInputs()
        inputs.append(
            SourceInput(
                path: "/tmp/MetadataSlot.range",
                source: """
                    macro styling(): Construct -> Void { target, diagnostics in
                    }

                    @styling
                    construct Panel {
                        let title: String
                    }
                    """,
                role: .project
            )
        )

        let program = try CompilerPipeline().buildValidated(inputs: inputs)
        let graph = program.declarationGraph
        #expect(graph.macroMetadataByName["styling"]?.hasMetadataSlotEffect == true)
        #expect(graph.constructsByName["Panel"]?.macros.contains { $0.name == "styling" } == true)
    }

    @Test("Metadata slot macros keep targets as declarations")
    func metadataSlotMacrosKeepTargetsAsDeclarations() throws {
        var inputs = try rangeCoreInputs()
        inputs.append(
            SourceInput(
                path: "/tmp/MetadataSlotTarget.range",
                source: """
                    macro persisted(prefix: String): Construct -> Void { target, diagnostics in
                    }

                    @persisted(prefix: "settings")
                    construct Profile {
                        let displayName: String
                    }
                    """,
                role: .project
            )
        )

        let program = try CompilerPipeline().buildValidated(inputs: inputs)
        let profile = try #require(program.declarationGraph.constructsByName["Profile"])
        #expect(profile.macros.map(\.name) == ["persisted"])
        #expect(profile.macros.first?.argumentClause == #"prefix : "settings""#)
    }

    @Test("Macro metadata values construct declared object tags")
    func macroMetadataValuesConstructDeclaredObjectTags() throws {
        var inputs = try rangeCoreInputs()
        inputs.append(
            SourceInput(
                path: "/tmp/MacroMetadataObjectTag.range",
                source: """
                    construct TagProofBehavior {
                        let key: String?
                        let exclude: Bool
                    }

                    macro tagProof<T>(key: String? = nil, exclude: Bool = false): Let<T> -> TagProofBehavior { target, diagnostics in
                        return TagProofBehavior(key: key ?? self.identifier.name, exclude: self.identifier != self.identifier)
                    }

                    macro selfFiltered(): Construct { target, diagnostics, graph in
                        let graphApplications: Array<Macro.Application>(
                            graph.macros(named: self.name)
                        )
                        let namedApplications: Array<Macro.Application>(
                            graphApplications.filter { application in
                                application.name == self.name
                            }
                        )
                        let ownApplications: Array<Macro.Application>(
                            namedApplications.filter { application in
                                application.identifier == self.identifier
                            }
                        )
                        if ownApplications.count != 1 {
                            diagnostics.error("Expected self-filtered macro application.")
                        }

                        target.declaration.expand {
                            extension #(target.declaration.self) {
                                function selfFilteredMacroCount(): Int {
                                    return #(ownApplications.count)
                                }
                            }
                        }
                    }

                    @selfFiltered
                    construct Profile {
                        @tagProof(key: "id")
                        let userId: Int
                    }
                    """,
                role: .project
            )
        )

        let program = try CompilerPipeline().buildValidated(inputs: inputs)
        let macrosByName = MacroExpander.collectMacroDeclarations(from: program.parsedFiles)
        let metadataByName = MacroExpander.collectMacroMetadata(from: program.parsedFiles)
        let context = program.declarationGraph.macroExpansionContext(
            macrosByName: macrosByName,
            macroMetadataDeclarationsByName: metadataByName
        )
        let userId = MacroTargetValueBuilder().graphIdentity(kind: "let", name: "Profile.userId")
        let macros = try #require(context.graphContext.macros(on: userId))

        guard case .array(let applications) = macros,
            case .object("Macro.Application", let fields)? = applications.first,
            case .object("TagProofBehavior", let valueFields)? = fields["value"]
        else {
            Issue.record("Expected @tagProof metadata to carry a TagProofBehavior object tag.")
            return
        }
        guard case .string("id")? = valueFields["key"],
            case .boolean(false)? = valueFields["exclude"]
        else {
            Issue.record("Expected TagProofBehavior fields to preserve @tagProof arguments.")
            return
        }
    }

    @Test("Package manifests collect package metadata")
    func packageManifestsCollectPackageMetadata() throws {
        var inputs = try rangeCoreInputs()
        inputs.append(
            SourceInput(
                path: "/tmp/PackageManifest.range",
                source: """
                    @package
                    construct Project {
                        let name: Title("Example")
                        let version: Version(0.1.0)
                        let author: "George"
                        let modules: ["acme/logger"]
                    }
                    """,
                role: .project
            )
        )

        let program = try CompilerPipeline().build(inputs: inputs)
        #expect(program.declarationGraph.packageValues(named: "name").count == 1)
        #expect(program.declarationGraph.packageValues(named: "version").count == 1)
        #expect(program.declarationGraph.packageValues(named: "author").count == 1)
    }

    @Test("Unknown attributes reject non-built-in spelling")
    func unknownAttributesRejectNonBuiltinSpelling() throws {
        var inputs = try rangeCoreInputs()
        inputs.append(
            SourceInput(
                path: "/tmp/UnknownAttribute.range",
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
            Issue.record("Expected @Missing to be rejected.")
        } catch {
            #expect(String(describing: error).contains("Unknown attached macro @Missing"))
        }
    }

    @Test("Project macros infer across project files")
    func projectMacrosInferAcrossProjectFiles() throws {
        var inputs = try rangeCoreInputs()
        inputs.append(
            SourceInput(
                path: "/tmp/ProjectMacros.range",
                source: """
                    macro styling(): Construct -> Void { target, diagnostics in
                    }
                    """,
                role: .project
            )
        )
        inputs.append(
            SourceInput(
                path: "/tmp/ProjectMain.range",
                source: """
                    @main {
                        let panel: Panel()
                    }

                    @styling
                    construct Panel {
                    }
                    """,
                role: .project
            )
        )

        _ = try CompilerPipeline().buildValidated(inputs: inputs)
    }

    @Test("Project callables and macros infer before later declarations")
    func projectDeclarationsInferBeforeLaterDeclarations() throws {
        var inputs = try rangeCoreInputs()
        inputs.append(
            SourceInput(
                path: "/tmp/ForwardDeclarations.range",
                source: """
                    @main {
                        let messageText: message()
                        let panel: Panel()
                    }

                    function message(): String {
                        return "Hello"
                    }

                    @styling
                    construct Panel {
                    }

                    macro styling(): Construct -> Void { target, diagnostics in
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
        let program = try CompilerPipeline().build(inputs: rangeCoreInputs())
        let graph = program.declarationGraph

        #expect(graph.constructsByName["Construct"] != nil)
        #expect(graph.constructsByName["Construct.Application"] != nil)
        #expect(
            graph.constructsByName["Construct"]?.macros.contains { $0.name == "syntax" } == true)
        #expect(
            graph.constructsByName["Construct.Declaration"]?.macros.contains { $0.name == "syntax" }
                == false)
        #expect(
            graph.constructsByName["Construct.Declaration"]?.macros.contains {
                $0.name == "graph" && $0.argumentClause == "role : . declaration"
            } == true)
        #expect(
            graph.constructsByName["Construct.Application"]?.macros.contains { $0.name == "syntax" }
                == false)
        #expect(
            graph.constructsByName["Construct.Application"]?.macros.contains {
                $0.name == "graph" && $0.argumentClause == "role : . application"
            } == true)
        #expect(graph.constructsByName["Macro"]?.macros.contains { $0.name == "syntax" } == true)
        #expect(
            graph.constructsByName["Macro.Declaration"]?.macros.contains { $0.name == "syntax" }
                == false)
        #expect(
            graph.constructsByName["Macro.Declaration"]?.macros.contains {
                $0.name == "graph" && $0.argumentClause == "role : . declaration"
            } == true)
        #expect(
            graph.constructsByName["Macro.Application"]?.macros.contains { $0.name == "syntax" }
                == false)
        #expect(
            graph.constructsByName["Macro.Application"]?.macros.contains {
                $0.name == "graph" && $0.argumentClause == "role : . application"
            } == true)
    }

    @Test("@syntax graph projection contains declaration and application surfaces")
    func syntaxGraphProjectionContainsDeclarationAndApplicationSurfaces() throws {
        let program = try CompilerPipeline().build(inputs: rangeCoreInputs())
        let syntax = program.programGraph.syntax

        let constructSyntax = try #require(
            syntax.first { $0.identity.label == "Construct" }
        )
        #expect(constructSyntax.declarations.map(\.label) == ["Declaration"])
        #expect(constructSyntax.applications.map(\.label) == ["Application"])
    }

    @Test("@syntax declarations are syntax-facing through metadata")
    func syntaxDeclarationsAreSyntaxFacingThroughMetadata() throws {
        let program = try CompilerPipeline().build(inputs: rangeCoreInputs())
        let graph = program.declarationGraph

        #expect(graph.constructsByName["Expression"]?.isCore == true)
        #expect(graph.syntaxResolver.typeConformsToSyntax(.named("Expression")))
        #expect(graph.syntaxResolver.syntaxTypeName(forSurface: "block") == "Block")
        #expect(graph.syntaxResolver.type(.named("Block"), matchesSyntaxSurface: "block"))
    }

    @Test("Token metadata reads delimiter macros")
    func tokenMetadataReadsDelimiterMacros() throws {
        let program = try CompilerPipeline().build(inputs: rangeCoreInputs())
        let tokens = program.declarationGraph.tokenMetadataConcepts
        let delimiters = program.declarationGraph.tokenDelimiterConcepts
        let lexerRepresentations = program.declarationGraph.lexerRepresentationConcepts

        #expect(
            tokens.contains(
                TokenMetadataConcept(
                    token: "LeftBracket",
                    pattern: "[",
                    delimiter: TokenDelimiterConcept(
                        token: "LeftBracket",
                        role: .prefix,
                        pairedToken: "RightBracket"
                    ),
                    operatorBinding: nil
                )
            )
        )
        #expect(
            tokens.contains(
                TokenMetadataConcept(
                    token: "Comma",
                    pattern: ",",
                    delimiter: nil,
                    operatorBinding: nil
                )
            )
        )
        #expect(
            lexerRepresentations.contains(
                LexerRepresentationConcept(
                    token: "Whitespace",
                    pattern: " ",
                    option: .skip,
                    delimiter: nil,
                    operatorBinding: nil
                )
            )
        )
        #expect(
            lexerRepresentations.contains(
                LexerRepresentationConcept(
                    token: "Comma",
                    pattern: ",",
                    option: .emit,
                    delimiter: nil,
                    operatorBinding: nil
                )
            )
        )
        #expect(
            lexerRepresentations.contains(
                LexerRepresentationConcept(
                    token: "LeftBracket",
                    pattern: "[",
                    option: .emit,
                    delimiter: TokenDelimiterConcept(
                        token: "LeftBracket",
                        role: .prefix,
                        pairedToken: "RightBracket"
                    ),
                    operatorBinding: nil
                )
            )
        )
        #expect(
            delimiters.contains(
                TokenDelimiterConcept(
                    token: "LeftBrace",
                    role: .prefix,
                    pairedToken: "RightBrace"
                )
            )
        )
        #expect(
            delimiters.contains(
                TokenDelimiterConcept(
                    token: "LeftParen",
                    role: .prefix,
                    pairedToken: "RightParen"
                )
            )
        )
        #expect(
            delimiters.contains(
                TokenDelimiterConcept(
                    token: "LeftBracket",
                    role: .prefix,
                    pairedToken: "RightBracket"
                )
            )
        )
        #expect(
            delimiters.contains(
                TokenDelimiterConcept(
                    token: "RightBracket",
                    role: .postfix,
                    pairedToken: "LeftBracket"
                )
            )
        )
    }

    @Test("Token metadata reads operator binding ranges")
    func tokenMetadataReadsOperatorBindingRanges() throws {
        let program = try CompilerPipeline().build(inputs: rangeCoreInputs())
        let operators = program.declarationGraph.tokenOperatorConcepts

        #expect(
            operators.contains(
                TokenOperatorConcept(
                    token: "Asterisk",
                    fixity: .infix,
                    binding: TokenOperatorBindingRange(lower: 70, upper: 80),
                    step: 10,
                    delta: -10,
                    signage: "negative",
                    associativity: .left
                )
            )
        )
        #expect(
            operators.contains(
                TokenOperatorConcept(
                    token: "Bang",
                    fixity: .prefix,
                    binding: TokenOperatorBindingRange(lower: 90, upper: 100),
                    step: 10,
                    delta: -10,
                    signage: "negative",
                    associativity: .none
                )
            )
        )
        #expect(
            operators.contains(
                TokenOperatorConcept(
                    token: "QuestionQuestion",
                    fixity: .infix,
                    binding: TokenOperatorBindingRange(lower: 50, upper: 60),
                    step: 10,
                    delta: -10,
                    signage: "negative",
                    associativity: .right
                )
            )
        )
        #expect(
            operators.contains(
                TokenOperatorConcept(
                    token: "Plus",
                    fixity: .infix,
                    binding: TokenOperatorBindingRange(lower: 60, upper: 70),
                    step: 10,
                    delta: -10,
                    signage: "negative",
                    associativity: .left
                )
            )
        )
        #expect(
            operators.contains(
                TokenOperatorConcept(
                    token: "Minus",
                    fixity: .infix,
                    binding: TokenOperatorBindingRange(lower: 60, upper: 70),
                    step: 10,
                    delta: -10,
                    signage: "negative",
                    associativity: .left
                )
            )
        )
        for comparisonToken in [
            "BangEqual", "EqualEqual", "Less", "LessEqual", "Greater", "GreaterEqual",
        ] {
            #expect(
                operators.contains(
                    TokenOperatorConcept(
                        token: comparisonToken,
                        fixity: .infix,
                        binding: TokenOperatorBindingRange(lower: 40, upper: 50),
                        step: 10,
                        delta: -10,
                        signage: "negative",
                        associativity: .none
                    )
                )
            )
        }
        #expect(
            program.declarationGraph.lexerRepresentationConcepts.contains(
                LexerRepresentationConcept(
                    token: "Plus",
                    pattern: "+",
                    option: .emit,
                    delimiter: nil,
                    operatorBinding: TokenOperatorConcept(
                        token: "Plus",
                        fixity: .infix,
                        binding: TokenOperatorBindingRange(lower: 60, upper: 70),
                        step: 10,
                        delta: -10,
                        signage: "negative",
                        associativity: .left
                    )
                )
            )
        )
        #expect(
            program.declarationGraph.lexerRepresentationConcepts.contains(
                LexerRepresentationConcept(
                    token: "Minus",
                    pattern: "-",
                    option: .emit,
                    delimiter: nil,
                    operatorBinding: TokenOperatorConcept(
                        token: "Minus",
                        fixity: .infix,
                        binding: TokenOperatorBindingRange(lower: 60, upper: 70),
                        step: 10,
                        delta: -10,
                        signage: "negative",
                        associativity: .left
                    )
                )
            )
        )
    }

    @Test("Range formation operators parse as binary expressions")
    func rangeFormationOperatorsParseAsBinaryExpressions() throws {
        var halfOpenParser = try Parser(source: "0..<limit")
        let halfOpen = try halfOpenParser.parseExpression()
        guard case .binary(.integer(0), .rangeUntil, .identifier("limit")) = halfOpen else {
            Issue.record("Expected half-open range formation to parse as a binary expression.")
            return
        }

        var closedParser = try Parser(source: "0...limit")
        let closed = try closedParser.parseExpression()
        guard case .binary(.integer(0), .closedRange, .identifier("limit")) = closed else {
            Issue.record("Expected closed range formation to parse as a binary expression.")
            return
        }
    }

    @Test("Range formation operators validate through RangeCore")
    func rangeFormationOperatorsValidateThroughRangeCore() throws {
        var inputs = try rangeCoreInputs()
        inputs.append(
            SourceInput(
                path: "/tmp/RangeFormationOperators.range",
                source: """
                    function halfOpen(limit: Int): Range<Int> {
                        return 0..<limit
                    }

                    function closed(limit: Int): ClosedRange<Int> {
                        return 0...limit
                    }
                    """,
                role: .project
            )
        )

        _ = try CompilerPipeline().buildValidated(inputs: inputs)
    }

    @Test("Precedence metadata records binding ranges")
    func precedenceMetadataRecordsBindingRanges() throws {
        let program = try CompilerPipeline().build(inputs: rangeCoreInputs())
        let precedence = program.declarationGraph.precedenceMetadataConcepts

        #expect(
            precedence.contains(
                PrecedenceMetadataConcept(
                    name: "AdditionPrecedence",
                    associativity: .left,
                    higherThan: ["NilCoalescingPrecedence"],
                    lowerThan: [],
                    assignment: nil,
                    step: 10,
                    binding: TokenOperatorBindingRange(lower: 50, upper: 60)
                )
            )
        )
        #expect(
            precedence.contains(
                PrecedenceMetadataConcept(
                    name: "MultiplicationPrecedence",
                    associativity: .left,
                    higherThan: ["AdditionPrecedence"],
                    lowerThan: [],
                    assignment: nil,
                    step: 10,
                    binding: TokenOperatorBindingRange(lower: 60, upper: 70)
                )
            )
        )
    }

    @Test("Declaration graph carries source locations")
    func declarationGraphCarriesSourceLocations() throws {
        let source = """
            macro codable(): Construct { target, diagnostics in
            }

            macro codingKey<T>(value: String): Let<T> -> String { target, diagnostics in
                return value
            }

            construct User {
            }

            function makeUser(): User {
                return User()
            }
            """
        let program = try CompilerPipeline().build(inputs: [
            SourceInput(path: "/tmp/GraphLocations.range", source: source, role: .project)
        ])
        let graph = program.declarationGraph

        let construct = graph.sourceLocation(named: "User", kinds: [.type])
        let macro = graph.sourceLocation(named: "codable", kinds: [.macro])
        let codingKeyMacro = graph.sourceLocation(named: "codingKey", kinds: [.macro])
        let function = graph.sourceLocation(named: "makeUser", kinds: [.function])

        #expect(construct?.path == "/tmp/GraphLocations.range")
        #expect(construct?.range.start.line == 7)
        #expect(construct?.range.start.character == 10)
        #expect(macro?.range.start.line == 0)
        #expect(codingKeyMacro?.range.start.line == 3)
        #expect(function?.range.start.line == 10)
    }

    @Test("Declaration graph registry snapshot covers current query facts")
    func declarationGraphRegistrySnapshotCoversCurrentQueryFacts() throws {
        var inputs = try rangeCoreInputs()
        inputs.append(
            SourceInput(
                path: "/tmp/DeclarationGraphRegistrySnapshot.range",
                source: """
                    @package
                    construct Project {
                        let packageName: String("Registry Snapshot")
                        let modules: ["acme/registry-snapshot"]
                    }

                    macro styling(): Construct -> Void { target, diagnostics in
                    }

                    macro hostSpace(): Construct -> Void { target, diagnostics in
                    }

                    macro decorate(): Construct { target, diagnostics in
                    }

                    enum DisplayMode {
                        case compact
                        case expanded
                    }

                    state globalCount: Int(0)

                    construct Address {
                        let street: String
                    }

                    @styling
                    @graph
                    construct Panel {
                        state count: Int(0)
                        binding selected: Bool {
                            get {
                                return true
                            }

                            set {
                            }
                        }
                        derived label: String {
                            return title
                        }
                        let title: String
                        let address: Address

                        function render(title: String): String {
                            return title
                        }

                        function configure(value: Int, name: String): String {
                            return name
                        }

                        construct Nested {
                            let value: Int
                        }
                    }

                    extension Panel {
                        function reset() {
                        }

                        enum ExtensionMode {
                            case reset
                        }
                    }

                    @hostSpace
                    construct Routes {
                        function home(): String {
                            return "home"
                        }
                    }
                    """,
                role: .project
            )
        )

        let program = try CompilerPipeline().buildValidated(inputs: inputs)
        let graph = program.declarationGraph
        let registry = graph.registryView

        #expect(registry.construct(named: "Panel") != nil)
        #expect(registry.construct(named: "Panel.Nested") != nil)
        #expect(registry.construct(named: "Routes") != nil)
        #expect(registry.hasEnumeration(named: "DisplayMode"))
        #expect(registry.hasMacro(named: "decorate"))
        #expect(graph.constructsByName["Panel"]?.macros.contains { $0.name == "graph" } == true)
        #expect(graph.macroMetadataByName["hostSpace"]?.hasMetadataSlotEffect == true)
        #expect(registry.hasExtensions(targeting: "Panel"))
        #expect(graph.packageValues(named: "packageName").count == 1)
        #expect(
            graph.topLevelStates(inFilePath: "/tmp/DeclarationGraphRegistrySnapshot.range")
                .map(\.name) == ["globalCount"])

        #expect(registry.states(onConstruct: "Panel").map(\.name) == ["count"])
        #expect(registry.bindings(onConstruct: "Panel").map(\.name) == ["selected"])
        #expect(registry.deriveds(onConstruct: "Panel").map(\.name) == ["label"])
        #expect(registry.values(onConstruct: "Panel").map(\.name) == ["title", "address"])
        #expect(
            graph.callables(onConstruct: "Panel").map(\.name).sorted() == [
                "configure",
                "render",
                "reset",
            ])

        let configure = try #require(graph.callable(named: "configure", onConstruct: "Panel"))
        let configureParameters = registry.parameters(ofCallable: configure, ownerName: "Panel")
        #expect(configureParameters.map(\.localName) == ["value", "name"])

        #expect(
            graph.declaredMemberSurfaces(forConstruct: "Panel").map(\.name).sorted() == [
                "address",
                "count",
                "label",
                "selected",
                "title",
            ])
        #expect(graph.declaresMemberPath("Panel.address.street", onConstruct: "Panel"))
        #expect(
            graph.initializerSurfaces(onConstruct: "Panel").first?.labels == [
                "title",
                "address",
                "count",
                "selected",
            ])

        #expect(graph.constructsByName["Panel"]?.macros.map(\.name).contains("styling") == true)
        #expect(graph.constructsByName["Routes"]?.callables.map(\.name) == ["home"])
        #expect(
            graph.programGraph.entities.contains {
                $0.kind == .macro && $0.label == "decorate"
            }
        )
    }

    @Test("Rewrite site decoding uses declaration-backed descriptors")
    func rewriteSiteDecodingUsesDeclarationBackedDescriptors() throws {
        let program = try CompilerPipeline().build(inputs: rangeCoreInputs())
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
                name: "target.call.arguments[0].expression.replace",
                arguments: [CallArgument(label: "with", value: .string("value"))]
            ),
            targetBinding: "target",
            targetType: .named("Function")
        )
        #expect(functionArgument?.site == .functionArgumentExpression)

        let functionApplication = context.resolvedRewriteCall(
            from: .call(
                name: "target.call.replace",
                arguments: [CallArgument(label: "with", value: .string("value"))]
            ),
            targetBinding: "target",
            targetType: .named("Function")
        )
        #expect(functionApplication?.site == .functionApplication)
    }

    @Test("Nested constructs qualify nested callables and constructs")
    func nestedConstructsQualifyNestedCallablesAndConstructs() throws {
        var inputs = try rangeCoreInputs()
        inputs.append(
            SourceInput(
                path: "/tmp/NestedConstructs.range",
                source: """
                    construct System {
                        construct Math {
                            function zero(): Int {
                                return 0
                            }

                            construct Box {
                                let number: Int
                            }
                        }
                    }
                    """,
                role: .project
            )
        )

        let program = try CompilerPipeline().buildValidated(inputs: inputs)

        #expect(
            program.declarationGraph.constructsByName["System.Math"]?.callables.map(\.name) == [
                "zero"
            ])
        #expect(program.declarationGraph.constructsByName["System.Math.Box"] != nil)
    }

    @Test("Metadata slot macro keeps target as construct")
    func metadataSlotMacroKeepsTargetAsConstruct() throws {
        var inputs = try rangeCoreInputs()
        inputs.append(
            SourceInput(
                path: "/tmp/MetadataSlotConstruct.range",
                source: """
                    macro semantic(): Construct -> Void { target, diagnostics in
                    }

                    @semantic
                    construct Language {
                        let defaultLocale: String("en")

                        function identifier(): String {
                            return defaultLocale
                        }

                        construct Token {
                            let raw: String
                        }
                    }

                    """,
                role: .project
            )
        )

        let program = try CompilerPipeline().buildValidated(inputs: inputs)
        let graph = program.declarationGraph

        #expect(graph.constructsByName["Language"] != nil)
        #expect(graph.constructsByName["Language.Token"] != nil)
        #expect(graph.constructsByName["Language"]?.callables.map(\.name) == ["identifier"])
        #expect(
            graph.programGraph.entities.contains {
                $0.kind == .value && $0.label == "defaultLocale"
            }
        )
        #expect(
            graph.programGraph.entities.contains {
                $0.kind == .field && $0.label == "defaultLocale"
            }
        )
    }

    @Test("Construct macro declares construct metadata slot")
    func metadataSlotMacroDeclaresConstructMetadataSlot() throws {
        var inputs = try rangeCoreInputs()
        inputs.append(
            SourceInput(
                path: "/tmp/RegisteredConstructMacro.range",
                source: """
                    macro hostSpace(): Construct -> Void { target, diagnostics in
                    }

                    @hostSpace
                    construct Client {
                        function route(): String {
                            return "home"
                        }
                    }
                    """,
                role: .project
            )
        )

        let program = try CompilerPipeline().buildValidated(inputs: inputs)
        let graph = program.declarationGraph

        #expect(graph.macroMetadataByName["hostSpace"]?.hasMetadataSlotEffect == true)
        #expect(graph.constructsByName["Client"] != nil)
        #expect(graph.constructsByName["Client"]?.callables.map(\.name) == ["route"])
    }

    @Test("Tuple macro attaches tuple storage metadata")
    func tupleMacroAttachesTupleStorageMetadata() throws {
        let fixture = try fixtureFile(in: "CompilePass", path: "Macros/TupleMacro.range")
        let program = try compile(fixture: fixture, expectedRole: .pass)

        let point = try #require(program.declarationGraph.constructsByName["Point"])
        #expect(point.macros.contains { $0.name == "tuple" && $0.genericArguments.isEmpty })
        #expect(program.declarationGraph.bindings(onConstruct: "Point").map(\.name) == ["x", "y"])
    }

    @Test("Tuple macro rejects non-pair binding shape")
    func tupleMacroRejectsNonPairBindingShape() throws {
        var inputs = try rangeCoreInputs()
        inputs.append(
            SourceInput(
                path: "/tmp/TupleShape.range",
                source: """
                    @tuple
                    construct Point {
                        binding x: String
                    }
                    """,
                role: .project
            )
        )

        do {
            _ = try CompilerPipeline().buildValidated(inputs: inputs)
            Issue.record("Expected @tuple with one binding field to fail validation.")
        } catch {
            #expect(
                String(describing: error).contains("@tuple expects exactly two binding fields."))
        }
    }

    @Test("Core Math construct is available")
    func coreMathConstructIsAvailable() throws {
        let program = try CompilerPipeline().buildValidated(inputs: rangeCoreInputs())

        #expect(
            program.declarationGraph.constructsByName["Math"]?.callables.map(\.name) == [
                "abs",
                "abs",
                "min",
                "max",
                "clamp",
            ])
    }

    @Test("Construct extensions reopen static member surface")
    func constructExtensionsReopenStaticMemberSurface() throws {
        var inputs = try rangeCoreInputs()
        inputs.append(
            SourceInput(
                path: "/tmp/ConstructExtension.range",
                source: """
                    extension Math {
                        function twice(value: Int): Int {
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

        #expect(program.declarationGraph.registryView.hasExtensions(targeting: "Math"))
    }

    @Test("Construct conformance clauses are unsupported")
    func constructConformanceClausesAreUnsupported() throws {
        let source = """
            construct Box: Codable { }
            """

        do {
            var parser = try Parser(source: source)
            _ = try parser.parseSourceFile()
            Issue.record("Expected construct conformance clause to fail parsing.")
        } catch {
            let description = String(describing: error)
            #expect(description.contains("Conformance clauses are no longer supported"))
        }
    }

    @Test("Property declarations use a single name")
    func propertyDeclarationsUseSingleName() throws {
        let sources = [
            """
            construct Box {
                let external internal: String("value")
            }
            """,
            """
            construct Box {
                binding external internal: String
            }
            """,
        ]

        for source in sources {
            do {
                var parser = try Parser(source: source)
                _ = try parser.parseSourceFile()
                Issue.record("Expected property declaration with two names to fail parsing.")
            } catch {
                let description = String(describing: error)
                #expect(description.contains("declarations use a single name"))
            }
        }
    }

    @Test("State transitions use colon syntax")
    func stateTransitionsUseColonSyntax() throws {
        let validSource = """
            function update(value: Int): Int {
                state total: Int(0)
                state total: total + value
                return total
            }
            """

        do {
            var parser = try Parser(source: validSource)
            _ = try parser.parseSourceFile()
        } catch {
            Issue.record("Expected state transition syntax to parse, got \(error).")
        }

        let invalidSources = [
            """
            function update(value: Int): Int {
                state total: Int(0)
                set total value
                return total
            }
            """,
            """
            function update(value: Int): Int {
                state total: Int(0)
                total += value
                return total
            }
            """,
        ]

        for source in invalidSources {
            do {
                var parser = try Parser(source: source)
                _ = try parser.parseSourceFile()
                Issue.record("Expected assignment-style syntax to fail parsing.")
            } catch {
                let description = String(describing: error)
                #expect(
                    description.contains("Expected statement")
                        || description.contains("Assignment statements use `state target: value`")
                )
            }
        }
    }

    @Test("Protocol declarations are not language surface")
    func protocolDeclarationsAreNotLanguageSurface() throws {
        let source = """
            protocol Renderable {
                function render(): String
            }
            """

        do {
            var parser = try Parser(source: source)
            _ = try parser.parseSourceFile()
            Issue.record("Expected protocol declaration to fail parsing.")
        } catch {
            let description = String(describing: error)
            #expect(description.contains("Expected top-level"))
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
        let fixture = try fixtureFile(in: "CompilePass", path: "Macros/ClampedState.range")
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
        let fixture = try fixtureFile(in: "CompilePass", path: "Macros/GetterState.range")
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

    @Test("Let macro rewrites initializer and reads")
    func letMacroRewritesInitializerAndReads() throws {
        let fixture = try fixtureFile(in: "CompilePass", path: "Macros/LetMacro.range")
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

    @Test("Binding macro rewrites reads and assignments")
    func bindingMacroRewritesReadsAndAssignments() throws {
        let fixture = try fixtureFile(in: "CompilePass", path: "Macros/BindingMacro.range")
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
        let fixture = try fixtureFile(
            in: "CompilePass", path: "Macros/ConstructAddExtensionSurface.range")
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
        #expect(extensionDeclaration.callables.contains(where: { $0.name == "greet" }))
        #expect(
            extensionDeclaration.callables.first(where: { $0.name == "clone" })?.returnType?
                .displayName == "ExtendableFixture"
        )
        #expect(module.constructs.contains(where: { $0.name == "SiblingConstruct" }))
    }

    @Test("Codable macro synthesizes string keyed encode and decode")
    func codableMacroSynthesizesStringKeyedEncodeAndDecode() throws {
        let fixture = try fixtureFile(in: "CompilePass", path: "Macros/CodableMacroSynthesis.range")
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
                extensionDeclaration.enumerations.contains(where: { $0.name == "CodingKeys" })
                    == false
            }
        )

        let object = try #require(
            module.extensions.first(where: { $0.targetName == "ObjectCodableMacroFixture" })
        )
        #expect(encodeKeys(in: object) == ["userId": "userId", "displayName": "displayName"])
        #expect(decodeKeys(in: object) == ["userId": "userId", "displayName": "displayName"])

        let identity = try #require(
            module.extensions.first(where: { $0.targetName == "IdentityCodableMacroFixture" })
        )
        #expect(encodeKeys(in: identity) == ["displayName": "displayName"])
        #expect(decodeKeys(in: identity) == ["displayName": "displayName"])

        let macroOverride = try #require(
            module.extensions.first(where: { $0.targetName == "MacroOverrideCodableMacroFixture" })
        )
        #expect(encodeKeys(in: macroOverride) == ["userId": "id"])
        #expect(decodeKeys(in: macroOverride) == ["userId": "id"])
    }

    @Test("Equatable macro synthesizes field comparisons")
    func equatableMacroSynthesizesFieldComparisons() throws {
        let fixture = try fixtureFile(
            in: "CompilePass", path: "Macros/EquatableMacroSynthesis.range")
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
        let fixture = try fixtureFile(
            in: "CompilePass", path: "Macros/HashableMacroSynthesis.range")
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
        #expect(hashCombines(in: fixtureExtension) == ["id", "name", "active"])

        let emptyExtension = try #require(
            module.extensions.first(where: { $0.targetName == "EmptyHashableMacroFixture" })
        )
        #expect(hashCombines(in: emptyExtension).isEmpty)
    }

    @Test("Comparable macro synthesizes lexicographic ordering")
    func comparableMacroSynthesizesLexicographicOrdering() throws {
        let fixture = try fixtureFile(
            in: "CompilePass", path: "Macros/ComparableMacroSynthesis.range")
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
        #expect(equalityComparisons(in: fixtureExtension) == ["major", "minor", "patch"])
        #expect(
            comparisonChecks(in: fixtureExtension) == [
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
        let fixture = try fixtureFile(
            in: "CompilePass", path: "Macros/CaseIterableMacroSynthesis.range")
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
        #expect(allCasesReturnValues(in: fixtureExtension) == [".loading", ".ready", ".failed"])

        let emptyExtension = try #require(
            module.extensions.first(where: { $0.targetName == "EmptyCaseIterableMacroFixture" })
        )
        #expect(allCasesReturnValues(in: emptyExtension).isEmpty)
    }

    @Test("Derived macro rewrites reads")
    func derivedMacroRewritesReads() throws {
        let fixture = try fixtureFile(in: "CompilePass", path: "Macros/DerivedMacro.range")
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

            function identity<T: Comparable, let count: Int = 3>(value: T): T {
                return value
            }

            macro clamped<T: Comparable, let count: Int = 3>(value: T): State<T> { target, diagnostics in
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
        #expect(module.callables.count == 1)
        #expect(module.macros.count == 1)

        expectSharedGenericShape(module.constructs[0].genericParameters)
        expectSharedGenericShape(module.enumerations[0].genericParameters)
        expectSharedGenericShape(module.callables[0].genericParameters)
        expectSharedGenericShape(module.macros[0].genericParameters)
    }

    @Test("Closed macros cannot be used outside declaring package")
    func closedMacrosCannotBeUsedOutsideDeclaringPackage() throws {
        var inputs = try rangeCoreInputs()
        inputs.append(
            SourceInput(
                path: "/test/ClosedMacro.range",
                source: """
                    closed macro coreOnly(): Construct { target, diagnostics in
                        target.declaration.expand {
                        }
                    }
                    """,
                role: .core
            )
        )
        inputs.append(
            SourceInput(
                path: "/test/UseClosedMacro.range",
                source: """
                    @coreOnly
                    construct UseClosedMacro {
                    }
                    """,
                role: .project
            )
        )

        do {
            _ = try CompilerPipeline().buildValidated(inputs: inputs)
            Issue.record("Expected closed macro use outside its package to fail.")
        } catch {
            #expect(
                String(describing: error).contains(
                    "Closed macro @coreOnly can only be used inside its declaring package"))
        }
    }

    @Test("Range runtime hook executes range lexer declaration")
    func rangeRuntimeHookExecutesRangeLexerDeclaration() throws {
        let program = try CompilerPipeline().build(
            inputs: try rangeCoreInputs(),
            runtimeHooks: [RangeFunctionRuntimeHook(functionName: "rangeLexer")]
        )

        let result = try #require(
            program.runtimeHookResults.first { $0.hookName == "range.function.rangeLexer" }
        )
        let artifact = try #require(result.artifacts["rangeLexer"])

        #expect(artifact.contains("Lexer("))
        #expect(artifact.contains("LexerRule("))
        #expect(artifact.contains("whitespace"))
        #expect(!artifact.contains("hashAttribute"))
    }

    @Test("FileManager readFile surface validates")
    func fileSystemReadTextSurfaceValidates() throws {
        let fixture = try fixtureFile(in: "CompilePass", path: "System/FileManagerReadFile.range")
        _ = try compile(fixture: fixture, expectedRole: .pass)
    }

    @Test("Compiler pipeline runtime hooks run beside Swift pipeline")
    func compilerPipelineRuntimeHooksRunBesideSwiftPipeline() throws {
        let hook = RecordingRuntimeHook()
        let diagnostics = RangeDiagnosticEngine()
        let program = try CompilerPipeline().build(
            inputs: try rangeCoreInputs(),
            diagnosticEngine: diagnostics,
            runtimeHooks: [hook]
        )

        #expect(
            hook.stages == [
                .coreDeclarationsDiscovered,
                .coreParsed,
                .projectDeclarationsDiscovered,
                .projectParsed,
                .macrosExpanded,
                .declarationGraphBuilt,
            ])
        #expect(program.runtimeHookResults.count == 6)
        #expect(program.runtimeHookResults.last?.artifacts["constructs"] != nil)
        #expect(
            diagnostics.diagnostics.contains {
                $0.source == "range-runtime-hook"
                    && $0.code == "runtime.side-by-side"
            }
        )
    }

}

private final class RecordingRuntimeHook: CompilerPipelineRuntimeHook {
    let name = "recording"
    var stages: [CompilerPipelineRuntimeStage] = []

    func run(context: CompilerPipelineRuntimeContext) throws -> CompilerPipelineRuntimeResult? {
        stages.append(context.stage)

        guard context.stage == .declarationGraphBuilt else {
            return CompilerPipelineRuntimeResult(hookName: name, stage: context.stage)
        }

        return CompilerPipelineRuntimeResult(
            hookName: name,
            stage: context.stage,
            diagnostics: [
                RangeDiagnostic(
                    severity: .information,
                    message: "runtime hook observed declaration graph",
                    source: "range-runtime-hook",
                    code: "runtime.side-by-side"
                )
            ],
            artifacts: [
                "constructs": String(context.declarationGraph?.constructsByName.count ?? 0)
            ]
        )
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
    var inputs = try rangeCoreInputs()
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
        .appendingPathComponent("Tests", isDirectory: true)
        .appendingPathComponent(suite, isDirectory: true)
    return try rangeFiles(in: root, excludingExploration: false)
}

private func fixtureFile(in suite: String, path: String) throws -> URL {
    try repositoryRoot()
        .appendingPathComponent("Tests", isDirectory: true)
        .appendingPathComponent(suite, isDirectory: true)
        .appendingPathComponent(path)
}

private func rangeCoreInputs() throws -> [SourceInput] {
    let root = try repositoryRoot()
        .appendingPathComponent("RangeCompiler", isDirectory: true)
        .appendingPathComponent("Range", isDirectory: true)
    let files =
        try rangeFiles(
            in: root.appendingPathComponent("Core", isDirectory: true),
            excludingExploration: true
        )
        + rangeFiles(
            in: root.appendingPathComponent("Foundation/Macros", isDirectory: true),
            excludingExploration: true
        )
        + rangeFiles(
            in: root.appendingPathComponent("Lexer", isDirectory: true),
            excludingExploration: true
        )

    return try files.map { file in
        SourceInput(
            path: file.path,
            source: try String(contentsOf: file, encoding: .utf8),
            role: .core
        )
    }
}

private func rangeFiles(in root: URL, excludingExploration: Bool) throws -> [URL] {
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
            url.path.contains("/RangeCompiler/Range/Core/")
        {
            enumerator.skipDescendants()
            continue
        }

        guard !isDirectory, url.pathExtension.lowercased() == "range" else {
            continue
        }
        files.append(url)
    }

    return files.sorted { $0.path < $1.path }
}

private func repositoryRoot() throws -> URL {
    var current = URL(fileURLWithPath: #filePath)
    while current.path != "/" {
        let candidateCore =
            current
            .appendingPathComponent("RangeCompiler", isDirectory: true)
            .appendingPathComponent("Range", isDirectory: true)
            .appendingPathComponent("Core", isDirectory: true)
        let candidateFixtures = current.appendingPathComponent("Tests", isDirectory: true)
        var isCoreDirectory: ObjCBool = false
        var isFixturesDirectory: ObjCBool = false
        if FileManager.default.fileExists(
            atPath: candidateCore.path, isDirectory: &isCoreDirectory),
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
    case commandFailed(String)
    case missingDirectory(String)
    case repositoryRootNotFound

    var description: String {
        switch self {
        case .commandFailed(let message):
            return message
        case .missingDirectory(let path):
            return "Missing fixture directory at \(path)."
        case .repositoryRootNotFound:
            return "Could not find repository root."
        }
    }
}
