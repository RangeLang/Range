import ArgumentParser
import Foundation
import NeatSyntax

enum TemplateLoader {
    private static let overrideRootEnv = "NEAT_CORE_TEMPLATE_ROOT"

    static func text(at relativePath: String) throws -> String {
        if let overrideRoot = ProcessInfo.processInfo.environment[overrideRootEnv],
            !overrideRoot.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            let overrideURL = URL(fileURLWithPath: overrideRoot, isDirectory: true)
                .appendingPathComponent(relativePath, isDirectory: false)
            if FileManager.default.fileExists(atPath: overrideURL.path) {
                return try String(contentsOf: overrideURL, encoding: .utf8)
            }
        }

        guard let resourceRoot = Bundle.module.resourceURL else {
            throw ValidationError("Template resource bundle is unavailable.")
        }

        if let resolved = resolveInBundle(relativePath: relativePath, resourceRoot: resourceRoot) {
            return try String(contentsOf: resolved, encoding: .utf8)
        }

        throw ValidationError("Missing template file: \(relativePath)")
    }

    private static func resolveInBundle(relativePath: String, resourceRoot: URL) -> URL? {
        let direct = resourceRoot.appendingPathComponent(relativePath, isDirectory: false)
        if FileManager.default.fileExists(atPath: direct.path) {
            return direct
        }

        let fallbackName = URL(fileURLWithPath: relativePath).lastPathComponent
        guard !fallbackName.isEmpty else { return nil }

        guard
            let enumerator = FileManager.default.enumerator(
                at: resourceRoot,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
        else {
            return nil
        }

        while let candidate = enumerator.nextObject() as? URL {
            if candidate.lastPathComponent == fallbackName {
                return candidate
            }
        }

        return nil
    }
}
