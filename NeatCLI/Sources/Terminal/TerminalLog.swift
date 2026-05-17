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

enum TerminalAccentColor {
    case custom(Int)

    var string: String {
        switch self {
        case .custom(let code):
            return "\u{001B}[38;5;\(code)m"
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
                return Platform.standardOutputFileDescriptor
            case .stderr:
                return Platform.standardErrorFileDescriptor
            }
        }
    }

    private static func statusColor(for level: CLIStatusLevel) -> TerminalColor {
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

    private static func runtimeColor(for level: RuntimeLogLevel) -> TerminalColor {
        switch level {
        case .log:
            return .gray
        case .debug:
            return .gray
        case .info:
            return .cyan
        case .success:
            return .success
        case .warning:
            return .warning
        case .error:
            return .error
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

        return Platform.isTerminal(stream.fileDescriptor)
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
        level: CLIStatusLevel,
        bold: Bool = false,
        dimmed: Bool = false
    ) -> String {
        style(text, level: level, bold: bold, dimmed: dimmed, on: .stdout)
    }

    private static func style(
        _ text: String,
        level: CLIStatusLevel,
        bold: Bool = false,
        dimmed: Bool = false,
        on stream: Stream
    ) -> String {
        var colors: [TerminalColor] = [statusColor(for: level)]
        if bold {
            colors.append(.bold)
        }
        if dimmed {
            colors.append(.dim)
        }
        return render(text, colors: colors, on: stream)
    }

    private static func runtimeStyle(
        _ text: String,
        level: RuntimeLogLevel,
        bold: Bool = false,
        dimmed: Bool = false,
        on stream: Stream
    ) -> String {
        var colors: [TerminalColor] = [runtimeColor(for: level)]
        if bold {
            colors.append(.bold)
        }
        if dimmed {
            colors.append(.dim)
        }
        return render(text, colors: colors, on: stream)
    }

    static func timed(
        _ text: String,
        milliseconds: Int,
        level: CLIStatusLevel
    ) -> String {
        timed(text, milliseconds: milliseconds, level: level, on: .stdout)
    }

    private static func timed(
        _ text: String,
        milliseconds: Int,
        level: CLIStatusLevel,
        on stream: Stream
    ) -> String {
        let message = style(text, level: level, bold: true, on: stream)
        let timing = render(
            "\(milliseconds)ms", colors: [statusColor(for: level), .dim], on: stream)
        return "\(message) \(timing)"
    }

    static func timedOut(_ text: String, milliseconds: Int, level: CLIStatusLevel) {
        Swift.print(timed(text, milliseconds: milliseconds, level: level, on: .stdout))
    }

    static func timedErr(_ text: String, milliseconds: Int, level: CLIStatusLevel) {
        fputs(timed(text, milliseconds: milliseconds, level: level, on: .stderr) + "\n", stderr)
    }

    private static func subtle(_ text: String, on stream: Stream) -> String {
        render(text, colors: [.dim, .gray], on: stream)
    }

    private static func runtimeOutput(_ text: String, on stream: Stream) -> String {
        let normalized: String
        if text.hasPrefix("// ") {
            normalized = "/" + String(text.dropFirst(3))
        } else if text.hasPrefix("/ ") {
            normalized = "/" + String(text.dropFirst(2))
        } else {
            normalized = text
        }

        if normalized.hasPrefix("/") {
            let slash = render("/", colors: [.lightGray], on: stream)
            let message = render(String(normalized.dropFirst()), colors: [.gray], on: stream)
            return " \(slash) \(message)"
        }

        return render(normalized, colors: [.gray], on: stream)
    }

    private static func runtimeLogPrefix(
        for level: RuntimeLogLevel,
        on stream: Stream
    ) -> String {
        let label: String
        switch level {
        case .log:
            label = "LOG"
        case .debug:
            label = "DEBUG"
        case .info:
            label = "INFO"
        case .success:
            label = "SUCCESS"
        case .warning:
            label = "WARNING"
        case .error:
            label = "ERROR"
        }

        return render("[\(label)]:", colors: [runtimeColor(for: level), .dim], on: stream)
    }

    private static func runtimeLog(
        _ text: String,
        level: RuntimeLogLevel,
        on stream: Stream
    ) -> String {
        let prefix = runtimeLogPrefix(for: level, on: stream)
        let message = runtimeStyle(text, level: level, on: stream)
        return "\(prefix) \(message)"
    }

    static func subtle(_ text: String) -> String {
        subtle(text, on: .stderr)
    }

    static func runtimeOutput(_ text: String) -> String {
        runtimeOutput(text, on: .stdout)
    }

    static func subtleStdout(_ text: String) -> String {
        subtle(text, on: .stdout)
    }

    static func captionStdout(_ text: String) -> String {
        render(text, colors: [.gray, .dim], on: .stdout)
    }

    static func accentStdout(_ text: String, color: TerminalColor, bold: Bool = false) -> String {
        var colors = [color]
        if bold {
            colors.append(.bold)
        }
        return render(text, colors: colors, on: .stdout)
    }

    static func accentStdout(
        _ text: String,
        color: TerminalAccentColor,
        bold: Bool = false
    ) -> String {
        var colors = [color.string]
        if bold {
            colors.append(TerminalColor.bold.string)
        }

        guard supportsColor(on: .stdout) else {
            return text
        }

        return "\(colors.joined())\(text)\(TerminalColor.reset.string)"
    }

    static func subtleOut(_ text: String) {
        Swift.print(subtle(text, on: .stdout))
    }

    static func runtimeOutputOut(_ text: String) {
        Swift.print(runtimeOutput(text, on: .stdout))
    }

    static func runtimeLogOut(_ text: String, level: RuntimeLogLevel) {
        Swift.print(runtimeLog(text, level: level, on: .stdout))
    }

    static func runtimeLogErr(_ text: String, level: RuntimeLogLevel) {
        fputs(runtimeLog(text, level: level, on: .stderr) + "\n", stderr)
    }

    static func light(_ text: String) -> String {
        render(text, colors: [.lightGray], on: .stderr)
    }

    static func out(
        _ text: String,
        level: CLIStatusLevel,
        bold: Bool = false,
        dimmed: Bool = false
    ) {
        Swift.print(style(text, level: level, bold: bold, dimmed: dimmed, on: .stdout))
    }

    static func err(
        _ text: String,
        level: CLIStatusLevel,
        bold: Bool = false,
        dimmed: Bool = false
    ) {
        fputs(style(text, level: level, bold: bold, dimmed: dimmed, on: .stderr) + "\n", stderr)
    }
}
