import ArgumentParser
import Foundation

struct ProjectBinaryLinker {
    static let defaultMacOSBinaryPath = "/usr/local/bin/neat"

    let projectPath: String
    let binaryPath: String

    @discardableResult
    func run() throws -> URL {
        let fileManager = FileManager.default
        let projectRoot = try packageRoot(from: projectPath)
        let binaryURL = URL(fileURLWithPath: binaryPath, isDirectory: false).standardizedFileURL

        guard fileManager.fileExists(atPath: binaryURL.path) else {
            throw ValidationError("Missing installed Neat binary at \(binaryURL.path).")
        }

        let linkDirectory = projectRoot
            .appendingPathComponent(".neat", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
        try fileManager.createDirectory(at: linkDirectory, withIntermediateDirectories: true)

        let linkURL = linkDirectory.appendingPathComponent("neat", isDirectory: false)
        if fileManager.fileExists(atPath: linkURL.path) {
            if try symlink(at: linkURL, pointsTo: binaryURL) {
                return linkURL
            }
            throw ValidationError(
                "Refusing to replace existing file at \(linkURL.path). Remove it and run link again."
            )
        }

        try fileManager.createSymbolicLink(at: linkURL, withDestinationURL: binaryURL)
        return linkURL
    }

    private func packageRoot(from rawPath: String) throws -> URL {
        let url = URL(fileURLWithPath: rawPath, isDirectory: true).standardizedFileURL
        let root: URL
        if url.lastPathComponent == "Package.neat" {
            root = url.deletingLastPathComponent()
        } else {
            root = url
        }

        let packageFile = root.appendingPathComponent("Package.neat", isDirectory: false)
        guard FileManager.default.fileExists(atPath: packageFile.path) else {
            throw ValidationError("Missing Package.neat in \(root.path).")
        }

        return root
    }

    private func symlink(at linkURL: URL, pointsTo binaryURL: URL) throws -> Bool {
        let destination = try FileManager.default.destinationOfSymbolicLink(atPath: linkURL.path)
        let destinationURL: URL
        if destination.hasPrefix("/") {
            destinationURL = URL(fileURLWithPath: destination, isDirectory: false)
        } else {
            destinationURL = linkURL
                .deletingLastPathComponent()
                .appendingPathComponent(destination, isDirectory: false)
        }

        return destinationURL.standardizedFileURL.path == binaryURL.path
    }
}
