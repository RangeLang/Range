import ArgumentParser
import Foundation

struct VersionUpdateStatus {
    let current: SemanticVersion
    let latest: SemanticVersion?
    let checkedRepository: String

    var updateAvailable: Bool {
        guard let latest else {
            return false
        }
        return current < latest
    }
}

struct VersionChecker {
    private let repository: String

    init(repository: String = RangeVersion.updateRepository) {
        self.repository = repository
    }

    func check(current: SemanticVersion = RangeVersion.current) throws -> VersionUpdateStatus {
        if let releaseAPIURL = Self.githubLatestReleaseAPIURL(for: repository) {
            let latest = try latestGitHubReleaseVersion(from: releaseAPIURL)
            return VersionUpdateStatus(
                current: current,
                latest: latest,
                checkedRepository: repository
            )
        }

        let tags = try remoteTags()
        let latest = Self.latestSemanticVersion(in: tags)
        return VersionUpdateStatus(
            current: current,
            latest: latest,
            checkedRepository: repository
        )
    }

    static func latestSemanticVersion(in tags: [String]) -> SemanticVersion? {
        tags.compactMap { tag in
            try? SemanticVersion.parse(tag)
        }
        .max()
    }

    static func githubLatestReleaseAPIURL(for repository: String) -> URL? {
        var trimmed = repository
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasSuffix(".git") {
            trimmed.removeLast(".git".count)
        }

        let reference: String
        if trimmed.hasPrefix("git@github.com:") {
            reference = String(trimmed.dropFirst("git@github.com:".count))
        } else if let url = URL(string: trimmed),
            url.host == "github.com"
        {
            reference = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        } else {
            return nil
        }

        let parts = reference.split(separator: "/").map(String.init)
        guard parts.count == 2 else {
            return nil
        }

        return URL(string: "https://api.github.com/repos/\(parts[0])/\(parts[1])/releases/latest")
    }

    static func latestSemanticVersion(inGitHubLatestReleaseJSON data: Data) throws -> SemanticVersion? {
        guard
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let tagName = object["tag_name"] as? String
        else {
            return nil
        }

        return try? SemanticVersion.parse(tagName)
    }

    private func latestGitHubReleaseVersion(from apiURL: URL) throws -> SemanticVersion? {
        let data = try Self.download(apiURL)
        return try Self.latestSemanticVersion(inGitHubLatestReleaseJSON: data)
    }

    private static func download(_ url: URL) throws -> Data {
        guard let lookupTool = Platform.defaultExecutableLookupTool else {
            throw ValidationError("Update checks require curl on PATH and are not available on this platform yet.")
        }

        let process = Process()
        process.executableURL = lookupTool
        process.arguments = ["curl", "-fsSL", url.absoluteString]

        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let message = String(data: error.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw ValidationError(message?.isEmpty == false ? message! : "Could not check for Range releases.")
        }

        return output.fileHandleForReading.readDataToEndOfFile()
    }

    private func remoteTags() throws -> [String] {
        guard let lookupTool = Platform.defaultExecutableLookupTool else {
            throw ValidationError("Update checks require git on PATH and are not available on this platform yet.")
        }

        let process = Process()
        process.executableURL = lookupTool
        process.arguments = ["git", "ls-remote", "--tags", "--refs", repository]

        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let message = String(data: error.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw ValidationError(message?.isEmpty == false ? message! : "Could not check for Range updates.")
        }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8) ?? ""
        return text
            .split(separator: "\n")
            .compactMap { line in
                line.split(separator: "\t").last.map(String.init)
            }
    }
}
