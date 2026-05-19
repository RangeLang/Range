import Foundation

func invalid() -> Void {
    return 1
}

@main
struct GradientMain {
    static func main() throws {
        invalid()
    }
}
