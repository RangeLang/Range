import ArgumentParser
import Foundation

struct InstalledPackage: Equatable {
    let reference: String
    let name: String
    let version: String?
    let manifestURL: URL
}

struct PackageSubscriptionManager {
    enum SubscribeAction {
        case subscribed
        case alreadySubscribed
        case browse

        var shouldDisplayDiscovery: Bool {
            switch self {
            case .subscribed, .alreadySubscribed:
                return false
            case .browse:
                return true
            }
        }
    }

    private let projectPath: String

    init(projectPath: String) {
        self.projectPath = projectPath
    }

    func subscribe(search: String) throws -> SubscribeAction {
        let context = try loadProjectContext()

        let packages = try installedPackages(in: context.projectRoot)
        if search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .browse
        }

        let matches = matchingPackages(packages, search: search)
        guard matches.count == 1 else {
            return .browse
        }

        return try subscribe(matches[0], packageFile: context.packageFile)
    }

    func displayDiscovery(search: String, cloudResults: [PackageSearchResult]) {
        let context: ProjectContext
        do {
            context = try loadProjectContext()
        } catch {
            ErrorPresenter.printError(error)
            return
        }

        let installed = (try? installedPackages(in: context.projectRoot)) ?? []
        let installedMatches = matchingPackages(installed, search: search)
        let hasSearch = !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        print(TerminalLog.style("Installed", level: .change, bold: true))
        let countText = hasSearch
            ? "\(installedMatches.count) of \(installed.count) installed"
            : "\(installed.count) installed"
        print(TerminalLog.subtleStdout(countText))

        if installedMatches.isEmpty {
            print(TerminalLog.subtleStdout(hasSearch ? "No installed packages match '\(search)'." : "No installed packages found."))
        } else {
            for package in installedMatches {
                print("  " + TerminalLog.style(package.reference, level: .change, bold: true) + "  " + TerminalLog.subtleStdout(package.name))
            }
        }

        print("")
        print(TerminalLog.style("Cloud Popular", level: .optimization, bold: true))
        if cloudResults.isEmpty {
            print(TerminalLog.subtleStdout("No cloud packages found."))
        } else {
            for result in cloudResults {
                let stars = result.stars == 1 ? "1 star" : "\(result.stars) stars"
                print("  " + TerminalLog.style(result.package, level: .optimization, bold: true) + "  " + TerminalLog.subtleStdout(stars))
                if let description = result.description?.trimmingCharacters(in: .whitespacesAndNewlines),
                    !description.isEmpty
                {
                    print("    " + description)
                }
            }
        }

        if hasSearch && installedMatches.count != 1 {
            print("")
            TerminalLog.subtleOut("Run again with a search that matches one installed package to subscribe.")
        }
    }

    func installedPackages(in projectRoot: URL) throws -> [InstalledPackage] {
        let packagesRoot =
            projectRoot
            .appendingPathComponent(".range", isDirectory: true)
            .appendingPathComponent("Packages", isDirectory: true)
            .standardizedFileURL
            .resolvingSymlinksInPath()

        guard FileManager.default.fileExists(atPath: packagesRoot.path) else {
            return []
        }

        var packages: [InstalledPackage] = []
        let owners = try FileManager.default.contentsOfDirectory(
            at: packagesRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        for ownerURL in owners {
            guard isDirectory(ownerURL) else {
                continue
            }

            let repos = try FileManager.default.contentsOfDirectory(
                at: ownerURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )

            for repoURL in repos where isDirectory(repoURL) {
                let url = repoURL.appendingPathComponent("Package.range", isDirectory: false)
                guard FileManager.default.fileExists(atPath: url.path) else {
                    continue
                }

                guard let manifest = try? PackageManifestLoader.load(from: url) else {
                    continue
                }
                let relative = relativePackageReference(for: url, packagesRoot: packagesRoot)
                packages.append(
                    InstalledPackage(
                        reference: relative,
                        name: manifest.name,
                        version: manifest.version,
                        manifestURL: url
                    )
                )
            }
        }

        return packages.sorted {
            $0.reference.localizedCaseInsensitiveCompare($1.reference) == .orderedAscending
        }
    }

    func matchingPackages(_ packages: [InstalledPackage], search: String) -> [InstalledPackage] {
        let normalizedSearch = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedSearch.isEmpty else {
            return packages
        }

        return packages.filter { package in
            let haystack = "\(package.reference) \(package.name)".lowercased()
            return normalizedSearch
                .split(separator: " ")
                .allSatisfy { haystack.contains($0) }
        }
    }

    private func subscribe(_ package: InstalledPackage, packageFile: URL) throws -> SubscribeAction {
        let source = try String(contentsOf: packageFile, encoding: .utf8)
        let existingModules = parseModules(from: source)

        guard !existingModules.contains(package.reference) else {
            TerminalLog.out("Already subscribed to \(package.reference).", level: .waiting)
            return .alreadySubscribed
        }

        let updatedSource = try addingModule(package.reference, to: source)
        try updatedSource.write(to: packageFile, atomically: true, encoding: .utf8)

        TerminalLog.out("Subscribed to \(package.reference).", level: .success)
        TerminalLog.subtleOut("Package.range: modules += \"\(package.reference)\"")
        return .subscribed
    }

    private func loadProjectContext() throws -> ProjectContext {
        let projectRoot = URL(fileURLWithPath: projectPath, isDirectory: true).standardizedFileURL
        let packageFile = projectRoot.appendingPathComponent("Package.range", isDirectory: false)

        guard FileManager.default.fileExists(atPath: packageFile.path) else {
            throw ValidationError("Missing Package.range in \(projectRoot.path)")
        }

        _ = try PackageManifestLoader.load(from: packageFile)
        return ProjectContext(projectRoot: projectRoot, packageFile: packageFile)
    }

    private func relativePackageReference(for manifestURL: URL, packagesRoot: URL) -> String {
        let packageDirectory = manifestURL.deletingLastPathComponent().standardizedFileURL
        let packagesRoot = packagesRoot.standardizedFileURL
        let rootPath = packagesRoot.path.hasSuffix("/") ? packagesRoot.path : packagesRoot.path + "/"
        let packagePath = packageDirectory.path

        guard packagePath.hasPrefix(rootPath) else {
            return packageDirectory.lastPathComponent
        }

        let relative = String(packagePath.dropFirst(rootPath.count))
        if relative.hasSuffix(".git") {
            return String(relative.dropLast(4))
        }
        return relative
    }

    private func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
    }

    private func parseModules(from source: String) -> Set<String> {
        guard
            let modulesRegex = try? NSRegularExpression(
                pattern: #"\blet\s+modules\s*:\s*\[String\]\s*=\s*\[(.*?)\]"#,
                options: [.dotMatchesLineSeparators]
            ),
            let stringRegex = try? NSRegularExpression(pattern: #""([^"]+)""#)
        else {
            return []
        }

        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        let moduleRanges = modulesRegex.matches(in: source, range: range)
            .compactMap { Range($0.range(at: 1), in: source) }
        let matches = moduleRanges.flatMap { moduleRange in
            stringRegex.matches(in: source, range: NSRange(moduleRange, in: source))
        }
        return Set(
            matches.compactMap { match in
                guard let groupRange = Range(match.range(at: 1), in: source) else {
                    return nil
                }
                return String(source[groupRange])
            }
        )
    }

    private func addingModule(_ package: String, to source: String) throws -> String {
        var lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let closingBraceIndex = lines.lastIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "}" }) else {
            throw ValidationError("Package.range must end with a package body closing brace.")
        }

        if closingBraceIndex > 0 && lines[closingBraceIndex - 1].trimmingCharacters(in: .whitespaces).isEmpty {
            lines.remove(at: closingBraceIndex - 1)
        }

        if let modulesLineIndex = lines.firstIndex(where: {
            $0.trimmingCharacters(in: .whitespaces).hasPrefix("let modules: [String] = [")
        }) {
            let line = lines[modulesLineIndex]
            if let bracketIndex = line.lastIndex(of: "]") {
                let prefix = String(line[..<bracketIndex])
                let separator = prefix.trimmingCharacters(in: .whitespaces).hasSuffix("[") ? "" : ", "
                lines[modulesLineIndex] =
                    prefix + separator + "\"\(package)\"]"
                    + String(line[line.index(after: bracketIndex)...])
                return lines.joined(separator: "\n") + (source.hasSuffix("\n") ? "\n" : "")
            }

            guard
                let closingArrayIndex = lines[modulesLineIndex...].firstIndex(where: {
                    $0.trimmingCharacters(in: .whitespaces) == "]"
                })
            else {
                throw ValidationError("Package.range modules declaration must end with ].")
            }

            lines.insert("        \"\(package)\",", at: closingArrayIndex)
            return lines.joined(separator: "\n") + (source.hasSuffix("\n") ? "\n" : "")
        }

        let insertionIndex = lines.lastIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "}" })!
        lines.insert("    let modules: [String] = [\"\(package)\"]", at: insertionIndex)
        return lines.joined(separator: "\n") + (source.hasSuffix("\n") ? "\n" : "")
    }
}

private struct ProjectContext {
    let projectRoot: URL
    let packageFile: URL
}
