public enum HorizontalAlignment: Sendable {
    /// Align content to the leading edge on the horizontal axis.
    ///
    /// - For left-to-right layouts, this corresponds to the left side.
    /// - For right-to-left layouts, this corresponds to the right side.
    case leading

    /// Center content along the horizontal axis.
    case center

    /// Align content to the trailing edge on the horizontal axis.
    ///
    /// - For left-to-right layouts, this corresponds to the right side.
    /// - For right-to-left layouts, this corresponds to the left side.
    case trailing

    /// Stretch content to fill the available horizontal space where applicable.
    ///
    /// This is typically interpreted as `align-self: stretch` /
    /// `justify-content: space-between`-style behavior in flex layouts,
    /// depending on context.
    case stretch
}

public enum VerticalAlignment: Sendable {
    /// Align content to the top edge on the vertical axis.
    case top

    /// Center content along the vertical axis.
    case center

    /// Align content to the bottom edge on the vertical axis.
    case bottom

    /// Stretch content to fill the available vertical space where applicable.
    ///
    /// This is typically interpreted as `align-self: stretch` /
    /// `justify-content: space-between`-style behavior in flex layouts,
    /// depending on context.
    case stretch
}

/// Describes a 2D alignment using independent horizontal and vertical values.
///
/// This is intended to be used by layout primitives such as `VStack` and
/// `HStack` to control how their children are placed within the available
/// space.
///
/// Example usage:
///
/// ```swift
/// VStack(alignment: .init(horizontal: .leading, vertical: .center)) { ... }
/// HStack(alignment: .center) { ... }
/// ```
public struct Alignment: Equatable, Hashable, Sendable {
    public var horizontal: HorizontalAlignment
    public var vertical: VerticalAlignment

    @inlinable
    public init(horizontal: HorizontalAlignment, vertical: VerticalAlignment) {
        self.horizontal = horizontal
        self.vertical = vertical
    }

    // Common presets

    /// Centered on both axes.
    public static let center = Alignment(horizontal: .center, vertical: .center)

    /// Top-leading corner.
    public static let topLeading = Alignment(horizontal: .leading, vertical: .top)

    /// Top-center.
    public static let top = Alignment(horizontal: .center, vertical: .top)

    /// Top-trailing corner.
    public static let topTrailing = Alignment(horizontal: .trailing, vertical: .top)

    /// Center-leading.
    public static let leading = Alignment(horizontal: .leading, vertical: .center)

    /// Center-trailing.
    public static let trailing = Alignment(horizontal: .trailing, vertical: .center)

    /// Bottom-leading corner.
    public static let bottomLeading = Alignment(horizontal: .leading, vertical: .bottom)

    /// Bottom-center.
    public static let bottom = Alignment(horizontal: .center, vertical: .bottom)

    /// Bottom-trailing corner.
    public static let bottomTrailing = Alignment(horizontal: .trailing, vertical: .bottom)
}
