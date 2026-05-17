import ArgumentParser
import Foundation

enum PackageVersionBump: String, ExpressibleByArgument {
    case major
    case minor
    case patch
}

struct PublishedPackage {
    let name: String
    let version: String
    let author: String?
    let packageFile: URL
}

struct PackagePublisher {
    private let projectPath: String

    init(projectPath: String) {
        self.projectPath = projectPath
    }

    func publish(_ bump: PackageVersionBump) throws -> PublishedPackage {
        let packageFile = URL(fileURLWithPath: projectPath, isDirectory: true)
            .standardizedFileURL
            .appendingPathComponent("Package.neat", isDirectory: false)

        guard FileManager.default.fileExists(atPath: packageFile.path) else {
            throw ValidationError("Missing Package.neat in \(packageFile.deletingLastPathComponent().path)")
        }

        let manifest = try PackageManifestLoader.load(from: packageFile)
        let currentVersion = try SemanticVersion.parse(manifest.version ?? "0.0.0")
        let nextVersion = currentVersion.bumping(bump)
        let source = try String(contentsOf: packageFile, encoding: .utf8)
        let updatedSource = try updatingVersion(
            in: source,
            to: nextVersion.description
        )

        try updatedSource.write(to: packageFile, atomically: true, encoding: .utf8)

        return PublishedPackage(
            name: manifest.name,
            version: nextVersion.description,
            author: manifest.author,
            packageFile: packageFile
        )
    }

    private func updatingVersion(in source: String, to version: String) throws -> String {
        let versionPattern = #"let\s+version\s*:\s*String\s*=\s*"([^"]*)""#
        let regex = try NSRegularExpression(pattern: versionPattern)
        let range = NSRange(source.startIndex..<source.endIndex, in: source)

        if let match = regex.firstMatch(in: source, range: range),
            let matchRange = Range(match.range, in: source)
        {
            return source.replacingCharacters(
                in: matchRange,
                with: #"let version: String = "\#(version)""#
            )
        }

        var lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let openingIndex = lines.firstIndex(where: { $0.contains("{") }) else {
            throw ValidationError("Package.neat must declare a package body.")
        }
        lines.insert(#"    let version: String = "\#(version)""#, at: openingIndex + 1)
        return lines.joined(separator: "\n") + (source.hasSuffix("\n") ? "\n" : "")
    }
}
