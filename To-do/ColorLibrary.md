# Color Library

RangeCore should model color as a value in a color space:

```range
Color<.rgb>
Color<.hsl>
Color<.hsv>
Color<.cmyk>
Color<.oklch>
```

The color space is not just a namespace label. It defines how the axes interact
to produce light.

## Core Shape

```range
enum ColorSpace {
    case rgb
    case hsl
    case hsv
    case cmyk
    case oklch
}

construct Color<let space: ColorSpace> {
    let storage: ComponentStorage<Float>
}
```

The generic `space` parameter carries the authoring model. The components live
in `ComponentStorage<Float>`, matching the existing vector/storage boundary in
RangeCore. Named constructors preserve axis meaning at the call site.

```range
ColorLibrary.rgb(red: 1.0, green: 0.0, blue: 0.0, alpha: 1.0)
ColorLibrary.hsl(hue: 0.0, saturation: 1.0, lightness: 0.5, alpha: 1.0)
ColorLibrary.oklch(lightness: 0.7, chroma: 0.2, hue: 30.0, alpha: 1.0)
```

## Axes And Light

Each color space should also be describable as metadata:

```range
construct ColorAxis {
    let name: Identifier
}

construct ColorSpaceModel<let space: ColorSpace> {
    let axes: [ColorAxis]
    let light: MathFunction<Color<space>, Color<.rgb>>
}
```

`axes` says what the color components mean. `light` says how those components
produce normalized visual light.

This keeps the model honest:

- RGB axes mix additively into light.
- HSL axes describe hue, saturation, and lightness before conversion.
- HSV axes describe hue, saturation, and value before conversion.
- CMYK axes describe subtractive print-style components before conversion.
- OKLCH axes describe perceptual lightness, chroma, and hue before conversion.

## Normalized Output

There is no separate visual-color wrapper. `Color<space>` is already the visual
color model. When a renderer needs emitted light, it asks the color space to
lower into RGB light.

```range
function light(_ value: Color<.rgb>): Color<.rgb>
function light<let space: ColorSpace>(_ value: Color<space>): Color<.rgb>
```

RGB light maps to itself. Other spaces are declared as conversion surfaces until
the color conversion math is implemented in RangeCore or backed by
runtime/compiler support.

## Vector Lowering

Using `ComponentStorage<Float>` makes vector lowering direct:

```range
Color<.rgb>.storage -> ComponentStorage<Float>
ComponentStorage<Float> -> Vector<4, Float>
```

The lowering should preserve the `Color<space>` type until a target explicitly
needs raw components. That way `Color<.hsl>` does not accidentally become an RGB
vector before the color-space `light` function has converted it.
