import Foundation

public enum RangeDiagnosticSeverity: Sendable {
    case error
    case warning
    case information
    case hint
}

public struct RangeSourceLocation: Sendable {
    public let path: String?
    public let line: Int
    public let character: Int

    public init(path: String? = nil, line: Int, character: Int) {
        self.path = path
        self.line = line
        self.character = character
    }
}

public struct RangeSourceRange: Sendable {
    public let start: RangeSourceLocation
    public let end: RangeSourceLocation

    public init(start: RangeSourceLocation, end: RangeSourceLocation) {
        self.start = start
        self.end = end
    }
}

public struct RangeDiagnosticNote: Sendable {
    public let message: String
    public let range: RangeSourceRange?

    public init(message: String, range: RangeSourceRange? = nil) {
        self.message = message
        self.range = range
    }
}

public struct RangeDiagnostic: Error, CustomStringConvertible, Sendable {
    public let severity: RangeDiagnosticSeverity
    public let message: String
    public let source: String
    public let code: String?
    public let path: String?
    public let range: RangeSourceRange?
    public let notes: [RangeDiagnosticNote]

    public init(
        severity: RangeDiagnosticSeverity,
        message: String,
        source: String = "range",
        code: String? = nil,
        path: String? = nil,
        range: RangeSourceRange? = nil,
        notes: [RangeDiagnosticNote] = []
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

    public func withPath(_ path: String?) -> RangeDiagnostic {
        guard self.path == nil, let path else {
            return self
        }
        return RangeDiagnostic(
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

public final class RangeDiagnosticEngine {
    public private(set) var diagnostics: [RangeDiagnostic] = []

    public init() {}

    public func emit(_ diagnostic: RangeDiagnostic) {
        diagnostics.append(diagnostic)
    }

    public func warning(
        _ message: String,
        source: String = "range",
        code: String? = nil,
        path: String? = nil,
        range: RangeSourceRange? = nil
    ) {
        emit(
            RangeDiagnostic(
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
        source: String = "range",
        code: String? = nil,
        path: String? = nil,
        range: RangeSourceRange? = nil
    ) {
        emit(
            RangeDiagnostic(
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
        source: String = "range",
        code: String? = nil,
        path: String? = nil,
        range: RangeSourceRange? = nil
    ) {
        emit(
            RangeDiagnostic(
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

public enum RangeDiagnosticConverter {
    public static func diagnostic(from error: Error, path: String? = nil) -> RangeDiagnostic {
        if let diagnostic = error as? RangeDiagnostic {
            return diagnostic
        }
        if let parse = error as? ParseError {
            return RangeDiagnostic(
                severity: .error,
                message: parse.description,
                source: "range-parser",
                path: path,
                range: parse.range
            )
        }
        if let semantic = error as? SemanticValidationError {
            return RangeDiagnostic(
                severity: .error,
                message: semantic.description,
                source: "range-semantics",
                path: path
            )
        }
        return RangeDiagnostic(
            severity: .error,
            message: "Unknown error",
            source: "range",
            path: path
        )
    }
}
