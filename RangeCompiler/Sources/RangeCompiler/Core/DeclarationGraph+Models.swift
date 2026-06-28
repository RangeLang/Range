import Foundation

public struct RealizedInitTarget: Hashable, Sendable {
    public let constructName: String
    public let parameterLabels: [String?]
    public let isCore: Bool

    public init(
        constructName: String,
        parameterLabels: [String?],
        isCore: Bool
    ) {
        self.constructName = constructName
        self.parameterLabels = parameterLabels
        self.isCore = isCore
    }
}

public struct RealizedLiteralBridge: Hashable, Sendable {
    public let initTarget: RealizedInitTarget
    public let carrierTypeName: String

    public init(
        initTarget: RealizedInitTarget,
        carrierTypeName: String,
    ) {
        self.initTarget = initTarget
        self.carrierTypeName = carrierTypeName
    }

    public var constructName: String {
        initTarget.constructName
    }

    public var parameterLabel: String? {
        guard initTarget.parameterLabels.count == 1 else {
            return nil
        }
        return initTarget.parameterLabels[0]
    }

    public var isCore: Bool {
        initTarget.isCore
    }
}

public enum DeclaredMemberKind: String, Sendable {
    case state
    case binding
    case derived
    case value
}

public struct DeclaredMemberSurface {
    public let ownerConstructName: String
    public let name: String
    public let kind: DeclaredMemberKind
    public let declaredTypeName: String?

    public init(
        ownerConstructName: String,
        name: String,
        kind: DeclaredMemberKind,
        declaredTypeName: String?
    ) {
        self.ownerConstructName = ownerConstructName
        self.name = name
        self.kind = kind
        self.declaredTypeName = declaredTypeName
    }

    public var path: String {
        "\(ownerConstructName).\(name)"
    }
}

public struct DeclaredCallableSurface {
    public let ownerConstructName: String?
    public let name: String
    public let labels: [String?]
    public let parameterTypeNames: [String?]
    public let parameters: [RangeFunctionParameter]
    public let returnTypeName: String?

    public init(
        ownerConstructName: String?,
        name: String,
        labels: [String?],
        parameterTypeNames: [String?],
        parameters: [RangeFunctionParameter],
        returnTypeName: String?
    ) {
        self.ownerConstructName = ownerConstructName
        self.name = name
        self.labels = labels
        self.parameterTypeNames = parameterTypeNames
        self.parameters = parameters
        self.returnTypeName = returnTypeName
    }

    public var identity: String {
        let owner = ownerConstructName ?? "<top-level>"
        return "\(owner)::\(name)(\(labels.map { $0 ?? "_" }.joined(separator: ",")))"
    }
}

public struct DeclaredInitializerSurface {
    public let ownerConstructName: String
    public let labels: [String?]
    public let parameterTypeNames: [String?]
    public let parameters: [RangeFunctionParameter]
    public let returnTypeName: String?

    public init(
        ownerConstructName: String,
        labels: [String?],
        parameterTypeNames: [String?],
        parameters: [RangeFunctionParameter],
        returnTypeName: String?
    ) {
        self.ownerConstructName = ownerConstructName
        self.labels = labels
        self.parameterTypeNames = parameterTypeNames
        self.parameters = parameters
        self.returnTypeName = returnTypeName
    }

    public var identity: String {
        "\(ownerConstructName)::init(\(labels.map { $0 ?? "_" }.joined(separator: ",")))"
    }
}
