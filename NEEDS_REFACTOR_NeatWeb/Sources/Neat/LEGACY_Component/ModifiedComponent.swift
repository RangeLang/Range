public struct ModifiedComponent<Base: Component>: _PrimitiveComponent {

    public var base: Base
    public var styles: [any StyleModifier]
    public var events: [any EventModifier]
    public var a11y: [any AccessibilityModifier]



    public init(
        base: Base,
        styles: [any StyleModifier] = [],
        events: [any EventModifier] = [],
        a11y: [any AccessibilityModifier] = []
    ) {
        self.base = base
        self.styles = styles
        self.events = events
        self.a11y = a11y
    }

    public func build(in context: RenderContext?) -> ElementNode {
        // Check for style forwarding, unwrapping AnyComponent if necessary
        var potentialForwarder: _StyleForwardingComponent? = base as? _StyleForwardingComponent
        if potentialForwarder == nil, let wrapped = base as? AnyComponent {
            potentialForwarder = wrapped._base as? _StyleForwardingComponent
        }

        if let forwarder = potentialForwarder {
            if let ctx = context {
                for style in styles {
                    ctx.registerStyle(style)
                }
            }
            var node = forwarder._buildForwardingStyles(styles, in: context)
            for event in events {
                node.apply(event)
            }
            for ax in a11y {
                node.apply(ax)
            }
            return node
        }

        var node = base.build(in: context)

        // 1. Register Styles for CSS generation
        if let ctx = context {
            for style in styles {
                ctx.registerStyle(style)
            }
        }

        // 2. Aggregate modifiers into a temporary node
        var modifiersNode = ElementNode(tag: "div") // dummy tag
        for style in styles {
            modifiersNode.apply(style)
        }
        for event in events {
            modifiersNode.apply(event)
        }
        for ax in a11y {
            modifiersNode.apply(ax)
        }

        // 3. Merge aggregated modifiers into the base node
        // This uses the "Inner Wins" logic (existing styles take precedence)
        node.merge(modifiersFrom: modifiersNode)

        // 4. Enforce Layout Box if needed
        // If any modifier requires a layout box (e.g. background color), we must ensure
        // the node does not have 'display: contents'.
        if styles.contains(where: { $0.requiresLayoutBox }) {
            node.removeStyle("display")
        }

        return node
    }

    // Optional helpers
    public func appending(style: any StyleModifier) -> Self {
        var copy = self
        copy.styles.append(wrapStyleWithCurrentPriority(style))
        return copy
    }

    public func appending(event: any EventModifier) -> Self {
        var copy = self
        copy.events.append(event)
        return copy
    }

    public func appending(a11y: any AccessibilityModifier) -> Self {
        var copy = self
        copy.a11y.append(a11y)
        return copy
    }
}

public extension ModifiedComponent {
    func style(_ style: any StyleModifier) -> ModifiedComponent<Base> {
        appending(style: style)
    }

    func event(_ event: any EventModifier) -> ModifiedComponent<Base> {
        appending(event: event)
    }

    func accessibility(_ ax: any AccessibilityModifier) -> ModifiedComponent<Base> {
        appending(a11y: ax)
    }
}

extension ModifiedComponent: _StyleForwardingComponent where Base: _StyleForwardingComponent {
    func _buildForwardingStyles(
        _ incoming: [any StyleModifier],
        in context: RenderContext?
    ) -> ElementNode {
        if let ctx = context {
            for style in styles {
                ctx.registerStyle(style)
            }
        }
        return base._buildForwardingStyles(styles + incoming, in: context)
    }
}

public protocol _ModifierContainer {
    var anyBase: any Component { get }
    var styles: [any StyleModifier] { get }
    var events: [any EventModifier] { get }
    var a11y: [any AccessibilityModifier] { get }
}

extension ModifiedComponent: _ModifierContainer {
    public var anyBase: any Component { base }
}
