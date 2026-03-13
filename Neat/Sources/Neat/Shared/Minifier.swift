import Foundation

public enum Minifier {
    public static func script(_ source: String) -> String {
        source
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined()
    }

    public static func css(_ source: String) -> String {
        var result = source
        while let start = result.range(of: "/*"),
              let end = result.range(of: "*/", range: start.upperBound..<result.endIndex) {
            result.removeSubrange(start.lowerBound..<end.upperBound)
        }

        result = result
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        let replacements = [
            " {": "{", "{ ": "{",
            " }": "}", "} ": "}",
            " ;": ";", "; ": ";",
            " :": ":", ": ": ":",
            " ,": ",", ", ": ",",
            " > ": ">", " >": ">", "> ": ">",
            " + ": "+", " +": "+", "+ ": "+",
            " ~ ": "~", " ~": "~", "~ ": "~"
        ]

        for (from, to) in replacements {
            result = result.replacingOccurrences(of: from, with: to)
        }

        return result
    }
}
