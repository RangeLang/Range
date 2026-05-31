import ArgumentParser
import Foundation

extension CLI {
    struct SemanticTokens: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "semantic-tokens",
            abstract: "Dump Range semantic tokens for a source file."
        )

        @Argument(help: "Path to the .range source file.")
        var path: String

        mutating func run() throws {
            let source = try String(contentsOfFile: path, encoding: .utf8)
            let snapshots = RangeLanguageServer.debugSemanticTokenSnapshots(in: source)
            let output = snapshots.map { snapshot in
                SemanticTokenDumpRow(
                    text: snapshot.text,
                    line: snapshot.line,
                    startCharacter: snapshot.startCharacter,
                    length: snapshot.length,
                    type: snapshot.type.rawValue,
                    modifiers: snapshot.modifiers
                        .map(\.rawValue)
                        .sorted()
                )
            }

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(output)
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data("\n".utf8))
        }
    }
}

private struct SemanticTokenDumpRow: Encodable {
    let text: String
    let line: Int
    let startCharacter: Int
    let length: Int
    let type: String
    let modifiers: [String]
}
