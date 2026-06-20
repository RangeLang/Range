import ArgumentParser
import Foundation

struct NativeLLVMRunner {
    func link(irURL: URL, executableURL: URL) throws {
        let parent = executableURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/clang")
        process.arguments = [
            irURL.path,
            "-o",
            executableURL.path,
        ]

        let errorPipe = Pipe()
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorText = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw ValidationError(
                "LLVM link failed with exit code \(process.terminationStatus)"
                    + (errorText.map { ": \($0)" } ?? ".")
            )
        }
    }

    func run(executableURL: URL) throws {
        let process = Process()
        process.executableURL = executableURL
        process.standardInput = FileHandle.standardInput
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw ValidationError(
                "Native LLVM executable failed with exit code \(process.terminationStatus)."
            )
        }
    }
}
