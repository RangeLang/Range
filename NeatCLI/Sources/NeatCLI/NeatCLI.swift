import ArgumentParser
import NeatSyntax

@main
struct NeatCLI: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "neat",
        abstract: "Compile .neat components into JavaScript.",
        subcommands: [Create.self, Run.self, Compile.self, Update.self, LSP.self]
    )
}
