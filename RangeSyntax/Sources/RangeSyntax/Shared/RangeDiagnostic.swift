import Foundation

public enum GradientDiagnosticSeverity: Sendable {
    case error
    case warning
    case information
    case hint
}

public struct GradientSourceLocation: Sendable {
    public let path: String?
    public let line: Int
    public let character: Int

    public init(path: String? = nil, line: Int, character: Int) {
        self.path = path
        self.line = line
        self.character = character
    }
}

public struct GradientSourceRange: Sendable {
    public let start: GradientSourceLocation
    public let end: GradientSourceLocation

    public init(start: GradientSourceLocation, end: GradientSourceLocation) {
        self.start = start
        self.end = end
    }
}

public struct GradientDiagnosticNote: Sendable {
    public let message: String
    public let range: GradientSourceRange?

    public init(message: String, range: GradientSourceRange? = nil) {
        self.message = message
        self.range = range
    }
}

public struct GradientDiagnostic: Error, CustomStringConvertible, Sendable {
    public let severity: GradientDiagnosticSeverity
    public let message: String
    public let source: String
    public let code: String?
    public let path: String?
    public let range: GradientSourceRange?
    public let notes: [GradientDiagnosticNote]

    public init(
        severity: GradientDiagnosticSeverity,
        message: String,
        source: String = "gradient",
        code: String? = nil,
        path: String? = nil,
        range: GradientSourceRange? = nil,
        notes: [GradientDiagnosticNote] = []
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

    public func withPath(_ path: String?) -> GradientDiagnostic {
        guard self.path == nil, let path else {
            return self
        }
        return GradientDiagnostic(
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

public final class GradientDiagnosticEngine {
    public private(set) var diagnostics: [GradientDiagnostic] = []

    public init() {}

    public func emit(_ diagnostic: GradientDiagnostic) {
        diagnostics.append(diagnostic)
    }

    public func warning(
        _ message: String,
        source: String = "gradient",
        code: String? = nil,
        path: String? = nil,
        range: GradientSourceRange? = nil
    ) {
        emit(
            GradientDiagnostic(
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
        source: String = "gradient",
        code: String? = nil,
        path: String? = nil,
        range: GradientSourceRange? = nil
    ) {
        emit(
            GradientDiagnostic(
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
        source: String = "gradient",
        code: String? = nil,
        path: String? = nil,
        range: GradientSourceRange? = nil
    ) {
        emit(
            GradientDiagnostic(
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

public enum GradientDiagnosticConverter {
    public static func diagnostic(from error: Error, path: String? = nil) -> GradientDiagnostic {
        if let diagnostic = error as? GradientDiagnostic {
            return diagnostic
        }
        if let parse = error as? ParseError {
            return GradientDiagnostic(
                severity: .error,
                message: parse.description,
                source: "gradient-parser",
                path: path,
                range: parse.range
            )
        }
        if let semantic = error as? SemanticValidationError {
            return GradientDiagnostic(
                severity: .error,
                message: semantic.description,
                source: "gradient-semantics",
                path: path
            )
        }
        return GradientDiagnostic(
            severity: .error,
            message: "Unknown error",
            source: "gradient",
            path: path
        )
    }
}
