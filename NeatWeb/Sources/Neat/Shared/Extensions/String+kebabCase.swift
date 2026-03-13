#if !os(WASI)
import Foundation
#endif

public extension String {
    /// Converts "HomePage" → "home-page"
    var kebabCase: String {
        #if os(WASI)
        return self
        #else
        unicodeScalars.reduce("") { result, scalar in
            if CharacterSet.uppercaseLetters.contains(scalar) {
                let lower = Character(UnicodeScalar(scalar.value + 32)!)
                return result.isEmpty ? "\(lower)" : result + "-\(lower)"
            } else {
                return result + String(scalar)
            }
        }
        #endif
    }
}
