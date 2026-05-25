import Testing
@testable import RangeBackendSwift

@Suite("Shadow style lowering")
struct ShadowStyleLoweringTests {
    @Test("HTML CSS lowering emits ordered box shadow layers")
    func htmlCSSLoweringEmitsOrderedBoxShadowLayers() {
        let stack = LoweredShadowStack(layers: [
            LoweredShadowLayer(
                placement: .outer,
                offset: LoweredShadowVector(x: 0, y: 8),
                radius: LoweredShadowRadius(blur: 24, spread: -4),
                color: LoweredShadowColor(red: 0, green: 0, blue: 0, alpha: 0.18)
            ),
            LoweredShadowLayer(
                placement: .inner,
                offset: LoweredShadowVector(x: 0, y: 1),
                radius: LoweredShadowRadius(blur: 2, spread: 0),
                color: LoweredShadowColor(red: 1, green: 1, blue: 1, alpha: 0.65)
            ),
        ])

        let css = ShadowStyleLowerer.lowerToHTMLCSS(stack).inlineStyle

        #expect(css == "box-shadow: 0px 8px 24px -4px rgba(0, 0, 0, 0.18), inset 0px 1px 2px 0px rgba(255, 255, 255, 0.65);")
    }

    @Test("Swift graphics lowering emits outer and inner operations")
    func swiftGraphicsLoweringEmitsOuterAndInnerOperations() {
        let stack = LoweredShadowStack(layers: [
            LoweredShadowLayer(
                placement: .outer,
                offset: LoweredShadowVector(x: 2, y: 3),
                radius: LoweredShadowRadius(blur: 12, spread: 0),
                color: LoweredShadowColor(red: 0.1, green: 0.2, blue: 0.3, alpha: 0.4)
            ),
            LoweredShadowLayer(
                placement: .inner,
                offset: LoweredShadowVector(x: -1, y: 1),
                radius: LoweredShadowRadius(blur: 3, spread: 0),
                color: LoweredShadowColor(red: 1, green: 1, blue: 1, alpha: 0.5)
            ),
        ])

        let swift = ShadowStyleLowerer.lowerToSwiftGraphics(stack).modifierChain

        #expect(swift.contains(".shadow(color: Color(red: 0.1, green: 0.2, blue: 0.3, opacity: 0.4), radius: 12, x: 2, y: 3)"))
        #expect(swift.contains(".overlay { shape.fill(Color(red: 1, green: 1, blue: 1, opacity: 0.5)).blur(radius: 3).offset(x: -1, y: 1).mask(shape) }"))
    }

    @Test("HTML CSS rectangle lowering emits dimensions and configured shadows")
    func htmlCSSRectangleLoweringEmitsDimensionsAndConfiguredShadows() {
        let rectangle = LoweredRectangleSurface(width: 160, height: 96)

        let css = ShadowStyleLowerer.lowerRectangleToHTMLCSS(rectangle).inlineStyle

        #expect(css.contains("width: 160px;"))
        #expect(css.contains("height: 96px;"))
        #expect(css.contains("box-sizing: border-box;"))
        #expect(css.contains("box-shadow: 0px 8px 24px -4px rgba(0, 0, 0, 0.18), inset 0px 1px 2px 0px rgba(255, 255, 255, 0.65);"))
    }
}
