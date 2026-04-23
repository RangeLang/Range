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

    @Test("Init application surface is present in declaration graph")
    func initApplicationSurfaceIsPresentInDeclarationGraph() throws {
        let program = try CompilerPipeline().build(inputs: neatCoreInputs())
        let graph = program.declarationGraph

        #expect(graph.constructsByName["Init"] != nil)
        #expect(graph.constructsByName["Init.Application"] != nil)
        #expect(graph.syntaxResolver.declaration(named: "Init.Application", conformsTo: "SyntaxReplaceable"))
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

        let initializer = context.resolvedRewriteCall(
            from: .call(
                name: "target.application.replace",
                arguments: [CallArgument(label: "with", value: .string("value"))]
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
        #expect(module.constructs.contains(where: { $0.name == "SiblingConstruct" }))
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
