public indirect enum ElementNode {
    case element(tag: String, attributes: [String: String], classes: [String], styles: [String: StyleValue], children: [ElementNode])
    case text(String)
    case fragment([ElementNode])

    public init(tag: String, attributes: [String: String] = [:], classes: [String] = [], styleValues: [String: StyleValue] = [:], children: [ElementNode] = []) {
        self = .element(tag: tag, attributes: attributes, classes: classes, styles: styleValues, children: children)
    }

    public init(tag: String, attributes: [String: String] = [:], classes: [String] = [], styles: [String: String], children: [ElementNode] = []) {
        let wrapped = styles.mapValues { StyleValue(value: $0, priority: 0) }
        self = .element(tag: tag, attributes: attributes, classes: classes, styles: wrapped, children: children)
    }
}

extension ElementNode {
    func normalizedForDiff() -> ElementNode {
        switch self {
        case .text:
            return self
        case .fragment(let nodes):
            let normalized = nodes.map { $0.normalizedForDiff() }
            return .fragment(flattenFragments(in: normalized))
        case .element(let tag, let attributes, let classes, let styles, let children):
            let normalizedChildren = children.map { $0.normalizedForDiff() }
            return .element(
                tag: tag,
                attributes: attributes,
                classes: classes,
                styles: styles,
                children: flattenFragments(in: normalizedChildren)
            )
        }
    }
}

private func flattenFragments(in nodes: [ElementNode]) -> [ElementNode] {
    var flattened: [ElementNode] = []
    for node in nodes {
        switch node {
        case .fragment(let children):
            flattened.append(contentsOf: flattenFragments(in: children))
        default:
            flattened.append(node)
        }
    }
    return flattened
}

public struct StyleValue {
    public let value: String
    public let priority: Int

    public init(value: String, priority: Int) {
        self.value = value
        self.priority = priority
    }
}

// MARK: - Modifier Application

public extension ElementNode {
    mutating func apply(_ modifier: any StyleModifier) {
        switch self {
        case .element(let tag, var attributes, var classes, var styles, let children):
            let priority = (modifier as? StylePriorityProviding)?.stylePriority ?? 0
            if let className = modifier.cssClass {
                if !classes.contains(className) {
                    classes.append(className)
                }
            }
            if let style = modifier.cssStyle {
                let declarations = style
                    .split(separator: ";")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }

                for declaration in declarations {
                    let parts = declaration.split(separator: ":", maxSplits: 1)
                    guard parts.count == 2 else { continue }
                    let key = String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines)
                    let value = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !key.isEmpty else { continue }
                    if let existing = styles[key], existing.priority > priority {
                        continue
                    }
                    if key == "--sh", let existing = styles[key]?.value, !existing.isEmpty {
                        let combined = "\(existing), \(value)"
                        styles[key] = StyleValue(value: combined, priority: priority)
                    } else {
                        styles[key] = StyleValue(value: value, priority: priority)
                    }
                }
            }
            for (name, value) in modifier.extraAttributes {
                attributes[name] = value
            }
            if modifier.requiresLayoutBox {
                styles.removeValue(forKey: "display")
            }
            self = .element(tag: tag, attributes: attributes, classes: classes, styles: styles, children: children)

        case .text(let string):
            // Cannot apply a style to a raw text node. Wrap it in a <span>.
            var newNode = ElementNode(tag: "span", children: [.text(string)])
            newNode.apply(modifier)
            self = newNode

        case .fragment(var nodes):
            for i in 0..<nodes.count {
                nodes[i].apply(modifier)
            }
            self = .fragment(nodes)
        }
    }

    mutating func merge(modifiersFrom other: ElementNode) {
        switch (self, other) {
        case (.element(let tag, var attributes, var classes, var styles, let children),
              .element(_, let otherAttributes, let otherClasses, let otherStyles, _)):

            // 1. Merge Styles (Inner/Self wins on >= priority)
            for (key, newVal) in otherStyles {
                if let existing = styles[key], existing.priority >= newVal.priority {
                    continue
                }
                styles[key] = newVal
            }

            // 2. Merge Classes (Union)
            for cls in otherClasses {
                if !classes.contains(cls) {
                    classes.append(cls)
                }
            }

            // 3. Merge Attributes (Inner/Self wins)
            for (key, val) in otherAttributes {
                if attributes[key] == nil {
                    attributes[key] = val
                }
            }

            self = .element(tag: tag, attributes: attributes, classes: classes, styles: styles, children: children)

        case (.text(let string), _):
            // Wrap text in span and merge
            var newNode = ElementNode(tag: "span", children: [.text(string)])
            newNode.merge(modifiersFrom: other)
            self = newNode

        case (.fragment(var nodes), _):
            // Apply modifiers to all children in fragment
            for i in 0..<nodes.count {
                nodes[i].merge(modifiersFrom: other)
            }
            self = .fragment(nodes)

        default:
            break
        }
    }

    mutating func removeStyle(_ key: String) {
        switch self {
        case .element(let tag, let attributes, let classes, var styles, let children):
            styles.removeValue(forKey: key)
            self = .element(tag: tag, attributes: attributes, classes: classes, styles: styles, children: children)
        case .fragment(var nodes):
            for i in 0..<nodes.count {
                nodes[i].removeStyle(key)
            }
            self = .fragment(nodes)
        case .text:
            break
        }
    }

    mutating func apply(_ modifier: any EventModifier) {
        switch self {
        case .element(let tag, var attributes, let classes, let styles, let children):
            // Event modifiers just add attributes like 'onclick'
            // for (name, value) in modifier.extraAttributes {
            //     attributes[name] = value
            // }
            self = .element(tag: tag, attributes: attributes, classes: classes, styles: styles, children: children)
        case .text:
            break
        case .fragment(var nodes):
            for i in 0..<nodes.count {
                nodes[i].apply(modifier)
            }
            self = .fragment(nodes)
        }
    }

    mutating func apply(_ modifier: any AccessibilityModifier) {
        switch self {
        case .element(let tag, var attributes, let classes, let styles, let children):
            for (name, value) in modifier.extraAttributes {
                attributes[name] = value
            }
            self = .element(tag: tag, attributes: attributes, classes: classes, styles: styles, children: children)
        case .text:
            break
        case .fragment(var nodes):
            for i in 0..<nodes.count {
                nodes[i].apply(modifier)
            }
            self = .fragment(nodes)
        }
    }
}

// MARK: - HTML Generation

extension ElementNode {
    public var htmlString: String {
        switch self {
        case .text(let string):
            return escapeText(string)

        case .fragment(let nodes):
            return nodes
                .map { $0.htmlString }
                .filter { !$0.isEmpty }
                .joined()

        case .element(let tag, let attributes, let classes, let styles, let children):
            var attrs: [String] = []

            // normal attributes
            for (name, value) in attributes {
                attrs.append(#"\#(name)="\#(escapeAttribute(value))""#)
            }

            // class attribute
            if !classes.isEmpty {
                let value = classes.joined(separator: " ")
                attrs.append(#"class="\#(escapeAttribute(value))""#)
            }

            // Inline styles (if any remain - typically buckets handle this, but for raw rendering:
            if !styles.isEmpty {
                 let styleString = styles
                     .map { "\($0.key): \($0.value.value)" }
                     .sorted { $0 < $1 } // Stable order
                     .joined(separator: "; ")
                 attrs.append(#"style="\#(escapeAttribute(styleString))""#)
            }

            let attrsString = attrs.isEmpty ? "" : " " + attrs.joined(separator: " ")

            let childrenHTML = children
                .map { $0.htmlString }
                .filter { !$0.isEmpty }
                .joined()

            if childrenHTML.isEmpty {
                return "<\(tag)\(attrsString)></\(tag)>"
            } else {
                return "<\(tag)\(attrsString)>\(childrenHTML)</\(tag)>"
            }
        }
    }
}

// MARK: - Helpers

private func escapeText(_ text: String) -> String {
    text
        .replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
}

private func escapeAttribute(_ text: String) -> String {
    text
        .replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "\"", with: "&quot;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
}
