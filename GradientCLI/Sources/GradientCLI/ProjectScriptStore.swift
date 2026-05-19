import ArgumentParser
import Foundation

struct ProjectScriptStore {
    let projectPath: String

    func scriptsDirectory(create: Bool = true) throws -> URL {
        let directory = try packageRoot(from: projectPath)
            .appendingPathComponent(".gradient", isDirectory: true)
            .appendingPathComponent(".scripts", isDirectory: true)
        if create {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }

    func create(_ name: String, force: Bool = false) throws -> URL {
        let scriptURL = try scriptURL(for: name, createDirectory: true)
        if FileManager.default.fileExists(atPath: scriptURL.path), !force {
            throw ValidationError("Script already exists at \(scriptURL.path). Pass --force to replace it.")
        }

        try starterScript(named: scriptURL.deletingPathExtension().lastPathComponent)
            .write(to: scriptURL, atomically: true, encoding: .utf8)
        return scriptURL
    }

    func save(_ name: String, content: String, force: Bool = false) throws -> URL {
        let scriptURL = try scriptURL(for: name, createDirectory: true)
        if FileManager.default.fileExists(atPath: scriptURL.path), !force {
            throw ValidationError("Script already exists at \(scriptURL.path). Pass --force to replace it.")
        }

        try normalized(content).write(to: scriptURL, atomically: true, encoding: .utf8)
        return scriptURL
    }

    func list() throws -> [URL] {
        let directory = try scriptsDirectory(create: false)
        guard FileManager.default.fileExists(atPath: directory.path) else {
            return []
        }

        return try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        .filter { url in
            ((try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false) == false
        }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func scriptURL(for rawName: String, createDirectory: Bool) throws -> URL {
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ValidationError("Script name cannot be empty.")
        }
        guard !trimmed.contains("/") && trimmed != "." && trimmed != ".." else {
            throw ValidationError("Script name must be a file name, not a path.")
        }

        let fileName = trimmed.hasSuffix(".gradient") ? trimmed : "\(trimmed).gradient"
        return try scriptsDirectory(create: createDirectory)
            .appendingPathComponent(fileName, isDirectory: false)
    }

    private func packageRoot(from rawPath: String) throws -> URL {
        let url = URL(fileURLWithPath: rawPath, isDirectory: true).standardizedFileURL
        let root = url.lastPathComponent == "Package.gradient" ? url.deletingLastPathComponent() : url
        let packageFile = root.appendingPathComponent("Package.gradient", isDirectory: false)
        guard FileManager.default.fileExists(atPath: packageFile.path) else {
            throw ValidationError("Missing Package.gradient in \(root.path).")
        }
        return root
    }

    private func starterScript(named name: String) -> String {
        """
        #main {
          Logger.info("Running \(name)")
        }
        """
    }

    private func normalized(_ content: String) -> String {
        content.hasSuffix("\n") ? content : content + "\n"
    }
}
