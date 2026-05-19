import Foundation

enum Logger {
    static func log(_ value: Any) {
        print(String(describing: value))
    }

    static func debug(_ value: Any) {
        print(String(describing: value))
    }

    static func info(_ value: Any) {
        print(String(describing: value))
    }

    static func success(_ value: Any) {
        print(String(describing: value))
    }

    static func warning(_ value: Any) {
        print(String(describing: value))
    }

    static func error(_ value: Any) {
        fputs("\(String(describing: value))\n", stderr)
    }
}