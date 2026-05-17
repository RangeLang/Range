import ArgumentParser
import Foundation
import NeatSyntax

struct ProjectUpdater {
    private let path: String
    private let updateCLI: Bool

    init(path: String, updateCLI: Bool) {
        self.path = path
        self.updateCLI = updateCLI
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
                try runProcessQuiet(
                    executable: "/usr/bin/env",
                    arguments: ["git", "-C", modulePath.path, "pull", "--ff-only"]
                )
                TerminalLog.out("Updated module \(module)", level: .success)
            } else {
                try runProcessQuiet(
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

        try runProcess(executable: script.path, arguments: [])
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

        let manifestRemote = manifest.remote?.trimmingCharacters(in: .whitespacesAndNewlines)
        let remoteURL: String
        if let manifestRemote, !manifestRemote.isEmpty {
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
            try runProcessQuiet(
                executable: "/usr/bin/env",
                arguments: ["git", "-C", packageRoot.path, "pull", "--ff-only", "origin", "main"]
            )
            TerminalLog.out("Downloaded \(reference) from origin.", level: .success)
        } else {
            try runProcessQuiet(
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

    private func runProcess(executable: String, arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
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

    private func runProcessQuiet(executable: String, arguments: [String]) throws {
        _ = try runProcessCapturing(executable: executable, arguments: arguments)
    }
}
