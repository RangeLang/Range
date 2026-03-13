import Foundation

/// Helper for turning a set of CSS declarations into a deterministic
/// `style-<hash>` class plus normalized CSS text.
public struct StyleBucket {

    /// Normalizes declarations into a canonical "a: 1; b: 2" string.
    ///
    /// - Trims whitespace around keys and values.
    /// - Strips trailing `;` from values.
    /// - Drops empty pairs.
    /// - Sorts by key (and then value) ascending so ordering is stable.
    public static func normalize(declarations: [(String, String)]) -> String {
        let cleaned = declarations
            .map { (rawKey, rawValue) -> (String, String) in
                let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
                var value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
                value = value.trimmingCharacters(in: CharacterSet(charactersIn: ";"))
                return (key, value)
            }
            .filter { !$0.0.isEmpty && !$0.1.isEmpty }

        if cleaned.isEmpty {
            return ""
        }

        // Sort A→Z by key, then by value for determinism
        let sorted = cleaned.sorted { lhs, rhs in
            if lhs.0 == rhs.0 {
                return lhs.1 < rhs.1
            }
            return lhs.0 < rhs.0
        }

        return sorted
            .map { "\($0): \($1)" }
            .joined(separator: "; ")
    }

    /// Builds a style bucket from pre-parsed declarations.
    ///
    /// Returns `nil` if there are no meaningful declarations.
    public static func makeBucket(
        from declarations: [(String, String)]
    ) -> (className: String, css: String)? {
        let normalized = normalize(declarations: declarations)
        guard !normalized.isEmpty else { return nil }

        let hash = fnv1a64(normalized)
        let className = "style-\(String(hash, radix: 36))"
        return (className, normalized)
    }

    /// Convenience that parses a raw CSS declaration string like
    /// `"--p: 8px; --m: 4px"` into declarations before bucketing.
    public static func makeBucket(fromRaw style: String) -> (className: String, css: String)? {
        let segments = style
            .split(separator: ";")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if segments.isEmpty {
            return nil
        }

        var pairs: [(String, String)] = []
        pairs.reserveCapacity(segments.count)

        for segment in segments {
            let parts = segment.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = String(parts[0])
            let value = String(parts[1])
            pairs.append((key, value))
        }

        return makeBucket(from: pairs)
    }

    // MARK: - Hashing

    /// FNV-1a 64-bit hash over UTF-8 bytes.
    private static func fnv1a64(_ string: String) -> UInt64 {
        let bytes = string.utf8
        var hash: UInt64 = 0xcbf29ce484222325
        let prime: UInt64 = 0x100000001b3

        for byte in bytes {
            hash ^= UInt64(byte)
            hash &*= prime
        }

        return hash
    }
}
