import Foundation

public struct MacroDeclaration {
    public let macros: [MacroApplication]
    public let name: String
    public let genericParameters: [GenericParameter]
    public let parameters: [RangeFunctionParameter]
    public let target: MacroTarget?
    public let expansionType: TypeReference?
    public let body: [Statement]
}

extension MacroDeclaration {
    static func bootstrapMacroSeed() -> MacroDeclaration {
        MacroDeclaration(
            macros: [],
            name: "macro",
            genericParameters: [],
            parameters: [
                RangeFunctionParameter(
                    macros: [],
                    name: "name",
                    typeReference: .named("String"),
                    valueCapability: .name,
                    slotName: nil
                ),
                RangeFunctionParameter(
                    macros: [],
                    name: "result",
                    typeReference: .named("String"),
                    slotName: nil
                ),
                RangeFunctionParameter(
                    macros: [],
                    name: "target",
                    typeReference: .named("String"),
                    slotName: nil
                ),
                RangeFunctionParameter(
                    macros: [],
                    name: "body",
                    typeReference: .named("String"),
                    slotName: nil
                ),
            ],
            target: .macroSurface("macro"),
            expansionType: .named("String"),
            body: []
        )
    }
}

public struct MacroMetadataDeclaration {
    public let name: String
    public let genericParameters: [GenericParameter]
    public let parameters: [RangeFunctionParameter]
    public let target: MacroTarget
    public let valueType: TypeReference
    public let body: [Statement]

    public var hasMetadataSlotEffect: Bool {
        target.typeReferences.contains(.named("Construct")) && valueType == .named("Void")
    }

    public var hasLanguageEffect: Bool {
        valueType.isLanguageEffect
    }

    public var foreignBodyLanguage: String? {
        guard parameters.count == 1 else {
            return nil
        }
        if parameters[0].capturesSyntax {
            return valueType.foreignBodyLanguageName
        }
        return parameters[0].typeReference?.foreignBodyLanguageName
    }
}

public struct MacroApplication {
    public let name: String
    public let genericArguments: [TypeReference]
    public let argumentClause: String?
    public let rawBodyLanguage: String?
    public let rawBody: String?
    // The macro's evaluated return value, when it produces one.
    public var evaluatedValue: CompileTimeValue?

    public init(
        name: String,
        genericArguments: [TypeReference],
        argumentClause: String?,
        rawBodyLanguage: String? = nil,
        rawBody: String? = nil,
        evaluatedValue: CompileTimeValue? = nil
    ) {
        self.name = name
        self.genericArguments = genericArguments
        self.argumentClause = argumentClause
        self.rawBodyLanguage = rawBodyLanguage
        self.rawBody = rawBody
        self.evaluatedValue = evaluatedValue
    }
}

public indirect enum MacroTarget {
    case syntax(TypeReference)
    case macroSurface(String)
    case anyOf([MacroTarget])
    case allOf([MacroTarget])

    public var typeReference: TypeReference {
        switch self {
        case .syntax(let typeReference):
            return typeReference
        case .macroSurface(let name):
            return .named("@\(name)")
        case .anyOf(let targets), .allOf(let targets):
            return targets.first?.typeReference ?? .named("Unknown")
        }
    }

    public var displayName: String {
        switch self {
        case .syntax(let typeReference):
            return typeReference.displayName
        case .macroSurface(let name):
            return "@\(name)"
        case .anyOf(let targets):
            return targets.map(\.displayName).joined(separator: " | ")
        case .allOf(let targets):
            return targets.map(\.displayName).joined(separator: " & ")
        }
    }

    public var typeReferences: [TypeReference] {
        switch self {
        case .syntax(let typeReference):
            return [typeReference]
        case .macroSurface:
            return []
        case .anyOf(let targets), .allOf(let targets):
            return targets.flatMap(\.typeReferences)
        }
    }
}

extension TypeReference {
    var macroMetadataEffectTarget: TypeReference? {
        guard case .generic(_, let arguments) = self,
            arguments.count == 1,
            macroMetadataEffectName == "Language"
        else {
            return nil
        }
        return arguments[0]
    }

    var macroMetadataEffectName: String? {
        guard case .generic(let base, _) = self,
            case .named(let name) = base
        else {
            return nil
        }
        return name
    }

    var isMacroMetadataEffect: Bool {
        macroMetadataEffectTarget != nil
    }

    var metadataSlotEffectTarget: TypeReference? {
        nil
    }

    var isMetadataSlotEffect: Bool {
        metadataSlotEffectTarget != nil
    }

    var languageEffectTarget: TypeReference? {
        guard macroMetadataEffectName == "Language" else {
            return nil
        }
        return macroMetadataEffectTarget
    }

    var isLanguageEffect: Bool {
        languageEffectTarget != nil
    }

    var foreignBodyLanguageName: String? {
        switch self {
        case .named("Markdown"):
            return "Markdown"
        case .function(let parameters, let returnType) where parameters.isEmpty:
            return returnType.foreignBodyLanguageName
        case .generic(let base, let arguments):
            guard case .named("Foreign") = base,
                arguments.count == 1,
                case .named(let language) = arguments[0]
            else {
                return nil
            }
            return language
        default:
            return nil
        }
    }
}
