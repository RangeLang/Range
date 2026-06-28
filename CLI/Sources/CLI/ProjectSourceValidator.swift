import ArgumentParser
import Foundation
import RangeCompiler

enum ProjectSourceValidator {
    static func compiledProgram(for project: LoadedProject) throws -> CompiledProgram {
        try compiledProgram(for: project.sourceInputs)
    }

    static func compiledProgram(for inputs: [SourceInput]) throws -> CompiledProgram {
        try CompilerPipeline().build(inputs: inputs)
    }

}
