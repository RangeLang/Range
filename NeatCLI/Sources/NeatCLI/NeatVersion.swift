import ArgumentParser
import Foundation

enum NeatVersion {
    static let current = SemanticVersion(major: 0, minor: 1, patch: 23)
    static let updateRepository = "https://github.com/georgetchelidze/Neat.git"
}

struct SemanticVersion: CustomStringConvertible, Equatable, Comparable {
    let major: Int
    let minor: Int
    let patch: Int

    var description: String {
        "\(major).\(minor).\(patch)"
    }

    static func parse(_ raw: String) throws -> SemanticVersion {
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingPrefix("refs/tags/")
            .trimmingPrefix("v")
        let parts = normalized.split(separator: ".")
        guard parts.count == 3,
            let major = Int(parts[0]),
            let minor = Int(parts[1]),
            let patch = Int(parts[2]),
            major >= 0,
            minor >= 0,
            patch >= 0
        else {
            throw ValidationError("Version must use semantic version format like 0.1.0.")
        }

        return SemanticVersion(major: major, minor: minor, patch: patch)
    }

    static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        if lhs.major != rhs.major {
            return lhs.major < rhs.major
        }
        if lhs.minor != rhs.minor {
            return lhs.minor < rhs.minor
        }
        return lhs.patch < rhs.patch
    }

    func bumping(_ bump: PackageVersionBump) -> SemanticVersion {
        switch bump {
        case .major:
            return SemanticVersion(major: major + 1, minor: 0, patch: 0)
        case .minor:
            return SemanticVersion(major: major, minor: minor + 1, patch: 0)
        case .patch:
            return SemanticVersion(major: major, minor: minor, patch: patch + 1)
        }
    }
}

private extension String {
    func trimmingPrefix(_ prefix: String) -> String {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : self
    }
}
