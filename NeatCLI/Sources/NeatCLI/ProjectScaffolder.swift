import ArgumentParser
import Darwin
import Foundation

struct ProjectScaffolder {
    private let initialName: String?
    private let initialPath: String?

    init(initialName: String?, initialPath: String?) {
        self.initialName = initialName
        self.initialPath = initialPath
    }

    func run() throws {
        let currentDirectoryName = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .lastPathComponent
        let projectName = try resolveProjectName(currentDirectoryName: currentDirectoryName)
        let targetDirectory = try resolveTargetDirectory(
            currentDirectoryName: currentDirectoryName,
            projectName: projectName
        )
        try createProject(name: projectName, targetDirectory: targetDirectory)

        TerminalLog.out(
            "Created Neat project \(projectName) at \(targetDirectory.path)",
            level: .success
        )
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

    private func createProject(name: String, targetDirectory: URL) throws {
        let packagePath = targetDirectory.appendingPathComponent("Package.neat", isDirectory: false)
        let playgroundPath = targetDirectory.appendingPathComponent(
            "Playground.neat",
            isDirectory: false
        )

        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: packagePath.path)
            || fileManager.fileExists(atPath: playgroundPath.path)
        {
            throw ValidationError("Target already contains Package.neat or Playground.neat.")
        }

        try renderProgramPackage(name: name).write(
            to: packagePath,
            atomically: true,
            encoding: .utf8
        )
        try renderProgramPlayground(name: name).write(
            to: playgroundPath,
            atomically: true,
            encoding: .utf8
        )
    }

    private func renderProgramPackage(name: String) -> String {
        let packageName = sanitizedSymbolName(from: name)
        return """
            construct \(packageName): Package {
                let version: String = "0.1.0"
                let author: String = "\(escapedStringLiteral(NSFullUserName()))"
                let remote: String = ""
            }
            """
    }

    private func renderProgramPlayground(name: String) -> String {
        return """
            @main
            {
              Logger.info("Neat program playground")

              let values = [1, 2, 3]
              state total = 0

              for value in values {
                total += value
              }

              if total == 6 {
                Logger.success("sum = \\(total)")
              } else {
                Logger.warning("unexpected sum")
              }
            }
            """
    }

    private func sanitizedSymbolName(from raw: String) -> String {
        let pieces =
            raw
            .split { !$0.isLetter && !$0.isNumber }
            .filter { !$0.isEmpty }
            .map { piece -> String in
                let lower = piece.lowercased()
                return lower.prefix(1).uppercased() + lower.dropFirst()
            }
        let joined = pieces.joined()
        if joined.isEmpty {
            return "Neat"
        }
        if let first = joined.first, first.isNumber {
            return "Neat\(joined)"
        }
        return joined
    }

    private func escapedStringLiteral(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private func prompt(
        _ label: String,
        placeholder: String? = nil,
        note: String? = nil,
        defaultValue: String? = nil
    ) -> String {
        let fallback = {
            let placeholderText =
                placeholder.map {
                    " \(TerminalColor.dim.string)\($0)\(TerminalColor.reset.string)"
                } ?? ""
            let noteText =
                note.map {
                    " \(TerminalColor.cyan.string)\(TerminalColor.dim.string)\($0)\(TerminalColor.reset.string)"
                } ?? ""
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
            note.map {
                " \(TerminalColor.cyan.string)\(TerminalColor.dim.string)\($0)\(TerminalColor.reset.string)"
            } ?? ""
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
            displayValue = "\(TerminalColor.dim.string)\(placeholder)\(TerminalColor.reset.string)"
            placeholderWidth = placeholder.count
        } else {
            displayValue = input
            placeholderWidth = 0
        }

        print(
            "\r\(TerminalColor.clearLine.string)\(prefix)\(displayValue)\(noteSuffix)",
            terminator: ""
        )
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
