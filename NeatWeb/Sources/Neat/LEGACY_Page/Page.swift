import Foundation

public protocol Page: Component where Body == Content {
    associatedtype HeadContent: Head = AnyHead
    associatedtype Content: Component
    init()

    @HeadBuilder
    var head: HeadContent { get }

    @ComponentBuilder
    var body: Content { get }

    static func __registerServerActions()
}

extension Page {
    public func build(in context: RenderContext?) -> ElementNode {
        context?.pushComponent(Self.componentName, typeName: Self.typeName, type: Self.self)
        defer { context?.popComponent() }

        let inner: ElementNode
        if let context {
            inner = context.withTracking {
                body.build(in: context)
            }
        } else {
            inner = body.build(in: context)
        }

        var attributes: [String: String] = [:]
        var classes: [String] = ["page"]

        return .element(
            tag: "div",
            attributes: attributes,
            classes: classes,
            styles: [:],
            children: [inner]
        )
    }

    public var head: AnyHead { AnyHead(EmptyHead()) }

    public static var componentName: String {
        #if os(WASI)
        return "page"
        #else
        let full = String(describing: Self.self)
        let noModule = full.split(separator: ".").last.map(String.init) ?? full
        let base = noModule.split(separator: "<").first.map(String.init) ?? noModule
        return base.kebabCase
        #endif
    }

    public static var typeName: String {
        #if os(WASI)
        return "Page"
        #else
        let full = String(describing: Self.self)
        return full.split(separator: ".").last.map(String.init) ?? full
        #endif
    }

    public static func __registerServerActions() {}
}

extension Page {
    public func renderHTML() -> String {
        let context = RenderContext()
        let router = RouterStore.current()
        context.environmentValues.router = router

        let bodyNode: ElementNode = context.withCurrent {
            context.pushComponent(Self.componentName, typeName: Self.typeName, type: Self.self)
            defer { context.popComponent() }

            let rootNode = body.build(in: context)
            let shellNode = ElementNode(
                tag: "div",
                attributes: [:],
                classes: ["page"],
                styleValues: [:],
                children: [rootNode]
            )
            return shellNode.withStyleBuckets(context: context)
        }

        let pageHeadNode = context.withCurrent { head.build(in: context) }
        let headNode: ElementNode
        if let globalHeadNode = context.withCurrent({
            GlobalHeadRegistry.shared.head()?.build(in: context)
        }) {
            headNode = mergeHeadNodes(global: globalHeadNode, page: pageHeadNode)
        } else {
            headNode = pageHeadNode
        }

        let primitiveStyles = Set([
            "scroll-area",
            "list",
            "label"
        ])

        let stylesheets = context.usedComponents
            .sorted()
            .compactMap { name -> String? in
                guard ComponentStylesRegistry.shared.hasStyles(for: name) || primitiveStyles.contains(name) else { return nil }
                return #"<link rel="stylesheet" href="/neat/styles/\#(name).css">"#
            }
            .joined(separator: "\n")

        let primitiveScripts = primitiveScriptTags(for: context.usedComponents)
        let scriptTags = #"<script src="/neat/wasm.js" defer></script>"#
        let routeAttribute = router.routeIndex(for: type(of: self)).map { " data-neat-route=\"\($0)\"" } ?? ""

        return """
            <!DOCTYPE html>
            <html>
            <head>
            \(headNode.htmlString)
            \(stylesheets)
            \(primitiveScripts)
            </head>
            <body\(routeAttribute)>
            \(bodyNode.htmlString)
            \(scriptTags)
            </body>
            </html>
            """
    }

    private func primitiveScriptTags(for components: Set<String>) -> String {
        let scripts: [(name: String, path: String)] = [
            ("button", "/neat/primitives/button.js"),
            ("toggle", "/neat/primitives/toggle.js"),
            ("text-field", "/neat/primitives/text-field.js"),
            ("portal", "/neat/primitives/portal.js"),
            ("scroll-area", "/neat/primitives/scroll-area.js"),
            ("list", "/neat/primitives/list.js")
        ]

        let tags = scripts.compactMap { entry -> String? in
            guard components.contains(entry.name) else { return nil }
            return #"<script src="\#(entry.path)" defer></script>"#
        }

        return tags.joined(separator: "\n")
    }

    private func mergeHeadNodes(global: ElementNode, page: ElementNode) -> ElementNode {
        let pageNodes = flattenHeadNodes(page)
        let overrideKeys = Set(pageNodes.compactMap(metaIdentifier))
        let filteredGlobal = flattenHeadNodes(global).filter { node in
            guard let key = metaIdentifier(node) else { return true }
            return !overrideKeys.contains(key)
        }
        return .fragment(filteredGlobal + pageNodes)
    }

    private func flattenHeadNodes(_ node: ElementNode) -> [ElementNode] {
        switch node {
        case .fragment(let nodes):
            return nodes.flatMap(flattenHeadNodes)
        default:
            return [node]
        }
    }

    private func metaIdentifier(_ node: ElementNode) -> String? {
        guard case .element(let tag, let attributes, _, _, _) = node else { return nil }
        guard tag.lowercased() == "meta" else { return nil }
        if attributes["charset"] != nil { return "charset" }
        if let name = attributes["name"] { return "name:\(name)" }
        if let property = attributes["property"] { return "property:\(property)" }
        if let httpEquiv = attributes["http-equiv"] { return "http-equiv:\(httpEquiv)" }
        return nil
    }
}
