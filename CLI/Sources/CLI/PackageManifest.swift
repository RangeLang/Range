import ArgumentParser
import Foundation
import RangeCompiler

struct PackageManifest {
    let name: String
    let version: String
    let author: String
    let remote: String?
    let remoteURLs: [String]
}

enum PackageManifestLoader {
    static func load(from fileURL: URL) throws -> PackageManifest {
        let source = try String(contentsOf: fileURL, encoding: .utf8)
        var parser = try Parser(
            source: source,
            literalBridgeResolver: try RangeCoreLoader.literalBridgeResolver()
        )

        let sourceFile = try parser.parseSourceFile()
        if let manifest = try blockMacroManifest(from: sourceFile, fileURL: fileURL) {
            return manifest
        }
        throw ValidationError("Project.range must declare @construct(name: \"Name\") { ... }.")
    }

    private static func blockMacroManifest(
        from module: ModuleFileNode,
        fileURL: URL
    ) throws -> PackageManifest? {
        guard let block = module.blockMacros.first,
            let application = block.macros.first,
            application.name == "construct"
        else {
            return nil
        }

        let declarationName = constructName(from: application.argumentClause) ?? "Package"
        let members = blockMemberValues(in: block)
        let name = try titleString(from: members["name"]) ?? declarationName
        let version = try versionString(from: members["version"])
        let author = try quotedString(from: members["author"])
        let remote = try members["remote"].map(quotedString(from:)) ?? nil
        let explicitRemoteURLs = remoteURLs(from: members["remotes"])
            + remoteURLs(from: members["remoteURLs"])
        let remoteURLs = uniqueStrings([remote].compactMap { $0 } + explicitRemoteURLs)
        let resolvedRemoteURLs = remoteURLs.isEmpty
            ? gitRemoteURLs(in: fileURL.deletingLastPathComponent())
            : remoteURLs

        return PackageManifest(
            name: name,
            version: version,
            author: author,
            remote: remote,
            remoteURLs: resolvedRemoteURLs
        )
    }

    private static func blockMemberValues(in block: BlockMacroNode) -> [String: String] {
        var values: [String: String] = [:]
        for statement in block.body {
            switch statement {
            case .macroInvocation(let name, let argumentClause, let body) where name == "let":
                guard let memberName = stringArgument(named: "name", in: argumentClause),
                    let value = valueCurrent(in: body)
                else {
                    continue
                }
                values[memberName] = value
            default:
                continue
            }
        }
        return values
    }

    private static func constructName(from argumentClause: String?) -> String? {
        guard let argumentClause else {
            return nil
        }
        let prefix = "name"
        guard let nameRange = argumentClause.range(of: prefix),
            let quoteStart = argumentClause[nameRange.upperBound...].firstIndex(of: "\""),
            let quoteEnd = argumentClause[argumentClause.index(after: quoteStart)...].firstIndex(of: "\"")
        else {
            return nil
        }
        return String(argumentClause[argumentClause.index(after: quoteStart)..<quoteEnd])
    }

    private static func stringArgument(
        named name: String,
        in arguments: [CallArgument]
    ) -> String? {
        arguments.first { $0.label == name }.flatMap { argument in
            guard case .string(let value) = argument.value else {
                return nil
            }
            return value
        }
    }

    private static func stringArgument(named name: String, in argumentClause: String?) -> String? {
        guard let argumentClause else {
            return nil
        }
        let pattern = #"\b\#(NSRegularExpression.escapedPattern(for: name))\s*:\s*"((?:\\"|[^"])*)""#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }
        let range = NSRange(argumentClause.startIndex..<argumentClause.endIndex, in: argumentClause)
        guard let match = regex.firstMatch(in: argumentClause, range: range),
            match.numberOfRanges > 1,
            let valueRange = Range(match.range(at: 1), in: argumentClause)
        else {
            return nil
        }
        return String(argumentClause[valueRange])
    }

    private static func valueCurrent(in statements: [Statement]) -> String? {
        for statement in statements {
            switch statement {
            case .macroApplication(let name, let arguments) where name == "value":
                if let current = stringArgument(named: "current", in: arguments) {
                    return current
                }
            case .macroInvocation(let name, let argumentClause, _) where name == "value":
                if let current = stringArgument(named: "current", in: argumentClause) {
                    return current
                }
            default:
                continue
            }
        }
        return nil
    }

    private static func titleString(from value: String?) throws -> String? {
        guard let value else {
            return nil
        }
        guard value.hasPrefix("Title("), value.hasSuffix(")") else {
            throw ValidationError("Project.range requires @let name value Title(\"...\").")
        }
        return try quotedString(from: String(value.dropFirst("Title(".count).dropLast()))
    }

    private static func versionString(from value: String?) throws -> String {
        guard let value else {
            throw ValidationError("Project.range requires @let version value Version(0.1.0).")
        }
        guard value.hasPrefix("Version("), value.hasSuffix(")") else {
            throw ValidationError("Project.range requires @let version value Version(0.1.0).")
        }
        let raw = String(value.dropFirst("Version(".count).dropLast())
        _ = try SemanticVersion.parse(raw)
        return raw
    }

    private static func quotedString(from value: String?) throws -> String {
        guard let value else {
            throw ValidationError("Project.range requires quoted string value.")
        }
        if value.hasPrefix("String("), value.hasSuffix(")") {
            return try quotedString(from: String(value.dropFirst("String(".count).dropLast()))
        }
        if value.hasPrefix("\\\""), value.hasSuffix("\\\""), value.count >= 4 {
            return String(value.dropFirst(2).dropLast(2))
        }
        guard value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 else {
            return value
        }
        return String(value.dropFirst().dropLast())
    }

    private static func remoteURLs(from value: String?) -> [String] {
        guard let value else {
            return []
        }

        let pattern = #"(?:Remote\s*\(\s*url:\s*)?\\?"([^"\\]+)\\?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return regex.matches(in: value, range: range).compactMap { match in
            guard match.numberOfRanges > 1,
                let matchRange = Range(match.range(at: 1), in: value)
            else {
                return nil
            }
            let candidate = String(value[matchRange])
            guard candidate.contains("://") || candidate.contains("@") else {
                return nil
            }
            return candidate
        }
    }

    private static func uniqueStrings(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !seen.contains(trimmed) else {
                continue
            }

            seen.insert(trimmed)
            result.append(trimmed)
        }
        return result
    }

    private static func gitRemoteURLs(in directory: URL) -> [String] {
        guard let git = Platform.defaultExecutableLookupTool else {
            return []
        }

        let process = Process()
        process.executableURL = git
        process.arguments = ["git", "remote", "-v"]
        process.currentDirectoryURL = directory

        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                return []
            }
            let data = output.fileHandleForReading.readDataToEndOfFile()
            let text = String(data: data, encoding: .utf8) ?? ""
            return uniqueStrings(
                text.split(separator: "\n").compactMap { line in
                    let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
                    guard parts.count >= 2 else {
                        return nil
                    }
                    return String(parts[1])
                }
            )
        } catch {
            return []
        }
    }
}
