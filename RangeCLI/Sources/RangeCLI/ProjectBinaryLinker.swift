import ArgumentParser
import Foundation

struct ProjectBinaryLinker {
    static var defaultMacOSBinaryPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".range/current/range", isDirectory: false)
            .path
    }

    let projectPath: String
    let binaryPath: String

    @discardableResult
    func run() throws -> URL {
        let fileManager = FileManager.default
        let projectRoot = try packageRoot(from: projectPath)
        let binaryURL = URL(fileURLWithPath: binaryPath, isDirectory: false).standardizedFileURL

        guard fileManager.fileExists(atPath: binaryURL.path) else {
            throw ValidationError("Missing installed Range binary at \(binaryURL.path).")
        }

        let selectedVersion = "\(RangeVersion.current)"
        let selectedInstallDirectory = projectRoot
            .appendingPathComponent(".range", isDirectory: true)
            .appendingPathComponent("versions", isDirectory: true)
            .appendingPathComponent(selectedVersion, isDirectory: true)
        let currentURL = projectRoot
            .appendingPathComponent(".range", isDirectory: true)
            .appendingPathComponent("current", isDirectory: false)
        let linksDirectory = projectRoot
            .appendingPathComponent(".range", isDirectory: true)
            .appendingPathComponent("Links", isDirectory: true)
        try fileManager.createDirectory(at: selectedInstallDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: linksDirectory, withIntermediateDirectories: true)

        let versionedBinaryURL = selectedInstallDirectory.appendingPathComponent(
            "range",
            isDirectory: false
        )
        let packageBinaryURL = currentURL.appendingPathComponent("range", isDirectory: false)
        let receiptURL = linksDirectory.appendingPathComponent(
            "range.package-link.json",
            isDirectory: false
        )

        if fileManager.fileExists(atPath: currentURL.path)
            && !isReplaceablePackageShim(at: currentURL, receiptURL: receiptURL)
        {
            throw ValidationError(
                "Refusing to replace existing file at \(currentURL.path). Remove it and run link again."
            )
        }

        if fileManager.fileExists(atPath: versionedBinaryURL.path) {
            try fileManager.removeItem(at: versionedBinaryURL)
        }
        try fileManager.copyItem(at: binaryURL, to: versionedBinaryURL)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: versionedBinaryURL.path)

        if fileManager.fileExists(atPath: currentURL.path) {
            try fileManager.removeItem(at: currentURL)
        }
        try fileManager.createSymbolicLink(at: currentURL, withDestinationURL: selectedInstallDirectory)

        let receipt = PackageLinkReceipt(
            kind: "range.package-link",
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
        if url.lastPathComponent == "Package.range" {
            root = url.deletingLastPathComponent()
        } else {
            root = url
        }

        let packageFile = root.appendingPathComponent("Package.range", isDirectory: false)
        guard FileManager.default.fileExists(atPath: packageFile.path) else {
            throw ValidationError("Missing Package.range in \(root.path).")
        }

        return root
    }

    private func isReplaceablePackageShim(at currentURL: URL, receiptURL: URL) -> Bool {
        if (try? FileManager.default.destinationOfSymbolicLink(atPath: currentURL.path)) != nil {
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
