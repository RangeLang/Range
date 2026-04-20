import Foundation

public struct ApplicationGraphBuilder {
    private let passes: [any ApplicationGraphBuildPass] = [
        ApplicationGraphSeedPass(),
        ApplicationGraphFileAnalysisPass(),
        ApplicationGraphResolutionPass(),
    ]

    public init() {}

    public func build(program: CompiledProgram) -> ApplicationGraph {
        build(
            files: program.expandedFiles,
            declarationGraph: program.declarationGraph
        )
    }

    public func build(files: [ParsedSourceFile]) -> ApplicationGraph {
        build(
            files: files,
            declarationGraph: DeclarationGraph(files: files)
        )
    }

    public func build(
        files: [ParsedSourceFile],
        declarationGraph: DeclarationGraph
    ) -> ApplicationGraph {
        var collector = GraphCollector(declarationGraph: declarationGraph)
        let sortedFiles = files.sorted(by: { $0.path < $1.path })
        for pass in passes {
            pass.apply(to: &collector, files: sortedFiles)
        }
        return collector.materialize()
    }
}

private protocol ApplicationGraphBuildPass {
    var name: String { get }

    func apply(to collector: inout GraphCollector, files: [ParsedSourceFile])
}

private struct ApplicationGraphSeedPass: ApplicationGraphBuildPass {
    let name = "ApplicationGraphSeed"

    func apply(to collector: inout GraphCollector, files: [ParsedSourceFile]) {
        collector.seedDeclarationProjection()
    }
}

private struct ApplicationGraphFileAnalysisPass: ApplicationGraphBuildPass {
    let name = "ApplicationGraphFileAnalysis"

    func apply(to collector: inout GraphCollector, files: [ParsedSourceFile]) {
        for file in files {
            collector.add(file)
        }
    }
}

private struct ApplicationGraphResolutionPass: ApplicationGraphBuildPass {
    let name = "ApplicationGraphResolution"

    func apply(to collector: inout GraphCollector, files: [ParsedSourceFile]) {
        collector.resolveApplicationEdges()
    }
}
