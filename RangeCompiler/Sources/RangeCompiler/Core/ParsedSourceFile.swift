import Foundation

public struct ParsedSourceFile {
    public let path: String
    public let source: String?
    public let sourceFile: SourceFileNode

    public init(path: String, source: String? = nil, sourceFile: SourceFileNode) {
        self.path = path
        self.source = source
        self.sourceFile = sourceFile
    }
}
