import ArgumentParser
import Foundation
import NeatSyntax

struct PackageManifest {
    let name: String
    let declaration: DeclarationNode
}

enum PackageManifestLoader {
    static func load(from fileURL: URL) throws -> PackageManifest {
        let source = try String(contentsOf: fileURL, encoding: .utf8)
        var parser = try Parser(source: source)

        let sourceFile = try parser.parseSourceFile()
        switch sourceFile {
        case .mainBlock:
            throw ValidationError("Package.neat must declare #Name: Package.")
        case .declaration(let declaration):
            guard declaration.attribute == nil else {
                throw ValidationError("Package.neat cannot use declaration attributes.")
            }
            guard declaration.projectionTarget == nil else {
                throw ValidationError(
                    "Package.neat cannot project a package declaration onto another type.")
            }
            guard declaration.conformances == ["Package"] else {
                throw ValidationError("Package.neat must declare exactly #Name: Package.")
            }
            guard declaration.body == nil else {
                throw ValidationError("Package.neat cannot declare a render body.")
            }

            return PackageManifest(name: declaration.name, declaration: declaration)
        }
    }
}
