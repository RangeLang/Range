import ArgumentParser
import Foundation
import RangeCompiler

struct PackageManifest {
    let name: String
    let version: String
    let author: String
    let remote: String?
    let remoteURLs: [String]
    let declaration: ConstructDeclaration?
}

enum PackageManifestLoader {
    static func load(from fileURL: URL) throws -> PackageManifest {
        let source = try String(contentsOf: fileURL, encoding: .utf8)
        var parser = try Parser(
            source: source,
            literalBridgeResolver: try RangeCoreLoader.literalBridgeResolver()
        )

        let sourceFile = try parser.parseSourceFile()
        switch sourceFile {
        case .mainBlock:
            throw ValidationError("Project.range must declare @project construct Name { ... }.")
        case .extensions:
            throw ValidationError("Project.range must declare @project construct Name { ... }.")
        case .module(let module):
            if let manifest = try blockMacroManifest(from: module, fileURL: fileURL) {
                return manifest
            }
            throw ValidationError("Project.range must declare @construct(name: \"Name\") { ... }.")
        case .construct:
            throw ValidationError("Project.range must declare @construct(name: \"Name\") { ... }.")
        case .enumeration:
            throw ValidationError("Project.range must declare @project construct Name { ... }.")
        case .macro:
            throw ValidationError("Project.range must declare @project construct Name { ... }.")
        }
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
        let remoteURLs =
            remote.map { [$0] } ?? gitRemoteURLs(in: fileURL.deletingLastPathComponent())

        return PackageManifest(
            name: name,
            version: version,
            author: author,
            remote: remote,
            remoteURLs: remoteURLs,
            declaration: nil
        )
    }

    private static func blockMemberValues(in block: BlockMacroNode) -> [String: String] {
        var values: [String: String] = [:]
        for statement in block.body {
            guard case .macroApplication(let name, let arguments) = statement,
                name == "let",
                let memberName = stringArgument(named: "name", in: arguments),
                let value = stringArgument(named: "value", in: arguments)
            else {
                continue
            }
            values[memberName] = value
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
        guard value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 else {
            return value
        }
        return String(value.dropFirst().dropLast())
    }

    private static func requiredStringValue(
        named name: String,
        in values: [ValueDeclaration]
    ) throws -> String {
        let value = try requireValue(named: name, typeName: "String", in: values)
        guard case .string(let string)? = value.value else {
            throw ValidationError("Project.range requires let \(name): \"...\".")
        }
        return string
    }

    private static func requiredTitleValue(
        named name: String,
        in values: [ValueDeclaration]
    ) throws -> String {
        guard let title = try titleValue(named: name, in: values) else {
            throw ValidationError("Project.range requires let \(name): Title(\"...\").")
        }
        return title
    }

    private static func titleValue(
        named name: String,
        in values: [ValueDeclaration]
    ) throws -> String? {
        guard let value = values.first(where: { $0.name == name }) else {
            return nil
        }
        guard value.typeName == "Title" else {
            throw ValidationError(
                "Project.range requires let \(name): Title, got \(value.typeName)."
            )
        }
        guard case .call(let callName, let arguments)? = value.value, callName == "Title" else {
            throw ValidationError("Project.range requires let \(name): Title(\"...\").")
        }
        guard arguments.count == 1, arguments[0].label == nil,
            case .string(let title) = arguments[0].value
        else {
            throw ValidationError("Project.range Title requires one string value.")
        }
        return title
    }

    private static func requiredVersionValue(
        named name: String,
        in values: [ValueDeclaration]
    ) throws -> String {
        let value = try requireValue(named: name, typeNames: ["Version"], in: values)
        guard case .call(let callName, let arguments)? = value.value, callName == "Version" else {
            throw ValidationError("Project.range requires let \(name): Version(0.1.0).")
        }
        guard arguments.count == 1, arguments[0].label == nil else {
            throw ValidationError("Project.range Version requires one unlabeled semantic version.")
        }
        guard case .string(let raw) = arguments[0].value else {
            throw ValidationError("Project.range Version requires a semantic version like Version(0.1.0).")
        }
        _ = try SemanticVersion.parse(raw)
        return raw
    }

    private static func requireValue(
        named name: String,
        typeName: String,
        in values: [ValueDeclaration]
    ) throws -> ValueDeclaration {
        try requireValue(named: name, typeNames: [typeName], in: values)
    }

    private static func requireValue(
        named name: String,
        typeNames: [String],
        in values: [ValueDeclaration]
    ) throws -> ValueDeclaration {
        guard let value = values.first(where: { $0.name == name }) else {
            throw ValidationError("Project.range requires let \(name): \(typeNames[0]).")
        }
        guard typeNames.contains(value.typeName) else {
            throw ValidationError(
                "Project.range requires let \(name): \(typeNames.joined(separator: " or ")), got \(value.typeName)."
            )
        }
        return value
    }

    private static func stringValue(named name: String, in values: [ValueDeclaration])
        -> String?
    {
        values.first { $0.name == name }.flatMap { value in
            guard case .string(let string)? = value.value else {
                return nil
            }
            return string
        }
    }

    private static func remoteURLs(remote: String?, in values: [ValueDeclaration]) -> [String] {
        uniqueStrings(
            [remote].compactMap { $0 }
                + stringArrayValue(named: "remotes", in: values)
                + stringArrayValue(named: "remoteURLs", in: values)
        )
    }

    private static func stringArrayValue(named name: String, in values: [ValueDeclaration])
        -> [String]
    {
        guard
            let value = values.first(where: { $0.name == name }),
            case .array(let expressions)? = value.value
        else {
            return []
        }

        return expressions.compactMap { expression in
            remoteURL(from: expression)
        }
    }

    private static func remoteURL(from expression: RangeCompiler.Expression) -> String? {
        switch expression {
        case .string(let string):
            return string
        case .call(let name, let arguments) where name == "Remote":
            return arguments.first { $0.label == "url" }.flatMap { argument in
                guard case .string(let string) = argument.value else {
                    return nil
                }
                return string
            }
        default:
            return nil
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
