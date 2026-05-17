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
}
