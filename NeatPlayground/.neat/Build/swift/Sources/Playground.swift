import Foundation

@main
struct NeatMain {
    static func main() throws {
        let numbers = [1, 2, 3, 4]
        var total = 0
        Logger.info("Neat playground")
        for number in numbers {
            total += number
            Logger.log(total)
        }
        Logger.success("sum is \(total == 10 ? "correct" : "incorrect")")
    }
}
