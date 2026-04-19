import ArgumentParser
import Foundation
import NeatSyntax

enum ProjectSourceValidator {
    static func programModel(for project: LoadedProject) throws -> ProgramModel {
        try programModel(for: project.sourceInputs)
    }

    static func programModel(for inputs: [SourceInput]) throws -> ProgramModel {
        try CompilerPipeline().build(inputs: inputs)
    }

    static func validatedProgramModel(for project: LoadedProject) throws -> ProgramModel {
        try validatedProgramModel(for: project.sourceInputs)
    }

    static func validatedProgramModel(for inputs: [SourceInput]) throws -> ProgramModel {
        try CompilerPipeline().buildValidated(inputs: inputs)
    }

    static func validateFiles(in project: LoadedProject) throws {
        _ = try validatedProgramModel(for: project)
    }

    static func validatePrimaryDeclarations(in project: LoadedProject) throws {
        try CompilerPipeline().validatePrimaryDeclarations(inputs: project.sourceInputs)
    }
}
