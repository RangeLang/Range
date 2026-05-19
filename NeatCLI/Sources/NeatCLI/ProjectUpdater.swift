import ArgumentParser
import Foundation
import NeatSyntax

struct ProjectUpdater {
    private static let releaseRepository = "georgetchelidze/Neat"

    private let path: String
    private let updateCLI: Bool

    init(path: String, updateCLI: Bool) {
        self.path = path
        self.updateCLI = updateCLI
    }

    static func updateInstalledCLI(
        repository: String = releaseRepository,
        version: String = "latest"
    ) throws {
        let platform = try releasePlatform()
        let archive = try releaseArchiveNameForCurrentPlatform()
        let urlString: String
        if version == "latest" {
            urlString = "https://github.com/\(repository)/releases/latest/download/\(archive)"
        } else {
            urlString = "https://github.com/\(repository)/releases/download/\(version)/\(archive)"
        }

        guard let url = URL(string: urlString) else {
            throw ValidationError("Invalid release URL: \(urlString)")
        }

        let fileManager = FileManager.default
        let temporaryRoot = fileManager.temporaryDirectory
            .appendingPathComponent("neat-update-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
        defer {
            try? fileManager.removeItem(at: temporaryRoot)
        }

        let archiveURL = temporaryRoot.appendingPathComponent(archive, isDirectory: false)
        TerminalLog.out("Downloading Neat from \(url.absoluteString)", level: .change)
        try download(url: url, to: archiveURL)

        try runProcess(
            executable: "/usr/bin/env",
            arguments: ["tar", "-xzf", archiveURL.path, "-C", temporaryRoot.path]
        )

        let packageRoot = temporaryRoot.appendingPathComponent(
            "neat-\(platform).lang",
            isDirectory: true
        )
        let installScript = packageRoot.appendingPathComponent("install.sh", isDirectory: false)
        guard fileManager.fileExists(atPath: installScript.path) else {
            throw ValidationError("Release archive is missing install.sh.")
        }

        let installPrefix = selfUpdateInstallPrefix()
        try runProcess(
            executable: installScript.path,
            arguments: [],
            environment: ["NEAT_INSTALL_PREFIX": installPrefix.path]
        )
        TerminalLog.out("Updated Neat CLI.", level: .success)
    }

    static func selfUpdateInstallPrefix() -> URL {
        let environment = ProcessInfo.processInfo.environment
        if let override = environment["NEAT_UPDATE_PREFIX"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true).standardizedFileURL
        }

        let executablePrefix = installedExecutableURL()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        if isNeatUserPrefix(executablePrefix), isWritableInstallPrefix(executablePrefix) {
            return executablePrefix
        }

        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".neat", isDirectory: true)
            .standardizedFileURL
    }

    private static func isNeatUserPrefix(_ prefix: URL) -> Bool {
        prefix.standardizedFileURL.path
            == FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".neat", isDirectory: true)
            .standardizedFileURL
            .path
    }

    private static func isWritableInstallPrefix(_ prefix: URL) -> Bool {
        let fileManager = FileManager.default
        let binDirectory = prefix.appendingPathComponent("bin", isDirectory: true)
        if fileManager.fileExists(atPath: binDirectory.path) {
            return fileManager.isWritableFile(atPath: binDirectory.path)
        }

        return fileManager.isWritableFile(atPath: prefix.path)
    }

    static func releaseArchiveNameForCurrentPlatform() throws -> String {
        "neat-\(try releasePlatform()).lang.tar.gz"
    }

    private static func installedExecutableURL() -> URL {
        let executable = CommandLine.arguments.first ?? "neat"
        if executable.contains("/") {
            return URL(fileURLWithPath: executable).standardizedFileURL
        }

        guard let lookupTool = Platform.defaultExecutableLookupTool else {
            return URL(fileURLWithPath: executable).standardizedFileURL
        }

        let process = Process()
        process.executableURL = lookupTool
        process.arguments = ["which", executable]
        let output = Pipe()
        process.standardOutput = output

        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                let data = output.fileHandleForReading.readDataToEndOfFile()
                let path = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if let path, !path.isEmpty {
                    return URL(fileURLWithPath: path).standardizedFileURL
                }
            }
        } catch {
            return URL(fileURLWithPath: executable).standardizedFileURL
        }

        return URL(fileURLWithPath: executable).standardizedFileURL
    }

    private static func releasePlatform() throws -> String {
        #if os(macOS)
        let os = "macos"
        #elseif os(Linux)
        let os = "linux"
        #else
        throw ValidationError("Neat release updates are not supported on this operating system yet.")
        #endif

        #if arch(arm64)
        let arch = "arm64"
        #elseif arch(x86_64)
        let arch = "x64"
        #else
        throw ValidationError("Neat release updates are not supported on this architecture yet.")
        #endif

        return "\(os)-\(arch)"
    }

    private static func download(url: URL, to destination: URL) throws {
        try runProcess(
            executable: "/usr/bin/env",
            arguments: ["curl", "-fsSL", url.absoluteString, "-o", destination.path]
        )
    }

    func run() throws {
        let root = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
        let packageFile = root.appendingPathComponent("Package.neat", isDirectory: false)

        guard FileManager.default.fileExists(atPath: packageFile.path) else {
            throw ValidationError("Missing Package.neat in \(root.path)")
        }

        let source = try String(contentsOf: packageFile, encoding: .utf8)
        let manifest = try PackageManifestLoader.load(from: packageFile)
        let isNeatPackage = manifest.name == "Neat"
        let modules = parseModules(from: source)
        try updateModules(modules, projectRoot: root, reportEmpty: !isNeatPackage)

        if updateCLI {
            try updateNeatCLIIfAvailable(from: root)
        }

        if isNeatPackage {
            try publishAndDownloadNeat(from: root, manifest: manifest)
        }

        TerminalLog.out("Update complete.", level: .success)
    }

    private func parseModules(from source: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"Module\("([^"]+)"\)"#) else {
            return []
        }
        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        let matches: [NSTextCheckingResult] = regex.matches(in: source, range: range)
        let values: [String] = matches.compactMap { match in
            guard let groupRange = Range(match.range(at: 1), in: source) else { return nil }
            return String(source[groupRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return Array(Set(values)).sorted()
    }

    private func updateModules(_ modules: [String], projectRoot: URL, reportEmpty: Bool = true) throws {
        guard !modules.isEmpty else {
            if reportEmpty {
                TerminalLog.subtleOut("Modules: none")
            }
            return
        }

        let modulesRoot =
            projectRoot
            .appendingPathComponent(".neat", isDirectory: true)
            .appendingPathComponent("Packages", isDirectory: true)
        try FileManager.default.createDirectory(at: modulesRoot, withIntermediateDirectories: true)

        for module in modules {
            let parts = module.split(separator: "/").map(String.init)
            guard parts.count >= 2 else {
                TerminalLog.out(
                    "Skipping invalid module '\(module)'. Use owner/repo.",
                    level: .warning
                )
                continue
            }

            let repoURL: String
            if module.contains("://") {
                repoURL = module
            } else {
                repoURL = "https://github.com/\(module).git"
            }

            let modulePath =
                parts.dropLast().reduce(modulesRoot) { partial, part in
                    partial.appendingPathComponent(part, isDirectory: true)
                }
                .appendingPathComponent(parts.last ?? "module", isDirectory: true)
            try FileManager.default.createDirectory(
                at: modulePath.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            let gitDir = modulePath.appendingPathComponent(".git", isDirectory: true)
            if FileManager.default.fileExists(atPath: gitDir.path) {
                try Self.runProcessQuiet(
                    executable: "/usr/bin/env",
                    arguments: ["git", "-C", modulePath.path, "pull", "--ff-only"]
                )
                TerminalLog.out("Updated module \(module)", level: .success)
            } else {
                try Self.runProcessQuiet(
                    executable: "/usr/bin/env",
                    arguments: ["git", "clone", "--depth", "1", repoURL, modulePath.path]
                )
                TerminalLog.out("Installed module \(module)", level: .success)
            }
        }
    }

    private func updateNeatCLIIfAvailable(from root: URL) throws {
        let script = root.appendingPathComponent("scripts/install-neat.sh", isDirectory: false)
        if !FileManager.default.fileExists(atPath: script.path) {
            TerminalLog.out(
                "Skipping CLI self-update: scripts/install-neat.sh not found in \(root.path)",
                level: .warning
            )
            return
        }

        try Self.runProcess(executable: script.path, arguments: [])
        TerminalLog.out("Updated Neat CLI", level: .success)
    }

    private func publishAndDownloadNeat(from root: URL, manifest: PackageManifest) throws {
        TerminalLog.out("Publishing Neat", level: .change)
        let published = try PackagePublisher(projectPath: root.path).publish(.patch)
        TerminalLog.out("Published \(published.name) \(published.version).", level: .success)
        switch published.git {
        case .published(let commit, let tag, let pushed):
            TerminalLog.subtleOut("Git: \(commit), \(tag)\(pushed ? ", pushed" : ", not pushed")")
        case .skipped(let reason):
            TerminalLog.subtleOut("Git: skipped (\(reason))")
        }

        let manifestRemote = manifest.remoteURLs.first
        let remoteURL: String
        if let manifestRemote {
            remoteURL = manifestRemote
        } else {
            remoteURL = try runProcessCapturing(
                executable: "/usr/bin/env",
                arguments: ["git", "-C", root.path, "remote", "get-url", "origin"]
            )
        }
        let reference = try gitHubReference(from: remoteURL)
        try downloadMachinePackage(reference: reference, remoteURL: remoteURL)
    }

    private func downloadMachinePackage(reference: String, remoteURL: String) throws {
        let parts = reference.split(separator: "/").map(String.init)
        guard parts.count == 2 else {
            throw ValidationError("Invalid package reference '\(reference)'.")
        }

        let packageRoot =
            FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".neat", isDirectory: true)
            .appendingPathComponent("Packages", isDirectory: true)
            .appendingPathComponent(parts[0], isDirectory: true)
            .appendingPathComponent(parts[1], isDirectory: true)
            .standardizedFileURL

        try FileManager.default.createDirectory(
            at: packageRoot.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let gitDir = packageRoot.appendingPathComponent(".git", isDirectory: true)
        if FileManager.default.fileExists(atPath: gitDir.path) {
            try Self.runProcessQuiet(
                executable: "/usr/bin/env",
                arguments: ["git", "-C", packageRoot.path, "pull", "--ff-only", "origin", "main"]
            )
            TerminalLog.out("Downloaded \(reference) from origin.", level: .success)
        } else {
            try Self.runProcessQuiet(
                executable: "/usr/bin/env",
                arguments: ["git", "clone", remoteURL, packageRoot.path]
            )
            TerminalLog.out("Downloaded \(reference) from origin.", level: .success)
        }
    }

    func gitHubReference(from remoteURL: String) throws -> String {
        let trimmed = remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let patterns = [
            #"github\.com[:/]([^/\s]+)/([^/\s]+?)(?:\.git)?$"#,
        ]

        for pattern in patterns {
            let regex = try NSRegularExpression(pattern: pattern)
            let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
            guard let match = regex.firstMatch(in: trimmed, range: range),
                let ownerRange = Range(match.range(at: 1), in: trimmed),
                let repoRange = Range(match.range(at: 2), in: trimmed)
            else {
                continue
            }

            return "\(trimmed[ownerRange])/\(trimmed[repoRange])"
        }

        throw ValidationError("Could not infer GitHub owner/repo from origin '\(trimmed)'.")
    }

    private static func runProcess(
        executable: String,
        arguments: [String],
        environment: [String: String] = [:]
    ) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in
            new
        }
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw ValidationError(
                "Command failed (\(process.terminationStatus)): \(executable) \(arguments.joined(separator: " "))"
            )
        }
    }

    private func runProcessCapturing(executable: String, arguments: [String]) throws -> String {
        try Self.runProcessCapturing(executable: executable, arguments: arguments)
    }

    private static func runProcessCapturing(executable: String, arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error
        try process.run()
        process.waitUntilExit()

        let outputText = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let errorText = String(data: error.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard process.terminationStatus == 0 else {
            let message = errorText.isEmpty ? outputText : errorText
            throw ValidationError(
                message.isEmpty
                    ? "Command failed (\(process.terminationStatus)): \(executable) \(arguments.joined(separator: " "))"
                    : message
            )
        }

        return outputText
    }

    private static func runProcessQuiet(executable: String, arguments: [String]) throws {
        _ = try runProcessCapturing(executable: executable, arguments: arguments)
    }
}
