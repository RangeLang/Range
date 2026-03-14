# NeatCore

Foundational Neat-provided declarations live here.

## Structure

- `Package.neat` declares the `NeatCore` package manifest
- `Sources/Packaging/Package.neat` defines the core `#Package` declaration
- `Sources/Graphics/Color.neat` defines the core `#Color` declaration
- `Sources/Graphics/RGB.neat`, `HSL.neat`, and `OKLCH.neat` define color-space projections on `Color`
- `Sources/Logging/Logger.neat` defines the core `#Logger` declaration

## Logging

`Logger` currently exposes:

- `@log(text: String)` for default runtime logging
- `@debug(text: String)` for debug-oriented output
- `@info(text: String)` for informational output
- `@success(text: String)` for success output
- `@warning(text: String)` for warning output
- `@error(text: String)` for error output

## Graphics

`Color` currently exposes:

- predefined named colors as `value` members on `Color`
- RGB projection entrypoints with optional trailing `alpha`
- HSL projection entrypoints with optional trailing `alpha`
- OKLCH projection entrypoints with optional trailing `alpha`
