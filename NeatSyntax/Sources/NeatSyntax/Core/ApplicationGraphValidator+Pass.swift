import Foundation

extension ApplicationGraphValidator: CompiledProgramValidationPass {
    public func validate(_ program: CompiledProgram) throws {
        let graphViews = program.declarationViews
        try validateControlFlow(in: program.expandedFiles)
        try validateCallArgumentLabels(
            in: program.expandedFiles,
            declarationGraph: program.declarationGraph
        )
        try validateCallableReturnSemantics(
            in: program.expandedFiles,
            declarationGraph: program.declarationGraph,
            registryView: graphViews.registryView,
            resolver: program.literalBridgeResolver,
            memberResolver: graphViews.memberResolver,
            operatorResolver: graphViews.operatorResolver,
            typeCompatibilityResolver: graphViews.typeCompatibilityResolver
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
        try validateEnvironmentStateResolution(
            in: program.expandedFiles,
            declarationGraph: program.declarationGraph
        )
        try validateValueBindings(
            in: program.expandedFiles,
            declarationGraph: program.declarationGraph
        )
    }
}
