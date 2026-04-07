import Foundation

@main
struct NeatMain {
    static func main() throws {
        var intSum = 1 + 2
        var floatSum = 1.5 + 2.0
        var mixedSum = 1 + 2.5
        let count = 3
        var incremented = count + 1
        var lessThan = count < 10
        var lessOrEqual = count <= 3
        var greaterThan = 10 > count
        var greaterOrEqual = count >= 3
        let name = "George"
        var ordered = name < "Zed"
    }
}
