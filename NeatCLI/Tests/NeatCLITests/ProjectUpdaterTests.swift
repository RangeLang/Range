import Foundation
@testable import NeatCLI
import Testing

@Suite("Project updating")
struct ProjectUpdaterTests {
    @Test("GitHub origin URLs produce package references")
    func gitHubOriginURLsProducePackageReferences() throws {
        let updater = ProjectUpdater(path: ".", updateCLI: false)

        #expect(try updater.gitHubReference(from: "https://github.com/georgetchelidze/Neat") == "georgetchelidze/Neat")
        #expect(try updater.gitHubReference(from: "https://github.com/georgetchelidze/Neat.git") == "georgetchelidze/Neat")
        #expect(try updater.gitHubReference(from: "git@github.com:georgetchelidze/Neat.git") == "georgetchelidze/Neat")
    }

    @Test("Release update archive name matches current platform")
    func releaseUpdateArchiveNameMatchesCurrentPlatform() throws {
        #if os(macOS) && arch(arm64)
        #expect(try ProjectUpdater.releaseArchiveNameForCurrentPlatform() == "neat-macos-arm64.lang.tar.gz")
        #elseif os(macOS) && arch(x86_64)
        #expect(try ProjectUpdater.releaseArchiveNameForCurrentPlatform() == "neat-macos-x64.lang.tar.gz")
        #endif
    }
}
