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
                    value text = #captureText(1 + 2)
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
                    value messageText = message()
                    value captured = #captureText(1 + 2)
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

    @Test("Binding parameters accept $ member arguments")
    func bindingParametersAcceptMemberBindingArguments() throws {
        var inputs = try neatCoreInputs()
        inputs.append(
            SourceInput(
                path: "/tmp/BindingArguments.neat",
                source: """
                function write(target _: binding Int, value _: Int) {
                    target = value
                }

                construct Counter {
                    state count: Int = 0

                    init() {
                        write($self.count, 3)
                    }
                }

                @main {
                    value counter = Counter()
                }
                """,
                role: .project
            )
        )

        _ = try CompilerPipeline().buildValidated(inputs: inputs)
    }

    @Test("Function-typed binding parameters compile")
    func functionTypedBindingParametersCompile() throws {
        var inputs = try neatCoreInputs()
        inputs.append(
            SourceInput(
                path: "/tmp/FunctionTypedBindingParameters.neat",
                source: """
                function replace(task _: binding () -> Int, replacement _: () -> Int) {
                    task = replacement
                }

                @main {
                }
                """,
                role: .project
            )
        )

        _ = try CompilerPipeline().buildValidated(inputs: inputs)
    }

    @Test("Function values can be passed as callable arguments")
    func functionValuesCanBePassedAsCallableArguments() throws {
        var inputs = try neatCoreInputs()
        inputs.append(
            SourceInput(
                path: "/tmp/FunctionValueArgument.neat",
                source: """
                function compute() -> Int {
                    return 1
                }

                function accept(task _: () -> Int) -> Int {
                    return task()
                }

                @main {
                    value result = accept(compute)
                }
                """,
                role: .project
            )
        )

        _ = try CompilerPipeline().buildValidated(inputs: inputs)
    }

    @Test("Callable declarations cannot be passed as binding references")
    func callableDeclarationsCannotBePassedAsBindingReferences() throws {
        var inputs = try neatCoreInputs()
        inputs.append(
            SourceInput(
                path: "/tmp/CallableBindingReference.neat",
                source: """
                function compute() -> Int {
                    return 1
                }

                function replace(task _: binding () -> Int, replacement _: () -> Int) {
                    task = replacement
                }

                @main {
                    replace($compute, compute)
                }
                """,
                role: .project
            )
        )

        do {
            _ = try CompilerPipeline().buildValidated(inputs: inputs)
            Issue.record("Expected passing a callable declaration as a binding reference to fail.")
        } catch {
            // Expected with the current storage binding model.
        }
    }

    @Test("Autoclosure load helper accepts unlabeled second argument")
    func autoclosureLoadHelperAcceptsUnlabeledSecondArgument() throws {
        var inputs = try neatCoreInputs()
        inputs.append(
            SourceInput(
                path: "/tmp/AutoclosureLoadUnlabeled.neat",
                source: """
                enum LoadError {
                    case missing
                }

                construct User {
                    value id: Int
                }

                enum Loadable<Value, Failure> {
                    case idle
                    case loading
                    case loaded(value: Value)
                    case failed(error: Failure)
                }

                function fetchUser(id: Int) -> Loadable<User, LoadError> {
                    return .loaded(value: User(id: id))
                }

                function load<Value, Failure>(
                    state _: binding Loadable<Value, Failure>,
                    #autoclosure task: Loadable<Value, Failure>
                ) {
                    state = .loading

                    @background {
                        state = task()
                    }
                }

                construct UserView {
                    state user: Loadable<User, LoadError> = .idle

                    init(id: Int) {
                        load($self.user, fetchUser(id: id))
                    }
                }

                @main {
                    value view = UserView(id: 1)
                }
                """,
                role: .project
            )
        )

        _ = try CompilerPipeline().buildValidated(inputs: inputs)
    }

    @Test("Autoclosure load helper rejects labeled second argument")
    func autoclosureLoadHelperRejectsLabeledSecondArgument() throws {
        var inputs = try neatCoreInputs()
        inputs.append(
            SourceInput(
                path: "/tmp/AutoclosureLoadLabeled.neat",
                source: """
                enum LoadError {
                    case missing
                }

                construct User {
                    value id: Int
                }

                enum Loadable<Value, Failure> {
                    case idle
                    case loading
                    case loaded(value: Value)
                    case failed(error: Failure)
                }

                function fetchUser(id: Int) -> Loadable<User, LoadError> {
                    return .loaded(value: User(id: id))
                }

                function load<Value, Failure>(
                    state _: binding Loadable<Value, Failure>,
                    #autoclosure task: Loadable<Value, Failure>
                ) {
                    state = .loading

                    @background {
                        state = task()
                    }
                }

                construct UserView {
                    state user: Loadable<User, LoadError> = .idle

                    init(id: Int) {
                        load($self.user, task: fetchUser(id: id))
                    }
                }

                @main {
                    value view = UserView(id: 1)
                }
                """,
                role: .project
            )
        )

        do {
            _ = try CompilerPipeline().buildValidated(inputs: inputs)
            Issue.record("Expected labeled second argument form to fail.")
        } catch {
            // Expected with the current parser/signature model.
        }
    }

    @Test("Current load helper fixture parses as written")
    func currentLoadHelperFixtureParsesAsWritten() throws {
        _ = try compile(
            fixture: try repositoryRoot()
                .appendingPathComponent("NeatCompilerFixtures", isDirectory: true)
                .appendingPathComponent("CompilePass/System/LoadHelper.neat"),
            expectedRole: .pass
        )
    }
}

private enum FixtureRole {
    case pass
    case fail
}

private func compile(fixture: URL, expectedRole: FixtureRole) throws -> SemanticProgram {
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
