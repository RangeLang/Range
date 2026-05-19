import ArgumentParser
import Foundation
import RangeSyntax

enum ProjectSourceValidator {
    static func compiledProgram(for project: LoadedProject) throws -> CompiledProgram {
        try compiledProgram(for: project.sourceInputs)
    }

    static func compiledProgram(for inputs: [SourceInput]) throws -> CompiledProgram {
        try CompilerPipeline().build(inputs: inputs)
    }

    static func validatedCompiledProgram(for project: LoadedProject) throws -> CompiledProgram {
        try validatedCompiledProgram(for: project.sourceInputs)
    }

    static func validatedCompiledProgram(for inputs: [SourceInput]) throws -> CompiledProgram {
        try CompilerPipeline().buildValidated(inputs: inputs)
    }

    static func validateFiles(in project: LoadedProject) throws {
        _ = try validatedCompiledProgram(for: project)
    }

    static func validatePrimaryDeclarations(in project: LoadedProject) throws {
        try CompilerPipeline().validatePrimaryDeclarations(inputs: project.sourceInputs)
    }
}
