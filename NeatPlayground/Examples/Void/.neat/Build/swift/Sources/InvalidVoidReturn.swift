import Foundation

func invalid() -> Void {
    return 1
}

@main
struct NeatMain {
    static func main() throws {
        invalid()
    }
}
