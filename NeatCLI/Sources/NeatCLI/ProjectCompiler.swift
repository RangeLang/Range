import ArgumentParser
import Foundation
import NeatSyntax

struct ProjectCompiler {
    private let path: String
    private let showSummary: Bool

    init(path: String, showSummary: Bool = true) {
        self.path = path
        self.showSummary = showSummary
    }

    func run() throws {
        let startedAt = Date()
        let root = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
        let packageFile = root.appendingPathComponent("Package.neat", isDirectory: false)
        let appFile = root.appendingPathComponent("App.neat", isDirectory: false)

        guard FileManager.default.fileExists(atPath: packageFile.path) else {
            throw ValidationError("Missing Package.neat in \(root.path)")
        }

        guard FileManager.default.fileExists(atPath: appFile.path) else {
            throw ValidationError("Missing App.neat in \(root.path)")
        }

        let packageSource = try String(contentsOf: packageFile, encoding: .utf8)
        let appSource = try String(contentsOf: appFile, encoding: .utf8)

        let appName =
            parseAppName(from: appSource) ?? parsePackageName(from: packageSource)
            ?? root.lastPathComponent
        let packageCoreStylesheets = parsePackageCoreStylesheets(from: packageSource)
        let customModifierStyles = try loadCustomModifierStyles(root: root)
        let head = parseHead(from: appSource)
        let routes = try parseRoutes(from: appSource)

        let componentLibrary = try loadComponentLibrary(root: root, routes: routes)

        let buildDirectory =
            root
            .appendingPathComponent(".neat", isDirectory: true)
            .appendingPathComponent("Build", isDirectory: true)
        let pagesBuildDirectory = buildDirectory.appendingPathComponent("Pages", isDirectory: true)
        let componentsBuildDirectory = buildDirectory.appendingPathComponent(
            "Components", isDirectory: true)
        let coreDirectory =
            buildDirectory
            .appendingPathComponent("Core", isDirectory: true)
        if FileManager.default.fileExists(atPath: buildDirectory.path) {
            try FileManager.default.removeItem(at: buildDirectory)
        }
        try FileManager.default.createDirectory(
            at: buildDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: pagesBuildDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: componentsBuildDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: coreDirectory, withIntermediateDirectories: true)

        try renderIndexHTML(appName: appName, head: head)
            .write(
                to: buildDirectory.appendingPathComponent("index.html", isDirectory: false),
                atomically: true,
                encoding: String.Encoding.utf8
            )

        let pageNames = routes.map(\.page).removingDuplicates()

        for pageName in pageNames {
            guard let page = componentLibrary[pageName] else {
                throw ValidationError("Missing compiled page '\(pageName)'")
            }
            try renderPageModule(
                page: page,
                library: componentLibrary,
                customModifierStyles: customModifierStyles
            )
            .write(
                to: pagesBuildDirectory.appendingPathComponent(
                    "\(pageName).js", isDirectory: false),
                atomically: true,
                encoding: String.Encoding.utf8
            )
        }

        for (name, component) in componentLibrary.sorted(by: { $0.key < $1.key })
        where !pageNames.contains(name) {
            try renderComponentModule(
                component: component,
                library: componentLibrary,
                customModifierStyles: customModifierStyles
            )
            .write(
                to: componentsBuildDirectory.appendingPathComponent(
                    "\(name).js",
                    isDirectory: false
                ),
                atomically: true,
                encoding: String.Encoding.utf8
            )
        }

        try renderAppJS(appName: appName, routes: routes, pageNames: pageNames)
            .write(
                to: buildDirectory.appendingPathComponent("app.js", isDirectory: false),
                atomically: true,
                encoding: String.Encoding.utf8
            )
        try defaultHMRJS().write(
            to: buildDirectory.appendingPathComponent("hmr.js", isDirectory: false),
            atomically: true,
            encoding: String.Encoding.utf8
        )

        let manifestData = try JSONEncoder().encode(routes)
        try manifestData.write(
            to: buildDirectory.appendingPathComponent("routes.json", isDirectory: false))

        try composeCoreCSS(root: root, packageCoreStylesheets: packageCoreStylesheets).write(
            to: coreDirectory.appendingPathComponent("index.css", isDirectory: false),
            atomically: true,
            encoding: String.Encoding.utf8
        )

        try String(Int(Date().timeIntervalSince1970))
            .write(
                to: buildDirectory.appendingPathComponent(".hmr-version", isDirectory: false),
                atomically: true,
                encoding: String.Encoding.utf8
            )

        let elapsedMS = Int((Date().timeIntervalSince(startedAt) * 1000.0).rounded())
        let durationText: String
        if elapsedMS >= 1000 {
            durationText = String(format: "%.2fs", Double(elapsedMS) / 1000.0)
        } else {
            durationText = "\(elapsedMS)ms"
        }
        if showSummary {
            Swift.print(
                TerminalLog.style("Compiled \(appName)", level: .warning)
                    + " "
                    + TerminalLog.style(durationText, level: .warning, dimmed: true)
            )
        }
    }

    private func parsePackageName(from source: String) -> String? {
        match(in: source, pattern: #"Package\("([^"]+)"\)"#)
    }

    private func parsePackageCoreStylesheets(from source: String) -> [String] {
        matches(in: source, pattern: #"CoreStylesheet\("([^"]+)"\)"#)
    }

    private func loadCustomModifierStyles(root: URL) throws -> [String: String] {
        let directory =
            root
            .appendingPathComponent(".neat", isDirectory: true)
            .appendingPathComponent("Core", isDirectory: true)
            .appendingPathComponent("V1", isDirectory: true)
            .appendingPathComponent("Modifiers", isDirectory: true)

        guard FileManager.default.fileExists(atPath: directory.path) else {
            return [:]
        }

        let files = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        .filter { $0.pathExtension.lowercased() == "css" }

        var styles: [String: String] = [:]
        for file in files {
            let key = file.deletingPathExtension().lastPathComponent
            let value = try String(contentsOf: file, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty, !value.isEmpty else { continue }
            styles[key] = value
            styles[key.lowercased()] = value
        }

        return styles
    }

    private func parseAppName(from source: String) -> String? {
        match(
            in: source,
            pattern: #"#([A-Za-z_][A-Za-z0-9_]*)\s*:\s*(?:App|Program)\b"#
        )
    }

    private func parseHead(from source: String) -> HeadSummary {
        HeadSummary(
            title: match(in: source, pattern: #"Title\("([^"]*)"\)"#),
            description: match(in: source, pattern: #"Description\("([^"]*)"\)"#),
            stylesheets: matches(in: source, pattern: #"Stylesheet\("([^"]+)"\)"#)
        )
    }

    private func parseRoutes(from source: String) throws -> [CompiledRoute] {
        let lines = source.components(separatedBy: .newlines)
        var routes: [CompiledRoute] = []
        var prefixes: [String] = []

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)

            if let group = routeGroup(in: line) {
                prefixes.append(group)
                continue
            }

            if let route = routeLine(in: line) {
                let path = normalizePath(prefixes + [route.path])
                routes.append(CompiledRoute(path: path, page: route.page))
                continue
            }

            if line == "}" && !prefixes.isEmpty {
                prefixes.removeLast()
            }
        }

        return routes
    }

    private func routeLine(in line: String) -> (path: String, page: String)? {
        let pattern = #"Route\("([^"]+)"\s*,\s*([A-Za-z_][A-Za-z0-9_]*)\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = regex.firstMatch(in: line, range: range),
            let pathRange = Range(match.range(at: 1), in: line),
            let pageRange = Range(match.range(at: 2), in: line)
        else {
            return nil
        }

        return (String(line[pathRange]), String(line[pageRange]))
    }

    private func routeGroup(in line: String) -> String? {
        match(in: line, pattern: #"Route\("([^"]+)"\)\s*\{"#)
    }

    private func match(in source: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        guard let match = regex.firstMatch(in: source, range: range),
            let groupRange = Range(match.range(at: 1), in: source)
        else {
            return nil
        }
        return String(source[groupRange])
    }

    private func matches(in source: String, pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        return regex.matches(in: source, range: range).compactMap { match in
            guard let groupRange = Range(match.range(at: 1), in: source) else { return nil }
            return String(source[groupRange])
        }
    }

    private func normalizePath(_ parts: [String]) -> String {
        let segments =
            parts
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "/")) }
            .filter { !$0.isEmpty }

        if segments.isEmpty {
            return "/"
        }

        return "/" + segments.joined(separator: "/")
    }

    private func loadComponentLibrary(
        root: URL,
        routes: [CompiledRoute]
    ) throws -> [String: ComponentNode] {
        var library: [String: ComponentNode] = [:]
        let componentIndex = try discoverComponentFiles(root: root)

        for route in routes {
            _ = try loadComponentNamed(
                route.page,
                preferredDirectories: [],
                componentIndex: componentIndex,
                root: root,
                into: &library
            )
        }

        return library
    }

    private func loadComponentNamed(
        _ name: String,
        preferredDirectories: [URL],
        componentIndex: [String: [URL]],
        root: URL,
        into library: inout [String: ComponentNode]
    ) throws -> ComponentNode {
        if let existing = library[name] {
            return existing
        }

        guard
            let fileURL = resolveComponentFile(
                named: name,
                preferredDirectories: preferredDirectories,
                componentIndex: componentIndex,
                root: root
            )
        else {
            throw ValidationError("Could not resolve component '\(name)'")
        }

        let source = try String(contentsOf: fileURL, encoding: .utf8)
        let transformed = preprocessRenderableSource(source, fileName: fileURL.lastPathComponent)
        var parser = try Parser(source: transformed)
        let component = try parser.parseComponent()
        _ = EntityLowerer().lower(component)
        library[name] = component

        let componentDirectory = fileURL.deletingLastPathComponent()
        for childName in referencedComponentNames(in: component) {
            _ = try loadComponentNamed(
                childName,
                preferredDirectories: [componentDirectory] + preferredDirectories,
                componentIndex: componentIndex,
                root: root,
                into: &library
            )
        }

        return component
    }

    private func discoverComponentFiles(root: URL) throws -> [String: [URL]] {
        let fileManager = FileManager.default
        guard
            let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: []
            )
        else {
            return [:]
        }

        let latestCoreDirectory = latestCoreVersionDirectory(root: root)
        var index: [String: [URL]] = [:]

        while let fileURL = enumerator.nextObject() as? URL {
            let path = fileURL.path
            let isDirectory =
                (try? fileURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory)
                ?? false

            if path.contains("/.git/") || path.contains("/.build/")
                || path.contains("/.neat/Build/") || path.contains("/.neat/Packages/")
            {
                if isDirectory {
                    enumerator.skipDescendants()
                }
                continue
            }

            if isDirectory {
                continue
            }

            guard fileURL.pathExtension.lowercased() == "neat" else { continue }

            let fileName = fileURL.lastPathComponent
            if fileName == "Package.neat" || fileName == "App.neat" || fileName == "Fonts.neat" {
                continue
            }

            if path.contains("/.neat/Core/"),
                let latestCoreDirectory,
                !path.hasPrefix(latestCoreDirectory.path + "/")
            {
                continue
            }

            let componentName = fileURL.deletingPathExtension().lastPathComponent
            index[componentName, default: []].append(fileURL)
        }

        return index
    }

    private func resolveComponentFile(
        named name: String,
        preferredDirectories: [URL],
        componentIndex: [String: [URL]],
        root: URL
    ) -> URL? {
        let fileManager = FileManager.default

        for directory in preferredDirectories {
            let candidate = directory.appendingPathComponent("\(name).neat", isDirectory: false)
            if fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
        }

        guard let candidates = componentIndex[name], !candidates.isEmpty else {
            return nil
        }

        return candidates.sorted {
            let lhsPriority = componentPriority(for: $0, root: root)
            let rhsPriority = componentPriority(for: $1, root: root)
            if lhsPriority == rhsPriority {
                return $0.path < $1.path
            }
            return lhsPriority < rhsPriority
        }.first
    }

    private func componentPriority(for url: URL, root: URL) -> Int {
        let path = url.path
        let corePrefix =
            root
            .appendingPathComponent(".neat", isDirectory: true)
            .appendingPathComponent("Core", isDirectory: true)
            .path + "/"
        if path.hasPrefix(corePrefix) {
            return 1
        }
        return 0
    }

    private func latestCoreVersionDirectory(root: URL) -> URL? {
        let coreRoot =
            root
            .appendingPathComponent(".neat", isDirectory: true)
            .appendingPathComponent("Core", isDirectory: true)
        guard FileManager.default.fileExists(atPath: coreRoot.path) else {
            return nil
        }

        guard
            let entries = try? FileManager.default.contentsOfDirectory(
                at: coreRoot,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        else {
            return nil
        }

        let versions: [(value: Int, url: URL)] =
            entries.compactMap { entry in
                let isDirectory =
                    (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory)
                    ?? false
                guard isDirectory else { return nil }
                let name = entry.lastPathComponent
                guard name.count > 1, name.lowercased().hasPrefix("v"),
                    let version = Int(name.dropFirst())
                else { return nil }
                return (version, entry)
            }

        return versions.max(by: { $0.value < $1.value })?.url
    }

    private func preprocessRenderableSource(_ source: String, fileName: String) -> String {
        var output = source
        output = output.replacingOccurrences(
            of:
                #"@(?!main\b|StyleModifier\b|State\b)([A-Za-z_][A-Za-z0-9_]*)(?:\s*:\s*[^{\n]+)?\s*\{"#,
            with: "component $1 {",
            options: .regularExpression
        )
        output = annotateDebugPrints(in: output, fileName: fileName)

        let lines = output.components(separatedBy: .newlines)
        var result: [String] = []
        var skippingMeta = false
        var metaDepth = 0

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

            if !skippingMeta && trimmed.hasPrefix("Meta {") {
                skippingMeta = true
                metaDepth = 1
                continue
            }

            if skippingMeta {
                metaDepth += line.filter { $0 == "{" }.count
                metaDepth -= line.filter { $0 == "}" }.count
                if metaDepth <= 0 {
                    skippingMeta = false
                }
                continue
            }

            result.append(line)
        }

        return result.joined(separator: "\n")
    }

    private func annotateDebugPrints(in source: String, fileName: String) -> String {
        let lines = source.components(separatedBy: .newlines)
        var result: [String] = []
        result.reserveCapacity(lines.count)

        for (index, rawLine) in lines.enumerated() {
            let lineNumber = index + 1
            let prefix = "[\(fileName):\(lineNumber)] "

            if let range = rawLine.range(of: "print(\"") {
                var line = rawLine
                line.replaceSubrange(range, with: "print(\"\(prefix)")
                result.append(line)
                continue
            }

            result.append(rawLine)
        }

        return result.joined(separator: "\n")
    }

    private func referencedComponentNames(in component: ComponentNode) -> [String] {
        referencedComponentNames(in: [component.body])
    }

    private func referencedComponentNames(in views: [ViewNode]) -> [String] {
        var names: [String] = []
        for view in views {
            switch view {
            case .component(let name, let children):
                names.append(name)
                if let children {
                    names.append(contentsOf: referencedComponentNames(in: children))
                }
            case .conditional(let branches):
                for branch in branches {
                    names.append(contentsOf: referencedComponentNames(in: branch.body))
                }
            case .element(_, let children):
                names.append(contentsOf: referencedComponentNames(in: children))
            case .slot:
                break
            case .modified(let base, _):
                names.append(contentsOf: referencedComponentNames(in: [base]))
            case .vStack(let children):
                names.append(contentsOf: referencedComponentNames(in: children))
            default:
                break
            }
        }
        return Array(Set(names)).sorted()
    }

    private func renderIndexHTML(appName: String, head: HeadSummary) -> String {
        let title = head.title ?? appName
        let descriptionMeta: String
        if let description = head.description {
            descriptionMeta =
                "    <meta name=\"description\" content=\"\(escapeHTML(description))\">\n"
        } else {
            descriptionMeta = ""
        }
        let stylesheets = head.stylesheets.map { "    <link rel=\"stylesheet\" href=\"\($0)\">" }
            .joined(separator: "\n")
        let stylesheetBlock = stylesheets.isEmpty ? "" : "\(stylesheets)\n"

        return """
            <!doctype html>
            <html lang="en">
              <head>
                <meta charset="utf-8">
                <meta name="viewport" content="width=device-width, initial-scale=1">
                <title>\(escapeHTML(title))</title>
            \(descriptionMeta)\(stylesheetBlock)    <link rel="stylesheet" href="./Core/index.css">
              </head>
              <body>
                <div id="app"></div>
                <script type="module" src="./app.js"></script>
              </body>
            </html>
            """
    }

    private func renderAppJS(
        appName: String,
        routes: [CompiledRoute],
        pageNames: [String]
    ) throws -> String {
        let routesJSON = String(data: try JSONEncoder().encode(routes), encoding: .utf8) ?? "[]"
        let pageLoaders =
            pageNames
            .map { "\"\($0)\": () => import(\"./Pages/\($0).js\")" }
            .joined(separator: ", ")
        let template = try loadTemplateText("Web/runtime/app.js")
        return
            template
            .replacingOccurrences(of: "__NEAT_ROUTES_JSON__", with: routesJSON)
            .replacingOccurrences(of: "__NEAT_PAGE_LOADERS__", with: pageLoaders)
            .replacingOccurrences(of: "__NEAT_APP_NAME__", with: escapeJavaScript(appName))
    }

    private func renderPageModule(
        page: ComponentNode,
        library: [String: ComponentNode],
        customModifierStyles: [String: String]
    ) throws -> String {
        let generated = try generatePageFactory(
            page: page,
            library: library,
            customModifierStyles: customModifierStyles
        )
        let enumDecls = renderCaseDeclarations(name: page.name, cases: page.cases)
        let modulePrefix = enumDecls.isEmpty ? "" : "\(enumDecls)\n\n"
        return """
            \(modulePrefix)\
            export function createPage() {
            \(indent(generated, level: 1))
            }
            """
    }

    private func renderComponentModule(
        component: ComponentNode,
        library: [String: ComponentNode],
        customModifierStyles: [String: String]
    ) throws -> String {
        let generated = try generatePageFactory(
            page: component,
            library: library,
            customModifierStyles: customModifierStyles
        )
        let enumDecls = renderCaseDeclarations(name: component.name, cases: component.cases)
        let modulePrefix = enumDecls.isEmpty ? "" : "\(enumDecls)\n\n"
        return """
            \(modulePrefix)\
            export function createComponent() {
            \(indent(generated, level: 1))
            }
            """
    }

    private func renderCaseDeclarations(name: String, cases: [EnumCaseDeclaration]) -> String {
        guard !cases.isEmpty else {
            return ""
        }

        let iterableCases = cases.filter { $0.associatedValues.isEmpty }

        var memberLines: [String] = []
        for caseDecl in iterableCases {
            memberLines.append("  \(caseDecl.name): \"\(escapeJavaScript(caseDecl.name))\",")
        }
        let allCasesValue =
            iterableCases
            .map { "\"\(escapeJavaScript($0.name))\"" }
            .joined(separator: ", ")
        memberLines.append("  allCases: [\(allCasesValue)],")

        return """
            export const \(name) = Object.freeze({
            \(memberLines.joined(separator: "\n"))
            });
            """
    }

    private func generatePageFactory(
        page: ComponentNode,
        library: [String: ComponentNode],
        customModifierStyles: [String: String]
    ) throws
        -> String
    {
        var context = RenderGenerationContext()
        let pageScope = RenderScope(
            prefix: page.name.lowercased(),
            stateNames: Set(
                page.states.compactMap { state in
                    if case .stored = state.storage { return state.name }
                    return nil
                }),
            derivedStateNames: Set(
                page.states.compactMap { state in
                    if case .derived = state.storage { return state.name }
                    return nil
                }),
            localBindings: []
        )
        for state in page.states {
            switch state.storage {
            case .stored(let expression):
                context.stateDeclarations[pageScope.stateKey(state.name)] = renderExpression(
                    expression,
                    scope: pageScope
                )
            case .derived(let body):
                var handlerContext = HandlerRenderContext()
                let statements = body.map {
                    renderStatement($0, scope: pageScope, context: &handlerContext)
                }
                .joined(separator: "\n")
                context.derivedStateDeclarations.append(
                    """
                    const \(pageScope.stateKey(state.name)) = () => {
                    \(indent(statements, level: 1))
                    };
                    """
                )
            }
        }
        let markup = try renderView(
            page.body,
            scope: pageScope,
            context: &context,
            library: library,
            customModifierStyles: customModifierStyles,
            slots: [:]
        )

        let orderedStates = context.stateDeclarations.keys.sorted().map { key in
            (key, context.stateDeclarations[key] ?? "null")
        }

        let stateLines =
            orderedStates.isEmpty
            ? "const __state = {};"
            : "const __state = {\n\(orderedStates.map { "  \($0.0): \($0.1)" }.joined(separator: ",\n"))\n};"

        let derivedStateLines =
            context.derivedStateDeclarations.isEmpty
            ? ""
            : context.derivedStateDeclarations.joined(separator: "\n\n")
        let handlerLines =
            context.handlers.isEmpty
            ? ""
            : context.handlers.joined(separator: "\n\n")
        let debugLines =
            context.debugLogs.isEmpty
            ? ""
            : context.debugLogs.joined(separator: "\n")
        let bindLines = [debugLines, handlerLines].filter { !$0.isEmpty }
            .joined(separator: "\n\n")
        let preRenderLines = [derivedStateLines].filter { !$0.isEmpty }.joined(separator: "\n\n")

        return """
            \(stateLines)
            \(preRenderLines.isEmpty ? "" : "\(preRenderLines)\n")
            return {
              render() {
                return `\(markup)`;
              },
              bind(root, rerender) {
            \(bindLines.isEmpty ? "    return;" : indent(bindLines, level: 2))
              }
            };
            """
    }

    private func renderView(
        _ view: ViewNode,
        scope: RenderScope,
        context: inout RenderGenerationContext,
        library: [String: ComponentNode],
        customModifierStyles: [String: String],
        slots: [String: [ViewNode]]
    ) throws -> String {
        switch view {
        case .text(let interpolated):
            return "<span>\(renderInterpolatedString(interpolated, scope: scope))</span>"
        case .debugPrint(let message):
            context.debugLogs.append(
                "console.log(`\(renderInterpolatedString(message, scope: scope))`);")
            return ""
        case .button(let title, let action):
            let buttonID = "button-\(context.nextButtonID)"
            context.nextButtonID += 1
            context.handlers.append(renderHandler(buttonID: buttonID, action: action, scope: scope))
            return "<button data-neat-click=\"\(buttonID)\">\(escapeJavaScript(title))</button>"
        case .forEach(let name, let sequence, let body):
            let loopScope = scope.addingLocalBinding(name)
            let content =
                try body
                .map {
                    try renderView(
                        $0,
                        scope: loopScope,
                        context: &context,
                        library: library,
                        customModifierStyles: customModifierStyles,
                        slots: slots
                    )
                }
                .joined(separator: "\n")
            let renderedSequence = renderExpression(sequence, scope: scope)
            return
                "${(\(renderedSequence) ?? []).map((\(name)) => `\(content)`).join(\"\")}"
        case .conditional(let branches):
            return try renderConditionalView(
                branches,
                scope: scope,
                context: &context,
                library: library,
                customModifierStyles: customModifierStyles,
                slots: slots
            )
        case .component(let name, let children):
            guard let component = library[name] else {
                throw ValidationError("Missing component '\(name)'")
            }
            let childScope = RenderScope(
                prefix: "\(scope.prefix)_\(name.lowercased())_\(context.nextComponentID)",
                stateNames: Set(
                    component.states.compactMap { state in
                        if case .stored = state.storage { return state.name }
                        return nil
                    }),
                derivedStateNames: Set(
                    component.states.compactMap { state in
                        if case .derived = state.storage { return state.name }
                        return nil
                    }),
                localBindings: scope.localBindings
            )
            context.nextComponentID += 1
            for state in component.states {
                switch state.storage {
                case .stored(let expression):
                    context.stateDeclarations["\(childScope.prefix)_\(state.name)"] =
                        renderExpression(expression, scope: childScope)
                case .derived(let body):
                    var handlerContext = HandlerRenderContext()
                    let statements = body.map {
                        renderStatement($0, scope: childScope, context: &handlerContext)
                    }
                    .joined(separator: "\n")
                    context.derivedStateDeclarations.append(
                        """
                        const \(childScope.stateKey(state.name)) = () => {
                        \(indent(statements, level: 1))
                        };
                        """
                    )
                }
            }
            var childSlots: [String: [ViewNode]] = [:]
            if let children {
                childSlots["content"] = children
            }
            return try renderView(
                component.body,
                scope: childScope,
                context: &context,
                library: library,
                customModifierStyles: customModifierStyles,
                slots: childSlots
            )
        case .slot(let name):
            let slotViews = slots[name] ?? []
            return try slotViews.map {
                try renderView(
                    $0,
                    scope: scope,
                    context: &context,
                    library: library,
                    customModifierStyles: customModifierStyles,
                    slots: slots
                )
            }
            .joined(separator: "\n")
        case .element(let tag, let children):
            let content =
                try children
                .map {
                    try renderView(
                        $0,
                        scope: scope,
                        context: &context,
                        library: library,
                        customModifierStyles: customModifierStyles,
                        slots: slots
                    )
                }
                .joined(separator: "\n")
            return "<\(tag)>\(content)</\(tag)>"
        case .vStack(let children):
            let content =
                try children
                .map {
                    try renderView(
                        $0,
                        scope: scope,
                        context: &context,
                        library: library,
                        customModifierStyles: customModifierStyles,
                        slots: slots
                    )
                }
                .joined(separator: "\n")
            return """
                <div class="vstack">
                \(content)
                </div>
                """
        case .modified(let base, let modifiers):
            let baseHTML = try renderView(
                base,
                scope: scope,
                context: &context,
                library: library,
                customModifierStyles: customModifierStyles,
                slots: slots
            )
            return renderModifiedView(
                baseHTML: baseHTML,
                modifiers: modifiers,
                customModifierStyles: customModifierStyles
            )
        }
    }

    private func renderConditionalView(
        _ branches: [ViewConditionalBranch],
        scope: RenderScope,
        context: inout RenderGenerationContext,
        library: [String: ComponentNode],
        customModifierStyles: [String: String],
        slots: [String: [ViewNode]]
    ) throws -> String {
        var lines: [String] = ["${(() => {"]

        for (index, branch) in branches.enumerated() {
            let content =
                try branch.body
                .map {
                    try renderView(
                        $0,
                        scope: scope,
                        context: &context,
                        library: library,
                        customModifierStyles: customModifierStyles,
                        slots: slots
                    )
                }
                .joined(separator: "\n")
            let markup = content.isEmpty ? "" : "\n\(content)\n"

            if let condition = branch.condition {
                let renderedCondition = renderExpression(condition, scope: scope)
                let prefix = index == 0 ? "  if" : "  else if"
                lines.append("\(prefix) (\(renderedCondition)) {")
                lines.append("    return `\(markup)`;")
                lines.append("  }")
            } else {
                lines.append("  else {")
                lines.append("    return `\(markup)`;")
                lines.append("  }")
            }
        }

        if branches.last?.condition != nil {
            lines.append("  return ``;")
        }

        lines.append("})()}")
        return lines.joined(separator: "\n")
    }

    private func renderModifiedView(
        baseHTML: String,
        modifiers: [ModifierCall],
        customModifierStyles: [String: String]
    ) -> String {
        var current = baseHTML
        var classes: [String] = []

        for modifier in modifiers {
            if modifier.name == "class",
                let argument = firstModifierArgumentValue(modifier),
                case .string(let className) = argument
            {
                classes.append(className)
                continue
            }
            let style = renderModifierStyle(modifier, customModifierStyles: customModifierStyles)
            if style.isEmpty {
                continue
            }
            current = "<div style=\"\(style)\">\(current)</div>"
        }

        if !classes.isEmpty {
            current = "<div class=\"\(classes.joined(separator: " "))\">\(current)</div>"
        }

        return current
    }

    private func renderModifierStyle(
        _ modifier: ModifierCall,
        customModifierStyles: [String: String]
    ) -> String {
        switch modifier.name.lowercased() {
        case "background":
            guard let argument = colorArgumentValue(from: modifier) else { return "" }
            let value = renderModifierColorValue(argument)
            if value.isEmpty { return "" }
            return "background: \(value);"
        case "padding":
            guard let value = renderPaddingValue(from: modifier) else { return "" }
            return "padding: \(value);"
        case "shadow", "shading":
            guard let value = renderShadowValue(from: modifier) else { return "" }
            return "box-shadow: \(value);"
        default:
            if modifier.arguments.isEmpty {
                return customModifierStyles[modifier.name]
                    ?? customModifierStyles[modifier.name.lowercased()]
                    ?? ""
            }
            return ""
        }
    }

    private func firstModifierArgumentValue(_ modifier: ModifierCall) -> ModifierArgument? {
        modifier.arguments.first?.value
    }

    private func colorArgumentValue(from modifier: ModifierCall) -> ModifierArgument? {
        if let labeled = modifier.arguments.first(where: { $0.label == "color" }) {
            return labeled.value
        }
        return firstModifierArgumentValue(modifier)
    }

    private func labeledArgumentValue(_ label: String, from modifier: ModifierCall)
        -> ModifierArgument?
    {
        modifier.arguments.first(where: { $0.label == label })?.value
    }

    private func renderPaddingValue(from modifier: ModifierCall) -> String? {
        var labeled: [String: ModifierArgument] = [:]
        for argument in modifier.arguments {
            guard let label = argument.label else { continue }
            labeled[label] = argument.value
        }

        if !labeled.isEmpty {
            let all = labeled["all"].flatMap(renderLengthToken)
            let horizontal = labeled["horizontal"].flatMap(renderLengthToken)
            let vertical = labeled["vertical"].flatMap(renderLengthToken)
            let top = labeled["top"].flatMap(renderLengthToken) ?? vertical ?? all
            let right = labeled["right"].flatMap(renderLengthToken) ?? horizontal ?? all
            let bottom = labeled["bottom"].flatMap(renderLengthToken) ?? vertical ?? all
            let left = labeled["left"].flatMap(renderLengthToken) ?? horizontal ?? all

            guard let top, let right, let bottom, let left else { return nil }
            return "\(top) \(right) \(bottom) \(left)"
        }

        let values = modifier.arguments.compactMap { renderLengthToken($0.value) }
        switch values.count {
        case 1:
            return values[0]
        case 2:
            return "\(values[0]) \(values[1])"
        case 3:
            return "\(values[0]) \(values[1]) \(values[2])"
        case 4:
            return "\(values[0]) \(values[1]) \(values[2]) \(values[3])"
        default:
            return nil
        }
    }

    private func renderShadowValue(from modifier: ModifierCall) -> String? {
        let defaultColor = "rgba(15, 23, 42, 18%)"
        let x =
            labeledArgumentValue("x", from: modifier).flatMap(renderLengthToken)
            ?? modifier.arguments.first.flatMap { renderLengthToken($0.value) }
            ?? "0px"
        let y =
            labeledArgumentValue("y", from: modifier).flatMap(renderLengthToken)
            ?? modifier.arguments.dropFirst().first.flatMap { renderLengthToken($0.value) }
            ?? "8px"
        let blur =
            labeledArgumentValue("blur", from: modifier).flatMap(renderLengthToken)
            ?? modifier.arguments.dropFirst(2).first.flatMap { renderLengthToken($0.value) }
            ?? "24px"
        let spread =
            labeledArgumentValue("spread", from: modifier).flatMap(renderLengthToken)
            ?? modifier.arguments.dropFirst(3).first.flatMap { renderLengthToken($0.value) }
            ?? "0px"

        let color: String
        if let labeledColor = labeledArgumentValue("color", from: modifier) {
            color = renderModifierColorValue(labeledColor)
        } else if modifier.arguments.count >= 4,
            modifier.arguments[3].label == nil,
            renderLengthToken(modifier.arguments[3].value) == nil
        {
            color = renderModifierColorValue(modifier.arguments[3].value)
        } else if modifier.arguments.count >= 5, modifier.arguments[4].label == nil {
            color = renderModifierColorValue(modifier.arguments[4].value)
        } else {
            color = defaultColor
        }

        let finalColor = color.isEmpty ? defaultColor : color
        return "\(x) \(y) \(blur) \(spread) \(finalColor)"
    }

    private func renderLengthToken(_ argument: ModifierArgument) -> String? {
        switch argument {
        case .integer(let value):
            return "\(value)px"
        case .double(let value):
            return "\(renderNumberLiteral(value))px"
        case .percentage(let value):
            return "\(renderNumberLiteral(value))%"
        case .string(let value):
            return value
        case .identifier(let value):
            return value
        case .enumCase, .enumCall:
            return nil
        }
    }

    private func renderModifierColorValue(_ argument: ModifierArgument) -> String {
        switch argument {
        case .enumCase(let name):
            switch name.lowercased() {
            case "red":
                return "#ef4444"
            case "blue":
                return "#3b82f6"
            case "green":
                return "#22c55e"
            case "orange":
                return "#f97316"
            case "yellow":
                return "#facc15"
            case "purple":
                return "#a855f7"
            case "pink":
                return "#ec4899"
            case "black":
                return "#000000"
            case "white":
                return "#ffffff"
            case "clear":
                return "transparent"
            default:
                return ""
            }
        case .enumCall(let name, let arguments):
            return renderColorFunction(name: name, arguments: arguments)
        case .string(let value):
            return value
        case .identifier(let value):
            return value
        case .integer(let value):
            return String(value)
        case .double(let value):
            return renderNumberLiteral(value)
        case .percentage(let value):
            return "\(renderNumberLiteral(value))%"
        }
    }

    private func renderColorFunction(name: String, arguments: [ModifierArgument]) -> String {
        let fn = name.lowercased()
        switch fn {
        case "rgb", "rgba", "hsl", "hsla", "hwb", "lab", "lch", "oklab", "oklch":
            let joined = arguments.map(renderColorArgumentToken).joined(separator: ", ")
            return "\(fn)(\(joined))"
        case "hex":
            guard let first = arguments.first else { return "" }
            let raw = renderColorArgumentToken(first).trimmingCharacters(
                in: .whitespacesAndNewlines)
            if raw.isEmpty { return "" }
            return raw.hasPrefix("#") ? raw : "#\(raw)"
        default:
            return ""
        }
    }

    private func renderColorArgumentToken(_ argument: ModifierArgument) -> String {
        switch argument {
        case .string(let value):
            return value
        case .integer(let value):
            return String(value)
        case .double(let value):
            return renderNumberLiteral(value)
        case .percentage(let value):
            return "\(renderNumberLiteral(value))%"
        case .identifier(let value):
            return value
        case .enumCase(let value):
            return value
        case .enumCall(let name, let args):
            return renderColorFunction(name: name, arguments: args)
        }
    }

    private func renderNumberLiteral(_ value: Double) -> String {
        if value.rounded() == value {
            return String(Int(value))
        }
        return String(value)
    }

    private func renderInterpolatedString(_ string: InterpolatedString, scope: RenderScope)
        -> String
    {
        string.segments.map { segment in
            switch segment {
            case .text(let value):
                return escapeJavaScript(value)
            case .expression(let expression):
                return "${\(renderExpression(expression, scope: scope))}"
            }
        }.joined()
    }

    private func renderHandler(buttonID: String, action: [Statement], scope: RenderScope) -> String
    {
        var handlerContext = HandlerRenderContext()
        let statements = action.map {
            renderStatement($0, scope: scope, context: &handlerContext)
        }
        .joined(separator: "\n")

        return """
            const \(buttonID.replacingOccurrences(of: "-", with: "_")) = root.querySelector('[data-neat-click="\(buttonID)"]');
            if (\(buttonID.replacingOccurrences(of: "-", with: "_"))) {
              \(buttonID.replacingOccurrences(of: "-", with: "_")).onclick = () => {
            \(indent(statements, level: 2))
                rerender();
              };
            }
            """
    }

    private func renderStatement(
        _ statement: Statement,
        scope: RenderScope,
        context: inout HandlerRenderContext
    ) -> String {
        switch statement {
        case .declaration(let kind, let name, let expression):
            let keyword: String
            switch kind {
            case .constant:
                keyword = "const"
            case .mutable:
                keyword = "let"
            }
            context.localBindings[name] = kind
            return
                "\(keyword) \(name) = \(renderExpression(expression, scope: scope, context: context));"
        case .assignment(let target, let expression):
            switch target {
            case .state(let name):
                return
                    "__state.\(scope.stateKey(name)) = \(renderExpression(expression, scope: scope, context: context));"
            case .local(let name):
                return "\(name) = \(renderExpression(expression, scope: scope, context: context));"
            }
        case .compoundAssignment(let target, .plusEquals, let expression):
            switch target {
            case .state(let name):
                let lhs = "__state.\(scope.stateKey(name))"
                return
                    "\(lhs) = \(lhs) + \(renderExpression(expression, scope: scope, context: context));"
            case .local(let name):
                return
                    "\(name) = \(name) + \(renderExpression(expression, scope: scope, context: context));"
            }
        case .forEach(let name, let sequence, let body):
            let sequenceValue = renderExpression(sequence, scope: scope, context: context)
            var loopContext = context
            loopContext.localBindings[name] = .constant
            let statements = body.map {
                renderStatement($0, scope: scope, context: &loopContext)
            }
            .joined(separator: "\n")
            return """
                for (const \(name) of (\(sequenceValue) ?? [])) {
                \(indent(statements, level: 1))
                }
                """
        case .whileLoop(let condition, let body):
            let renderedCondition = renderExpression(condition, scope: scope, context: context)
            var loopContext = context
            let statements = body.map {
                renderStatement($0, scope: scope, context: &loopContext)
            }
            .joined(separator: "\n")
            return """
                while (\(renderedCondition)) {
                \(indent(statements, level: 1))
                }
                """
        case .conditional(let branches):
            return renderConditionalStatement(branches: branches, scope: scope, context: context)
        case .return(let expression):
            if let expression {
                return "return \(renderExpression(expression, scope: scope, context: context));"
            }
            return "return;"
        case .break:
            return "break;"
        case .continue:
            return "continue;"
        case .switchStatement(let expression, let cases, let defaultBody):
            return renderSwitchStatement(
                expression: expression,
                cases: cases,
                defaultBody: defaultBody,
                scope: scope,
                context: context
            )
        case .debugPrint(let message):
            return "console.log(`\(renderInterpolatedString(message, scope: scope))`);"
        }
    }

    private func renderConditionalStatement(
        branches: [StatementConditionalBranch],
        scope: RenderScope,
        context: HandlerRenderContext
    ) -> String {
        var lines: [String] = []

        for (index, branch) in branches.enumerated() {
            var branchContext = context
            let statements = branch.body.map {
                renderStatement($0, scope: scope, context: &branchContext)
            }
            .joined(separator: "\n")

            if let condition = branch.condition {
                let renderedCondition = renderExpression(condition, scope: scope, context: context)
                let prefix = index == 0 ? "if" : "else if"
                lines.append("\(prefix) (\(renderedCondition)) {")
            } else {
                lines.append("else {")
            }

            if !statements.isEmpty {
                lines.append(indent(statements, level: 1))
            }
            lines.append("}")
        }

        return lines.joined(separator: "\n")
    }

    private func renderSwitchStatement(
        expression: NeatSyntax.Expression,
        cases: [SwitchCase],
        defaultBody: [Statement]?,
        scope: RenderScope,
        context: HandlerRenderContext
    ) -> String {
        let subject = renderExpression(expression, scope: scope, context: context)

        var lines: [String] = ["switch (\(subject)) {"]

        for caseNode in cases {
            let value = renderExpression(caseNode.value, scope: scope, context: context)
            var caseContext = context
            let statements = caseNode.body.map {
                renderStatement($0, scope: scope, context: &caseContext)
            }
            .joined(separator: "\n")

            lines.append("  case \(value): {")
            if !statements.isEmpty {
                lines.append(indent(statements, level: 2))
            }
            lines.append("    break;")
            lines.append("  }")
        }

        if let defaultBody {
            var defaultContext = context
            let statements = defaultBody.map {
                renderStatement($0, scope: scope, context: &defaultContext)
            }
            .joined(separator: "\n")
            lines.append("  default: {")
            if !statements.isEmpty {
                lines.append(indent(statements, level: 2))
            }
            lines.append("    break;")
            lines.append("  }")
        }

        lines.append("}")
        return lines.joined(separator: "\n")
    }

    private func renderExpression(
        _ expression: NeatSyntax.Expression,
        scope: RenderScope,
        context: HandlerRenderContext? = nil
    ) -> String {
        switch expression {
        case .integer(let value):
            return String(value)
        case .string(let value):
            return "\"\(escapeJavaScript(value))\""
        case .boolean(let value):
            return value ? "true" : "false"
        case .none:
            return "null"
        case .identifier(let name):
            if scope.localBindings.contains(name) {
                return name
            }
            if context?.localBindings[name] != nil {
                return name
            }
            if scope.derivedStateNames.contains(name) {
                return "\(scope.stateKey(name))()"
            }
            if scope.stateNames.contains(name) {
                return "__state.\(scope.stateKey(name))"
            }
            return "__state.\(scope.stateKey(name))"
        case .array(let values):
            let rendered = values.map { renderExpression($0, scope: scope, context: context) }
                .joined(separator: ", ")
            return "[\(rendered)]"
        case .ternary(let condition, let trueExpression, let falseExpression):
            return
                "\(renderExpression(condition, scope: scope, context: context)) ? \(renderExpression(trueExpression, scope: scope, context: context)) : \(renderExpression(falseExpression, scope: scope, context: context))"
        case .unary(let op, let nested):
            return "\(op.rawValue)\(renderExpression(nested, scope: scope, context: context))"
        case .binary(let lhs, let op, let rhs):
            return
                "\(renderExpression(lhs, scope: scope, context: context)) \(op.rawValue) \(renderExpression(rhs, scope: scope, context: context))"
        }
    }

    private func composeCoreCSS(root: URL, packageCoreStylesheets: [String]) throws -> String {
        if packageCoreStylesheets.isEmpty {
            return try defaultRuntimeCoreCSS()
        }

        let loadedFiles = try packageCoreStylesheets.map { relativePath -> String in
            let fileURL = root.appendingPathComponent(relativePath, isDirectory: false)
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                throw ValidationError(
                    "Core stylesheet '\(relativePath)' not found in project root."
                )
            }
            return try String(contentsOf: fileURL, encoding: .utf8)
        }

        return loadedFiles.joined(separator: "\n\n")
    }

    private func defaultRuntimeCoreCSS() throws -> String {
        let styleFiles = [
            "Web/runtime/Styles/preflight.css",
            "Web/runtime/Styles/root.css",
            "Web/runtime/Styles/layout.css",
            "Web/runtime/Styles/typography.css",
            "Web/runtime/Styles/style.css",
        ]
        let contents = try styleFiles.map(loadTemplateText)
        return contents.joined(separator: "\n\n")
    }

    private func defaultHMRJS() -> String {
        (try? loadTemplateText("Web/runtime/hmr.js")) ?? ""
    }

    private func loadTemplateText(_ relativePath: String) throws -> String {
        try TemplateLoader.text(at: relativePath)
    }

    private func escapeHTML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private func escapeJavaScript(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "$", with: "\\$")
    }

    private func indent(_ value: String, level: Int) -> String {
        let prefix = String(repeating: "  ", count: level)
        return
            value
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { "\(prefix)\($0)" }
            .joined(separator: "\n")
    }
}

private struct HeadSummary {
    let title: String?
    let description: String?
    let stylesheets: [String]
}

private struct CompiledRoute: Codable {
    let path: String
    let page: String
}

private struct RenderGenerationContext {
    var stateDeclarations: [String: String] = [:]
    var derivedStateDeclarations: [String] = []
    var handlers: [String] = []
    var debugLogs: [String] = []
    var nextButtonID: Int = 0
    var nextComponentID: Int = 0
}

private struct RenderScope {
    let prefix: String
    let stateNames: Set<String>
    let derivedStateNames: Set<String>
    let localBindings: Set<String>

    func stateKey(_ name: String) -> String {
        "\(prefix)_\(name)"
    }

    func addingLocalBinding(_ name: String) -> RenderScope {
        RenderScope(
            prefix: prefix,
            stateNames: stateNames,
            derivedStateNames: derivedStateNames,
            localBindings: localBindings.union([name])
        )
    }
}

private struct HandlerRenderContext {
    var localBindings: [String: LocalBindingKind] = [:]
}

extension Array where Element: Hashable {
    fileprivate func removingDuplicates() -> [Element] {
        var seen: Set<Element> = []
        return filter { seen.insert($0).inserted }
    }
}
