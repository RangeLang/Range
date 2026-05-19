import Foundation

public enum NeatDiagnosticSeverity: Sendable {
    case error
    case warning
    case information
    case hint
}

public struct NeatSourceLocation: Sendable {
    public let path: String?
    public let line: Int
    public let character: Int

    public init(path: String? = nil, line: Int, character: Int) {
        self.path = path
        self.line = line
        self.character = character
    }
}

public struct NeatSourceRange: Sendable {
    public let start: NeatSourceLocation
    public let end: NeatSourceLocation

    public init(start: NeatSourceLocation, end: NeatSourceLocation) {
        self.start = start
        self.end = end
    }
}

public struct NeatDiagnosticNote: Sendable {
    public let message: String
    public let range: NeatSourceRange?

    public init(message: String, range: NeatSourceRange? = nil) {
        self.message = message
        self.range = range
    }
}

public struct NeatDiagnostic: Error, CustomStringConvertible, Sendable {
    public let severity: NeatDiagnosticSeverity
    public let message: String
    public let source: String
    public let code: String?
    public let path: String?
    public let range: NeatSourceRange?
    public let notes: [NeatDiagnosticNote]

    public init(
        severity: NeatDiagnosticSeverity,
        message: String,
        source: String = "neat",
        code: String? = nil,
        path: String? = nil,
        range: NeatSourceRange? = nil,
        notes: [NeatDiagnosticNote] = []
    ) {
        self.severity = severity
        self.message = message
        self.source = source
        self.code = code
        self.path = path
        self.range = range
        self.notes = notes
    }

    public var description: String { message }

    public func withPath(_ path: String?) -> NeatDiagnostic {
        guard self.path == nil, let path else {
            return self
        }
        return NeatDiagnostic(
            severity: severity,
            message: message,
            source: source,
            code: code,
            path: path,
            range: range,
            notes: notes
        )
    }
}

public final class NeatDiagnosticEngine {
    public private(set) var diagnostics: [NeatDiagnostic] = []

    public init() {}

    public func emit(_ diagnostic: NeatDiagnostic) {
        diagnostics.append(diagnostic)
    }

    public func warning(
        _ message: String,
        source: String = "neat",
        code: String? = nil,
        path: String? = nil,
        range: NeatSourceRange? = nil
    ) {
        emit(
            NeatDiagnostic(
                severity: .warning,
                message: message,
                source: source,
                code: code,
                path: path,
                range: range
            )
        )
    }

    public func error(
        _ message: String,
        source: String = "neat",
        code: String? = nil,
        path: String? = nil,
        range: NeatSourceRange? = nil
    ) {
        emit(
            NeatDiagnostic(
                severity: .error,
                message: message,
                source: source,
                code: code,
                path: path,
                range: range
            )
        )
    }

    public func information(
        _ message: String,
        source: String = "neat",
        code: String? = nil,
        path: String? = nil,
        range: NeatSourceRange? = nil
    ) {
        emit(
            NeatDiagnostic(
                severity: .information,
                message: message,
                source: source,
                code: code,
                path: path,
                range: range
            )
        )
    }
}

public enum NeatDiagnosticConverter {
    public static func diagnostic(from error: Error, path: String? = nil) -> NeatDiagnostic {
        if let diagnostic = error as? NeatDiagnostic {
            return diagnostic
        }
        if let parse = error as? ParseError {
            return NeatDiagnostic(
                severity: .error,
                message: parse.description,
                source: "neat-parser",
                path: path,
                range: parse.range
            )
        }
        if let semantic = error as? SemanticValidationError {
            return NeatDiagnostic(
                severity: .error,
                message: semantic.description,
                source: "neat-semantics",
                path: path
            )
        }
        return NeatDiagnostic(
            severity: .error,
            message: "Unknown error",
            source: "neat",
            path: path
        )
    }
}
