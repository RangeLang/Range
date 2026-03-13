public struct Axis: OptionSet, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let horizontal = Axis(rawValue: 1 << 0)
    public static let vertical = Axis(rawValue: 1 << 1)
}
