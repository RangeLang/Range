import Foundation

public struct MacroDeclaration {
    public let packageVisibility: PackageVisibility
    public let name: String
    public let genericParameters: [GenericParameter]
    public let parameters: [RangeFunctionParameter]
    public let target: MacroTarget?
    public let expansionType: TypeReference?
    public let bindings: MacroBindings?
    public let body: [Statement]
    public let syntaxBody: EmittedCodeBlock?
}

public enum PackageVisibility {
    case open
    case closed
}

public struct MacroMetadataDeclaration {
    public let packageVisibility: PackageVisibility
    public let name: String
    public let genericParameters: [GenericParameter]
    public let parameters: [RangeFunctionParameter]
    public let target: MacroTarget
    public let valueType: TypeReference
    public let bindings: MacroBindings?
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

public struct EmittedCodeBlock {
    public let parts: [EmittedCodePart]

    public init(parts: [EmittedCodePart]) {
        self.parts = parts
    }
}

public enum EmittedSyntaxKind: String {
    case declaration
    case expression
    case expressionList
    case typeReference
    case nominalTypeReference
    case callableName

    var diagnosticDescription: String {
        switch self {
        case .declaration:
            return "a declaration"
        case .expression:
            return "an expression"
        case .expressionList:
            return "an expression list"
        case .typeReference:
            return "a type reference"
        case .nominalTypeReference:
            return "a nominal type reference"
        case .callableName:
            return "a callable name"
        }
    }
}

public enum EmittedCodePart {
    case text(String)
    case splice(expression: Expression, expected: EmittedSyntaxKind)
    case syntaxMacroInvocation(name: String, arguments: [CallArgument])
}

public struct MacroApplication {
    public let name: String
    public let genericArguments: [TypeReference]
    public let argumentClause: String?
    public let rawBodyLanguage: String?
    public let rawBody: String?
    // The macro's evaluated string return value, when it produces one. This is
    // the Range-authored processed result (e.g. an @llvm template after splice
    // substitution), carried so emission can consume the macro's output rather
    // than re-deriving it from the raw argument.
    public var evaluatedStringValue: String?

    public init(
        name: String,
        genericArguments: [TypeReference],
        argumentClause: String?,
        rawBodyLanguage: String? = nil,
        rawBody: String? = nil,
        evaluatedStringValue: String? = nil
    ) {
        self.name = name
        self.genericArguments = genericArguments
        self.argumentClause = argumentClause
        self.rawBodyLanguage = rawBodyLanguage
        self.rawBody = rawBody
        self.evaluatedStringValue = evaluatedStringValue
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

public struct MacroBindings {
    public let target: String
    public let diagnostics: String
    public let graph: String?
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
