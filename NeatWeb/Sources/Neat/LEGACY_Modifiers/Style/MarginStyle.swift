public struct MarginStyle: StyleModifier {
    public let value: Double
    public let edges: EdgeSet

    public init(value: Double, edges: EdgeSet = .all) {
        self.value = value
        self.edges = edges
    }

    public var cssStyle: String? {
        let v = value

        var parts: [String] = []

        if edges.isAll || edges.contains(.top) {
            parts.append("--mt: \(v);")
        }
        if edges.isAll || edges.contains(.leading) {
            parts.append("--ml: \(v);")
        }
        if edges.isAll || edges.contains(.bottom) {
            parts.append("--mb: \(v);")
        }
        if edges.isAll || edges.contains(.trailing) {
            parts.append("--mr: \(v);")
        }

        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    public var cssClass: String? {
        "margin"
    }

    public var extraAttributes: [(name: String, value: String)] { [] }

    public var utilityRule: (name: String, declaration: String)? { nil }

    public var requiresLayoutBox: Bool { true }
}

public extension Component {
    func margin(_ value: Double) -> some Component {
        style(MarginStyle(value: value))
    }

    func margin(_ edges: EdgeSet, _ value: Double) -> some Component {
        style(MarginStyle(value: value, edges: edges))
    }
}
