import ArgumentParser
import Foundation
import NeatSyntax

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
        projectRoot.appendingPathComponent(".neat/Build/swift", isDirectory: true)
    }

    var defaultArtifactsRoot: URL {
        projectRoot.appendingPathComponent(".neat/Artifacts", isDirectory: true)
    }

    func relativeOutputPath(for fileURL: URL) -> String {
        if isSingleFile {
            return fileURL.deletingPathExtension().lastPathComponent
        }

        let rootPath = projectRoot.path.hasSuffix("/") ? projectRoot.path : projectRoot.path + "/"
        let fullPath = fileURL.path
        if fullPath.hasPrefix(rootPath) {
            let relative = String(fullPath.dropFirst(rootPath.count))
            return relative.replacingOccurrences(of: ".neat", with: "")
        }

        return fileURL.deletingPathExtension().lastPathComponent
    }
}

enum ProjectLoader {
    struct Options {
        var includeCore: Bool = true
        var requireManifestForDirectory: Bool = false
        var excludedDirectoryNames: Set<String> = [".git", ".build", ".neat"]
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
        guard fileURL.pathExtension.lowercased() == "neat" else {
            throw ValidationError("Expected a .neat file or project directory.")
        }
        if fileURL.lastPathComponent == "Package.neat" {
            throw ValidationError(
                "Package.neat cannot be used directly. Use a source file or project directory."
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
        let packageFile = rootURL.appendingPathComponent("Package.neat", isDirectory: false)
        let packageManifest: PackageManifest?
        let packageManifestURL: URL?

        if FileManager.default.fileExists(atPath: packageFile.path) {
            packageManifest = try PackageManifestLoader.load(from: packageFile)
            packageManifestURL = packageFile
        } else if options.requireManifestForDirectory {
            throw ValidationError("Missing Package.neat in \(rootURL.path)")
        } else {
            packageManifest = nil
            packageManifestURL = nil
        }

        let projectFiles = try neatFiles(
            in: rootURL,
            packageManifestURL: packageManifestURL,
            options: options
        )
        guard !projectFiles.isEmpty else {
            throw ValidationError("No .neat source files found in \(rootURL.path)")
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

    private static func neatFiles(
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

            guard fileURL.pathExtension.lowercased() == "neat" else {
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
        let coreInputs = includeCore ? try NeatCoreLoader.sourceInputs() : []
        let projectInputs = try files.map { fileURL in
            do {
                return SourceInput(
                    path: fileURL.path,
                    source: try String(contentsOf: fileURL, encoding: .utf8),
                    role: .project
                )
            } catch {
                throw ValidationError("Failed to read \(fileURL.path): \(error)")
            }
        }
        return coreInputs + projectInputs
    }
}
