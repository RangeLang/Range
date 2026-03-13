public protocol _PrimitiveHead: Head where Body == Never {}

public extension _PrimitiveHead {
    var body: Never {
        fatalError("Primitive head items do not have a body.")
    }
}
