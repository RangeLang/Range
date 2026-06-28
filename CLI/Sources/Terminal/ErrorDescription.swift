import ArgumentParser
import RangeEmission
import RangeCompiler

enum ErrorDescription {
    static func message(for error: Error) -> String {
        if let diagnostic = error as? RangeDiagnostic {
            return diagnostic.description
        }
        if let parse = error as? ParseError {
            return parse.description
        }
        if let validation = error as? ValidationError {
            return validation.message
        }
        if let backend = error as? SwiftBackendError {
            return backend.message
        }
        return "Unknown error"
    }
}
