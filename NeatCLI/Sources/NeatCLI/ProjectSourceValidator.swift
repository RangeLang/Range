import ArgumentParser
import Foundation
import NeatSyntax

enum ProjectSourceValidator {
    static func semanticProgram(for project: LoadedProject) throws -> SemanticProgram {
        try semanticProgram(for: project.sourceInputs)
    }

    static func semanticProgram(for inputs: [SourceInput]) throws -> SemanticProgram {
        try CompilerPipeline().build(inputs: inputs)
    }

    static func validatedSemanticProgram(for project: LoadedProject) throws -> SemanticProgram {
        try validatedSemanticProgram(for: project.sourceInputs)
    }

    static func validatedSemanticProgram(for inputs: [SourceInput]) throws -> SemanticProgram {
        try CompilerPipeline().buildValidated(inputs: inputs)
    }

    static func validateFiles(in project: LoadedProject) throws {
        _ = try validatedSemanticProgram(for: project)
    }

    static func validatePrimaryDeclarations(in project: LoadedProject) throws {
        try CompilerPipeline().validatePrimaryDeclarations(inputs: project.sourceInputs)
    }
}
