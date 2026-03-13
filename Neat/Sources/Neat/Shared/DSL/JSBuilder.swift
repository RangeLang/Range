import Foundation

// Lightweight JS DSL for composing readable JS from Swift.

public struct JSBlock {
    public var text: String

    public init(text: String) {
        self.text = text
    }
}

@resultBuilder
public struct JSBuilder {
    public static func buildBlock(_ components: JSBlock...) -> JSBlock {
        JSBlock(text: components.map { $0.text }.joined(separator: "\n"))
    }
    public static func buildOptional(_ component: JSBlock?) -> JSBlock { component ?? JSBlock(text: "") }
    public static func buildEither(first: JSBlock) -> JSBlock { first }
    public static func buildEither(second: JSBlock) -> JSBlock { second }
    public static func buildArray(_ components: [JSBlock]) -> JSBlock {
        JSBlock(text: components.map { $0.text }.joined(separator: "\n"))
    }
}

// Public entry: render builder content to a single JS string.
public func js(pretty: Bool = true, @JSBuilder _ content: () -> JSBlock) -> String {
    let text = content().text
    if pretty { return text }
    return text.split(separator: "\n")
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .joined(separator: "")
}

// MARK: - Primitives

public func line(indent level: Int = 0, _ code: String) -> JSBlock {
    guard level > 0 else { return JSBlock(text: code) }
    return JSBlock(text: indent(code, by: level))
}
public func raw(_ code: String) -> JSBlock { JSBlock(text: code) }

public func const(_ name: String, _ value: String) -> JSBlock {
    JSBlock(text: "const \(name) = \(value);")
}

public func letDecl(_ name: String, _ value: String) -> JSBlock {
    JSBlock(text: "let \(name) = \(value);")
}

public func call(_ name: String, args: [String] = []) -> JSBlock {
    JSBlock(text: "\(name)(\(args.joined(separator: ", ")));")
}

// call with inline callback body: fn(() => { ... });
public func call(_ name: String, callbackParams: [String] = [], @JSBuilder _ body: () -> JSBlock) -> JSBlock {
    let params = callbackParams.joined(separator: ", ")
    let rendered = indent(body().text)
    let cb = "() => {\n\(rendered)\n}"
    let callLine = params.isEmpty ? "\(name)(\(cb));" : "\(name)(\(params), \(cb));"
    return JSBlock(text: callLine)
}

public func function(_ name: String, params: [String] = [], @JSBuilder _ body: () -> JSBlock) -> JSBlock {
    let bodyText = indent(body().text)
    return JSBlock(text: "function \(name)(\(params.joined(separator: ", "))) {\n\(bodyText)\n}")
}

public func exportFunction(_ name: String, params: [String] = [], @JSBuilder _ body: () -> JSBlock) -> JSBlock {
    let inner = function(name, params: params, body)
    return JSBlock(text: "export \(inner.text)")
}

public func ifBlock(_ condition: String, @JSBuilder _ body: () -> JSBlock) -> JSBlock {
    let bodyText = indent(body().text)
    return JSBlock(text: "if (\(condition)) {\n\(bodyText)\n}")
}

public func block(@JSBuilder _ body: () -> JSBlock) -> JSBlock {
    let bodyText = indent(body().text)
    return JSBlock(text: "{\n\(bodyText)\n}")
}

// Convenience: element.addEventListener("event", (event) => { ... })
public func addEventListener(_ element: String, _ event: String, @JSBuilder _ body: () -> JSBlock) -> JSBlock {
    let bodyText = indent(body().text)
    return JSBlock(text: "\(element).addEventListener(\"\(event)\", (event) => {\n\(bodyText)\n});")
}

// MARK: - Literals

public func str(_ value: String) -> String {
    let escaped = value
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
    return "\"\(escaped)\""
}

public func template(_ value: String) -> String {
    let escaped = value.replacingOccurrences(of: "`", with: "\\`")
    return "`\(escaped)`"
}

// MARK: - Utilities

private func indent(_ text: String, by level: Int = 1, unit: String = "    ") -> String {
    let prefix = String(repeating: unit, count: level)
    return text
        .split(separator: "\n", omittingEmptySubsequences: false)
        .map { $0.isEmpty ? String($0) : prefix + $0 }
        .joined(separator: "\n")
}
