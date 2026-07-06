import Foundation
import SwiftBootstrap

private struct DriverError: LocalizedError {
    let message: String

    var errorDescription: String? {
        message
    }
}

private func usage() -> String {
    """
    Usage:
      range check-llvm-runs --range-root ROOT MANIFEST [--require-full-coverage]
      range compile-executable --range-root ROOT INPUT
      range emit-llvm --range-root ROOT INPUT OUTPUT
      range run --range-root ROOT INPUT [-- ARGS...]
    """
}

private func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

private func emitLLVM(arguments: [String]) throws {
    guard arguments.count == 4, arguments[0] == "--range-root" else {
        throw DriverError(message: usage())
    }

    let rangeRoot = URL(fileURLWithPath: arguments[1])
    let input = URL(fileURLWithPath: arguments[2])
    let output = URL(fileURLWithPath: arguments[3])

    try SwiftBootstrapCompiler().emitLLVM(rangeRoot: rangeRoot, input: input, output: output)
}

private func compileExecutable(arguments: [String]) throws {
    guard arguments.count == 3, arguments[0] == "--range-root" else {
        throw DriverError(message: usage())
    }

    let rangeRoot = URL(fileURLWithPath: arguments[1])
    let input = URL(fileURLWithPath: arguments[2])

    let executable = try SwiftBootstrapCompiler().compileExecutable(
        rangeRoot: rangeRoot,
        input: input
    )
    print(executable.path)
}

private func run(arguments: [String]) throws -> Int32 {
    guard arguments.count >= 3, arguments[0] == "--range-root" else {
        throw DriverError(message: usage())
    }

    let rangeRoot = URL(fileURLWithPath: arguments[1])
    let input = URL(fileURLWithPath: arguments[2])
    var executableArguments = Array(arguments.dropFirst(3))
    if executableArguments.first == "--" {
        executableArguments.removeFirst()
    }

    return try SwiftBootstrapCompiler().run(
        rangeRoot: rangeRoot,
        input: input,
        arguments: executableArguments
    )
}

private func checkLLVMRuns(arguments: [String]) throws {
    guard arguments.count >= 3, arguments[0] == "--range-root" else {
        throw DriverError(message: usage())
    }

    let rangeRoot = URL(fileURLWithPath: arguments[1])
    let manifest = URL(fileURLWithPath: arguments[2])
    let remainingArguments = Array(arguments.dropFirst(3))
    guard remainingArguments.allSatisfy({ $0 == "--require-full-coverage" }) else {
        throw DriverError(message: usage())
    }

    try SwiftBootstrapCompiler().checkLLVMRuns(
        rangeRoot: rangeRoot,
        manifest: manifest,
        requireFullCoverage: remainingArguments.contains("--require-full-coverage")
    )
}

let arguments = Array(CommandLine.arguments.dropFirst())

do {
    guard let command = arguments.first else {
        throw DriverError(message: usage())
    }

    switch command {
    case "check-llvm-runs":
        try checkLLVMRuns(arguments: Array(arguments.dropFirst()))
    case "compile-executable":
        try compileExecutable(arguments: Array(arguments.dropFirst()))
    case "emit-llvm":
        try emitLLVM(arguments: Array(arguments.dropFirst()))
    case "run":
        let exitCode = try run(arguments: Array(arguments.dropFirst()))
        if exitCode != 0 {
            exit(exitCode)
        }
    default:
        throw DriverError(message: usage())
    }
} catch {
    fail(error.localizedDescription)
}
