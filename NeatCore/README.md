# NeatCore

Foundational Neat-provided declarations live here.

## Structure

- `Package.neat` declares the `NeatCore` package manifest
- `Sources/Packaging/Package.neat` defines the core `#Package` declaration
- `Sources/Graphics/Color.neat` defines the core `#Color` declaration
- `Sources/Graphics/RGB.neat`, `HSL.neat`, and `OKLCH.neat` define color-space projections on `Color`

## Graphics

`Color` currently exposes:

- named colors through `case red, blue, green, white, black, gray, clear`
- RGB projection entrypoints with optional trailing `alpha`
- HSL projection entrypoints with optional trailing `alpha`
- OKLCH projection entrypoints with optional trailing `alpha`
