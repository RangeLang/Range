import ArgumentParser
import Foundation
import NeatSyntax

struct PackageManifest {
    let name: String
    let version: String?
    let author: String?
    let remote: String?
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

            return PackageManifest(
                name: declaration.name,
                version: stringValue(named: "version", in: declaration),
                author: stringValue(named: "author", in: declaration),
                remote: stringValue(named: "remote", in: declaration),
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
}
