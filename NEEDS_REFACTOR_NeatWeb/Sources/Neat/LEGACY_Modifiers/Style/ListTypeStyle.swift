public extension Component {
    func listType(_ type: ListType) -> some Component {
        environment(\.listType, type)
    }

    func listRowSpacing(_ spacing: Double?) -> some Component {
        environment(\.listRowSpacing, spacing)
    }
}
