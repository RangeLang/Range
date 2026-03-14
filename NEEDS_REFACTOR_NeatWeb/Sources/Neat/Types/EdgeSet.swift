public struct EdgeSet: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let top    = EdgeSet(rawValue: 1 << 0)
    public static let leading  = EdgeSet(rawValue: 1 << 1)
    public static let bottom = EdgeSet(rawValue: 1 << 2)
    public static let trailing   = EdgeSet(rawValue: 1 << 3)

    public static let all: EdgeSet = [.top, .leading, .bottom, .trailing]
    public static let horizontal: EdgeSet = [.trailing, .leading]
    public static let vertical: EdgeSet = [.top, .bottom]

    public var isAll: Bool { self == .all }
}
