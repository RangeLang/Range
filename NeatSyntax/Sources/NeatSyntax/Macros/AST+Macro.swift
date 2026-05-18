import Foundation

public struct MacroDeclaration {
    public let name: String
    public let genericParameters: [GenericParameter]
    public let parameters: [NeatFunctionParameter]
    public let target: MacroTarget?
    public let expansionType: TypeReference?
    public let bindings: MacroBindings?
    public let body: [Statement]
    public let syntaxBody: EmittedCodeBlock?
}

public struct MarkerDeclaration {
    public let name: String
    public let genericParameters: [GenericParameter]
    public let parameters: [NeatFunctionParameter]
    public let target: MacroTarget
    public let valueType: TypeReference
    public let globalRegistrations: [MarkerGlobalRegistration]
    public let body: [Statement]

    public var registersNamespace: Bool {
        globalRegistrations.contains(.namespace) || valueType.isNamespaceRegistration
    }

    public var registersLanguageBoundary: Bool {
        valueType.isLanguageRegistration
    }
}

public enum MarkerGlobalRegistration: String, Equatable {
    case namespace
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
}

public enum MacroTarget {
    case syntax(TypeReference)

    public var typeReference: TypeReference {
        switch self {
        case .syntax(let typeReference):
            return typeReference
        }
    }
}

public struct MacroBindings {
    public let target: String
    public let diagnostics: String
}

extension TypeReference {
    var markerEffectTarget: TypeReference? {
        guard case .generic(_, let arguments) = self,
            arguments.count == 1
        else {
            return nil
        }
        return arguments[0]
    }

    var markerEffectName: String? {
        guard case .generic(let base, _) = self,
            case .named(let name) = base
        else {
            return nil
        }
        return name
    }

    var isMarkerEffect: Bool {
        markerEffectTarget != nil
    }

    var namespaceRegistrationTarget: TypeReference? {
        guard markerEffectName == "Namespace" else {
            return nil
        }
        return markerEffectTarget
    }

    var isNamespaceRegistration: Bool {
        namespaceRegistrationTarget != nil
    }

    var languageRegistrationTarget: TypeReference? {
        guard markerEffectName == "Language" else {
            return nil
        }
        return markerEffectTarget
    }

    var isLanguageRegistration: Bool {
        languageRegistrationTarget != nil
    }
}
