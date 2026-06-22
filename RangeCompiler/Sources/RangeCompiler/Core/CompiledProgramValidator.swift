import Foundation

public struct CompiledProgramValidator {
    private let passes: [any CompiledProgramValidationPass] = [
        DeclarationGraphValidator(),
    ]

    public init() {}

    public func validate(_ program: CompiledProgram) throws {
        for pass in passes {
            try pass.validate(program)
        }
    }

    public func validatePrimaryDeclarations(in program: CompiledProgram) throws {
        try DeclarationGraphValidator().validatePrimaryDeclarations(in: program)
    }
}

private struct ProgramGraphValidationPass: CompiledProgramValidationPass {
    let name = "ProgramGraph"

    func validate(_ program: CompiledProgram) throws {
        try ProgramGraphValidator().validate(program.programGraph)
    }
}
