import Foundation

public enum StringLiteral {
    public static func decodeEscapes(_ value: String) -> String {
        var result = ""
        var index = value.startIndex

        while index < value.endIndex {
            let character = value[index]
            guard character == "\\" else {
                result.append(character)
                index = value.index(after: index)
                continue
            }

            let nextIndex = value.index(after: index)
            guard nextIndex < value.endIndex else {
                result.append(character)
                index = nextIndex
                continue
            }

            let escaped = value[nextIndex]
            switch escaped {
            case "\"":
                result.append("\"")
            case "\\":
                result.append("\\")
            case "n":
                result.append("\n")
            case "r":
                result.append("\r")
            case "t":
                result.append("\t")
            default:
                result.append(character)
                result.append(escaped)
            }

            index = value.index(after: nextIndex)
        }

        return result
    }
}
