public struct PaddingStyle: StyleModifier {
    public let edges: EdgeSet
    public let value: Double

    public init(edges: EdgeSet = .all, value: Double) {
        self.edges = edges
        self.value = value
    }

    public var cssStyle: String? {
        let v = PaddingStyle.scaledValue(for: value)

        var parts: [String] = []

        if edges.isAll || edges.contains(.top) {
            parts.append("--pt: \(v);")
        }
        if edges.isAll || edges.contains(.leading) {
            parts.append("--pl: \(v);")
        }
        if edges.isAll || edges.contains(.bottom) {
            parts.append("--pb: \(v);")
        }
        if edges.isAll || edges.contains(.trailing) {
            parts.append("--pr: \(v);")
        }

        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    public var cssClass: String? { "padding" }
    public var extraAttributes: [(name: String, value: String)] { [] }
    public var utilityRule: (name: String, declaration: String)? { nil }
    public var requiresLayoutBox: Bool { true }

    private static func scaledValue(for raw: Double) -> String {
        return "\(raw)"
    }

}

public extension Component {
    /// Uniform padding on all edges.
    func padding(_ value: Double) -> some Component {
        style(PaddingStyle(edges: .all, value: value))
    }

    /// Directional padding using an `EdgeSet`, e.g. `padding([.leading, .top], 2)`.
    func padding(_ edges: EdgeSet, _ value: Double) -> some Component {
        style(PaddingStyle(edges: edges, value: value))
    }

}
