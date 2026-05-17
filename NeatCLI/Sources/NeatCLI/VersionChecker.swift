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

    init(repository: String = NeatVersion.updateRepository) {
        self.repository = repository
    }

    func check(current: SemanticVersion = NeatVersion.current) throws -> VersionUpdateStatus {
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

    private func remoteTags() throws -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
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
            throw ValidationError(message?.isEmpty == false ? message! : "Could not check for Neat updates.")
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
