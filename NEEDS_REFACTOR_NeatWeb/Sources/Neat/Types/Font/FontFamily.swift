import Foundation

public struct FontFamily: Sendable {
    public let name: String
    public let url: String?

    public init(name: String, url: String? = nil) {
        self.name = name
        self.url = url
    }

    public var isExternal: Bool {
        guard let url else { return false }
        return url.hasPrefix("http://") || url.hasPrefix("https://")
    }
}

public extension FontFamily {
    static let system = FontFamily(name: "system-ui", url: nil)

    var cssFamilyValue: String {
        "\"\(name)\", system-ui, -apple-system, BlinkMacSystemFont, \"Segoe UI\", sans-serif"
    }
}
