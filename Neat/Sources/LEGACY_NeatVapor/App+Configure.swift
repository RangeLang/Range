import Vapor
import Neat

public func configure<T: App>(_ app: Application, for appType: T.Type) async throws {
    // 1. Instantiate the application's root type
    let site = T()
    // 2. Register global head content so each page inherits it.
    GlobalHeadRegistry.shared.register(head: AnyHead(site.head))

    // 3. Prepare reverse routing infrastructure (future use)
    let nodes = site.router.build()
    let router = RouterBuilder.build(from: nodes)
    RouterStore.set(router)

    // 4. Register all user-defined routes
    VaporRouteRegistrar.register(nodes, on: app.routes)

    // 6. Serve Neat WASM runtime
    app.get("neat", "wasm.js") { _ async throws -> Response in
        let runtimeJS = ResourceLoader.load("WasmRuntime.js", subdirectory: "Resources/Scripts")
        var res = Response(body: .init(string: runtimeJS))
        res.headers.contentType = HTTPMediaType(type: "application", subType: "javascript")
        return res
    }

    // 6.1 Serve primitive scripts
    app.get("neat", "primitives", ":name") { req async throws -> Response in
        guard let raw = req.parameters.get("name") else {
            throw Abort(.badRequest)
        }

        let name = raw.hasSuffix(".js") ? String(raw.dropLast(3)) : raw
        let script: String
        switch name {
        case "button":
            script = ResourceLoader.load("Button.js", subdirectory: "Resources/Primitives")
        case "toggle":
            script = ResourceLoader.load("Toggle.js", subdirectory: "Resources/Primitives")
        case "text-field":
            script = ResourceLoader.load("TextField.js", subdirectory: "Resources/Primitives")
        case "portal":
            script = ResourceLoader.load("Portal.js", subdirectory: "Resources/Primitives")
        case "scroll-area":
            script = ResourceLoader.load("ScrollArea.js", subdirectory: "Resources/Primitives/ScrollArea")
        case "list":
            script = ResourceLoader.load("List.js", subdirectory: "Resources/Primitives/List")
        default:
            throw Abort(.notFound)
        }

        var res = Response(body: .init(string: script))
        res.headers.contentType = HTTPMediaType(type: "application", subType: "javascript")
        return res
    }

    // 7. Serve per-component CSS bundles
    app.get("neat", "styles", ":name") { req async throws -> Response in
        guard let raw = req.parameters.get("name") else {
            throw Abort(.badRequest)
        }

        let componentName = raw.hasSuffix(".css") ? String(raw.dropLast(4)) : raw
        if componentName == "scroll-area" {
            let css = ResourceLoader.load("ScrollArea.css", subdirectory: "Resources/Primitives/ScrollArea")
            var res = Response(body: .init(string: css))
            res.headers.contentType = HTTPMediaType(type: "text", subType: "css")
            return res
        }
        if componentName == "list" {
            let css = ResourceLoader.load("List.css", subdirectory: "Resources/Primitives/List")
            var res = Response(body: .init(string: css))
            res.headers.contentType = HTTPMediaType(type: "text", subType: "css")
            return res
        }
        if componentName == "label" {
            let css = ResourceLoader.load("Label.css", subdirectory: "Resources/Primitives/Label")
            var res = Response(body: .init(string: css))
            res.headers.contentType = HTTPMediaType(type: "text", subType: "css")
            return res
        }

        guard let css = ComponentStylesRegistry.shared.css(for: componentName) else {
            throw Abort(.notFound)
        }

        var res = Response(body: .init(string: css))
        res.headers.contentType = HTTPMediaType(type: "text", subType: "css")
        return res
    }

    // Bind all registered server actions as routes
    ServerActionRegistry.shared.registerAll(on: app)

    // Serve static assets from /Resources
    app.get("preflight.css") { _ async throws -> Response in
        let css = ResourceLoader.load("preflight.css", subdirectory: "Resources/Styles")
        var res = Response(body: .init(string: css))
        res.headers.contentType = HTTPMediaType(type: "text", subType: "css")
        return res
    }

    app.get("global.css") { _ async throws -> Response in
        let styleSubdirectory = "Resources/Styles"
        let styleFiles = [
            "layout.css",
            "root.css",
            "style.css",
            "typography.css"
        ]
        app.logger.debug("global.css files: \(styleFiles.joined(separator: ", "))")
        let css = styleFiles
            .map { ResourceLoader.load($0, subdirectory: styleSubdirectory) }
            .filter { !$0.isEmpty }
            .joined(separator: "")
        let minified = Minifier.css(css)
        var res = Response(body: .init(string: minified))
        res.headers.contentType = HTTPMediaType(type: "text", subType: "css")
        return res
    }

    // Serve locally-built WASM artifacts from .neat/generated at /wasm/*
    app.get("wasm", ":name") { req async throws -> Response in
        guard let name = req.parameters.get("name") else {
            throw Abort(.badRequest)
        }

        let wasmPath = app.directory.workingDirectory + ".neat/generated/" + name
        guard FileManager.default.fileExists(atPath: wasmPath) else {
            throw Abort(.notFound)
        }

        let response = req.fileio.streamFile(at: wasmPath)
        response.headers.contentType = HTTPMediaType(type: "application", subType: "wasm")
        return response
    }

    // Serve static assets from /Public
    app.middleware.use(FileMiddleware(publicDirectory: app.directory.publicDirectory))
}
