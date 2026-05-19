import Foundation

public struct SwiftBackendProject {
    public let projectFiles: [URL]
    public let isSingleFile: Bool
    public let buildRoot: URL

    public init(projectFiles: [URL], isSingleFile: Bool, buildRoot: URL) {
        self.projectFiles = projectFiles
        self.isSingleFile = isSingleFile
        self.buildRoot = buildRoot
    }
}
