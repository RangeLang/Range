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
      range emit-llvm --range-root ROOT INPUT OUTPUT
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

let arguments = Array(CommandLine.arguments.dropFirst())

do {
    guard let command = arguments.first else {
        throw DriverError(message: usage())
    }

    switch command {
    case "emit-llvm":
        try emitLLVM(arguments: Array(arguments.dropFirst()))
    default:
        throw DriverError(message: usage())
    }
} catch {
    fail(error.localizedDescription)
}
