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

        let selectedVersion = "\(NeatVersion.current)"
        let selectedInstallDirectory = projectRoot
            .appendingPathComponent(".neat", isDirectory: true)
            .appendingPathComponent("NeatCLI", isDirectory: true)
            .appendingPathComponent(selectedVersion, isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
        let shimDirectory = projectRoot
            .appendingPathComponent(".neat", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
        let linksDirectory = projectRoot
            .appendingPathComponent(".neat", isDirectory: true)
            .appendingPathComponent("Links", isDirectory: true)
        try fileManager.createDirectory(at: selectedInstallDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: shimDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: linksDirectory, withIntermediateDirectories: true)

        let versionedBinaryURL = selectedInstallDirectory.appendingPathComponent(
            "neat",
            isDirectory: false
        )
        let packageBinaryURL = shimDirectory.appendingPathComponent("neat", isDirectory: false)
        let receiptURL = linksDirectory.appendingPathComponent(
            "neat.package-link.json",
            isDirectory: false
        )

        if fileManager.fileExists(atPath: packageBinaryURL.path)
            && !isReplaceablePackageShim(at: packageBinaryURL, receiptURL: receiptURL)
        {
            throw ValidationError(
                "Refusing to replace existing file at \(packageBinaryURL.path). Remove it and run link again."
            )
        }

        if fileManager.fileExists(atPath: versionedBinaryURL.path) {
            try fileManager.removeItem(at: versionedBinaryURL)
        }
        try fileManager.copyItem(at: binaryURL, to: versionedBinaryURL)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: versionedBinaryURL.path)

        if fileManager.fileExists(atPath: packageBinaryURL.path) {
            try fileManager.removeItem(at: packageBinaryURL)
        }
        try fileManager.createSymbolicLink(at: packageBinaryURL, withDestinationURL: versionedBinaryURL)

        let receipt = PackageLinkReceipt(
            kind: "neat.package-link",
            version: 1,
            selectedVersion: selectedVersion,
            source: binaryURL.path,
            packageBinary: packageBinaryURL.path,
            versionedBinary: versionedBinaryURL.path
        )
        let data = try JSONEncoder.packageLink.encode(receipt)
        try data.write(to: receiptURL, options: .atomic)

        return packageBinaryURL
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

    private func isReplaceablePackageShim(at packageBinaryURL: URL, receiptURL: URL) -> Bool {
        if (try? FileManager.default.destinationOfSymbolicLink(atPath: packageBinaryURL.path)) != nil {
            return true
        }
        return FileManager.default.fileExists(atPath: receiptURL.path)
    }
}

private struct PackageLinkReceipt: Codable {
    let kind: String
    let version: Int
    let selectedVersion: String
    let source: String
    let packageBinary: String
    let versionedBinary: String
}

private extension JSONEncoder {
    static var packageLink: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}
