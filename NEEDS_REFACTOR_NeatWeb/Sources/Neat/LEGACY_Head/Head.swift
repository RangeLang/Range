public protocol Head: _Renderable {
    associatedtype Body
    @HeadBuilder var body: Body { get }
}

// Default composite behavior only when Body itself is a Head
public extension Head where Body: Head {
    func build() -> ElementNode {
        body.build()
    }
}
