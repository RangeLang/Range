@resultBuilder
public struct TableColumnBuilder<RowData> {
    public static func buildExpression(_ column: TableColumn<RowData>) -> TableColumn<RowData> {
        column
    }

    public static func buildBlock(_ columns: TableColumn<RowData>...) -> [TableColumn<RowData>] {
        columns
    }

    public static func buildOptional(_ column: [TableColumn<RowData>]?) -> [TableColumn<RowData>] {
        column ?? []
    }

    public static func buildEither(first: [TableColumn<RowData>]) -> [TableColumn<RowData>] {
        first
    }

    public static func buildEither(second: [TableColumn<RowData>]) -> [TableColumn<RowData>] {
        second
    }

    public static func buildArray(_ columns: [[TableColumn<RowData>]]) -> [TableColumn<RowData>] {
        columns.flatMap { $0 }
    }

    public static func buildLimitedAvailability(_ columns: [TableColumn<RowData>]) -> [TableColumn<RowData>] {
        columns
    }
}

public struct TableColumn<RowData> {
    public let title: String
    let value: (RowData) -> String

    public init(_ title: String, value: @escaping (RowData) -> String) {
        self.title = title
        self.value = value
    }

    public init<Value: CustomStringConvertible>(_ title: String, value: KeyPath<RowData, Value>) {
        self.title = title
        self.value = { row in
            String(describing: row[keyPath: value])
        }
    }
}

public struct Table<Data: RandomAccessCollection>: _PrimitiveComponent {
    public let data: Data
    public let columns: [TableColumn<Data.Element>]

    public init(_ data: Data, @TableColumnBuilder<Data.Element> columns: () -> [TableColumn<Data.Element>]) {
        self.data = data
        self.columns = columns()
    }

    public func build(in context: RenderContext?) -> ElementNode {
        let headerCells = columns.map { column in
            ElementNode(tag: "th", children: [.text(column.title)])
        }
        let headerRow = ElementNode(tag: "tr", children: headerCells)
        let head = ElementNode(tag: "thead", children: [headerRow])

        let bodyRows = data.map { row in
            let cells = columns.map { column in
                ElementNode(tag: "td", children: [.text(column.value(row))])
            }
            return ElementNode(tag: "tr", children: cells)
        }
        let body = ElementNode(tag: "tbody", children: bodyRows)

        return ElementNode(
            tag: "table",
            children: [head, body]
        )
    }
}
