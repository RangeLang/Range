@testable import CLI
import Testing

@Suite("Version checking")
struct VersionCheckerTests {
    @Test("Latest semantic version ignores non-version tags")
    func latestSemanticVersionIgnoresNonVersionTags() throws {
        let latest = VersionChecker.latestSemanticVersion(in: [
            "refs/tags/v0.1.0",
            "refs/tags/not-a-version",
            "refs/tags/0.2.0",
            "refs/tags/v0.1.9",
        ])

        #expect(latest == SemanticVersion(major: 0, minor: 2, patch: 0))
    }

    @Test("Semantic versions compare by major minor patch")
    func semanticVersionsCompareByMajorMinorPatch() throws {
        #expect(try SemanticVersion.parse("v1.0.0") > SemanticVersion(major: 0, minor: 9, patch: 9))
        #expect(try SemanticVersion.parse("0.2.0") > SemanticVersion(major: 0, minor: 1, patch: 9))
        #expect(try SemanticVersion.parse("0.1.2") > SemanticVersion(major: 0, minor: 1, patch: 1))
    }

    @Test("GitHub release URL is derived from update repository")
    func githubReleaseURLIsDerivedFromUpdateRepository() throws {
        #expect(
            VersionChecker.githubLatestReleaseAPIURL(
                for: "https://github.com/georgetchelidze/Range.git"
            )?.absoluteString
                == "https://api.github.com/repos/georgetchelidze/Range/releases/latest"
        )
        #expect(
            VersionChecker.githubLatestReleaseAPIURL(
                for: "git@github.com:georgetchelidze/Range.git"
            )?.absoluteString
                == "https://api.github.com/repos/georgetchelidze/Range/releases/latest"
        )
    }

    @Test("Latest GitHub release JSON parses semantic tag")
    func latestGitHubReleaseJSONParsesSemanticTag() throws {
        let data = #"{"tag_name":"v0.1.24"}"#.data(using: .utf8)!
        #expect(
            try VersionChecker.latestSemanticVersion(inGitHubLatestReleaseJSON: data)
                == SemanticVersion(major: 0, minor: 1, patch: 24)
        )
    }
}
