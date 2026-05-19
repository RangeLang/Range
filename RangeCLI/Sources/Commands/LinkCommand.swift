import ArgumentParser

extension GradientCLI {
    struct Link: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Install the macOS Gradient CLI into a Package.gradient project."
        )

        @Argument(help: "Package.gradient project root.")
        var project: String = "."

        @Option(help: "Installed Gradient binary to link.")
        var binary: String = ProjectBinaryLinker.defaultMacOSBinaryPath

        mutating func run() throws {
            do {
                let link = try ProjectBinaryLinker(
                    projectPath: project,
                    binaryPath: binary
                ).run()
                TerminalLog.out("Installed project Gradient at \(link.path)", level: .success)
                TerminalLog.subtleOut("Source: \(binary)")
            } catch {
                ErrorPresenter.printError(error)
                throw ExitCode.failure
            }
        }
    }
}
