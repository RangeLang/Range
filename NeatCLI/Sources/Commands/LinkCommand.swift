import ArgumentParser

extension NeatCLI {
    struct Link: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Link the installed macOS Neat binary into a Package.neat project."
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
                TerminalLog.out("Linked Neat at \(link.path)", level: .success)
                TerminalLog.subtleOut("Target: \(binary)")
            } catch {
                ErrorPresenter.printError(error)
                throw ExitCode.failure
            }
        }
    }
}
