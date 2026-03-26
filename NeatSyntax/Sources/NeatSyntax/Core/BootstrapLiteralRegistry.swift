import Foundation

enum BootstrapLiteralRegistry {
    static func bridge(for type: BootstrapLiteralType) -> BootstrapLiteralBridge? {
        switch type {
        case .intLiteral:
            return BootstrapLiteralBridge(
                carrierType: .named("IntLiteral"),
                defaultDestinationType: .named("Int"),
                acceptedDestinationTypeNames: ["Int"],
                requiresOptionalContext: false
            )
        case .floatLiteral:
            return BootstrapLiteralBridge(
                carrierType: .named("FloatLiteral"),
                defaultDestinationType: .named("Float"),
                acceptedDestinationTypeNames: ["Float", "Double"],
                requiresOptionalContext: false
            )
        case .stringLiteral:
            return BootstrapLiteralBridge(
                carrierType: .named("StringLiteral"),
                defaultDestinationType: .named("String"),
                acceptedDestinationTypeNames: ["String"],
                requiresOptionalContext: false
            )
        case .boolLiteral:
            return BootstrapLiteralBridge(
                carrierType: .named("BoolLiteral"),
                defaultDestinationType: .named("Bool"),
                acceptedDestinationTypeNames: ["Bool"],
                requiresOptionalContext: false
            )
        case .nilLiteral:
            return BootstrapLiteralBridge(
                carrierType: .named("NilLiteral"),
                defaultDestinationType: nil,
                acceptedDestinationTypeNames: [],
                requiresOptionalContext: true
            )
        case .typed:
            return nil
        }
    }
}
