import ArgumentParser
import NeatSyntax

@main
struct NeatCLI: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "neat",
        abstract: "Create and validate Neat language projects.",
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
