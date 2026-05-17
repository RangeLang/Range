import ArgumentParser
import Foundation

extension NeatCLI {
    struct Machine: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Interact with machine-level Neat state.",
            subcommands: [
                List.self,
            ]
        )

        mutating func run() throws {
            let root = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
            let packageStore = root
                .appendingPathComponent(".neat", isDirectory: true)
                .appendingPathComponent("Packages", isDirectory: true)

            TerminalSection(
                header: TerminalLog.style("Machine", level: .change, bold: true),
                content: TerminalContent([
                    machineInfoRow(label: "OS", value: MachineInfo.operatingSystem, color: .custom(81)),
                    machineInfoRow(label: "Architecture", value: MachineInfo.architecture, color: .custom(117)),
                    machineInfoRow(label: "Host", value: MachineInfo.hostName, color: .custom(114)),
                    machineInfoRow(label: "Packages", value: packageStore.path, color: .custom(222)),
                ]).indented()
            ).print()
        }

        private func machineInfoRow(label: String, value: String, color: TerminalAccentColor) -> String {
            TerminalLog.accentStdout("\(label):", color: color, bold: true)
                + " "
                + TerminalLog.subtleStdout(value)
        }

        struct List: ParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "List packages downloaded on this machine."
            )

            @Argument(
                parsing: .remaining,
                help: "Optional search terms."
            )
            var terms: [String] = []

            mutating func run() throws {
                do {
                    let root = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
                    let manager = PackageSubscriptionManager(projectPath: root.path)
                    let packages = try manager.installedPackages(in: root)
                    let query = terms.joined(separator: " ")
                    let matches = manager.matchingPackages(packages, search: query)

                    print(TerminalLog.style("Machine", level: .change, bold: true)
                        + " "
                        + TerminalLog.subtleStdout(MachineInfo.hostName))
                    print(TerminalLog.captionStdout("\(packages.count) downloaded"))

                    if matches.isEmpty {
                        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            print(TerminalLog.subtleStdout("No machine packages downloaded."))
                        } else {
                            print(TerminalLog.subtleStdout("No machine packages match '\(query)'."))
                        }
                        return
                    }

                    for package in matches {
                        print("  " + packageRow(
                            reference: package.reference,
                            version: package.version ?? "unknown"
                        ))
                    }
                } catch {
                    ErrorPresenter.printError(error)
                    throw ExitCode.failure
                }
            }

            private func packageRow(reference: String, version: String) -> String {
                let package = "\(reference)@latest"
                let width = max(32, package.count + 4)
                let padding = String(repeating: " ", count: max(1, width - package.count))
                return TerminalLog.style(package, level: .change, bold: true)
                    + padding
                    + TerminalLog.subtleStdout(version)
            }
        }
    }
}

private enum MachineInfo {
    static var operatingSystem: String {
        #if os(macOS)
        return "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)"
        #else
        return ProcessInfo.processInfo.operatingSystemVersionString
        #endif
    }

    static var hostName: String {
        ProcessInfo.processInfo.hostName
    }

    static var architecture: String {
        Platform.machineArchitecture()
    }
}
