import Foundation

public struct ParseError: Error, CustomStringConvertible, LocalizedError {
    public let message: String
    public let range: RangeSourceRange?

    public init(_ message: String, range: RangeSourceRange? = nil) {
        self.message = message
        self.range = range
    }

    public var description: String { message }

    public var errorDescription: String? { message }
}
