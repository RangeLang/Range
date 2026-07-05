import Foundation

public enum CompiledProgramGraphProjection {
    case program(ProgramGraph)
    case declaration(DeclarationGraph)
    case application(ApplicationGraph)

    public var name: String {
        switch self {
        case .program:
            return "ProgramGraph"
        case .declaration:
            return "DeclarationGraph"
        case .application:
            return "ApplicationGraph"
        }
    }
}

public protocol CompiledProgramGraphPass {
    var name: String { get }

    func derive(from program: CompiledProgram) -> CompiledProgramGraphProjection
}

public struct CompiledProgramGraphFlow {
    private let passes: [any CompiledProgramGraphPass] = [
        ProgramGraphPass(),
        DeclarationGraphPass(),
        ApplicationGraphPass(),
    ]

    public init() {}

    public func deriveGraphs(from program: CompiledProgram) -> [CompiledProgramGraphProjection] {
        passes.map { $0.derive(from: program) }
    }
}

public struct ProgramGraphPass: CompiledProgramGraphPass {
    public let name = "ProgramGraph"

    public init() {}

    public func derive(from program: CompiledProgram) -> CompiledProgramGraphProjection {
        .program(program.programGraph)
    }
}

public struct DeclarationGraphPass: CompiledProgramGraphPass {
    public let name = "DeclarationGraph"

    public init() {}

    public func derive(from program: CompiledProgram) -> CompiledProgramGraphProjection {
        .declaration(program.declarationGraph)
    }
}

public struct ApplicationGraphPass: CompiledProgramGraphPass {
    public let name = "ApplicationGraph"

    public init() {}

    public func derive(from program: CompiledProgram) -> CompiledProgramGraphProjection {
        .application(ApplicationGraphBuilder().build(program: program))
    }
}
