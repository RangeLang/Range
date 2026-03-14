import Foundation

public struct FontFamilyStyle: StyleModifier {
    public let font: FontFamily

    public init(_ font: FontFamily) {
        self.font = font
    }

    public var cssStyle: String? {
        "--ff: \(font.cssFamilyValue);"
    }

    public var cssClass: String? { "font-family" }

    public var extraAttributes: [(name: String, value: String)] { [] }
}

public extension Component {
    func font(_ font: FontFamily) -> some Component {
        style(FontFamilyStyle(font))
    }
}
