import ArgumentParser
import GradientSyntax

@main
struct GradientCLI: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "gradient",
        abstract: "Create and validate Gradient language projects.",
        subcommands: [
            Create.self,
            Link.self,
            Run.self,
            Compile.self,
            Graph.self,
            Artifacts.self,
            Update.self,
            Scripts.self,
            Package.self,
            Machine.self,
            Version.self,
            SemanticTokens.self,
            LSP.self,
        ]
    )
}
