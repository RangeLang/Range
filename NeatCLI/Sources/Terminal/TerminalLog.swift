import Darwin
import Foundation

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
    private enum Stream {
        case stdout
        case stderr

        var fileDescriptor: Int32 {
            switch self {
            case .stdout:
                return STDOUT_FILENO
            case .stderr:
                return STDERR_FILENO
            }
        }
    }

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

    private static func supportsColor(on stream: Stream) -> Bool {
        let environment = ProcessInfo.processInfo.environment

        if environment["NO_COLOR"] != nil {
            return false
        }

        if let force = environment["CLICOLOR_FORCE"], force != "0" {
            return true
        }

        if let term = environment["TERM"], term == "dumb" {
            return false
        }

        if let colorTerm = environment["COLORTERM"], !colorTerm.isEmpty {
            return true
        }

        if let cliColor = environment["CLICOLOR"], cliColor == "0" {
            return false
        }

        return isatty(stream.fileDescriptor) == 1
    }

    private static func render(
        _ text: String,
        colors: [TerminalColor],
        on stream: Stream
    ) -> String {
        guard supportsColor(on: stream) else {
            return text
        }

        let prefix = colors.map(\.string).joined()
        return "\(prefix)\(text)\(TerminalColor.reset.string)"
    }

    static func style(
        _ text: String,
        level: LogLevel,
        bold: Bool = false,
        dimmed: Bool = false
    ) -> String {
        style(text, level: level, bold: bold, dimmed: dimmed, on: .stdout)
    }

    private static func style(
        _ text: String,
        level: LogLevel,
        bold: Bool = false,
        dimmed: Bool = false,
        on stream: Stream
    ) -> String {
        var colors: [TerminalColor] = [color(for: level)]
        if bold {
            colors.append(.bold)
        }
        if dimmed {
            colors.append(.dim)
        }
        return render(text, colors: colors, on: stream)
    }

    static func subtle(_ text: String) -> String {
        render(text, colors: [.dim, .gray], on: .stderr)
    }

    static func light(_ text: String) -> String {
        render(text, colors: [.lightGray], on: .stderr)
    }

    static func out(_ text: String, level: LogLevel, bold: Bool = false, dimmed: Bool = false) {
        Swift.print(style(text, level: level, bold: bold, dimmed: dimmed, on: .stdout))
    }

    static func err(_ text: String, level: LogLevel, bold: Bool = false, dimmed: Bool = false) {
        fputs(style(text, level: level, bold: bold, dimmed: dimmed, on: .stderr) + "\n", stderr)
    }
}
