import _Concurrency

public enum StylePriorityContext {
    @TaskLocal public static var current: Int = 0

    public static func withPriority<T>(
        _ priority: Int,
        _ body: () throws -> T
    ) rethrows -> T {
        try $current.withValue(priority, operation: body)
    }
}

public protocol StylePriorityProviding {
    var stylePriority: Int { get }
}

public struct PrioritizedStyleModifier: StyleModifier, StylePriorityProviding {
    public let base: any StyleModifier
    public let stylePriority: Int

    public init(_ base: any StyleModifier, priority: Int) {
        self.base = base
        self.stylePriority = priority
    }

    public var cssStyle: String? { base.cssStyle }
    public var cssClass: String? { base.cssClass }
    public var extraAttributes: [(name: String, value: String)] { base.extraAttributes }
    public var utilityRule: (name: String, declaration: String)? { base.utilityRule }
    public var requiresLayoutBox: Bool { base.requiresLayoutBox }
}

func wrapStyleWithCurrentPriority(_ style: any StyleModifier) -> any StyleModifier {
    let priority = StylePriorityContext.current
    guard priority != 0 else { return style }

    if let prioritized = style as? PrioritizedStyleModifier {
        if prioritized.stylePriority == priority {
            return style
        }
        return PrioritizedStyleModifier(prioritized.base, priority: priority)
    }

    return PrioritizedStyleModifier(style, priority: priority)
}
