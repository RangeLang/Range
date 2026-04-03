import ArgumentParser
import Foundation
import NeatBackendSwift
import NeatSyntax

enum ErrorPresenter {
    static func printError(_ error: Error) {
        let message = detailMessage(for: error)
        TerminalLog.err("An Error has Occurred", level: .error, bold: true)
        fputs(TerminalLog.light("[\(timestamp())] \(message)") + "\n", stderr)
    }

    private static func detailMessage(for error: Error) -> String {
        if let parse = error as? ParseError {
            return parse.description
        }
        if let validation = error as? SemanticValidationError {
            return validation.description
        }
        if let validation = error as? ValidationError {
            return validation.message
        }
        if let backend = error as? SwiftBackendError {
            return backend.message
        }
        return String(describing: error)
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE MMM d h:mma"
        return formatter.string(from: Date())
    }
}
