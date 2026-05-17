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
    let git: GitPublishResult
}

struct PackagePublisher {
    private let projectPath: String

    init(projectPath: String) {
        self.projectPath = projectPath
    }

    func publish(
        _ bump: PackageVersionBump,
        automateGit: Bool = true,
        push: Bool = true
    ) throws -> PublishedPackage {
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
        let gitResult =
            automateGit
            ? try GitPackagePublisher(packageFile: packageFile).publish(
                packageName: manifest.name,
                version: nextVersion,
                push: push
            )
            : .skipped("disabled")

        return PublishedPackage(
            name: manifest.name,
            version: nextVersion.description,
            author: manifest.author,
            packageFile: packageFile,
            git: gitResult
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

enum GitPublishResult: Equatable {
    case published(commit: String, tag: String, pushed: Bool)
    case skipped(String)
}

private struct GitPackagePublisher {
    private let packageFile: URL

    init(packageFile: URL) {
        self.packageFile = packageFile
    }

    func publish(packageName: String, version: SemanticVersion, push: Bool) throws
        -> GitPublishResult
    {
        let packageDirectory = packageFile.deletingLastPathComponent()
        guard let repositoryRoot = try? git(["rev-parse", "--show-toplevel"], in: packageDirectory)
        else {
            return .skipped("not a git repository")
        }

        let repositoryURL = URL(fileURLWithPath: repositoryRoot, isDirectory: true)
        let relativePackagePath = packageFile.path.replacingPrefix(
            repositoryURL.path.hasSuffix("/") ? repositoryURL.path : repositoryURL.path + "/",
            with: ""
        )
        let tag = "v\(version)"

        try gitVoid(["add", "--", relativePackagePath], in: repositoryURL)
        try gitVoid(["commit", "-m", "Publish \(packageName) \(version)"], in: repositoryURL)
        try gitVoid(["tag", tag], in: repositoryURL)

        let commit = try git(["rev-parse", "--short", "HEAD"], in: repositoryURL)
        let pushed = try pushIfAvailable(push: push, tag: tag, repositoryURL: repositoryURL)
        return .published(commit: commit, tag: tag, pushed: pushed)
    }

    private func pushIfAvailable(push: Bool, tag: String, repositoryURL: URL) throws -> Bool {
        guard push else {
            return false
        }

        guard (try? git(["remote", "get-url", "origin"], in: repositoryURL)) != nil else {
            return false
        }

        let branch = try git(["branch", "--show-current"], in: repositoryURL)
        guard !branch.isEmpty else {
            return false
        }

        try gitVoid(["push", "origin", branch], in: repositoryURL)
        try gitVoid(["push", "origin", tag], in: repositoryURL)
        return true
    }

    private func gitVoid(_ arguments: [String], in directory: URL) throws {
        _ = try git(arguments, in: directory)
    }

    private func git(_ arguments: [String], in directory: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "-C", directory.path] + arguments

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
            throw ValidationError(message.isEmpty ? "Git publish step failed." : message)
        }

        return outputText
    }
}

private extension String {
    func replacingPrefix(_ prefix: String, with replacement: String) -> String {
        hasPrefix(prefix) ? replacement + dropFirst(prefix.count) : self
    }
}
