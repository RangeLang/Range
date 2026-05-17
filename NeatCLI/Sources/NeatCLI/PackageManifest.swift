import ArgumentParser
import Foundation
import NeatSyntax

struct PackageManifest {
    let name: String
    let version: String
    let author: String
    let remote: String?
    let remoteURLs: [String]
    let declaration: ConstructDeclaration
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
        case .module:
            throw ValidationError("Package.neat must declare construct Name: Package.")
        case .namespace:
            throw ValidationError("Package.neat must declare construct Name: Package.")
        case .construct(let declaration):
            guard declaration.attribute == nil else {
                throw ValidationError("Package.neat cannot use declaration attributes.")
            }
            guard declaration.conformances == [.named("Package")] else {
                throw ValidationError(
                    "Package.neat must declare exactly construct Name: Package.")
            }

            let version = try requiredStringValue(named: "version", in: declaration)
            let author = try requiredStringValue(named: "author", in: declaration)
            _ = try requireValue(named: "remotes", typeName: "[Remote]", in: declaration)

            let remote = stringValue(named: "remote", in: declaration)
            return PackageManifest(
                name: declaration.name,
                version: version,
                author: author,
                remote: remote,
                remoteURLs: remoteURLs(remote: remote, in: declaration),
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
        in declaration: ConstructDeclaration
    ) throws -> String {
        let value = try requireValue(named: name, typeName: "String", in: declaration)
        guard case .string(let string)? = value.value else {
            throw ValidationError("Package.neat requires let \(name): String = \"...\".")
        }
        return string
    }

    private static func requireValue(
        named name: String,
        typeName: String,
        in declaration: ConstructDeclaration
    ) throws -> ValueDeclaration {
        guard let value = declaration.values.first(where: { $0.name == name }) else {
            throw ValidationError("Package.neat requires let \(name): \(typeName).")
        }
        guard value.typeName == typeName else {
            throw ValidationError(
                "Package.neat requires let \(name): \(typeName), got \(value.typeName)."
            )
        }
        return value
    }

    private static func stringValue(named name: String, in declaration: ConstructDeclaration)
        -> String?
    {
        declaration.values.first { $0.name == name }.flatMap { value in
            guard case .string(let string)? = value.value else {
                return nil
            }
            return string
        }
    }

    private static func remoteURLs(remote: String?, in declaration: ConstructDeclaration) -> [String] {
        uniqueStrings(
            [remote].compactMap { $0 }
                + stringArrayValue(named: "remotes", in: declaration)
                + stringArrayValue(named: "remoteURLs", in: declaration)
        )
    }

    private static func stringArrayValue(named name: String, in declaration: ConstructDeclaration)
        -> [String]
    {
        guard
            let value = declaration.values.first(where: { $0.name == name }),
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
}
