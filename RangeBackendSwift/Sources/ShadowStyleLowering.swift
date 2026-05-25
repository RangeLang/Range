import Foundation

struct LoweredShadowColor: Equatable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double
}

struct LoweredShadowVector: Equatable {
    var x: Double
    var y: Double
}

struct LoweredShadowRadius: Equatable {
    var blur: Double
    var spread: Double
}

enum LoweredShadowPlacement: Equatable {
    case outer
    case inner
}

struct LoweredShadowLayer: Equatable {
    var placement: LoweredShadowPlacement
    var offset: LoweredShadowVector
    var radius: LoweredShadowRadius
    var color: LoweredShadowColor
}

struct LoweredShadowStack: Equatable {
    var layers: [LoweredShadowLayer]
}

struct LoweredRectangleSurface: Equatable {
    var width: Double
    var height: Double
}

struct LoweredShadowConfiguration: Equatable {
    var outer: LoweredShadowLayer
    var inner: LoweredShadowLayer

    var stack: LoweredShadowStack {
        LoweredShadowStack(layers: [outer, inner])
    }
}

struct SwiftGraphicsShadowLowering {
    var modifierChain: String
}

struct HTMLCSSShadowLowering {
    var declarations: [String]

    var inlineStyle: String {
        declarations.joined(separator: " ")
    }
}

struct HTMLCSSRectangleLowering {
    var declarations: [String]

    var inlineStyle: String {
        declarations.joined(separator: " ")
    }
}

enum ShadowStyleLowerer {
    static let defaultRectangleConfiguration = LoweredShadowConfiguration(
        outer: LoweredShadowLayer(
            placement: .outer,
            offset: LoweredShadowVector(x: 0, y: 8),
            radius: LoweredShadowRadius(blur: 24, spread: -4),
            color: LoweredShadowColor(red: 0, green: 0, blue: 0, alpha: 0.18)
        ),
        inner: LoweredShadowLayer(
            placement: .inner,
            offset: LoweredShadowVector(x: 0, y: 1),
            radius: LoweredShadowRadius(blur: 2, spread: 0),
            color: LoweredShadowColor(red: 1, green: 1, blue: 1, alpha: 0.65)
        )
    )

    static func lowerToSwiftGraphics(_ stack: LoweredShadowStack) -> SwiftGraphicsShadowLowering {
        let modifiers = stack.layers.map { layer in
            switch layer.placement {
            case .outer:
                return """
                    .shadow(color: \(swiftUIColor(layer.color)), radius: \(number(layer.radius.blur)), x: \(number(layer.offset.x)), y: \(number(layer.offset.y)))
                    """
            case .inner:
                return """
                    .overlay { shape.fill(\(swiftUIColor(layer.color))).blur(radius: \(number(layer.radius.blur))).offset(x: \(number(layer.offset.x)), y: \(number(layer.offset.y))).mask(shape) }
                    """
            }
        }

        return SwiftGraphicsShadowLowering(modifierChain: modifiers.joined(separator: "\n"))
    }

    static func lowerToHTMLCSS(_ stack: LoweredShadowStack) -> HTMLCSSShadowLowering {
        guard !stack.layers.isEmpty else {
            return HTMLCSSShadowLowering(declarations: [])
        }

        let shadows = stack.layers.map { layer in
            [
                layer.placement == .inner ? "inset" : nil,
                "\(cssLength(layer.offset.x)) \(cssLength(layer.offset.y))",
                cssLength(layer.radius.blur),
                cssLength(layer.radius.spread),
                cssRGBA(layer.color),
            ]
            .compactMap { $0 }
            .joined(separator: " ")
        }

        return HTMLCSSShadowLowering(declarations: ["box-shadow: \(shadows.joined(separator: ", "));"])
    }

    static func lowerRectangleToHTMLCSS(
        _ rectangle: LoweredRectangleSurface,
        configuration: LoweredShadowConfiguration = defaultRectangleConfiguration
    ) -> HTMLCSSRectangleLowering {
        let shadow = lowerToHTMLCSS(configuration.stack)
        return HTMLCSSRectangleLowering(
            declarations: [
                "width: \(cssLength(rectangle.width));",
                "height: \(cssLength(rectangle.height));",
                "box-sizing: border-box;",
            ] + shadow.declarations
        )
    }

    private static func swiftUIColor(_ color: LoweredShadowColor) -> String {
        "Color(red: \(number(color.red)), green: \(number(color.green)), blue: \(number(color.blue)), opacity: \(number(color.alpha)))"
    }

    private static func cssRGBA(_ color: LoweredShadowColor) -> String {
        let red = Int((clamp(color.red) * 255.0).rounded())
        let green = Int((clamp(color.green) * 255.0).rounded())
        let blue = Int((clamp(color.blue) * 255.0).rounded())
        return "rgba(\(red), \(green), \(blue), \(number(clamp(color.alpha))))"
    }

    private static func cssLength(_ value: Double) -> String {
        "\(number(value))px"
    }

    private static func number(_ value: Double) -> String {
        let rounded = (value * 1000.0).rounded() / 1000.0
        if rounded == rounded.rounded() {
            return String(Int(rounded))
        }
        return String(rounded)
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, 0.0), 1.0)
    }
}
