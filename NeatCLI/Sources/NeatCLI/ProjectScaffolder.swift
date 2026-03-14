import ArgumentParser
import Darwin
import Foundation

struct ProjectScaffolder {
    enum ProjectKind: String, CaseIterable {
        case web
        case program

        var label: String {
            rawValue
        }
    }

    private enum TerminalStyle {
        static let reset = "\u{001B}[0m"
        static let dim = "\u{001B}[2m"
        static let cyan = "\u{001B}[36m"
        static let clearLine = "\u{001B}[2K"
    }

    private let initialKind: ProjectKind?
    private let initialName: String?
    private let initialPath: String?

    init(initialKind: ProjectKind?, initialName: String?, initialPath: String?) {
        self.initialKind = initialKind
        self.initialName = initialName
        self.initialPath = initialPath
    }

    func run() throws {
        let currentDirectoryName = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .lastPathComponent
        let projectKind = try resolveProjectKind()
        let projectName = try resolveProjectName(currentDirectoryName: currentDirectoryName)
        let targetDirectory = try resolveTargetDirectory(
            currentDirectoryName: currentDirectoryName,
            projectName: projectName
        )
        try createProject(
            kind: projectKind,
            name: projectName,
            targetDirectory: targetDirectory,
            includeStarterFiles: true
        )

        print("Created \(projectKind.label) project \(projectName) at \(targetDirectory.path)")
    }

    private func resolveProjectKind() throws -> ProjectKind {
        if let initialKind {
            return initialKind
        }

        let response = prompt(
            "Project Kind",
            placeholder: "web",
            note: "(web/program)",
            defaultValue: "web"
        )
        guard
            let kind = ProjectKind(
                rawValue: response.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
        else {
            throw ValidationError(
                "Unknown project kind '\(response)'. Supported kinds: \(ProjectKind.allCases.map(\.rawValue).joined(separator: ", "))."
            )
        }
        return kind
    }

    private func resolveProjectName(currentDirectoryName: String) throws -> String {
        if let initialName, !initialName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return initialName
        }

        if let initialPath {
            let trimmedPath = initialPath.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedPath.isEmpty {
                let pathURL = URL(fileURLWithPath: trimmedPath, isDirectory: true)
                    .standardizedFileURL
                var isDirectory: ObjCBool = false
                let exists = FileManager.default.fileExists(
                    atPath: pathURL.path,
                    isDirectory: &isDirectory
                )

                if exists && isDirectory.boolValue && !pathLooksLikeContainerDirectory(trimmedPath)
                    && directoryHasVisibleEntries(pathURL)
                {
                    let suggested = inferredProjectName(from: trimmedPath) ?? "NeatProject"
                    let response = prompt(
                        "Project Name",
                        placeholder: suggested,
                        note: "(directory not empty)",
                        defaultValue: suggested
                    )
                    let candidate = response.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !candidate.isEmpty {
                        return candidate
                    }
                    return suggested
                }

                if !pathLooksLikeContainerDirectory(trimmedPath),
                    let inferred = inferredProjectName(from: trimmedPath)
                {
                    return inferred
                }
            }
        }

        let response = prompt(
            "Project Name",
            placeholder: currentDirectoryName.isEmpty ? "NeatProject" : currentDirectoryName,
            note: "(enter for ./)"
        )
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }

        if !currentDirectoryName.isEmpty {
            return currentDirectoryName
        }

        throw ValidationError("Unable to derive project name from the current directory.")
    }

    private func resolveTargetDirectory(currentDirectoryName: String, projectName: String) throws
        -> URL
    {
        if let initialPath {
            let provided = initialPath.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !provided.isEmpty else {
                throw ValidationError("Target path cannot be empty.")
            }

            let providedURL = URL(fileURLWithPath: provided, isDirectory: true)
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(
                atPath: providedURL.path, isDirectory: &isDirectory)

            if exists && isDirectory.boolValue {
                if pathLooksLikeContainerDirectory(provided) {
                    return providedURL.appendingPathComponent(projectName, isDirectory: true)
                }

                if directoryHasVisibleEntries(providedURL) {
                    return providedURL.appendingPathComponent(projectName, isDirectory: true)
                }

                return providedURL
            }

            return providedURL
        }

        let defaultPath: String
        let placeholderName: String
        let autoCreateDefaultDirectory: Bool
        if projectName == currentDirectoryName {
            defaultPath = "./"
            placeholderName = currentDirectoryName.isEmpty ? "Root" : currentDirectoryName
            autoCreateDefaultDirectory = false
        } else {
            defaultPath = "./\(projectName)"
            placeholderName = projectName
            autoCreateDefaultDirectory = true
        }

        let proposedPath =
            initialPath
            ?? prompt(
                "Directory",
                placeholder: placeholderName,
                note: "(enter for \(defaultPath))",
                defaultValue: defaultPath
            )
        let trimmedPath = proposedPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedPath = trimmedPath.isEmpty ? defaultPath : trimmedPath
        let baseURL = URL(fileURLWithPath: resolvedPath, isDirectory: true)

        if FileManager.default.fileExists(atPath: baseURL.path) {
            return baseURL
        }

        if autoCreateDefaultDirectory && resolvedPath == defaultPath {
            try FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
            return baseURL
        }

        let createChoice = prompt(
            "Directory '\(baseURL.path)' does not exist. Create it? (Y/n)",
            defaultValue: "Y"
        )

        if createChoice.lowercased() == "n" {
            throw ValidationError("Aborted.")
        }

        try FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
        return baseURL
    }

    private func inferredProjectName(from rawPath: String) -> String? {
        let url = URL(fileURLWithPath: rawPath, isDirectory: true).standardizedFileURL
        let name = url.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty || name == "." || name == ".." {
            return nil
        }
        return name
    }

    private func pathLooksLikeContainerDirectory(_ rawPath: String) -> Bool {
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.hasSuffix("/") || trimmed == "." || trimmed == ".."
            || trimmed == "./" || trimmed == "../"
        {
            return true
        }
        let inferred = inferredProjectName(from: trimmed)
        return inferred == nil
    }

    private func directoryHasVisibleEntries(_ directory: URL) -> Bool {
        guard
            let entries = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isHiddenKey],
                options: [.skipsHiddenFiles]
            )
        else {
            return false
        }

        return !entries.isEmpty
    }

    private func createProject(
        kind: ProjectKind,
        name: String,
        targetDirectory: URL,
        includeStarterFiles: Bool
    ) throws {
        switch kind {
        case .web:
            try createWebProject(
                name: name,
                targetDirectory: targetDirectory,
                includeStarterFiles: includeStarterFiles
            )
        case .program:
            try createProgramProject(name: name, targetDirectory: targetDirectory)
        }
    }

    private func createWebProject(
        name: String,
        targetDirectory: URL,
        includeStarterFiles: Bool
    ) throws {
        let packagePath = targetDirectory.appendingPathComponent("Package.neat", isDirectory: false)
        let appPath = targetDirectory.appendingPathComponent("App.neat", isDirectory: false)
        let fontsPath = targetDirectory.appendingPathComponent("Fonts.neat", isDirectory: false)
        let neatDirectory = targetDirectory.appendingPathComponent(".neat", isDirectory: true)
        let neatBuildDirectory = neatDirectory.appendingPathComponent("Build", isDirectory: true)
        let coreVersionDirectory =
            neatDirectory
            .appendingPathComponent("Core", isDirectory: true)
            .appendingPathComponent("V1", isDirectory: true)
        let coreModifiersDirectory = coreVersionDirectory.appendingPathComponent(
            "Modifiers", isDirectory: true)
        let coreComponentsDirectory = coreVersionDirectory.appendingPathComponent(
            "Components", isDirectory: true)
        let coreIndexCSSPath = coreVersionDirectory.appendingPathComponent(
            "index.css", isDirectory: false)
        let pagesDirectory = targetDirectory.appendingPathComponent("Pages", isDirectory: true)
        let componentsDirectory = targetDirectory.appendingPathComponent(
            "Components", isDirectory: true)
        let publicDirectory = targetDirectory.appendingPathComponent("Public", isDirectory: true)

        try ensureProjectDoesNotExist(at: packagePath, appPath: appPath, fontsPath: fontsPath)

        try FileManager.default.createDirectory(
            at: pagesDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: neatBuildDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: coreComponentsDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: coreModifiersDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: componentsDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: publicDirectory, withIntermediateDirectories: true)

        try renderPackage(name: name).write(
            to: packagePath, atomically: true, encoding: String.Encoding.utf8)
        try renderApp(name: name).write(
            to: appPath, atomically: true, encoding: String.Encoding.utf8)
        try renderFonts().write(
            to: fontsPath, atomically: true, encoding: String.Encoding.utf8)
        try defaultRuntimeCoreCSS().write(
            to: coreIndexCSSPath, atomically: true, encoding: String.Encoding.utf8)

        let coreCardPath = coreComponentsDirectory.appendingPathComponent(
            "CoreCard.neat", isDirectory: false)
        let coreHeroPath = coreComponentsDirectory.appendingPathComponent(
            "CoreHero.neat", isDirectory: false)
        let vStackPath = coreComponentsDirectory.appendingPathComponent(
            "VStack.neat", isDirectory: false)
        let surfaceModifierPath = coreModifiersDirectory.appendingPathComponent(
            "surface.css", isDirectory: false)
        try loadTemplateText("Web/core/V1/Components/CoreCard.neat").write(
            to: coreCardPath, atomically: true, encoding: String.Encoding.utf8)
        try loadTemplateText("Web/core/V1/Components/CoreHero.neat").write(
            to: coreHeroPath, atomically: true, encoding: String.Encoding.utf8)
        try loadTemplateText("Web/core/V1/Components/VStack.neat").write(
            to: vStackPath, atomically: true, encoding: String.Encoding.utf8)
        try """
        border: 1px solid var(--neat-border);
        background: var(--neat-surface);
        border-radius: 14px;
        padding: 1rem;
        """.write(
            to: surfaceModifierPath,
            atomically: true,
            encoding: String.Encoding.utf8
        )

        guard includeStarterFiles else { return }

        let homePagePath = pagesDirectory.appendingPathComponent(
            "HomePage.neat", isDirectory: false)
        let aboutPagePath = pagesDirectory.appendingPathComponent(
            "AboutPage.neat", isDirectory: false)
        let headerPath = componentsDirectory.appendingPathComponent(
            "HomePageHeader.neat", isDirectory: false)

        try renderHomePage(appName: name).write(
            to: homePagePath, atomically: true, encoding: String.Encoding.utf8)
        try renderAboutPage(appName: name).write(
            to: aboutPagePath, atomically: true, encoding: String.Encoding.utf8)
        try renderHeader().write(to: headerPath, atomically: true, encoding: String.Encoding.utf8)
    }

    private func createProgramProject(name: String, targetDirectory: URL) throws {
        let packagePath = targetDirectory.appendingPathComponent("Package.neat", isDirectory: false)
        let mainPath = targetDirectory.appendingPathComponent("Main.neat", isDirectory: false)
        let sourcesDirectory = targetDirectory.appendingPathComponent("Sources", isDirectory: true)

        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: packagePath.path)
            || fileManager.fileExists(atPath: mainPath.path)
        {
            throw ValidationError("Target already contains Package.neat or Main.neat.")
        }

        try fileManager.createDirectory(at: sourcesDirectory, withIntermediateDirectories: true)
        try renderProgramPackage(name: name).write(
            to: packagePath,
            atomically: true,
            encoding: .utf8
        )
        try renderProgramMain(name: name).write(
            to: mainPath,
            atomically: true,
            encoding: .utf8
        )
    }

    private func ensureProjectDoesNotExist(at packagePath: URL, appPath: URL, fontsPath: URL) throws
    {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: packagePath.path)
            || fileManager.fileExists(atPath: appPath.path)
            || fileManager.fileExists(atPath: fontsPath.path)
        {
            throw ValidationError("Target already contains Package.neat, App.neat, or Fonts.neat.")
        }
    }

    private func renderPackage(name: String) -> String {
        """
        Package("\(name)") {
          Platform(.web)
          Entry("App.neat")

          Directories {
            Pages("Pages")
            Components("Components")
            Assets("Public")
          }

          Dependencies {
          }

          Core {
            CoreStylesheet(".neat/Core/V1/index.css")
            CoreComponents(".neat/Core/V1/Components")
          }
        }
        """
    }

    private func renderProgramPackage(name: String) -> String {
        """
        Package("\(name)") {
          Platform(.program)
          Entry("Main.neat")

          Dependencies {
          }
        }
        """
    }

    private func renderApp(name: String) -> String {
        """
        #\(name): App {
          var head: Head {
            Meta.title("\(name)")
            Meta.description("A .neat application scaffolded by NeatCLI.")
          }

          var routes: Routes {
            Route("/", HomePage)
            Route("about", AboutPage)

            Route("dashboard") {
              Route("settings", AboutPage)
            }
          }
        }
        """
    }

    private func renderProgramMain(name: String) -> String {
        """
        #\(name): Program {
          @run() {
          }
        }
        """
    }

    private func renderFonts() -> String {
        """
        Fonts {
          Family(.geist) {
            Name("Geist")
            URL("https://fonts.googleapis.com/css2?family=Geist:wght@100..900&display=swap")
          }

          Family(.geistMono) {
            Name("Geist Mono")
            URL("https://fonts.googleapis.com/css2?family=Geist+Mono:wght@100..900&display=swap")
          }
        }
        """
    }

    private func renderHomePage(appName: String) -> String {
        """
        #Background: StyleModifier {
          var color: Color
        }

        #HomePage: Page {
          var head: Head {
            Meta.title("Home")
            Meta.description("The home page for \(appName).")
          }

          state count: Int = 0

          var body: Component {
            VStack {
              HomePageHeader()
              CoreHero()
              CoreCard()
                .background(.rgba(255, 255, 255, 72%))
                .padding(24, 28)
                .shadow(y: 12, blur: 36, color: .rgba(15, 23, 42, 20%))
              Text("Count: \\(count)")
              Button("Add") {
                count += 1
              }
            }
          }
        }
        """
    }

    private func renderAboutPage(appName: String) -> String {
        """
        #AboutPage: Page {
          var head: Head {
            Meta.title("About")
            Meta.description("About the \(appName) application.")
          }

          var body: Component {
            VStack {
              Text("About")
              Text("This project was created with neat create.")
            }
          }
        }
        """
    }

    private func renderHeader() -> String {
        """
        #HomePageHeader: Component {
          var body: Component {
            VStack {
              Text("Neat")
              Text("Swift-shaped UI compiled for the browser.")
            }
          }
        }
        """
    }

    private func loadTemplateText(_ relativePath: String) throws -> String {
        try TemplateLoader.text(at: relativePath)
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

    private func prompt(
        _ label: String,
        placeholder: String? = nil,
        note: String? = nil,
        defaultValue: String? = nil
    ) -> String {
        let fallback = {
            let placeholderText =
                placeholder.map { " \(TerminalStyle.dim)\($0)\(TerminalStyle.reset)" } ?? ""
            let noteText =
                note.map { " \(TerminalStyle.cyan)\(TerminalStyle.dim)\($0)\(TerminalStyle.reset)" }
                ?? ""
            print("\(label):\(placeholderText)\(noteText) ", terminator: "")
            fflush(stdout)
            let response = readLine() ?? ""
            if let defaultValue, response.isEmpty {
                return defaultValue
            }
            return response
        }

        guard isatty(STDIN_FILENO) == 1 else {
            return fallback()
        }

        let prefix = "\(label): "
        let noteSuffix =
            note.map { " \(TerminalStyle.cyan)\(TerminalStyle.dim)\($0)\(TerminalStyle.reset)" }
            ?? ""
        let noteWidth = note.map { 1 + $0.count } ?? 0
        var buffer: [Character] = []

        do {
            let rawMode = try RawTerminalMode()
            defer { rawMode.restore() }

            redrawPrompt(
                prefix: prefix, buffer: buffer, placeholder: placeholder, noteSuffix: noteSuffix,
                noteWidth: noteWidth)

            while true {
                var byte: UInt8 = 0
                let readResult = Darwin.read(STDIN_FILENO, &byte, 1)
                if readResult <= 0 {
                    print()
                    return defaultValue ?? String(buffer)
                }

                switch byte {
                case 3:
                    print("^C")
                    Foundation.exit(130)
                case 10, 13:
                    print()
                    let response = String(buffer)
                    if let defaultValue, response.isEmpty {
                        return defaultValue
                    }
                    return response
                case 8, 127:
                    if !buffer.isEmpty {
                        buffer.removeLast()
                    }
                default:
                    if byte >= 32 {
                        buffer.append(Character(UnicodeScalar(byte)))
                    }
                }

                redrawPrompt(
                    prefix: prefix, buffer: buffer, placeholder: placeholder,
                    noteSuffix: noteSuffix, noteWidth: noteWidth)
            }
        } catch {
            return fallback()
        }
    }

    private func redrawPrompt(
        prefix: String,
        buffer: [Character],
        placeholder: String?,
        noteSuffix: String,
        noteWidth: Int
    ) {
        let input = String(buffer)
        let displayValue: String
        let placeholderWidth: Int

        if input.isEmpty, let placeholder {
            displayValue = "\(TerminalStyle.dim)\(placeholder)\(TerminalStyle.reset)"
            placeholderWidth = placeholder.count
        } else {
            displayValue = input
            placeholderWidth = 0
        }

        print("\r\(TerminalStyle.clearLine)\(prefix)\(displayValue)\(noteSuffix)", terminator: "")
        let rewind = noteWidth + (input.isEmpty ? placeholderWidth : 0)
        if rewind > 0 {
            print("\u{001B}[\(rewind)D", terminator: "")
        }
        fflush(stdout)
    }
}

private struct RawTerminalMode {
    private let original: termios

    init() throws {
        var state = termios()
        guard tcgetattr(STDIN_FILENO, &state) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }

        original = state
        var raw = state
        raw.c_lflag &= ~tcflag_t(ICANON | ECHO)
        raw.c_cc.16 = 1
        raw.c_cc.17 = 0

        guard tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    func restore() {
        var state = original
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &state)
    }
}
