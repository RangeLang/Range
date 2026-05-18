import ArgumentParser
import Foundation
import NeatSyntax

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
            literalBridgeResolver: try NeatCoreLoader.literalBridgeResolver()
        )

        let sourceFile = try parser.parseSourceFile()
        switch sourceFile {
        case .mainBlock:
            throw ValidationError("Package.neat must declare construct Name: Package.")
        case .extensions:
            throw ValidationError("Package.neat must declare construct Name: Package.")
        case .module(let module):
            guard let packageSpace = module.packageSpaces.first else {
                throw ValidationError("Package.neat must declare @package { ... } or construct Name: Package.")
            }
            let name = try requiredTitleValue(named: "name", in: packageSpace.values)
            let version = try requiredVersionValue(named: "version", in: packageSpace.values)
            let author = try requiredStringValue(named: "author", in: packageSpace.values)
            let remote = stringValue(named: "remote", in: packageSpace.values)
            let remoteURLs = remoteURLs(remote: remote, in: packageSpace.values)
            let resolvedRemoteURLs = remoteURLs.isEmpty
                ? gitRemoteURLs(in: fileURL.deletingLastPathComponent())
                : remoteURLs
            return PackageManifest(
                name: name,
                version: version,
                author: author,
                remote: remote,
                remoteURLs: resolvedRemoteURLs,
                declaration: nil
            )
        case .namespace:
            throw ValidationError("Package.neat must declare construct Name: Package.")
        case .construct(let declaration):
            guard declaration.attribute == nil else {
                throw ValidationError("Package.neat cannot use declaration attributes.")
            }
            let usesPackageMacro = declaration.macros.contains { $0.name == "package" }
            guard usesPackageMacro || declaration.conformances == [.named("Package")] else {
                throw ValidationError(
                    "Package.neat must declare construct Name: Package or #package construct Name.")
            }

            let name =
                try titleValue(named: "name", in: declaration.values)
                ?? (usesPackageMacro ? declaration.name : nil)
                ?? requiredTitleValue(named: "name", in: declaration.values)
            let version = try requiredVersionValue(named: "version", in: declaration.values)
            let author = try requiredStringValue(named: "author", in: declaration.values)
            if !usesPackageMacro {
                _ = try requireValue(named: "remotes", typeName: "[Remote]", in: declaration.values)
            }

            let remote = stringValue(named: "remote", in: declaration.values)
            let remoteURLs = remoteURLs(remote: remote, in: declaration.values)
            let resolvedRemoteURLs =
                remoteURLs.isEmpty && usesPackageMacro
                ? gitRemoteURLs(in: fileURL.deletingLastPathComponent())
                : remoteURLs
            return PackageManifest(
                name: name,
                version: version,
                author: author,
                remote: remote,
                remoteURLs: resolvedRemoteURLs,
                declaration: declaration
            )
        case .enumeration:
            throw ValidationError("Package.neat must declare construct Name: Package.")
        case .protocolDefinition:
            throw ValidationError("Package.neat must declare construct Name: Package.")
        case .macro, .marker:
            throw ValidationError("Package.neat must declare construct Name: Package.")
        }
    }

    private static func requiredStringValue(
        named name: String,
        in values: [ValueDeclaration]
    ) throws -> String {
        let value = try requireValue(named: name, typeName: "String", in: values)
        guard case .string(let string)? = value.value else {
            throw ValidationError("Package.neat requires let \(name): String = \"...\".")
        }
        return string
    }

    private static func requiredTitleValue(
        named name: String,
        in values: [ValueDeclaration]
    ) throws -> String {
        guard let title = try titleValue(named: name, in: values) else {
            throw ValidationError("Package.neat requires let \(name): Title = Title(\"...\").")
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
                "Package.neat requires let \(name): Title, got \(value.typeName)."
            )
        }
        guard case .call(let callName, let arguments)? = value.value, callName == "Title" else {
            throw ValidationError("Package.neat requires let \(name): Title = Title(\"...\").")
        }
        guard arguments.count == 1, arguments[0].label == nil,
            case .string(let title) = arguments[0].value
        else {
            throw ValidationError("Package.neat Title requires one string value.")
        }
        return title
    }

    private static func requiredVersionValue(
        named name: String,
        in values: [ValueDeclaration]
    ) throws -> String {
        let value = try requireValue(named: name, typeNames: ["Version", "String"], in: values)
        if value.typeName == "String" {
            guard case .string(let string)? = value.value else {
                throw ValidationError("Package.neat requires let \(name): String = \"...\".")
            }
            return string
        }

        guard case .call(let callName, let arguments)? = value.value, callName == "Version" else {
            throw ValidationError("Package.neat requires let \(name): Version = Version(0.1.0).")
        }
        guard arguments.count == 1, arguments[0].label == nil else {
            throw ValidationError("Package.neat Version requires one unlabeled semantic version.")
        }
        guard case .string(let raw) = arguments[0].value else {
            throw ValidationError("Package.neat Version requires a semantic version like Version(0.1.0).")
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
            throw ValidationError("Package.neat requires let \(name): \(typeNames[0]).")
        }
        guard typeNames.contains(value.typeName) else {
            throw ValidationError(
                "Package.neat requires let \(name): \(typeNames.joined(separator: " or ")), got \(value.typeName)."
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

    private static func remoteURL(from expression: NeatSyntax.Expression) -> String? {
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
