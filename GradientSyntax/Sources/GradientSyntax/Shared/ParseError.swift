import Foundation

public struct ParseError: Error, CustomStringConvertible {
    public let message: String
    public let range: GradientSourceRange?

    public init(_ message: String, range: GradientSourceRange? = nil) {
        self.message = message
        self.range = range
    }

    public var description: String { message }
}
