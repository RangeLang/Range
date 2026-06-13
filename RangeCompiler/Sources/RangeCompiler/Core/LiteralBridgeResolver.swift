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

    public func bridge(
        expected: TypeReference,
        carrierTypeName: String
    ) -> RealizedLiteralBridge? {
        guard carrierTypeName != "NilLiteral",
            let expectedConstructName = Self.constructName(for: expected)
        else {
            return nil
        }

        let matches = bridgesByCarrier[carrierTypeName, default: []].filter {
            $0.constructName == expectedConstructName
        }
        guard matches.count == 1 else {
            return nil
        }
        return matches[0]
    }

    public func isCompatible(expected: TypeReference, carrierTypeName: String) -> Bool {
        if carrierTypeName == "NilLiteral" {
            if case .optional = expected {
                return true
            }
            return false
        }

        guard let expectedConstructName = Self.constructName(for: expected) else {
            return false
        }

        return bridgesByCarrier[carrierTypeName, default: []].contains {
            $0.constructName == expectedConstructName
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

    private static func constructName(for typeReference: TypeReference) -> String? {
        switch typeReference {
        case .named, .member:
            return typeReference.displayName
        case .generic(let base, _):
            return constructName(for: base)
        case .array:
            return "Array"
        case .optional:
            return "Optional"
        case .variadic(let element):
            return constructName(for: element)
        case .function:
            return nil
        }
    }
}
