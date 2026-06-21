import ArgumentParser
import RangeCompiler

@main
struct CLI: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "range",
        abstract: "Create and validate Range language projects.",
        subcommands: [
            Create.self,
            Link.self,
            Build.self,
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
