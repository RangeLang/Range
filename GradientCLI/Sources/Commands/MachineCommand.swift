import ArgumentParser
import Foundation

extension GradientCLI {
    struct Machine: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Interact with machine-level Gradient state.",
            subcommands: [
                List.self,
                Link.self,
            ]
        )

        mutating func run() throws {
            let root = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
            let packageStore = root
                .appendingPathComponent(".gradient", isDirectory: true)
                .appendingPathComponent("Packages", isDirectory: true)

            TerminalSection(
                header: TerminalLog.style("Machine", level: .change, bold: true),
                content: TerminalContent([
                    machineInfoRow(label: "OS", value: MachineInfo.operatingSystem, color: .custom(81)),
                    machineInfoRow(label: "Architecture", value: MachineInfo.architecture, color: .custom(117)),
                    machineInfoRow(label: "Host", value: MachineInfo.hostName, color: .custom(114)),
                    machineInfoRow(label: "Packages", value: packageStore.path, color: .custom(222)),
                ])
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
                    try PackageListRenderer.render(scope: .machine, projectPath: ".", terms: terms)
                } catch {
                    ErrorPresenter.printError(error)
                    throw ExitCode.failure
                }
            }
        }

        struct Link: ParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "Install the macOS Gradient CLI into a Package.gradient project."
            )

            @Argument(help: "Package.gradient project root.")
            var project: String = "."

            @Option(help: "Installed Gradient binary to link.")
            var binary: String = ProjectBinaryLinker.defaultMacOSBinaryPath

            mutating func run() throws {
                var command = GradientCLI.Link(project: project, binary: binary)
                try command.run()
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
