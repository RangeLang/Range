import ArgumentParser
import Foundation
import GradientBackendSwift
import GradientSyntax

enum ErrorPresenter {
    static func printError(_ error: Error) {
        let message = detailMessage(for: error)
        TerminalLog.err("An Error has Occurred", level: .error, bold: true)
        fputs(TerminalLog.light("[\(timestamp())] \(message)") + "\n", stderr)
    }

    private static func detailMessage(for error: Error) -> String {
        ErrorDescription.message(for: error)
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE MMM d h:mma"
        return formatter.string(from: Date())
    }
}
