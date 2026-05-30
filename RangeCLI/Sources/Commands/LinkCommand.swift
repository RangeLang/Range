import ArgumentParser

extension RangeCLI {
    struct Link: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Install the Range CLI into a Project.range project."
        )

        @Argument(help: "Project.range project root.")
        var project: String = "."

        @Option(help: "Installed Range binary to link.")
        var binary: String = ProjectBinaryLinker.defaultMacOSBinaryPath

        mutating func run() throws {
            do {
                let link = try ProjectBinaryLinker(
                    projectPath: project,
                    binaryPath: binary
                ).run()
                TerminalLog.out("Installed project Range at \(link.path)", level: .success)
                TerminalLog.subtleOut("Source: \(binary)")
            } catch {
                ErrorPresenter.printError(error)
                throw ExitCode.failure
            }
        }
    }
}
