import ArgumentParser
import Foundation
import RangeSyntax

struct LoadedProject {
    enum Kind {
        case singleFile
        case directory
    }

    let kind: Kind
    let inputURL: URL
    let projectRoot: URL
    let packageManifestURL: URL?
    let packageManifest: PackageManifest?
    let packageName: String
    let projectFiles: [URL]
    let sourceInputs: [SourceInput]

    var isSingleFile: Bool {
        kind == .singleFile
    }

    var defaultBuildRoot: URL {
        projectRoot.appendingPathComponent(".range/Build/swift", isDirectory: true)
    }

    var defaultArtifactsRoot: URL {
        projectRoot.appendingPathComponent(".range/Artifacts", isDirectory: true)
    }

    func relativeOutputPath(for fileURL: URL) -> String {
        if isSingleFile {
            return fileURL.deletingPathExtension().lastPathComponent
        }

        let rootPath = projectRoot.path.hasSuffix("/") ? projectRoot.path : projectRoot.path + "/"
        let fullPath = fileURL.path
        if fullPath.hasPrefix(rootPath) {
            let relative = String(fullPath.dropFirst(rootPath.count))
            return relative.replacingOccurrences(of: ".range", with: "")
        }

        return fileURL.deletingPathExtension().lastPathComponent
    }
}

enum ProjectLoader {
    struct Options {
        var includeCore: Bool = true
        var requireManifestForDirectory: Bool = false
        var excludedDirectoryNames: Set<String> = [".git", ".build", ".range", "Examples"]
        var excludedFileNames: Set<String> = []
        var excludedPathFragments: [String] = []
    }

    static func load(
        at path: String,
        options: Options = Options()
    ) throws -> LoadedProject {
        let inputURL = URL(fileURLWithPath: path).standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: inputURL.path, isDirectory: &isDirectory)
        else {
            throw ValidationError("Missing input at \(inputURL.path)")
        }

        if !isDirectory.boolValue {
            return try loadSingleFile(at: inputURL, options: options)
        }

        return try loadDirectory(at: inputURL, options: options)
    }

    private static func loadSingleFile(
        at fileURL: URL,
        options: Options
    ) throws -> LoadedProject {
        guard fileURL.pathExtension.lowercased() == "range" else {
            throw ValidationError("Expected a .range file or project directory.")
        }
        if fileURL.lastPathComponent == "Project.range" {
            throw ValidationError(
                "Project.range cannot be used directly. Use a source file or project directory."
            )
        }

        let sourceInputs = try sourceInputs(for: [fileURL], includeCore: options.includeCore)
        return LoadedProject(
            kind: .singleFile,
            inputURL: fileURL,
            projectRoot: fileURL.deletingLastPathComponent(),
            packageManifestURL: nil,
            packageManifest: nil,
            packageName: fileURL.deletingPathExtension().lastPathComponent,
            projectFiles: [fileURL],
            sourceInputs: sourceInputs
        )
    }

    private static func loadDirectory(
        at rootURL: URL,
        options: Options
    ) throws -> LoadedProject {
        let packageFile = rootURL.appendingPathComponent("Project.range", isDirectory: false)
        let packageManifest: PackageManifest?
        let packageManifestURL: URL?

        if FileManager.default.fileExists(atPath: packageFile.path) {
            packageManifest = try PackageManifestLoader.load(from: packageFile)
            packageManifestURL = packageFile
        } else if options.requireManifestForDirectory {
            throw ValidationError("Missing Project.range in \(rootURL.path)")
        } else {
            packageManifest = nil
            packageManifestURL = nil
        }

        let projectFiles = try rangeFiles(
            in: rootURL,
            packageManifestURL: packageManifestURL,
            options: options
        )
        guard !projectFiles.isEmpty else {
            throw ValidationError("No .range source files found in \(rootURL.path)")
        }

        let sourceInputs = try sourceInputs(for: projectFiles, includeCore: options.includeCore)
        return LoadedProject(
            kind: .directory,
            inputURL: rootURL,
            projectRoot: rootURL,
            packageManifestURL: packageManifestURL,
            packageManifest: packageManifest,
            packageName: packageManifest?.name ?? rootURL.lastPathComponent,
            projectFiles: projectFiles,
            sourceInputs: sourceInputs
        )
    }

    private static func rangeFiles(
        in root: URL,
        packageManifestURL: URL?,
        options: Options
    ) throws -> [URL] {
        guard
            let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        else {
            throw ValidationError("Could not inspect project files in \(root.path)")
        }

        var files: [URL] = []
        while let fileURL = enumerator.nextObject() as? URL {
            let path = fileURL.path
            let isDirectory =
                (try? fileURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false

            if options.excludedPathFragments.contains(where: { path.contains($0) }) {
                if isDirectory {
                    enumerator.skipDescendants()
                }
                continue
            }

            if isDirectory {
                if options.excludedDirectoryNames.contains(fileURL.lastPathComponent) {
                    enumerator.skipDescendants()
                }
                continue
            }

            guard fileURL.pathExtension.lowercased() == "range" else {
                continue
            }
            if let packageManifestURL,
                fileURL.standardizedFileURL == packageManifestURL.standardizedFileURL
            {
                continue
            }
            if options.excludedFileNames.contains(fileURL.lastPathComponent) {
                continue
            }
            files.append(fileURL)
        }

        return files.sorted { $0.path < $1.path }
    }

    private static func sourceInputs(
        for files: [URL],
        includeCore: Bool
    ) throws -> [SourceInput] {
        let coreInputs = includeCore ? try RangeCoreLoader.sourceInputs() : []
        let projectInputs = try files.compactMap { fileURL -> SourceInput? in
            let isCoreFile = try RangeCoreLoader.isCoreFile(fileURL)
            if includeCore, isCoreFile {
                return nil
            }
            do {
                return SourceInput(
                    path: fileURL.path,
                    source: try String(contentsOf: fileURL, encoding: .utf8),
                    role: isCoreFile ? .core : .project
                )
            } catch {
                throw ValidationError("Failed to read \(fileURL.path): \(ErrorDescription.message(for: error))")
            }
        }
        return coreInputs + projectInputs
    }
}
