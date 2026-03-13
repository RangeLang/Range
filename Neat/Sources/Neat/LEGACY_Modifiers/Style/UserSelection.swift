import Foundation


public struct UserSelection: StyleModifier {

    public init() {}

    // MARK: - OpenTagModifier

    /// No inline style; we rely on the utility class instead.
    public var cssStyle: String? { nil }

    /// Utility class name applied to the component's opening tag.
    public var cssClass: String? { "user-selection" }

    /// No additional attributes required.
    public var extraAttributes: [(name: String, value: String)] { [] }

    /// Utility rule that re-enables text selection.
    ///
    /// This will be emitted once per component that uses the modifier,
    /// allowing the runtime to keep all styling in CSS rather than inline.
    public var utilityRule: (name: String, declaration: String)? {
        (
            name: "user-selection",
            declaration: """
            -webkit-user-select: text;
            -moz-user-select: text;
            -ms-user-select: text;
            user-select: text;
            """
        )
    }

    /// Selectability does not require an extra layout box.
}

public extension Component {
    func selection() -> some Component { style(UserSelection()) }
}
