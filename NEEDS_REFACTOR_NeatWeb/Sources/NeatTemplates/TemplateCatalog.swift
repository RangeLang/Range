import Foundation

public enum NeatTemplateCatalog {
    public static func text(at relativePath: String) throws -> String {
        guard let resourceRoot = Bundle.module.resourceURL else {
            throw TemplateCatalogError.unavailableBundle
        }

        let fileName = URL(fileURLWithPath: relativePath).lastPathComponent
        let resolved = resourceRoot.appendingPathComponent(fileName, isDirectory: false)

        guard FileManager.default.fileExists(atPath: resolved.path) else {
            throw TemplateCatalogError.missing(relativePath)
        }

        return try String(contentsOf: resolved, encoding: .utf8)
    }
}

public enum TemplateCatalogError: Error, LocalizedError {
    case unavailableBundle
    case missing(String)

    public var errorDescription: String? {
        switch self {
        case .unavailableBundle:
            return "Neat template bundle is unavailable."
        case .missing(let relativePath):
            return "Missing Neat template file: \(relativePath)"
        }
    }
}
