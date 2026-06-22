import Foundation

extension ApplicationGraphValidator: CompiledProgramValidationPass {
    public func validate(_ program: CompiledProgram) throws {
        let graphViews = program.declarationViews
        try validateCallArgumentLabels(
            in: program.expandedFiles,
            declarationGraph: program.declarationGraph
        )
        try validateLiteralBridgeCompatibility(
            in: program.parsedFiles,
            declarationGraph: program.declarationGraph,
            registryView: graphViews.registryView,
            resolver: program.literalBridgeResolver,
            memberResolver: graphViews.memberResolver,
            operatorResolver: graphViews.operatorResolver,
            typeCompatibilityResolver: graphViews.typeCompatibilityResolver
        )
        try validateBindingReferences(
            in: program.expandedFiles,
            declarationGraph: program.declarationGraph,
            registryView: graphViews.registryView
        )
        try validateValueBindings(
            in: program.expandedFiles,
            declarationGraph: program.declarationGraph
        )
    }
}
