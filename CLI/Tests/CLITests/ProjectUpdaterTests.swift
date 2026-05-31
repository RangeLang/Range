import Foundation
@testable import CLI
import Testing

@Suite("Project updating")
struct ProjectUpdaterTests {
    @Test("GitHub origin URLs produce package references")
    func gitHubOriginURLsProducePackageReferences() throws {
        let updater = ProjectUpdater(path: ".", updateCLI: false)

        #expect(try updater.gitHubReference(from: "https://github.com/georgetchelidze/Range") == "georgetchelidze/Range")
        #expect(try updater.gitHubReference(from: "https://github.com/georgetchelidze/Range.git") == "georgetchelidze/Range")
        #expect(try updater.gitHubReference(from: "git@github.com:georgetchelidze/Range.git") == "georgetchelidze/Range")
    }

    @Test("Release update archive name matches current platform")
    func releaseUpdateArchiveNameMatchesCurrentPlatform() throws {
        #if os(macOS) && arch(arm64)
        #expect(try ProjectUpdater.releaseArchiveNameForCurrentPlatform() == "range-macos-arm64.lang.tar.gz")
        #elseif os(macOS) && arch(x86_64)
        #expect(try ProjectUpdater.releaseArchiveNameForCurrentPlatform() == "range-macos-x64.lang.tar.gz")
        #endif
    }

    @Test("Self update prefix is absolute")
    func selfUpdatePrefixIsAbsolute() {
        #expect(ProjectUpdater.selfUpdateInstallPrefix().path.hasPrefix("/"))
    }

    @Test("Release repository URL normalizes owner repo references")
    func releaseRepositoryURLNormalizesOwnerRepoReferences() {
        #expect(
            ProjectUpdater.releaseRepositoryURL(for: "georgetchelidze/Range")
                == "https://github.com/georgetchelidze/Range.git"
        )
        #expect(
            ProjectUpdater.releaseRepositoryURL(for: "https://github.com/georgetchelidze/Range.git")
                == "https://github.com/georgetchelidze/Range.git"
        )
    }
}
