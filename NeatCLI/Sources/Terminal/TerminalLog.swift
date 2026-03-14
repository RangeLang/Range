import Foundation
import NeatSyntax

enum TerminalColor {
    case reset
    case bold
    case dim
    case gray
    case lightGray
    case cyan
    case error
    case warning
    case success
    case change
    case optimization
    case waiting
    case clearLine

    var string: String {
        switch self {
        case .reset:
            return "\u{001B}[0m"
        case .bold:
            return "\u{001B}[1m"
        case .dim:
            return "\u{001B}[2m"
        case .gray:
            return "\u{001B}[90m"
        case .lightGray:
            return "\u{001B}[97m"
        case .cyan:
            return "\u{001B}[36m"
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
        case .clearLine:
            return "\u{001B}[2K"
        }
    }
}

enum TerminalLog {
    private static func color(for level: LogLevel) -> TerminalColor {
        switch level {
        case .error:
            return .error
        case .warning:
            return .warning
        case .success:
            return .success
        case .change:
            return .change
        case .optimization:
            return .optimization
        case .waiting:
            return .waiting
        }
    }

    static func style(_ text: String, level: LogLevel, bold: Bool = false, dimmed: Bool = false)
        -> String
    {
        var prefix = color(for: level).string
        if bold {
            prefix += TerminalColor.bold.string
        }
        if dimmed {
            prefix += TerminalColor.dim.string
        }
        return "\(prefix)\(text)\(TerminalColor.reset.string)"
    }

    static func subtle(_ text: String) -> String {
        "\(TerminalColor.dim.string)\(TerminalColor.gray.string)\(text)\(TerminalColor.reset.string)"
    }

    static func light(_ text: String) -> String {
        "\(TerminalColor.lightGray.string)\(text)\(TerminalColor.reset.string)"
    }

    static func out(_ text: String, level: LogLevel, bold: Bool = false, dimmed: Bool = false) {
        Swift.print(style(text, level: level, bold: bold, dimmed: dimmed))
    }

    static func err(_ text: String, level: LogLevel, bold: Bool = false, dimmed: Bool = false) {
        fputs(style(text, level: level, bold: bold, dimmed: dimmed) + "\n", stderr)
    }
}
