@resultBuilder
public struct HeadBuilder {

    // Lift any Head into the builder's internal representation.
    public static func buildExpression<H: Head>(_ head: H) -> AnyHead {
        AnyHead(head)
    }

    // Base block: one or more children.
    public static func buildBlock(_ heads: AnyHead...) -> AnyHead {
        switch heads.count {
        case 0:
            return AnyHead(EmptyHead())
        case 1:
            return heads[0]
        default:
            return AnyHead(HeadFragment(heads))
        }
    }

    // Optional
    public static func buildOptional(_ head: AnyHead?) -> AnyHead {
        head ?? AnyHead(EmptyHead())
    }

    // if / else
    public static func buildEither(first: AnyHead) -> AnyHead {
        first
    }

    public static func buildEither(second: AnyHead) -> AnyHead {
        second
    }

    // for-in loops
    public static func buildArray(_ heads: [AnyHead]) -> AnyHead {
        AnyHead(HeadFragment(heads))
    }

    // #available
    public static func buildLimitedAvailability(_ head: AnyHead) -> AnyHead {
        head
    }
}

@inline(__always)
public func Heads(@HeadBuilder _ content: () -> AnyHead) -> AnyHead {
    content()
}
