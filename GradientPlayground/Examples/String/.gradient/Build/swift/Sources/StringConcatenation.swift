import Foundation

@main
struct NeatMain {
    static func main() throws {
        let greeting = "Hello" + " World"
        let text = "Hello"
        let message = text + " World"
        let explicit: String = "Hello" + " World"
        let constructed = String("Hello" + " World")
    }
}
