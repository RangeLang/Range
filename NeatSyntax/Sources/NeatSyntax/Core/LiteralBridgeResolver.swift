import Foundation

public struct LiteralBridgeResolver: Sendable {
    private let defaultConstructNameByCarrier: [String: String]

    public static let empty = LiteralBridgeResolver(realizedLiteralBridges: [])

    public init(realizedLiteralBridges: [RealizedLiteralBridge]) {
        var grouped: [String: Set<String>] = [:]
        for bridge in realizedLiteralBridges {
            grouped[bridge.carrierTypeName, default: []].insert(bridge.constructName)
        }

        self.defaultConstructNameByCarrier = grouped.reduce(into: [:]) { result, entry in
            guard entry.key != "NilLiteral", entry.value.count == 1,
                let constructName = entry.value.first
            else {
                return
            }
            result[entry.key] = constructName
        }
    }

    public func defaultDestinationType(for carrierTypeName: String) -> TypeReference? {
        guard let constructName = defaultConstructNameByCarrier[carrierTypeName] else {
            return nil
        }
        return .named(constructName)
    }

    public func isCompatible(expected: TypeReference, carrierTypeName: String) -> Bool {
        if carrierTypeName == "NilLiteral" {
            if case .optional = expected {
                return true
            }
            return false
        }

        guard let constructName = defaultConstructNameByCarrier[carrierTypeName] else {
            return false
        }
        return constructName == expected.displayName
    }
}
