import Foundation

/// A set of individual corners on a rectangular element.
///
/// This mirrors the semantic shape of SwiftUI-style APIs, allowing you to
/// express both specific corners and grouped convenience sets.
///
/// Examples:
///
/// - A single corner:
///   - `.topLeading`
///   - `.bottomTrailing`
///
/// - Groups:
///   - `.top`          → top-leading + top-trailing
///   - `.bottom`       → bottom-leading + bottom-trailing
///   - `.leading`      → top-leading + bottom-leading
///   - `.trailing`     → top-trailing + bottom-trailing
///
/// - All corners:
///   - `.all`
public struct CornerSet: OptionSet, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    // MARK: - Individual corners

    /// Top-left corner in a left-to-right coordinate system.
    /// Conceptually equivalent to "top leading".
    public static let topLeading    = CornerSet(rawValue: 1 << 0)

    /// Top-right corner in a left-to-right coordinate system.
    /// Conceptually equivalent to "top trailing".
    public static let topTrailing   = CornerSet(rawValue: 1 << 1)

    /// Bottom-left corner in a left-to-right coordinate system.
    /// Conceptually equivalent to "bottom leading".
    public static let bottomLeading = CornerSet(rawValue: 1 << 2)

    /// Bottom-right corner in a left-to-right coordinate system.
    /// Conceptually equivalent to "bottom trailing".
    public static let bottomTrailing = CornerSet(rawValue: 1 << 3)

    // MARK: - Groups

    /// All four corners.
    public static let all: CornerSet = [
        .topLeading,
        .topTrailing,
        .bottomLeading,
        .bottomTrailing
    ]

    /// Top edge corners (top-leading and top-trailing).
    public static let top: CornerSet = [
        .topLeading,
        .topTrailing
    ]

    /// Bottom edge corners (bottom-leading and bottom-trailing).
    public static let bottom: CornerSet = [
        .bottomLeading,
        .bottomTrailing
    ]

    /// Leading edge corners (top-leading and bottom-leading).
    public static let leading: CornerSet = [
        .topLeading,
        .bottomLeading
    ]

    /// Trailing edge corners (top-trailing and bottom-trailing).
    public static let trailing: CornerSet = [
        .topTrailing,
        .bottomTrailing
    ]



    // MARK: - Derived helpers

    /// Returns `true` when this set represents all four corners.
    public var isAll: Bool { self == .all }
}

public extension CornerSet {
    /// Convenience initializer that derives a `CornerSet` from an `EdgeSet`.
    ///
    /// This is useful when APIs accept edge-based specifications but need to
    /// reason about concrete corners. Each edge expands into the corners that
    /// touch it:
    ///
    /// - `.top`      → `.topLeading`, `.topTrailing`
    /// - `.bottom`   → `.bottomLeading`, `.bottomTrailing`
    /// - `.leading`  → `.topLeading`, `.bottomLeading`
    /// - `.trailing` → `.topTrailing`, `.bottomTrailing`
    ///
    /// Combined edges (e.g. `.horizontal`, `.vertical`, or custom unions)
    /// simply OR the resulting corner sets together.
    init(edges: EdgeSet) {
        var result: CornerSet = []

        if edges.contains(.top) {
            result.insert(.topLeading)
            result.insert(.topTrailing)
        }
        if edges.contains(.bottom) {
            result.insert(.bottomLeading)
            result.insert(.bottomTrailing)
        }
        if edges.contains(.leading) {
            result.insert(.topLeading)
            result.insert(.bottomLeading)
        }
        if edges.contains(.trailing) {
            result.insert(.topTrailing)
            result.insert(.bottomTrailing)
        }

        self = result
    }
}
