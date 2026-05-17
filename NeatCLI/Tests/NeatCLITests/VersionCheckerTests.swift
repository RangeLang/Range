@testable import NeatCLI
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
}
