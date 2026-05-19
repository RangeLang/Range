import ArgumentParser
import GradientBackendSwift
import GradientSyntax

enum ErrorDescription {
    static func message(for error: Error) -> String {
        if let diagnostic = error as? GradientDiagnostic {
            return diagnostic.description
        }
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
        return "Unknown error"
    }
}
