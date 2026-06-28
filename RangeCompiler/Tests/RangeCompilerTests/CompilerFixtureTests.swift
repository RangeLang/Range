import Foundation
import Testing

@testable import RangeCompiler

@Suite("Compiler fixtures")
struct CompilerFixtureTests {
    @Test("Construct application generics expose type LLVM metadata")
    func constructApplicationGenericsExposeTypeLLVMMetadata() throws {
        let int = ConstructDeclaration(
            macros: [
                MacroApplication(
                    name: "integer",
                    genericArguments: [],
                    argumentClause: nil,
                    evaluatedStringValue: "i64"
                )
            ],
            kind: .declaration,
            attribute: nil,
            name: "Int",
            genericParameters: [],
            conformances: [],
            states: [],
            bindings: [],
            deriveds: [],
            values: [],
            initializers: [],
            callables: [],
            constructs: []
        )
        let array = ConstructDeclaration(
            macros: [],
            kind: .declaration,
            attribute: nil,
            name: "Array",
            genericParameters: [.type(name: "Element", constraint: nil, defaultArgument: nil)],
            conformances: [],
            states: [],
            bindings: [],
            deriveds: [],
            values: [],
            initializers: [],
            callables: [],
            constructs: []
        )

        let target = MacroTargetValueBuilder(
            constructsByName: ["Array": array, "Int": int]
        ).targetValue(for: array, applicationArguments: [.named("Int")])
        let application = try #require(target.field("application"))
        let generics = try #require(application.field("generics"))
        guard case .array(let values) = generics else {
            Issue.record("Expected target.application.generics to be an array.")
            return
        }
        let generic = try #require(values.first)
        let type = try #require(generic.field("type"))

        #expect(stringField(type, "name") == "Int")
        #expect(stringField(type, "llvm") == "i64")
    }

    @Test("Construct macro collects stringy member macro records")
    func constructMacroCollectsStringyMemberMacroRecords() throws {
        var inputs = try rangeFoundationMacroInputs()
        inputs.append(
            SourceInput(
                path: "/tmp/StringyConstruct.range",
                source: """
                    @construct(name: "Counter") {
                        @let(name: "label") {
                            @value(type: "String")
                        }
                        @state(name: "count") {
                            @value(type: "Int", current: "27")
                        }
                        @function(name: "increment", result: "Bool", body: "count: count + amount") {
                            @parameter(name: "amount") {
                                @value(type: "Int")
                            }
                        }
                    }
                    """,
                role: .project
            )
        )

        let program = try CompilerPipeline().build(inputs: inputs)
        let projectFile = try #require(program.projectExpandedFiles.first)
        let module = projectFile.sourceFile
        let blockMacro = try #require(module.blockMacros.first)
        let constructMacro = try #require(blockMacro.macros.first)

        #expect(
            constructMacro.evaluatedStringValue
                == """
                construct|name=Counter|llvm=%Range.Counter = type { i64 }
                member|kind=let|name=label|ordinal=0
                member|kind=value|type=String|current=|ordinal=0
                member|kind=state|name=count|ordinal=1
                member|kind=value|type=Int|current=27|ordinal=0
                member|kind=function|name=increment|result=Bool|body=count: count + amount|ordinal=2
                member|kind=parameter|name=amount|ordinal=0
                member|kind=value|type=Int|current=|ordinal=0
                """
        )

        let emittedConstruct = try #require(program.declarationGraph.constructsByName["Counter"])
        #expect(emittedConstruct.macros.first?.evaluatedStringValue == constructMacro.evaluatedStringValue)
        #expect(program.declarationGraph.values(onConstruct: "Counter").map(\.name) == ["label"])
        #expect(program.declarationGraph.values(onConstruct: "Counter").first?.typeName == "String")
        #expect(program.declarationGraph.states(onConstruct: "Counter").map(\.name) == ["count"])
        #expect(program.declarationGraph.states(onConstruct: "Counter").first?.type.displayName == "Int")
        #expect(program.declarationGraph.callables(onConstruct: "Counter").map(\.name) == ["increment"])
        #expect(program.declarationGraph.callables(onConstruct: "Counter").first?.returnType?.displayName == "Bool")
        #expect(program.declarationGraph.callables(onConstruct: "Counter").first?.parameters.map(\.name) == ["amount"])
        #expect(
            program.declarationGraph.callables(onConstruct: "Counter").first?.parameters.first?
                .typeReference?.displayName == "Int"
        )
    }

    @Test("Construct root starts as top-level macro block")
    func constructRootStartsAsTopLevelMacroBlock() throws {
        let source = """
            @main {
                @return(value: "Int(0)")
            }

            @construct(name: "Counter") {
                @state(name: "count") {
                    @value(type: "Int", current: "0")
                }
            }
            """

        var parser = try Parser(source: source)
        let parsed = try parser.parseSourceFile()
        let module = parsed

        #expect(module.constructs.isEmpty)
        #expect(module.blockMacros.count == 2)
        #expect(module.blockMacros.map { $0.macros.first?.name } == ["main", "construct"])
    }

    @Test("Standard source rejects Swift-owned roots")
    func standardSourceRejectsSwiftOwnedRoots() throws {
        for source in [
            "construct Counter {\n}",
            "enum Mode {\n    case ready\n}",
            "state total = 0",
            "function add(): Int {\n    @return(value: \"Int(0)\")\n}",
            "extension Counter {\n}",
            "precedencegroup AdditionPrecedence {\n}",
            "infix operator +: AdditionPrecedence",
        ] {
            do {
                var parser = try Parser(source: source)
                _ = try parser.parseSourceFile()
                Issue.record("Expected bare root syntax to be rejected.")
            } catch {
                #expect(
                    String(describing: error)
                        .contains(
                            "Range source accepts only @macro declarations and top-level macro blocks."
                        ))
            }
        }
    }

    @Test("Macro-only source accepts root macro blocks")
    func macroOnlySourceAcceptsRootMacroBlocks() throws {
        let source = """
            @main {
                @return(value: "Int(0)")
            }

            @construct(name: "Counter") {
                @state(name: "count") {
                    @value(type: "Int", current: "0")
                }
            }
            """

        var parser = try Parser(source: source)
        let parsed = try parser.parseSourceFile()
        let module = parsed

        #expect(module.constructs.isEmpty)
        #expect(module.blockMacros.map { $0.macros.first?.name } == ["main", "construct"])
    }

    @Test("Background and defer parse as statement macro invocations")
    func backgroundAndDeferParseAsStatementMacroInvocations() throws {
        let source = """
            @main {
                @background {
                    @return(value: "Int(0)")
                }
                @defer {
                    @return(value: "Int(0)")
                }
            }
            """

        var parser = try Parser(source: source)
        let parsed = try parser.parseSourceFile()
        let module = parsed
        guard let mainBlock = module.blockMacros.first,
            mainBlock.macros.first?.name == "main"
        else {
            Issue.record("Expected @main source to parse as a top-level macro block.")
            return
        }

        #expect(
            mainBlock.body.compactMap { statement -> String? in
                guard case .macroInvocation(let name, _, _) = statement else {
                    return nil
                }
                return name
            } == ["background", "defer"]
        )
    }

    @Test("Macro-only source rejects Swift-owned roots")
    func macroOnlySourceRejectsSwiftOwnedRoots() throws {
        let source = """
            construct Counter {
            }
            """

        do {
            var parser = try Parser(source: source)
            _ = try parser.parseSourceFile()
            Issue.record("Expected Range source to reject bare construct roots.")
        } catch {
            #expect(
                String(describing: error)
                    .contains(
                        "Range source accepts only @macro declarations and top-level macro blocks."
                    ))
        }
    }

    @Test("Macro-only input role builds through emitted records")
    func macroOnlyInputRoleBuildsThroughEmittedRecords() throws {
        var inputs = try rangeFoundationMacroInputs()
        inputs.append(
            SourceInput(
                path: "/tmp/MacroOnlyCounter.range",
                source: """
                    @main {
                        @return(value: "Int(0)")
                    }

                    @construct(name: "MacroOnlyCounter") {
                        @state(name: "count") {
                            @value(type: "Int", current: "0")
                        }
                    }
                    """,
                role: .macroOnly
            )
        )

        let program = try CompilerPipeline().build(inputs: inputs)
        let parsedFile = try #require(
            program.parsedFiles.first { $0.path == "/tmp/MacroOnlyCounter.range" }
        )
        let parsedModule = parsedFile.sourceFile

        #expect(parsedModule.constructs.isEmpty)
        #expect(parsedModule.blockMacros.map { $0.macros.first?.name } == ["main", "construct"])
        #expect(program.projectParsedFiles.contains { $0.path == "/tmp/MacroOnlyCounter.range" })
        #expect(program.declarationGraph.mainBlockMacros.map(\.name) == ["main"])
        #expect(program.declarationGraph.constructsByName["MacroOnlyCounter"] != nil)
    }

    @Test("Macro-only input role rejects Swift-owned roots")
    func macroOnlyInputRoleRejectsSwiftOwnedRoots() throws {
        let inputs = [
            SourceInput(
                path: "/tmp/LegacyCounter.range",
                source: """
                    construct Counter {
                    }
                    """,
                role: .macroOnly
            )
        ]

        do {
            _ = try CompilerPipeline().build(inputs: inputs)
            Issue.record("Expected macro-only input role to reject bare construct roots.")
        } catch {
            #expect(
                String(describing: error)
                    .contains(
                        "Range source accepts only @macro declarations and top-level macro blocks."
                    ))
        }
    }

    @Test("RangeCore declarations build through macro-only records")
    func rangeCoreDeclarationsBuildThroughMacroOnlyRecords() throws {
        let program = try CompilerPipeline().build(inputs: try rangeCoreInputs())

        for input in program.inputs
        where input.path.contains("/Range/Core/")
            || input.path.contains("/Range/Foundation/Macros/")
        {
            #expect(input.role == .core)
        }

        #expect(program.declarationGraph.constructsByName["Title"] != nil)
        #expect(program.declarationGraph.constructsByName["Remote"] != nil)
        #expect(program.declarationGraph.constructsByName["Version"] != nil)
        #expect(program.declarationGraph.constructsByName["Versioned<Value>"] != nil)
        #expect(program.declarationGraph.constructsByName["MacroTarget"] != nil)
        #expect(program.declarationGraph.constructsByName["Macro"] != nil)
        #expect(program.declarationGraph.constructsByName["Macro<Value>"] != nil)
        #expect(program.declarationGraph.constructsByName["GraphContext"] != nil)
        #expect(program.declarationGraph.enumsByName["GraphRole"] != nil)
        #expect(program.declarationGraph.enumsByName["TypeRole"] != nil)
    }

    @Test("Extension macro accepts positional target name")
    func extensionMacroAcceptsPositionalTargetName() throws {
        var inputs = try rangeFoundationMacroInputs()
        inputs.append(
            SourceInput(
                path: "/tmp/StringyExtension.range",
                source: """
                    @construct(name: "User") {
                        @let(name: "name") {
                            @value(type: "String")
                        }
                    }

                    @extension("User") {
                        @function(name: "displayName", result: "String", body: "name")
                    }
                    """,
                role: .project
            )
        )

        let program = try CompilerPipeline().build(inputs: inputs)
        let projectFile = try #require(program.projectExpandedFiles.first)
        let module = projectFile.sourceFile
        let blockMacro = try #require(module.blockMacros.first(where: { blockMacro in
            blockMacro.macros.first?.name == "extension"
        }))
        let extensionMacro = try #require(blockMacro.macros.first)

        #expect(
            extensionMacro.evaluatedStringValue
                == """
                extension|name=User|llvm=%Range.User.extension = type { }
                member|kind=function|name=displayName|result=String|body=name|ordinal=0
                """
        )
    }

    @Test("Enum macro collects stringy case member records")
    func enumMacroCollectsStringyCaseMemberRecords() throws {
        var inputs = try rangeFoundationMacroInputs()
        inputs.append(
            SourceInput(
                path: "/tmp/StringyEnum.range",
                source: """
                    @enum(name: "BuildMessageLevel") {
                        @case(name: "info")
                        @case(name: "error", value: "1")
                    }
                    """,
                role: .project
            )
        )

        let program = try CompilerPipeline().build(inputs: inputs)
        let projectFile = try #require(program.projectExpandedFiles.first)
        let module = projectFile.sourceFile
        let blockMacro = try #require(module.blockMacros.first)
        let enumMacro = try #require(blockMacro.macros.first)

        #expect(
            enumMacro.evaluatedStringValue
                == """
                enum|name=BuildMessageLevel
                member|kind=case|name=info|value=|ordinal=0
                member|kind=case|name=error|value=1|ordinal=1
                """
        )

        let declaration = try #require(program.declarationGraph.enumsByName["BuildMessageLevel"])
        #expect(declaration.cases.map(\.name) == ["info", "error"])
    }

    @Test("Statement block macro parses with members")
    func statementBlockMacroParsesWithMembers() throws {
        var parser = try Parser(source: """
            function spin() {
                @while {
                    continue
                }
            }
            """)
        let sourceFile = try parser.parseSourceFile()
        let module = sourceFile
        guard let callable = callableDeclarations(in: module).first,
            let statement = callable.body?.first,
            case .macroInvocation(let name, let argumentClause, let body) = statement
        else {
            Issue.record("Expected @while { ... } to parse as a statement block macro.")
            return
        }

        #expect(name == "while")
        #expect(argumentClause == nil)
        #expect(body.count == 1)
    }

    @Test("Statement block macro expands through Range-authored projection")
    func statementBlockMacroExpandsThroughRangeAuthoredProjection() throws {
        var inputs = try rangeFoundationMacroInputs()
        inputs.append(
            SourceInput(
                path: "/tmp/StringyWhile.range",
                source: """
                    function spin() {
                        @state(name: "x", type: "Int", value: "Int(0)")
                        @while("x > 5") {
                            @assignment(target: "x", value: "x + 1")
                        }
                    }
                    """,
                role: .project
            )
        )

        let program = try CompilerPipeline().build(inputs: inputs)
        let whileMacro = try #require(program.declarationGraph.macrosByName["while"])
        #expect(whileMacro.target?.displayName == "@statement")
        #expect(whileMacro.macros.isEmpty)

        let projectFile = try #require(program.projectExpandedFiles.first)
        let module = projectFile.sourceFile
        guard let callable = callableDeclarations(in: module).first,
            let statement = callable.body?.first(where: {
                if case .emitted(let text) = $0 {
                    return text.contains("statement|kind=while")
                }
                return false
            }),
            case .emitted(let text) = statement
        else {
            Issue.record("Expected @while to expand to an emitted statement string.")
            return
        }

        #expect(
            text
                == """
                statement|kind=while|condition=x > 5|projection=target.declaration.statements
                statement|kind=assign|target=x|value=x + 1|projection=target.declaration
                """
        )
    }

    @Test("If statement block macro expands through Range-authored projection")
    func ifStatementBlockMacroExpandsThroughRangeAuthoredProjection() throws {
        var inputs = try rangeFoundationMacroInputs()
        inputs.append(
            SourceInput(
                path: "/tmp/StringyIf.range",
                source: """
                    function branch() {
                        @if("x > 5") {
                            @return(value: "x")
                        }
                    }
                    """,
                role: .project
            )
        )

        let program = try CompilerPipeline().build(inputs: inputs)
        let ifMacro = try #require(program.declarationGraph.macrosByName["if"])
        #expect(ifMacro.target?.displayName == "@statement")
        #expect(ifMacro.macros.isEmpty)

        let projectFile = try #require(program.projectExpandedFiles.first)
        let module = projectFile.sourceFile
        guard let callable = callableDeclarations(in: module).first,
            let statement = callable.body?.first(where: {
                if case .emitted = $0 {
                    return true
                }
                return false
            }),
            case .emitted(let text) = statement
        else {
            Issue.record("Expected @if to expand to an emitted statement string.")
            return
        }

        #expect(
            text
                == """
                statement|kind=if|condition=x > 5|projection=target.declaration.statements
                statement|kind=return|value=x|projection=target.declaration|llvm=ret x
                """
        )
    }

    @Test("Return statement macro expands through Range-authored projection")
    func returnStatementMacroExpandsThroughRangeAuthoredProjection() throws {
        var inputs = try rangeFoundationMacroInputs()
        inputs.append(
            SourceInput(
                path: "/tmp/StringyReturn.range",
                source: """
                    function answer() {
                        @return(value: "Int(42)")
                    }
                    """,
                role: .project
            )
        )

        let program = try CompilerPipeline().build(inputs: inputs)
        let returnMacro = try #require(program.declarationGraph.macrosByName["return"])
        #expect(returnMacro.target?.displayName == "@statement")
        #expect(returnMacro.macros.map(\.name) == ["statement"])

        let projectFile = try #require(program.projectExpandedFiles.first)
        let module = projectFile.sourceFile
        guard let callable = callableDeclarations(in: module).first,
            let statement = callable.body?.first,
            case .emitted(let text) = statement
        else {
            Issue.record("Expected @return to expand to an emitted statement string.")
            return
        }

        #expect(
            text
                == "statement|kind=return|value=Int(42)|projection=target.declaration|llvm=ret i64 42"
        )
    }

    @Test("Bare return is rejected inside macro-only statement bodies")
    func bareReturnIsRejectedInsideMacroOnlyStatementBodies() throws {
        var inputs = try rangeFoundationMacroInputs()
        inputs.append(
            SourceInput(
                path: "/tmp/BareReturnStatementRecord.range",
                source: """
                    @function(name: "answer", result: "Int") {
                        return Int(42)
                    }
                    """,
                role: .project
            )
        )

        do {
            _ = try CompilerPipeline().build(inputs: inputs)
            Issue.record("Expected bare return syntax to fail parsing.")
        } catch {
            #expect(String(describing: error).contains("Expected statement"))
        }
    }

    @Test("Bare if and while are rejected inside macro-only statement bodies")
    func bareIfAndWhileAreRejectedInsideMacroOnlyStatementBodies() throws {
        var inputs = try rangeFoundationMacroInputs()
        inputs.append(
            SourceInput(
                path: "/tmp/BareControlFlowStatementRecords.range",
                source: """
                    @function(name: "branch", result: "Int") {
                        if x > 5 {
                            @return(value: "x")
                        }
                        while x > 0 {
                            @break()
                        }
                    }
                    """,
                role: .project
            )
        )

        do {
            _ = try CompilerPipeline().build(inputs: inputs)
            Issue.record("Expected bare control-flow syntax to fail parsing.")
        } catch {
            #expect(String(describing: error).contains("Expected statement"))
        }
    }

    @Test("Scalar members and assignments lower through Range-authored statement macros")
    func scalarMembersAndAssignmentsLowerThroughRangeAuthoredStatementMacros() throws {
        var inputs = try rangeFoundationMacroInputs()
        inputs.append(
            SourceInput(
                path: "/tmp/ScalarLocalAssignmentStatementRecords.range",
                source: """
                    @main {
                        @state(name: "x", type: "Int", value: "Int(0)")
                        @assignment(target: "x", value: "x + 1")
                        @return(value: "x")
                    }
                    """,
                role: .project
            )
        )

        let program = try CompilerPipeline().build(inputs: inputs)
        let projectFile = try #require(program.projectExpandedFiles.first)
        let module = projectFile.sourceFile
        guard let body = module.blockMacros.first(where: { $0.macros.first?.name == "main" })?.body
        else {
            Issue.record("Expected @main block body.")
            return
        }

        let emitted = body.compactMap { statement -> String? in
            guard case .emitted(let text) = statement else { return nil }
            return text
        }
        #expect(
            emitted
                == [
                    "@state(name: \"x\", type: \"Int\", value: \"Int(0)\")",
                    "statement|kind=assign|target=x|value=x + 1|projection=target.declaration",
                    "statement|kind=return|value=x|projection=target.declaration|llvm=ret x",
                ])
    }

    @Test("Scalar string members keep constructor-shaped values in statement records")
    func scalarStringMembersKeepConstructorShapedValuesInStatementRecords() throws {
        var inputs = try rangeFoundationMacroInputs()
        inputs.append(
            SourceInput(
                path: "/tmp/ScalarStringStatementRecords.range",
                source: """
                    @main {
                        @let(name: "text") {
                            @value(type: "String", current: "String(\\"Hello World\\")")
                        }
                        @return(value: "text")
                    }
                    """,
                role: .project
            )
        )

        let program = try CompilerPipeline().build(inputs: inputs)
        let projectFile = try #require(program.projectExpandedFiles.first)
        let module = projectFile.sourceFile
        guard let body = module.blockMacros.first(where: { $0.macros.first?.name == "main" })?.body
        else {
            Issue.record("Expected @main block body.")
            return
        }

        let emitted = body.compactMap { statement -> String? in
            guard case .emitted(let text) = statement else { return nil }
            return text
        }
        #expect(
            emitted
                == [
                    """
                    member|kind=let|name=text|ordinal=0
                    @value(type: "String", current: "String("Hello World")")
                    """,
                    "statement|kind=return|value=text|projection=target.declaration|llvm=ret text",
                ])
    }

    @Test("Function macro collects statement body LLVM records")
    func functionMacroCollectsStatementBodyLLVMRecords() throws {
        var inputs = try rangeFoundationMacroInputs()
        inputs.append(
            SourceInput(
                path: "/tmp/StringyFunctionBody.range",
                source: """
                    @construct(name: "Answer") {
                        @function(name: "answer", result: "Int", body: "statement|kind=return|value=Int(42)|projection=target.declaration|llvm=ret i64 42")
                    }
                    """,
                role: .project
            )
        )

        let program = try CompilerPipeline().build(inputs: inputs)
        let projectFile = try #require(program.projectExpandedFiles.first)
        let module = projectFile.sourceFile
        let blockMacro = try #require(module.blockMacros.first)
        let constructMacro = try #require(blockMacro.macros.first)

        #expect(
            constructMacro.evaluatedStringValue
                == """
                construct|name=Answer|llvm=%Range.Answer = type { ret i64 42, ret i64 42 }
                member|kind=function|name=answer|result=Int|body=records|ordinal=0|llvm=ret i64 42
                statement|kind=return|value=Int(42)|projection=target.declaration|llvm=ret i64 42
                """
        )
    }

    @Test("Break and continue statement macros expand through Range-authored projection")
    func breakAndContinueStatementMacrosExpandThroughRangeAuthoredProjection() throws {
        var inputs = try rangeFoundationMacroInputs()
        inputs.append(
            SourceInput(
                path: "/tmp/StringyBreakContinue.range",
                source: """
                    function flow() {
                        @break()
                        @continue()
                    }
                    """,
                role: .project
            )
        )

        let program = try CompilerPipeline().build(inputs: inputs)
        let breakMacro = try #require(program.declarationGraph.macrosByName["break"])
        let continueMacro = try #require(program.declarationGraph.macrosByName["continue"])
        #expect(breakMacro.target?.displayName == "@statement")
        #expect(continueMacro.target?.displayName == "@statement")
        #expect(breakMacro.macros.isEmpty)
        #expect(continueMacro.macros.isEmpty)

        let projectFile = try #require(program.projectExpandedFiles.first)
        let module = projectFile.sourceFile
        guard let callable = callableDeclarations(in: module).first
        else {
            Issue.record("Expected expanded module with flow function.")
            return
        }

        let emitted = callable.body?.compactMap { statement -> String? in
            guard case .emitted(let text) = statement else {
                return nil
            }
            return text
        } ?? []

        #expect(
            emitted == [
                "statement|kind=break|projection=target.declaration|llvm=br label %loop.end",
                "statement|kind=continue|projection=target.declaration|llvm=br label %loop.condition",
            ]
        )
    }

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
            in: "CompileFail",
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

    @Test("Identifier init macro stringifies bare syntax")
    func identifierInitMacroStringifiesBareSyntax() throws {
        let fixture = try fixtureFile(in: "CompilePass", path: "Macros/IdentifierInitMacro.range")
        _ = try compile(fixture: fixture, expectedRole: .pass)
    }

    @Test("@macro bootstrap declaration parses")
    func macroPrefixDeclarationParses() throws {
        var parser = try Parser(source: """
            @macro -> String {
                @parameter(name: "name") {
                    @value(type: "String")
                }
                @return(value: declaration.name)
            }
            """)
        let sourceFile = try parser.parseSourceFile()
        let module = sourceFile
        guard let declaration = module.macros.first
        else {
            Issue.record("Expected @macro prefix declaration to parse as a macro declaration.")
            return
        }

        #expect(declaration.name == "macro")
        #expect(declaration.parameters.map(\.name) == ["name"])
        #expect(declaration.expansionType == .named("String"))
        guard case .macroSurface("macro")? = declaration.target else {
            Issue.record("Expected @macro prefix declaration to target @macro.")
            return
        }
    }

    @Test("Macro body assignment remains a macro application at parse time")
    func macroBodyAssignmentRemainsMacroApplicationAtParseTime() throws {
        var parser = try Parser(source: """
            @macro -> String {
                @state(name: "value", value: "String()")
                @assignment(target: "value", value: "updated")
                @return(value: value)
            }
            """)
        let sourceFile = try parser.parseSourceFile()
        let module = sourceFile
        guard let declaration = module.macros.first,
            declaration.body.count >= 2,
            case .macroApplication(let name, let arguments) = declaration.body[1]
        else {
            Issue.record("Expected @assignment to remain a macro application.")
            return
        }

        #expect(name == "assignment")
        #expect(arguments.map(\.label) == ["target", "value"])
    }

    @Test("@macro entrypoint lowers macro declarations to stringy records")
    func macroEntrypointLowersMacroDeclarationsToStringyRecords() throws {
        let program = try CompilerPipeline().build(inputs: rangeFoundationMacroInputs())
        let macrosByName = program.declarationGraph.macrosByName
        let entrypoint = try #require(macrosByName["macro"])

        let context = program.declarationGraph.macroExpansionContext(macrosByName: macrosByName)
        let evaluator = CompileTimeValueEvaluator(
            targetBinding: "target",
            targetValue: .object(typeName: "MacroDeclaration", fields: [:]),
            graphBinding: "graph",
            selfValue: MacroTargetValueBuilder(
                macroDeclarationsByName: macrosByName,
                macroMetadataByName: context.macroMetadataByName,
                knownObjectTypeNames: context.graphContext.knownObjectTypeNames
            ).value(for: entrypoint),
            localBindings: [:],
            macroDeclarationsByName: macrosByName,
            context: context
        )
        var locals: [String: RangeCompiler.Expression] = [
            "name": .string("decorate"),
            "result": .string("String"),
            "target": .string(""),
            "body": .string("@return(value: \"ok\")"),
        ]
        guard case .string(let record)? = evaluator.evaluateStatements(
            entrypoint.body,
            locals: &locals
        ) else {
            Issue.record("Expected @macro entrypoint to emit a stringy macro record.")
            return
        }

        #expect(
            record
                == """
                macro|name=decorate|result=String|target=
                @return(value: "ok")
                """
        )
    }

    @Test("@self macro parses as value expression")
    func selfMacroParsesAsValueExpression() throws {
        var parser = try Parser(source: "@self")
        let expression = try parser.parseExpression()
        guard case .macroInvocation(let name, let arguments) = expression
        else {
            Issue.record("Expected @self to parse as a value macro expression.")
            return
        }

        #expect(name == "self")
        #expect(arguments.isEmpty)
    }

    @Test("@self resolves through macro context current identity")
    func selfMacroResolvesThroughMacroContextCurrentIdentity() throws {
        let program = try CompilerPipeline().build(inputs: rangeCoreInputs())
        let macrosByName = MacroExpander.collectMacroDeclarations(from: program.parsedFiles)
        _ = try #require(macrosByName["self"])

        var parser = try Parser(source: """
            construct User {
                @let name: String
            }
            """)
        let sourceFile = try parser.parseSourceFile()
        let module = sourceFile
        guard let construct = module.constructs.first
        else {
            Issue.record("Expected construct.")
            return
        }

        let context = program.declarationGraph.macroExpansionContext(macrosByName: macrosByName)
        let target = MacroTargetValueBuilder(
            macroDeclarationsByName: macrosByName,
            macroMetadataByName: context.macroMetadataByName,
            knownObjectTypeNames: context.graphContext.knownObjectTypeNames
        ).targetValue(for: construct)
        let evaluator = CompileTimeValueEvaluator(
            targetBinding: "target",
            targetValue: target,
            localBindings: [:],
            macroDeclarationsByName: macrosByName,
            context: context
        )

        guard
            case .object("GraphIdentity", let fields)? = evaluator.evaluate(
                .macroInvocation(name: "self", arguments: [])
            ),
            case .string("construct:User")? = fields["id"],
            case .string("construct")? = fields["kind"],
            case .string("User")? = fields["name"]
        else {
            Issue.record("Expected @self to resolve to the current construct graph identity.")
            return
        }
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
                        @let value: Int
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
                @let name: String
                @let age: Int

                function displayName(): String {
                    return name
                }

                construct Nested {
                    @let value: Int
                }
            }
            """
        var parser = try Parser(source: source)
        let sourceFile = try parser.parseSourceFile()
        let module = sourceFile
        guard let construct = module.constructs.first
        else {
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
            macros: [],
            name: "tracked",
            genericParameters: [],
            parameters: [],
            target: .macroSurface("syntax"),
            expansionType: nil,
            body: [.return(.string("macro body"))]
        )
        let context = graph.macroExpansionContext(macrosByName: ["tracked": trackedMacro])
        let propertyTargetKinds = macroTargetKinds(
            for: .macroSurface("property"),
            syntaxResolver: context.syntaxResolver
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
                        diagnostics.note(declaration.identifier.name)
                    }

                    @graphNamed
                    construct User {
                        @let name: String
                    }
                    """,
                role: .project
            )
        )

        _ = try CompilerPipeline().build(inputs: inputs)
    }

    @Test("llvm macro returns an LLVM template string")
    func llvmMacroReturnsTemplateString() throws {
        var inputs = try rangeCoreInputs()
        inputs.append(
            SourceInput(
                path: "/tmp/LLVMMacro.range",
                source: """
                    macro lower(): Construct -> String { target, diagnostics in
                        return @llvm(body: "%r = add i$bits $lhs, $rhs")
                    }

                    @lower
                    construct Widget {
                        @let value: Int
                    }
                    """,
                role: .project
            )
        )

        let program = try CompilerPipeline().build(inputs: inputs)
        let construct = try #require(program.declarationGraph.constructsByName["Widget"])
        let lower = try #require(construct.macros.first(where: { $0.name == "lower" }))
        #expect(lower.evaluatedStringValue == "%r = add i$bits $lhs, $rhs")
    }

    @Test("String supports + concatenation")
    func stringSupportsConcatenation() throws {
        var inputs = try rangeCoreInputs()
        inputs.append(
            SourceInput(
                path: "/tmp/StringConcat.range",
                source: """
                    function label(): String {
                        let head: String("i")
                        let width: String("15")
                        return head + width
                    }
                    """,
                role: .project
            )
        )

        let program = try CompilerPipeline().build(inputs: inputs)
        let stringConstruct = try #require(program.declarationGraph.constructsByName["String"])
        let hasPlus = program.declarationGraph.extensionsByTargetName["String"]?
            .flatMap(\.callables)
            .contains(where: { $0.name == "+" }) ?? false
        #expect(hasPlus)
        #expect(stringConstruct.name == "String")
    }

    @Test("Core Int construct carries attached integer lowering behavior")
    func coreIntConstructCarriesAttachedIntegerLoweringBehavior() throws {
        let inputs = try rangeCoreInputs()
        let program = try CompilerPipeline().build(inputs: inputs)
        let intConstruct = try #require(program.declarationGraph.constructsByName["Int"])
        let construct = try #require(intConstruct.macros.first(where: { $0.name == "construct" }))
        #expect(
            construct.evaluatedStringValue
                == """
                construct|name=Int|llvm=%Range.Int = type { i64 }
                integer|bits=64|signedness=signed
                """
        )
    }

    @Test("Core Void construct carries attached void behavior")
    func coreVoidConstructCarriesAttachedVoidBehavior() throws {
        let inputs = try rangeCoreInputs()
        let program = try CompilerPipeline().build(inputs: inputs)
        let voidConstruct = try #require(program.declarationGraph.constructsByName["Void"])
        let construct = try #require(voidConstruct.macros.first(where: { $0.name == "construct" }))
        #expect(
            construct.evaluatedStringValue
                == """
                construct|name=Void|llvm=%Range.Void = type {  }
                void
                """
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
                        @let name: String
                    }
                    """,
                role: .project
            )
        )

        let program = try CompilerPipeline().build(inputs: inputs)
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
                        @let name: String
                    }
                    """,
                role: .project
            )
        )

        _ = try CompilerPipeline().build(inputs: inputs)
    }

    @Test("Macro evaluator treats String construction as empty string")
    func macroEvaluatorTreatsStringConstructionAsEmptyString() throws {
        var inputs = try rangeCoreInputs()
        inputs.append(
            SourceInput(
                path: "/tmp/MacroStringConstruction.range",
                source: """
                    macro emptyString(): Construct -> String { target, diagnostics in
                        state value: String()
                        return value
                    }

                    @emptyString
                    construct User {
                        @let name: String
                    }
                    """,
                role: .project
            )
        )

        let program = try CompilerPipeline().build(inputs: inputs)
        let construct = try #require(program.declarationGraph.constructsByName["User"])
        let macro = try #require(construct.macros.first(where: { $0.name == "emptyString" }))
        #expect(macro.evaluatedStringValue == "")
    }

    @Test("Macro evaluator supports property string transforms")
    func macroEvaluatorSupportsPropertyStringTransforms() throws {
        var inputs = try rangeCoreInputs()
        inputs.append(
            SourceInput(
                path: "/tmp/MacroStringTransform.range",
                source: """
                    macro transformedName(): Construct -> String { target, diagnostics in
                        return target.declaration.identifier.name.snakeCase
                    }

                    @transformedName
                    construct UserProfile {
                        @let name: String
                    }
                    """,
                role: .project
            )
        )

        let program = try CompilerPipeline().build(inputs: inputs)
        let construct = try #require(program.declarationGraph.constructsByName["UserProfile"])
        let macro = try #require(construct.macros.first(where: { $0.name == "transformedName" }))
        #expect(macro.evaluatedStringValue == "user_profile")
    }

    @Test("Macro evaluator requires String construction for string concatenation")
    func macroEvaluatorRequiresStringConstructionForStringConcatenation() throws {
        var inputs = try rangeCoreInputs()
        inputs.append(
            SourceInput(
                path: "/tmp/MacroRawStringConcat.range",
                source: """
                    macro rawConcat(): Construct -> String { target, diagnostics in
                        let lhs: String("a")
                        let rhs: String("b")
                        return lhs + rhs
                    }

                    @rawConcat
                    construct User {
                        @let name: String
                    }
                    """,
                role: .project
            )
        )

        do {
            _ = try CompilerPipeline().build(inputs: inputs)
            Issue.record("Expected raw string concatenation in a macro return to fail.")
        } catch {
            #expect(String(describing: error).contains("could not be evaluated at compile time"))
        }
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
                        @let name: String
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

        let program = try CompilerPipeline().build(inputs: inputs)
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
                        @let name: String
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
            _ = try CompilerPipeline().build(inputs: inputs)
            Issue.record("Expected construct macro on extension to fail validation.")
        } catch {
            #expect(
                String(describing: error).contains("used on an extension but targets Construct"))
        }
    }

    @Test("addable requirement is satisfied by an extension-declared +")
    func addableRequirementSatisfiedByExtensionFunction() throws {
        var inputs = try rangeCoreInputs()
        inputs.append(
            SourceInput(
                path: "/tmp/AddableExtension.range",
                source: """
                    @addable
                    construct Money {
                        @let cents: Int
                    }

                    extension Money {
                        function +(lhs: Self, rhs: Self): Self
                    }
                    """,
                role: .project
            )
        )

        let program = try CompilerPipeline().build(inputs: inputs)
        #expect(program.declarationGraph.constructsByName["Money"] != nil)
    }

    @Test("addable requirement fails when no + is declared")
    func addableRequirementFailsWithoutAddition() throws {
        var inputs = try rangeCoreInputs()
        inputs.append(
            SourceInput(
                path: "/tmp/AddableMissing.range",
                source: """
                    @addable
                    construct Money {
                        @let cents: Int
                    }
                    """,
                role: .project
            )
        )

        do {
            _ = try CompilerPipeline().build(inputs: inputs)
            Issue.record("Expected @addable to fail when no + function is declared.")
        } catch {
            #expect(String(describing: error).contains("@addable requires a function identified as +"))
        }
    }

    @Test("Core Int satisfies the addable requirement")
    func coreIntSatisfiesAddable() throws {
        let inputs = try rangeCoreInputs()
        let program = try CompilerPipeline().build(inputs: inputs)
        #expect(program.declarationGraph.constructsByName["Int"] != nil)
    }

    @Test("Construct macro target value exposes attached primitive macro value")
    func constructMacroTargetValueExposesAttachedPrimitiveMacroValue() throws {
        let inputs = try rangeCoreInputs()
        let program = try CompilerPipeline().build(inputs: inputs)
        let graph = program.declarationGraph
        let intConstruct = try #require(graph.constructsByName["Int"])
        let targetValueBuilder = MacroTargetValueBuilder(
            macroDeclarationsByName: graph.macrosByName,
            macroMetadataByName: graph.macroMetadataByName,
            constructsByName: graph.constructsByName,
            extensionsByTargetName: graph.extensionsByTargetName
        )

        let target = targetValueBuilder.targetValue(for: intConstruct)
        #expect(
            attachedMacroValue(named: "integer", in: target)
                == "integer|bits=64|signedness=signed")
    }

    private func attachedMacroValue(
        named name: String,
        in target: CompileTimeValue
    ) -> String? {
        guard
            case .object(_, let targetFields) = target,
            case .object(_, let declarationFields)? = targetFields["declaration"],
            case .array(let macros)? = declarationFields["macros"]
        else {
            return nil
        }

        for macro in macros {
            guard
                case .object("Macro.Application", let fields) = macro,
                case .string(let macroName)? = fields["name"],
                macroName == name,
                case .string(let value)? = fields["evaluatedStringValue"]
            else {
                continue
            }
            return value
        }
        return nil
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
                        @let value: String

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
                        @let id: Int
                        @let name: String
                    }

                    @main {
                        let user: User(id: 1, name: "George")
                    }
                    """,
                role: .project
            )
        )

        _ = try CompilerPipeline().build(inputs: inputs)
    }

    @Test("Typed construction annotations can be optional")
    func typedConstructionAnnotationsCanBeOptional() throws {
        let source = """
            construct WidgetCount {
                @let value: Double
            }

            construct Counter {
                @let count: Optional<Int>(5)
                @let widgetCount: Optional<WidgetCount>(value: 0.1)
                @state current: Optional<Int>(5)
            }

            @main {
                let local: Optional<Int>(5)
            }
            """

        var parser = try Parser(source: source)
        let file = try parser.parseSourceFile()

        let module = file
        let counter = try #require(module.constructs.first(where: { $0.name == "Counter" }))

        var inputs = try rangeCoreInputs()
        inputs.append(
            SourceInput(
                path: "/tmp/TypedConstructionOptional.range",
                source: source,
                role: .project
            )
        )
        _ = try CompilerPipeline().build(inputs: inputs)

        let count = try #require(counter.values.first(where: { $0.name == "count" }))
        #expect(count.typeName == "Optional<Int>")
        guard case .integer(5)? = count.value else {
            Issue.record("Expected typed construction literal value.")
            return
        }

        let widgetCount = try #require(counter.values.first(where: { $0.name == "widgetCount" }))
        #expect(widgetCount.typeName == "Optional<WidgetCount>")
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

        let mainBlock = try #require(module.blockMacros.first { $0.macros.first?.name == "main" })
        let local = try #require(mainBlock.body.first)
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
        _ = try CompilerPipeline().build(inputs: validInputs)

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
                        @let id: Int
                        @let name: String
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
                        @let title: String
                    }
                    """,
                role: .project
            )
        )

        let program = try CompilerPipeline().build(inputs: inputs)
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
                        @let displayName: String
                    }
                    """,
                role: .project
            )
        )

        let program = try CompilerPipeline().build(inputs: inputs)
        let profile = try #require(program.declarationGraph.constructsByName["Profile"])
        #expect(profile.macros.map(\.name) == ["persisted"])
        #expect(profile.macros.first?.argumentClause == #"prefix : "settings""#)
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

        _ = try CompilerPipeline().build(inputs: inputs)
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

        _ = try CompilerPipeline().build(inputs: inputs)
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

    @Test("@syntax declarations are syntax-facing through metadata")
    func syntaxDeclarationsAreSyntaxFacingThroughMetadata() throws {
        let program = try CompilerPipeline().build(inputs: rangeCoreInputs())
        let graph = program.declarationGraph

        #expect(graph.constructsByName["Expression"]?.isCore == true)
        #expect(graph.syntaxResolver.typeConformsToSyntax(.named("Expression")))
        #expect(graph.syntaxResolver.syntaxTypeName(forSurface: "block") == "Block")
        #expect(graph.syntaxResolver.type(.named("Block"), matchesSyntaxSurface: "block"))
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

        _ = try CompilerPipeline().build(inputs: inputs)
    }

    @Test("Range for loop validates with Int loop binding")
    func rangeForLoopValidatesWithIntLoopBinding() throws {
        var inputs = try rangeCoreInputs()
        inputs.append(
            SourceInput(
                path: "/tmp/RangeForLoop.range",
                source: """
                    function sum(limit: Int): Int {
                        state total: Int(0)

                        for index in 0..<limit {
                            state total: total + index
                        }

                        return total
                    }
                    """,
                role: .project
            )
        )

        _ = try CompilerPipeline().build(inputs: inputs)
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
                                @let number: Int
                            }
                        }
                    }
                    """,
                role: .project
            )
        )

        let program = try CompilerPipeline().build(inputs: inputs)

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
                        @let defaultLocale: String("en")

                        function identifier(): String {
                            return defaultLocale
                        }

                        construct Token {
                            @let raw: String
                        }
                    }

                    """,
                role: .project
            )
        )

        let program = try CompilerPipeline().build(inputs: inputs)
        let graph = program.declarationGraph

        #expect(graph.constructsByName["Language"] != nil)
        #expect(graph.constructsByName["Language.Token"] != nil)
        #expect(graph.constructsByName["Language"]?.callables.map(\.name) == ["identifier"])
        #expect(
            graph.valuesByConstructName["Language"]?.contains { $0.name == "defaultLocale" }
                == true
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

        let program = try CompilerPipeline().build(inputs: inputs)
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
            _ = try CompilerPipeline().build(inputs: inputs)
            Issue.record("Expected @tuple with one binding field to fail validation.")
        } catch {
            #expect(
                String(describing: error).contains("@tuple expects exactly two binding fields."))
        }
    }

    @Test("Core Math construct is available")
    func coreMathConstructIsAvailable() throws {
        let program = try CompilerPipeline().build(inputs: rangeCoreInputs())

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
                            @let number: Int
                        }
                    }
                    """,
                role: .project
            )
        )

        let program = try CompilerPipeline().build(inputs: inputs)

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
                @let external internal: String("value")
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

    @Test("State transitions use explicit statement macros")
    func stateTransitionsUseExplicitStatementMacros() throws {
        let validSource = """
            function update(value: Int): Int {
                @state(name: "total", type: "Int", value: "Int(0)")
                @assignment(target: "total", value: "total + value")
                @return(value: "total")
            }
            """

        do {
            var parser = try Parser(source: validSource)
            _ = try parser.parseSourceFile()
        } catch {
            Issue.record("Expected explicit state transition macros to parse, got \(error).")
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
                @state(name: "total", type: "Int", value: "Int(0)")
                total: total + value
                @return(value: "total")
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
                Issue.record("Expected bare assignment/control-flow syntax to fail parsing.")
            } catch {
                let description = String(describing: error)
                #expect(description.contains("Expected statement"))
            }
        }
    }

    @Test("Bare assignment is rejected inside macro bodies")
    func bareAssignmentIsRejectedInsideMacroBodies() throws {
        try expectBareMacroBodySyntaxRejected(
            """
            value: "updated"
            @return(value: value)
            """
        )
    }

    @Test("Bare control flow is rejected inside macro bodies")
    func bareControlFlowIsRejectedInsideMacroBodies() throws {
        try expectBareMacroBodySyntaxRejected(
            """
            if true {
                @return(value: "ok")
            }
            """
        )
        try expectBareMacroBodySyntaxRejected(
            """
            while true {
                break
            }
            """
        )
        try expectBareMacroBodySyntaxRejected(
            """
            return "ok"
            """
        )
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
            extension Array<Int> { }
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

    @Test("Construct macro expand emits extension declarations")
    func constructMacroExpandEmitsExtensionDeclarations() throws {
        let fixture = try fixtureFile(
            in: "CompilePass", path: "Macros/ConstructAddExtensionSurface.range")
        let program = try compile(fixture: fixture, expectedRole: .pass)
        let expandedFile = try #require(
            program.projectExpandedFiles.first(where: { $0.path == fixture.path })
        )

        let module = expandedFile.sourceFile

        let extensionDeclaration = try #require(module.extensions.first)
        #expect(extensionDeclaration.targetType.displayName == "ExtendableFixture")
        #expect(extensionDeclaration.callables.contains(where: { $0.name == "greet" }))
        #expect(
            extensionDeclaration.callables.first(where: { $0.name == "clone" })?.returnType?
                .displayName == "ExtendableFixture"
        )
        #expect(module.constructs.contains(where: { $0.name == "SiblingConstruct" }))
    }

    @Test("Equatable macro synthesizes field comparisons")
    func equatableMacroSynthesizesFieldComparisons() throws {
        let fixture = try fixtureFile(
            in: "CompilePass", path: "Macros/EquatableMacroSynthesis.range")
        let program = try compile(fixture: fixture, expectedRole: .pass)
        let expandedFile = try #require(
            program.projectExpandedFiles.first(where: { $0.path == fixture.path })
        )

        let module = expandedFile.sourceFile

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

        let module = expandedFile.sourceFile

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

        let module = expandedFile.sourceFile

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

        let module = expandedFile.sourceFile

        let fixtureExtension = try #require(
            module.extensions.first(where: { $0.targetName == "CaseIterableMacroFixture" })
        )
        #expect(allCasesReturnValues(in: fixtureExtension) == [".loading", ".ready", ".failed"])

        let emptyExtension = try #require(
            module.extensions.first(where: { $0.targetName == "EmptyCaseIterableMacroFixture" })
        )
        #expect(allCasesReturnValues(in: emptyExtension).isEmpty)
    }

    @Test("Generic parameter clauses are shared across declarations")
    func genericParameterClausesAreSharedAcrossDeclarations() throws {
        let source = """
            construct Box<T, count: Int(3)> { }

            enum Maybe<T, count: Int(3)> {
                case value(T)
            }

            function identity<T, count: Int(3)>(value: T): T {
                return value
            }

            macro clamped<T, count: Int(3)>(value: T): State<T> { target, diagnostics in
                diagnostics.note("clamped")
            }
            """

        var parser = try Parser(source: source)
        let file = try parser.parseSourceFile()

        let module = file

        #expect(module.constructs.count == 1)
        #expect(module.enumerations.count == 1)
        #expect(callableDeclarations(in: module).count == 1)
        #expect(module.macros.count == 1)

        expectSharedGenericShape(module.constructs[0].genericParameters)
        expectSharedGenericShape(module.enumerations[0].genericParameters)
        expectSharedGenericShape(callableDeclarations(in: module)[0].genericParameters)
        expectSharedGenericShape(module.macros[0].genericParameters)
    }

    @Test("Core macros can be used outside declaring package")
    func coreMacrosCanBeUsedOutsideDeclaringPackage() throws {
        var inputs = try rangeCoreInputs()
        inputs.append(
            SourceInput(
                path: "/test/CoreMacro.range",
                source: """
                    macro coreOnly(): Construct { target, diagnostics in
                        diagnostics.note("core")
                    }
                    """,
                role: .core
            )
        )
        inputs.append(
            SourceInput(
                path: "/test/UseCoreMacro.range",
                source: """
                    @coreOnly
                    construct UseCoreMacro {
                    }
                    """,
                role: .project
            )
        )

        _ = try CompilerPipeline().build(inputs: inputs)
    }

}

private enum FixtureRole {
    case pass
    case fail
}

private func expectSharedGenericShape(_ parameters: [GenericParameter]) {
    #expect(parameters.count == 2)

    guard case .type(let typeName, let constraint, let defaultArgument) = parameters[0] else {
        Issue.record("Expected first generic parameter to be a type parameter.")
        return
    }

    #expect(typeName == "T")
    #expect(constraint == nil)
    #expect(defaultArgument == nil)

    guard case .value(let valueName, let typeReference, let defaultValue?) = parameters[1] else {
        Issue.record("Expected second generic parameter to be a value parameter with a default.")
        return
    }

    #expect(valueName == "count" || valueName == "capacity")
    #expect(typeReference.displayName == "Int")

    guard
        case .call(let name, let arguments) = defaultValue,
        name == "Int",
        case .integer(let value)? = arguments.first?.value
    else {
        Issue.record("Expected generic value default to parse as a typed integer value.")
        return
    }

    #expect(value == 3 || value == 1)
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
    return try CompilerPipeline().build(inputs: inputs)
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
        + (try rangeFiles(
            in: root.appendingPathComponent("Foundation/Macros", isDirectory: true),
            excludingExploration: true
        ))

    return try files.map { file in
        SourceInput(
            path: file.path,
            source: try String(contentsOf: file, encoding: .utf8),
            role: .core
        )
    }
}

private func rangeFoundationMacroInputs() throws -> [SourceInput] {
    let root = try repositoryRoot()
        .appendingPathComponent("RangeCompiler", isDirectory: true)
        .appendingPathComponent("Range", isDirectory: true)
    let macroRoot = root.appendingPathComponent("Foundation/Macros", isDirectory: true)
    let files =
        [
            macroRoot.appendingPathComponent("Macro.range"),
            macroRoot.appendingPathComponent("Member.range"),
            macroRoot.appendingPathComponent("Value.range"),
            macroRoot.appendingPathComponent("Let.range"),
            macroRoot.appendingPathComponent("State.range"),
            macroRoot.appendingPathComponent("Parameter.range"),
            macroRoot.appendingPathComponent("Construct.range"),
            macroRoot.appendingPathComponent("Function.range"),
            macroRoot.appendingPathComponent("Assignment.range"),
            macroRoot.appendingPathComponent("Return.range"),
            macroRoot.appendingPathComponent("If.range"),
            macroRoot.appendingPathComponent("While.range"),
            macroRoot.appendingPathComponent("Break.range"),
            macroRoot.appendingPathComponent("Continue.range"),
            macroRoot.appendingPathComponent("Case.range"),
        ]

    return try files.sorted(by: rangeCoreFilePrecedence).map { file in
        SourceInput(
            path: file.path,
            source: try String(contentsOf: file, encoding: .utf8),
            role: .core
        )
    }
}

private func expectBareMacroBodySyntaxRejected(
    _ body: String,
    sourceLocation: SourceLocation = #_sourceLocation
) throws {
    var inputs = try rangeFoundationMacroInputs()
    inputs.append(
        SourceInput(
            path: "/tmp/BareMacroBodySyntax.range",
            source: """
                @macro(name: "sample", result: "String") {
                    @state(name: "value", value: "String()")
                \(body)
                }
                """,
            role: .project
        )
    )

    do {
        _ = try CompilerPipeline().build(inputs: inputs)
        Issue.record(
            "Expected bare macro-body syntax to fail parsing.",
            sourceLocation: sourceLocation
        )
    } catch {
        #expect(
            String(describing: error).contains("Expected statement"),
            sourceLocation: sourceLocation
        )
    }
}

private func callableDeclarations(in module: ModuleFileNode) -> [CallableDeclaration] {
    module.constructs.flatMap(callableDeclarations(in:))
        + module.extensions.flatMap { extensionDeclaration in
            extensionDeclaration.callables
                + extensionDeclaration.constructs.flatMap(callableDeclarations(in:))
        }
}

private func callableDeclarations(in construct: ConstructDeclaration) -> [CallableDeclaration] {
    construct.callables + construct.constructs.flatMap(callableDeclarations(in:))
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

    return files.sorted(by: rangeCoreFilePrecedence)
}

private func rangeCoreFilePrecedence(_ lhs: URL, _ rhs: URL) -> Bool {
    let lhsPriority = lhs.path.hasSuffix("/Range/Foundation/Macros/Macro.range") ? 0 : 1
    let rhsPriority = rhs.path.hasSuffix("/Range/Foundation/Macros/Macro.range") ? 0 : 1
    if lhsPriority != rhsPriority {
        return lhsPriority < rhsPriority
    }
    return lhs.path < rhs.path
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

private func stringField(_ value: CompileTimeValue, _ name: String) -> String? {
    guard case .string(let text)? = value.field(name) else {
        return nil
    }
    return text
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
