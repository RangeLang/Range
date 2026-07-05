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
        """
        define i32 @main() {
        entry:
          ret i32 \(value)
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
