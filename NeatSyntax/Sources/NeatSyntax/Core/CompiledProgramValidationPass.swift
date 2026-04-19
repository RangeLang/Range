import Foundation

public protocol CompiledProgramValidationPass {
    var name: String { get }

    func validate(_ program: CompiledProgram) throws
}
