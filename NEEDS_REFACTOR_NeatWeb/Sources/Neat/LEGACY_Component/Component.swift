public protocol Component: _Renderable {
    associatedtype Body: _Renderable
    @ComponentBuilder var body: Body { get }
    static var componentName: String { get }
    static var typeName: String { get }
}

public extension Component {
    func build(in context: RenderContext?) -> ElementNode {
        // Use unified PrimitiveContext logic for consistency
        // Note: Generic Components are treated as "primitives" in terms of ID consumption
        // to ensure the global counter stays in sync between Server and Client.
        let primitive = PrimitiveContext.prepare(
            in: context,
            name: Self.componentName,
            typeName: Self.typeName
        )

        context?.pushComponent(Self.componentName, typeName: Self.typeName, type: Self.self)
        defer { context?.popComponent() }

        let inner: ElementNode
        if let context {
            let key = context.consumePendingKey()
            let node = context.resolveRuntimeNode(type: Self.self, key: key)
            assignStateSlots(for: self, owner: node)
            inner = context.withRuntimeNode(node) {
                context.withTracking {
                    body.build(in: context)
                }
            }
        } else {
            inner = body.build(in: context)
        }

        return .element(
            tag: "div",
            attributes: primitive?.attributes ?? [:],
            classes: [],
            styles: ["display": StyleValue(value: "contents", priority: 0)],
            children: [inner]
        )
    }

    static var typeName: String {
        #if os(WASI)
        return "Component"
        #else
        let full = String(describing: Self.self)
        return full.split(separator: ".").last.map(String.init) ?? full
        #endif
    }
}

private func assignStateSlots(for component: Any, owner: RuntimeNode) {
    let mirror = Mirror(reflecting: component)
    var slotIndex = 0
    for child in mirror.children {
        if let assignable = child.value as? StateSlotAssignable {
            assignable.assign(owner: owner, slot: slotIndex)
            slotIndex += 1
        }
    }
}

// Default name (works for all Components, including macro ones)
public extension Component {
    static var componentName: String {
        #if os(WASI)
        return "component"
        #else
        let full = String(describing: Self.self)              // "Neat.Button<Text>" or "HomePage"

        let noModule = full.split(separator: ".").last
            .map(String.init) ?? full                         // "Button<Text>" or "HomePage"

        let base = noModule.split(separator: "<").first
            .map(String.init) ?? noModule                     // "Button" or "HomePage"

        return base.kebabCase                                 // "button", "home-page"
        #endif
    }
}
