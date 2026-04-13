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

@main
struct NeatMain {
    static func main() throws {
        Logger.info("Neat logger fixture")
        Logger.debug("debug path reached")
        Logger.success("success path reached")
        Logger.warning("warning path reached")
        Logger.error("error path reached")
    }
}
