import Foundation

func invalid() -> Void {
    return 1
}

@main
struct RangeMain {
    static func main() throws {
        invalid()
    }
}
