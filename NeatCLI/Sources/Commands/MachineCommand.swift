import ArgumentParser
import Darwin
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

            print(TerminalLog.style("Machine", level: .change, bold: true))
            print(machineInfoRow(label: "OS", value: MachineInfo.operatingSystem, level: .change))
            print(machineInfoRow(label: "Architecture", value: MachineInfo.architecture, level: .optimization))
            print(machineInfoRow(label: "Host", value: MachineInfo.hostName, level: .success))
            print(machineInfoRow(label: "Packages", value: packageStore.path, level: .waiting))
        }

        private func machineInfoRow(label: String, value: String, level: CLIStatusLevel) -> String {
            TerminalLog.style("\(label):", level: level, bold: true)
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
        var systemInfo = utsname()
        uname(&systemInfo)

        return withUnsafePointer(to: &systemInfo.machine) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: 1) { charPointer in
                String(cString: charPointer)
            }
        }
    }
}
