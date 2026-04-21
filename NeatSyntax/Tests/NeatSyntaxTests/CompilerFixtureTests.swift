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

    @Test("Project macros infer across project files")
    func projectMacrosInferAcrossProjectFiles() throws {
        var inputs = try neatCoreInputs()
        inputs.append(
            SourceInput(
                path: "/tmp/ProjectMacros.neat",
                source: """
                macro captureText(value _: capture Expression): Expression -> String { target, diagnostics in
                    target.rewrite("captured: \\(value)")
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

                macro captureText(value _: capture Expression): Expression -> String { target, diagnostics in
                    target.rewrite("captured: \\(value)")
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

    @Test("Init application surface is present in declaration graph")
    func initApplicationSurfaceIsPresentInDeclarationGraph() throws {
        let program = try CompilerPipeline().build(inputs: neatCoreInputs())
        let graph = program.declarationGraph

        #expect(graph.constructsByName["Init"] != nil)
        #expect(graph.constructsByName["Init.Application"] != nil)
        #expect(graph.syntaxResolver.declaration(named: "Init.Application", conformsTo: "SupportsRewrite"))
    }

    @Test("Rewrite site decoding uses declaration-backed descriptors")
    func rewriteSiteDecodingUsesDeclarationBackedDescriptors() throws {
        let program = try CompilerPipeline().build(inputs: neatCoreInputs())
        let context = program.declarationGraph.macroExpansionContext(macrosByName: [:])

        let direct = context.resolvedRewriteCall(
            from: .call(
                name: "target.rewrite",
                arguments: [CallArgument(label: nil, value: .string("value"))]
            ),
            targetBinding: "target",
            targetType: .named("Expression")
        )
        #expect(direct?.site == .targetDirect)

        let parameter = context.resolvedRewriteCall(
            from: .call(
                name: "target.application.expression.rewrite",
                arguments: [CallArgument(label: nil, value: .string("value"))]
            ),
            targetBinding: "target",
            targetType: .named("Parameter")
        )
        #expect(parameter?.site == .parameterApplicationArgument)

        let functionArgument = context.resolvedRewriteCall(
            from: .call(
                name: "target.application.arguments[0].expression.rewrite",
                arguments: [CallArgument(label: nil, value: .string("value"))]
            ),
            targetBinding: "target",
            targetType: .named("Function")
        )
        #expect(functionArgument?.site == .functionArgumentExpression)

        let initializer = context.resolvedRewriteCall(
            from: .call(
                name: "target.application.rewrite",
                arguments: [CallArgument(label: nil, value: .string("value"))]
            ),
            targetBinding: "target",
            targetType: .named("Init")
        )
        #expect(initializer?.site == .initApplication)
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

        macro clamped<T: Comparable, let count: Int = 3>(value _: T): State<T> { target, diagnostics in
            target.rewrite(value)
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
            url.path.contains("/NeatCore/Macros/")
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
