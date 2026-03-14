public struct ShadowStyle: StyleModifier {
    public init(
        offset: Offset? = nil,
        blur: Int,
        spread: Int? = nil,
        color: Color? = nil
    ) {
        self.offset = offset
        self.blur = blur
        self.spread = spread
        self.color = color
    }

    public let offset: Offset?
    public let blur: Int
    public let spread: Int?
    public let color: Color?

    public var cssStyle: String? {
        guard offset != nil || blur != nil || spread != nil || color != nil else {
            return nil
        }
        let sx = offset?.x ?? 0
        let sy = offset?.y ?? 0
        let sb = blur
        let ss = spread ?? 0
        let sc = color?.cssValue ?? "rgba(0, 0, 0, 0.2)"
        return "--sh: \(sx)px \(sy)px \(sb)px \(ss)px \(sc)"
    }

    public var cssClass: String? {
        "shadow"
    }

    public var extraAttributes: [(name: String, value: String)] { [] }

}

public extension Component {
    func shadow(
        offset: Offset? = nil,
        blur: Int,
        spread: Int? = nil,
        color: Color? = nil
    ) -> some Component {
        style(ShadowStyle(offset: offset, blur: blur, spread: spread, color: color))
    }
}
