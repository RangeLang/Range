import ArgumentParser
import Foundation

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
        let modules = parseModules(from: source)
        try updateModules(modules, projectRoot: root)

        if updateCLI {
            try updateNeatCLIIfAvailable(from: root)
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

    private func updateModules(_ modules: [String], projectRoot: URL) throws {
        guard !modules.isEmpty else {
            TerminalLog.out("No modules declared in Package.neat.", level: .waiting, dimmed: true)
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
                try runProcess(
                    executable: "/usr/bin/env",
                    arguments: ["git", "-C", modulePath.path, "pull", "--ff-only"]
                )
                TerminalLog.out("Updated module \(module)", level: .success)
            } else {
                try runProcess(
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
}
