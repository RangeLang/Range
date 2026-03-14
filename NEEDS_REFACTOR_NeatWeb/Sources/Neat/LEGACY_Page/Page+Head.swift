public extension Page where HeadContent == AnyHead {
    @HeadBuilder
    var head: HeadContent {
        EmptyHead()
    }
}
