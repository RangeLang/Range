struct ImageAttributeModifier: StyleModifier {
    let attributes: [(name: String, value: String)]

    init(_ attributes: [(name: String, value: String)]) {
        self.attributes = attributes
    }

    var cssStyle: String? { nil }
    var cssClass: String? { nil }
    var extraAttributes: [(name: String, value: String)] { attributes }
    var utilityRule: (name: String, declaration: String)? { nil }
    var requiresLayoutBox: Bool { false }
}
