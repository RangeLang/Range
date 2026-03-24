import Foundation

public struct InterpolatedString {
    public let segments: [StringSegment]
}

public indirect enum StringSegment {
    case text(String)
    case expression(Expression)
}
