import Foundation
import RangeCompiler
import RangeEmission
import Testing

@Suite("LLVM module emission")
struct LLVMModuleEmitterTests {
    @Test("Empty main emits zero return")
    func emptyMainEmitsZeroReturn() throws {
        let module = try emit(
            """
            @main {
            }
            """
        )

        #expect(module == expectedMain(returning: 0))
    }

    @Test("Bare integer return emits integer return")
    func bareIntegerReturnEmitsIntegerReturn() throws {
        let module = try emit(
            """
            @main {
                return 7
            }
            """
        )

        #expect(module == expectedMain(returning: 7))
    }

    @Test("Int constructor return emits integer return")
    func intConstructorReturnEmitsIntegerReturn() throws {
        let module = try emit(
            """
            @main {
                return Int(9)
            }
            """
        )

        #expect(module == expectedMain(returning: 9))
    }

    @Test("Integer local return emits bound integer return")
    func integerLocalReturnEmitsBoundIntegerReturn() throws {
        let module = try emit(
            """
            @main {
                let count: Int(5)
                return count
            }
            """
        )

        #expect(
            module == expectedMain(
                """
                  %count = alloca i32
                  store i32 5, ptr %count
                  %0 = load i32, ptr %count
                  ret i32 %0
                """
            )
        )
    }

    @Test("Integer arithmetic return emits LLVM instructions")
    func integerArithmeticReturnEmitsLLVMInstructions() throws {
        let module = try emit(
            """
            @main {
                return 5 + 2 * 3
            }
            """
        )

        #expect(
            module == expectedMain(
                """
                  %0 = mul i32 2, 3
                  %1 = add i32 5, %0
                  ret i32 %1
                """
            )
        )
    }

    @Test("Integer arithmetic local return emits LLVM instructions")
    func integerArithmeticLocalReturnEmitsLLVMInstructions() throws {
        let module = try emit(
            """
            @main {
                let count: Int(5)
                let total: Int(count + 2)
                return total
            }
            """
        )

        #expect(
            module == expectedMain(
                """
                  %count = alloca i32
                  store i32 5, ptr %count
                  %0 = load i32, ptr %count
                  %1 = add i32 %0, 2
                  %total = alloca i32
                  store i32 %1, ptr %total
                  %2 = load i32, ptr %total
                  ret i32 %2
                """
            )
        )
    }

    @Test("Mutable integer state assignment emits updated return")
    func mutableIntegerStateCompoundAssignmentEmitsUpdatedReturn() throws {
        let module = try emit(
            """
            @main {
                state count: Int(5)
                count: count + 2
                return count
            }
            """
        )

        #expect(
            module == expectedMain(
                """
                  %count = alloca i32
                  store i32 5, ptr %count
                  %0 = load i32, ptr %count
                  %1 = add i32 %0, 2
                  store i32 %1, ptr %count
                  %2 = load i32, ptr %count
                  ret i32 %2
                """
            )
        )
    }

    private func emit(_ source: String) throws -> String {
        var inputs = try rangeCoreInputs()
        inputs.append(
            SourceInput(
                path: "/tmp/Main.range",
                source: source,
                role: .project
            )
        )

        let program = try CompilerPipeline().buildValidated(inputs: inputs)
        return try LLVMModuleEmitter().emit(program: program)
    }

    private func expectedMain(returning value: Int) -> String {
        expectedMain("  ret i32 \(value)")
    }

    private func expectedMain(_ body: String) -> String {
        """
        define i32 @main() {
        entry:
        \(body)
        }

        """
    }

    private func rangeCoreInputs() throws -> [SourceInput] {
        let rangeRoot = try repositoryRoot()
            .appendingPathComponent("RangeCompiler", isDirectory: true)
            .appendingPathComponent("Range", isDirectory: true)
        let roots = [
            rangeRoot.appendingPathComponent("Core", isDirectory: true),
            rangeRoot.appendingPathComponent("Foundation", isDirectory: true),
            rangeRoot.appendingPathComponent("Lexer", isDirectory: true),
        ]

        return try roots.flatMap { root in
            try rangeFiles(in: root).map { file in
                SourceInput(
                    path: file.path,
                    source: try String(contentsOf: file, encoding: .utf8),
                    role: .core
                )
            }
        }
    }

    private func rangeFiles(in root: URL) throws -> [URL] {
        guard
            let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        else {
            throw TestFixtureError.missingDirectory(root.path)
        }

        var files: [URL] = []
        while let url = enumerator.nextObject() as? URL {
            let isDirectory =
                (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            guard !isDirectory else {
                continue
            }
            guard url.pathExtension.lowercased() == "range" else {
                continue
            }
            files.append(url)
        }

        return files.sorted { $0.path < $1.path }
    }

    private func repositoryRoot() throws -> URL {
        var current = URL(fileURLWithPath: #filePath)
        while current.path != "/" {
            let packageFile = current
                .appendingPathComponent("RangeCompiler", isDirectory: true)
                .appendingPathComponent("Package.swift")
            if FileManager.default.fileExists(atPath: packageFile.path) {
                return current
            }
            current.deleteLastPathComponent()
        }
        throw TestFixtureError.missingRepositoryRoot
    }
}

private enum TestFixtureError: Error, CustomStringConvertible {
    case missingDirectory(String)
    case missingRepositoryRoot

    var description: String {
        switch self {
        case .missingDirectory(let path):
            return "Missing directory: \(path)"
        case .missingRepositoryRoot:
            return "Could not locate repository root."
        }
    }
}
