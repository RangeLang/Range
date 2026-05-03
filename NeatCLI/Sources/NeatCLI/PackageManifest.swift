import ArgumentParser
import Foundation
import NeatSyntax

struct PackageManifest {
    let name: String
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

            return PackageManifest(name: declaration.name, declaration: declaration)
        case .enumeration:
            throw ValidationError("Package.neat must declare construct Name: Package.")
        case .protocolDefinition:
            throw ValidationError("Package.neat must declare construct Name: Package.")
        case .macro, .marker:
            throw ValidationError("Package.neat must declare construct Name: Package.")
        }
    }
}
