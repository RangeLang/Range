import Foundation

public enum ResourceLoader {
    public static func load(
        _ name: String,
        subdirectory: String,
        extension ext: String = "js",
        minify: Bool = true
    ) -> String {
        let (resourceName, resolvedExtension) = splitNameAndExtension(name, fallback: ext)
        let cleanedSubdirectory = subdirectory.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var candidates: [String?] = []
        if !cleanedSubdirectory.isEmpty {
            candidates.append(cleanedSubdirectory)
            if cleanedSubdirectory.hasPrefix("Resources/") {
                let stripped = String(cleanedSubdirectory.dropFirst("Resources/".count))
                if !stripped.isEmpty {
                    candidates.append(stripped)
                }
            } else {
                candidates.append("Resources/\(cleanedSubdirectory)")
            }
        }
        candidates.append(nil)

        for candidate in candidates {
            if let url = Bundle.module.url(forResource: resourceName, withExtension: resolvedExtension, subdirectory: candidate) {
                let source = (try? String(contentsOf: url)) ?? ""
                return minify ? minifyContent(source, extension: resolvedExtension) : source
            }
        }
        return ""
    }

    private static func splitNameAndExtension(_ name: String, fallback: String) -> (String, String) {
        let parts = name.split(separator: ".", maxSplits: 1).map(String.init)
        if parts.count == 2 {
            return (parts[0], parts[1])
        }
        return (name, fallback)
    }

    private static func minifyContent(_ source: String, extension ext: String) -> String {
        switch ext.lowercased() {
        case "css":
            return Minifier.css(source)
        default:
            return Minifier.script(source)
        }
    }
}
