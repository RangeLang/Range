import Foundation
import NeatSyntax

enum LogLevel {
    case error
    case warning
    case success
    case change
    case optimization
    case waiting
}

enum TerminalLog {
    private static let reset = "\u{001B}[0m"
    private static let bold = "\u{001B}[1m"
    private static let dim = "\u{001B}[2m"
    private static let gray = "\u{001B}[90m"
    private static let lightGray = "\u{001B}[97m"

    private static func color(for level: LogLevel) -> String {
        switch level {
        case .error:
            return "\u{001B}[31m"
        case .warning:
            return "\u{001B}[38;5;208m"
        case .success:
            return "\u{001B}[32m"
        case .change:
            return "\u{001B}[34m"
        case .optimization:
            return "\u{001B}[35m"
        case .waiting:
            return "\u{001B}[33m"
        }
    }

    static func style(_ text: String, level: LogLevel, bold: Bool = false, dimmed: Bool = false)
        -> String
    {
        var prefix = color(for: level)
        if bold {
            prefix += self.bold
        }
        if dimmed {
            prefix += self.dim
        }
        return "\(prefix)\(text)\(reset)"
    }

    static func subtle(_ text: String) -> String {
        "\(dim)\(gray)\(text)\(reset)"
    }

    static func light(_ text: String) -> String {
        "\(lightGray)\(text)\(reset)"
    }

    static func out(_ text: String, level: LogLevel, bold: Bool = false, dimmed: Bool = false) {
        Swift.print(style(text, level: level, bold: bold, dimmed: dimmed))
    }

    static func err(_ text: String, level: LogLevel, bold: Bool = false, dimmed: Bool = false) {
        fputs(style(text, level: level, bold: bold, dimmed: dimmed) + "\n", stderr)
    }
}
