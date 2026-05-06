import Foundation

public struct ParseError: Error, CustomStringConvertible {
    public let message: String
    public let range: NeatSourceRange?

    public init(_ message: String, range: NeatSourceRange? = nil) {
        self.message = message
        self.range = range
    }

    public var description: String { message }
}
