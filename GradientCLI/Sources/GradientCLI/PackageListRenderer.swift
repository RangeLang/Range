import ArgumentParser
import Foundation

enum PackageListScope: String, ExpressibleByArgument {
    case machine
    case project
}

enum PackageListRenderer {
    static func render(scope: PackageListScope, projectPath: String, terms: [String]) throws {
        let root: URL
        let title: String
        let countLabel: String
        let emptyMessage: String
        let noMatchPrefix: String

        switch scope {
        case .machine:
            root = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
            title = TerminalLog.style("Machine", level: .change, bold: true)
                + " "
                + TerminalLog.subtleStdout(ProcessInfo.processInfo.hostName)
            countLabel = "downloaded"
            emptyMessage = "No machine packages downloaded."
            noMatchPrefix = "No machine packages match"
        case .project:
            root = URL(fileURLWithPath: projectPath, isDirectory: true).standardizedFileURL
            title = TerminalLog.style("Project", level: .change, bold: true)
                + " "
                + TerminalLog.subtleStdout(root.path)
            countLabel = "installed"
            emptyMessage = "No project packages installed."
            noMatchPrefix = "No project packages match"
        }

        let manager = PackageSubscriptionManager(projectPath: projectPath)
        let packages = try manager.installedPackages(in: root)
        let query = terms.joined(separator: " ")
        let matches = manager.matchingPackages(packages, search: query)

        print(title)
        print(TerminalLog.captionStdout("\(packages.count) \(countLabel)"))

        if matches.isEmpty {
            if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                print(TerminalLog.subtleStdout(emptyMessage))
            } else {
                print(TerminalLog.subtleStdout("\(noMatchPrefix) '\(query)'."))
            }
            return
        }

        for package in matches {
            print("  " + packageRow(
                reference: package.reference,
                version: package.version ?? "unknown"
            ))
        }
    }

    private static func packageRow(reference: String, version: String) -> String {
        let package = "\(reference)@latest"
        let width = max(32, package.count + 4)
        let padding = String(repeating: " ", count: max(1, width - package.count))
        return TerminalLog.style(package, level: .change, bold: true)
            + padding
            + TerminalLog.subtleStdout(version)
    }
}
