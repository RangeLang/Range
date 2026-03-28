import Foundation

public struct LiteralBridgeResolver: Sendable {
    private let bridgesByCarrier: [String: [RealizedLiteralBridge]]

    public static let empty = LiteralBridgeResolver(realizedLiteralBridges: [])

    public init(realizedLiteralBridges: [RealizedLiteralBridge]) {
        var grouped: [String: [RealizedLiteralBridge]] = [:]
        for bridge in realizedLiteralBridges {
            grouped[bridge.carrierTypeName, default: []].append(bridge)
        }
        self.bridgesByCarrier = grouped
    }

    public func defaultDestinationType(for carrierTypeName: String) -> TypeReference? {
        guard let bridge = preferredDefaultBridge(for: carrierTypeName) else {
            return nil
        }
        return .named(bridge.constructName)
    }

    public func isCompatible(expected: TypeReference, carrierTypeName: String) -> Bool {
        if carrierTypeName == "NilLiteral" {
            if case .optional = expected {
                return true
            }
            return false
        }

        return bridgesByCarrier[carrierTypeName, default: []].contains {
            $0.constructName == expected.displayName
        }
    }

    public func preferredDefaultBridge(for carrierTypeName: String) -> RealizedLiteralBridge? {
        guard carrierTypeName != "NilLiteral" else {
            return nil
        }

        let matches = bridgesByCarrier[carrierTypeName, default: []]
        guard !matches.isEmpty else {
            return nil
        }

        let coreMatches = matches.filter(\.isCore)
        if coreMatches.count == 1 {
            return coreMatches[0]
        }
        if coreMatches.isEmpty, matches.count == 1 {
            return matches[0]
        }
        return nil
    }
}
