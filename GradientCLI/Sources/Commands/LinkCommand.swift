import ArgumentParser

extension NeatCLI {
    struct Link: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Install the macOS Neat CLI into a Package.neat project."
        )

        @Argument(help: "Package.neat project root.")
        var project: String = "."

        @Option(help: "Installed Neat binary to link.")
        var binary: String = ProjectBinaryLinker.defaultMacOSBinaryPath

        mutating func run() throws {
            do {
                let link = try ProjectBinaryLinker(
                    projectPath: project,
                    binaryPath: binary
                ).run()
                TerminalLog.out("Installed project Neat at \(link.path)", level: .success)
                TerminalLog.subtleOut("Source: \(binary)")
            } catch {
                ErrorPresenter.printError(error)
                throw ExitCode.failure
            }
        }
    }
}
