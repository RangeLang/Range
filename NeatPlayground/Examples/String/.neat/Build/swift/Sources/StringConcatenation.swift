import Foundation

@main
struct NeatMain {
    static func main() throws {
        var greeting = "Hello" + " World"
        let text = "Hello"
        var message = text + " World"
        var explicit: String = "Hello" + " World"
        var constructed = String("Hello" + " World")
    }
}
