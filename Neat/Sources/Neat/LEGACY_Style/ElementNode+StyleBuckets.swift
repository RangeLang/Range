import Foundation

extension ElementNode {

    /// Returns a new ElementNode tree where each ElementNode's inline `styles` dictionary
    /// is converted into a single hashed style bucket class (e.g. `style-abc123`),
    /// registered in the ComponentStylesRegistry, and removed from the inline style map.
    func withStyleBuckets(context: RenderContext?) -> ElementNode {
        guard let context else { return self }
        switch self {
        case .text:
            return self

        case .fragment(let nodes):
            let newNodes = nodes.map { $0.withStyleBuckets(context: context) }
            return .fragment(newNodes)

        case .element(let tag, var attributes, var classes, var styles, var children):
            // First, recurse into children so their buckets are created as well.
            children = children.map { $0.withStyleBuckets(context: context) }

            guard !styles.isEmpty else {
                return .element(tag: tag, attributes: attributes, classes: classes, styles: styles, children: children)
            }

            let declarations: [(String, String)] = styles.map { (key: String, value: StyleValue) in
                (key, value.value)
            }

            var stackDeclarations: [(String, String)] = []
            var paddingDeclarations: [(String, String)] = []
            var marginDeclarations: [(String, String)] = []
            var radiusDeclarations: [(String, String)] = []
            var textColorDeclarations: [(String, String)] = []
            var backgroundColorDeclarations: [(String, String)] = []
            var borderColorDeclarations: [(String, String)] = []
            var borderDeclarations: [(String, String)] = []
            var outlineDeclarations: [(String, String)] = []
            var shadowDeclarations: [(String, String)] = []
            var offsetDeclarations: [(String, String)] = []
            var zstackDeclarations: [(String, String)] = []
            var zIndexDeclarations: [(String, String)] = []
            var otherDeclarations: [(String, String)] = []
            for declaration in declarations {
                if declaration.0.hasPrefix("--stack-") {
                    stackDeclarations.append(declaration)
                } else if declaration.0 == "--pt" || declaration.0 == "--pr" || declaration.0 == "--pb" || declaration.0 == "--pl" {
                    paddingDeclarations.append(declaration)
                } else if declaration.0 == "--mt" || declaration.0 == "--mr" || declaration.0 == "--mb" || declaration.0 == "--ml" {
                    marginDeclarations.append(declaration)
                } else if declaration.0 == "--cr-tl"
                            || declaration.0 == "--cr-tr"
                            || declaration.0 == "--cr-br"
                            || declaration.0 == "--cr-bl" {
                    radiusDeclarations.append(declaration)
                } else if declaration.0 == "--c" {
                    textColorDeclarations.append(declaration)
                } else if declaration.0 == "--bg" {
                    backgroundColorDeclarations.append(declaration)
                } else if declaration.0 == "--bc" {
                    borderColorDeclarations.append(declaration)
                } else if declaration.0 == "--bw" || declaration.0 == "--bs" {
                    borderDeclarations.append(declaration)
                } else if declaration.0 == "--ow" || declaration.0 == "--os" || declaration.0 == "--oc" {
                    outlineDeclarations.append(declaration)
                } else if declaration.0 == "--sh" {
                    shadowDeclarations.append(declaration)
                } else if declaration.0 == "--ox" || declaration.0 == "--oy" {
                    offsetDeclarations.append(declaration)
                } else if declaration.0 == "--z-align" || declaration.0 == "--z-justify" {
                    zstackDeclarations.append(declaration)
                } else if declaration.0 == "--z" {
                    zIndexDeclarations.append(declaration)
                } else {
                    otherDeclarations.append(declaration)
                }
            }

            let bucketPairs: [(String, String)] = [
                ("stack", normalizeStyleDeclarations(stackDeclarations)),
                ("padding", normalizeStyleDeclarations(paddingDeclarations)),
                ("margin", normalizeStyleDeclarations(marginDeclarations)),
                ("radius", normalizeStyleDeclarations(radiusDeclarations)),
                ("text-color", normalizeStyleDeclarations(textColorDeclarations)),
                ("background-color", normalizeStyleDeclarations(backgroundColorDeclarations)),
                ("border-color", normalizeStyleDeclarations(borderColorDeclarations)),
                ("border", normalizeStyleDeclarations(borderDeclarations)),
                ("outline", normalizeStyleDeclarations(outlineDeclarations)),
                ("shadow", normalizeStyleDeclarations(shadowDeclarations)),
                ("offset", normalizeStyleDeclarations(offsetDeclarations)),
                ("zstack", normalizeStyleDeclarations(zstackDeclarations)),
                ("z-index", normalizeStyleDeclarations(zIndexDeclarations)),
                ("base", normalizeStyleDeclarations(otherDeclarations))
            ].filter { !$0.1.isEmpty }

            guard !bucketPairs.isEmpty else {
                styles = [:]
                return .element(tag: tag, attributes: attributes, classes: classes, styles: styles, children: children)
            }

            for (bucketKey, normalized) in bucketPairs {
                let className: String
                let prefix: String
                switch bucketKey {
                case "stack":
                    prefix = "stack"
                case "padding":
                    prefix = "padding"
                case "margin":
                    prefix = "margin"
                case "radius":
                    prefix = "radius"
                case "text-color":
                    prefix = "text-color"
                case "background-color":
                    prefix = "bg-color"
                case "border-color":
                    prefix = "border-color"
                case "border":
                    prefix = "border"
                case "outline":
                    prefix = "outline"
                case "shadow":
                    prefix = "shadow"
                case "offset":
                    prefix = "offset"
                case "zstack":
                    prefix = "zstack"
                case "z-index":
                    prefix = "z-index"
                default:
                    prefix = "style"
                }
                if let componentName = context.currentComponent {
                    let key = "\(componentName)|\(bucketKey)|\(normalized)"
                    className = bucketClassName(for: key, prefix: prefix)
                    let rule = ".\(className) { \(normalized); }"
                    ComponentStylesRegistry.shared.register(rule: rule, for: componentName)
                } else {
                    className = bucketClassName(for: "\(bucketKey)|\(normalized)", prefix: prefix)
                    let rule = ".\(className) { \(normalized); }"
                    ComponentStylesRegistry.shared.register(rule: rule, for: "global")
                }
                classes.append(className)
            }

            // Clear inline styles so they are not emitted in the style="" attribute.
            styles = [:]

            return .element(tag: tag, attributes: attributes, classes: classes, styles: styles, children: children)
        }
    }
}

// MARK: - Helpers

/// Normalize a collection of (property, value) style declarations into a canonical string:
/// - Trims whitespace/newlines around keys and values
/// - Strips trailing semicolons from values
/// - Drops empty keys/values
/// - Sorts by key ascending (A→Z)
/// - Joins as "key: value" pairs separated by "; "
private func normalizeStyleDeclarations(_ declarations: [(String, String)]) -> String {
    let cleaned: [(String, String)] = declarations.map { rawKey, rawValue in
        let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)

        var value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        // Remove any trailing semicolons so "8" and "8;" are treated the same.
        value = value.trimmingCharacters(in: CharacterSet(charactersIn: ";").union(.whitespaces))

        return (key, value)
    }

    let filtered = cleaned.filter { !$0.0.isEmpty && !$0.1.isEmpty }

    let sorted = filtered.sorted { lhs, rhs in
        lhs.0 < rhs.0
    }

    return sorted
        .map { "\($0): \($1)" }
        .joined(separator: "; ")
}

/// Produce a deterministic class name for a given normalized declaration string.
private func bucketClassName(for normalizedDeclarations: String, prefix: String = "style") -> String {
    let hashValue = fnv1a64(normalizedDeclarations)
    let suffix = String(hashValue, radix: 36, uppercase: false)
    return "\(prefix)-\(suffix)"
}

/// Simple 64-bit FNV-1a hash for stable, fast hashing of small strings.
private func fnv1a64(_ string: String) -> UInt64 {
    let bytes = Array(string.utf8)
    var hash: UInt64 = 0xcbf29ce484222325
    let prime: UInt64 = 0x100000001b3

    for byte in bytes {
        hash ^= UInt64(byte)
        hash &*= prime
    }

    return hash
}
