import Foundation

extension ApplicationGraphValidator {
    struct ControlFlowContext {
        let insideAnonymousBackground: Bool
        let loopDepth: Int
        let switchDepth: Int

        static let root = ControlFlowContext(
            insideAnonymousBackground: false,
            loopDepth: 0,
            switchDepth: 0
        )

        func enteringBackground() -> ControlFlowContext {
            ControlFlowContext(
                insideAnonymousBackground: true,
                loopDepth: 0,
                switchDepth: 0
            )
        }

        func enteringLoop() -> ControlFlowContext {
            ControlFlowContext(
                insideAnonymousBackground: insideAnonymousBackground,
                loopDepth: loopDepth + 1,
                switchDepth: switchDepth
            )
        }

        func enteringSwitch() -> ControlFlowContext {
            ControlFlowContext(
                insideAnonymousBackground: insideAnonymousBackground,
                loopDepth: loopDepth,
                switchDepth: switchDepth + 1
            )
        }
    }

    struct CallLabelValidationContext {
        let currentConstructName: String?
        var localCallablesByName: [String: [CallLabelCandidate]]
        var accessibleConstructTypesByName: [String: String]
    }

    struct CallLabelValidationEnvironment {
        let topLevelCallablesByName: [String: [CallLabelCandidate]]
        let declarationGraph: DeclarationGraph
    }

    struct CallLabelCandidate {
        let name: String
        let parameters: [RangeFunctionParameter]
    }

    struct BindingReferenceContext {
        var mutableNames: Set<String>
        var selfAvailable: Bool
        var currentConstructName: String?
    }

    func accessibleTypesForSwitchCasePattern(
        _ pattern: SwitchCasePattern,
        base: [String: BootstrapLiteralType]
    ) -> [String: BootstrapLiteralType] {
        guard case .enumCase(_, let binding?) = pattern else {
            return base
        }

        var extended = base
        extended[binding.name] = .typed(.named("Never"))
        return extended
    }

    func declarations(in sourceFile: SourceFileNode) -> [ConstructDeclaration] {
        switch sourceFile {
        case .construct(let declaration):
            return [declaration]
        case .namespace(let declaration):
            return declaration.constructs + declaration.namespaces.flatMap { declarations(in: .namespace($0)) }
        case .module(let module):
            return module.constructs + module.namespaces.flatMap { declarations(in: .namespace($0)) }
        case .mainBlock, .extensions, .enumeration, .protocolDefinition, .macro, .marker:
            return []
        }
    }

    func lastPathComponent(of path: String) -> String {
        URL(fileURLWithPath: path).lastPathComponent
    }
}
