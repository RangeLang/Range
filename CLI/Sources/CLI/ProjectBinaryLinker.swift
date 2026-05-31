import ArgumentParser
import Foundation

struct ProjectBinaryLinker {
    static var defaultMacOSBinaryPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".range/current/\(RangeVersion.current)/range", isDirectory: false)
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
            .appendingPathComponent("releases", isDirectory: true)
            .appendingPathComponent(selectedVersion, isDirectory: true)
        let currentDirectoryURL = projectRoot
            .appendingPathComponent(".range", isDirectory: true)
            .appendingPathComponent("current", isDirectory: true)
        let currentVersionURL = currentDirectoryURL
            .appendingPathComponent(selectedVersion, isDirectory: true)
        let linksDirectory = projectRoot
            .appendingPathComponent(".range", isDirectory: true)
            .appendingPathComponent("Links", isDirectory: true)
        try fileManager.createDirectory(at: selectedInstallDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: linksDirectory, withIntermediateDirectories: true)

        let versionedBinaryURL = selectedInstallDirectory.appendingPathComponent(
            "range",
            isDirectory: false
        )
        let packageBinaryURL = currentVersionURL.appendingPathComponent("range", isDirectory: false)
        let receiptURL = linksDirectory.appendingPathComponent(
            "range.package-link.json",
            isDirectory: false
        )

        let currentIsSymlink = (try? fileManager.destinationOfSymbolicLink(atPath: currentDirectoryURL.path)) != nil
        var currentIsDirectory: ObjCBool = false
        let currentExists = fileManager.fileExists(
            atPath: currentDirectoryURL.path,
            isDirectory: &currentIsDirectory
        )
        if currentExists
            && !currentIsDirectory.boolValue
            && !isReplaceablePackageShim(at: currentDirectoryURL, receiptURL: receiptURL)
        {
            throw ValidationError(
                "Refusing to replace existing file at \(currentDirectoryURL.path). Remove it and run link again."
            )
        }

        if fileManager.fileExists(atPath: versionedBinaryURL.path) {
            try fileManager.removeItem(at: versionedBinaryURL)
        }
        try fileManager.copyItem(at: binaryURL, to: versionedBinaryURL)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: versionedBinaryURL.path)

        if currentIsSymlink {
            try fileManager.removeItem(at: currentDirectoryURL)
        }
        try fileManager.createDirectory(at: currentDirectoryURL, withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: currentVersionURL.path)
            || (try? fileManager.destinationOfSymbolicLink(atPath: currentVersionURL.path)) != nil
        {
            try fileManager.removeItem(at: currentVersionURL)
        }
        try fileManager.createSymbolicLink(
            at: currentVersionURL,
            withDestinationURL: selectedInstallDirectory
        )

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
        if url.lastPathComponent == "Project.range" {
            root = url.deletingLastPathComponent()
        } else {
            root = url
        }

        let packageFile = root.appendingPathComponent("Project.range", isDirectory: false)
        guard FileManager.default.fileExists(atPath: packageFile.path) else {
            throw ValidationError("Missing Project.range in \(root.path).")
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
