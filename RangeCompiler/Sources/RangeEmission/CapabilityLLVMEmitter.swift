import Foundation
import RangeCompiler

public struct CapabilityScalarApplication: Equatable {
    public let macroName: String
    public let targetName: String
    public let resolvedValue: String
    public let path: String
}

public struct CapabilityScalarDeclaration: Equatable {
    public let macroName: String
    public let targetName: String
    public let llvmType: String
    public let path: String
}

public struct CapabilityLLVMModule: Equatable {
    public let scalarApplications: [CapabilityScalarApplication]
    public let scalarDeclarations: [CapabilityScalarDeclaration]
    public let mainIR: String?
    public let ir: String
}

public struct CapabilityLLVMEmitter {
    private let scalarMacroNames: Set<String> = ["integer", "bool", "boolean", "float"]

    public init() {}

    public func emitModule(compiledProgram: CompiledProgram) -> CapabilityLLVMModule {
        let mainIR = collectMainIR(files: compiledProgram.expandedFiles)
        return emitModule(declarationGraph: compiledProgram.declarationGraph, mainIR: mainIR)
    }

    public func emitModule(files: [ParsedSourceFile]) -> CapabilityLLVMModule {
        let mainIR = collectMainIR(files: files)
        return emitModule(declarationGraph: DeclarationGraph(files: files), mainIR: mainIR)
    }

    private func emitModule(
        declarationGraph: DeclarationGraph,
        mainIR: String?
    ) -> CapabilityLLVMModule {
        let applications = collectScalarApplications(declarationGraph: declarationGraph)
        let declarations = resolveScalarDeclarations(applications: applications)
        return CapabilityLLVMModule(
            scalarApplications: applications,
            scalarDeclarations: declarations,
            mainIR: mainIR,
            ir: mainIR ?? ""
        )
    }

    public func emitModuleFile(
        compiledProgram: CompiledProgram,
        outputURL: URL
    ) throws -> URL {
        let module = emitModule(compiledProgram: compiledProgram)
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try module.ir.write(to: outputURL, atomically: true, encoding: .utf8)
        return outputURL
    }

    public func collectScalarApplications(
        files: [ParsedSourceFile]
    ) -> [CapabilityScalarApplication] {
        collectScalarApplications(declarationGraph: DeclarationGraph(files: files))
    }

    public func collectScalarApplications(
        declarationGraph: DeclarationGraph
    ) -> [CapabilityScalarApplication] {
        constructDeclarations(in: declarationGraph).flatMap { declaration in
            scalarApplications(in: declaration)
        }
        .sorted {
            ($0.targetName, $0.macroName, $0.path) < ($1.targetName, $1.macroName, $1.path)
        }
    }

    public func resolveScalarDeclarations(
        applications: [CapabilityScalarApplication]
    ) -> [CapabilityScalarDeclaration] {
        applications.map { application in
            CapabilityScalarDeclaration(
                macroName: application.macroName,
                targetName: application.targetName,
                llvmType: application.resolvedValue,
                path: application.path
            )
        }
        .sorted {
            ($0.targetName, $0.macroName, $0.path) < ($1.targetName, $1.macroName, $1.path)
        }
    }

    public func collectMainIR(files: [ParsedSourceFile]) -> String? {
        files.compactMap { file -> String? in
            file.sourceFile.blockMacros
                .compactMap { block -> String? in
                    guard block.macros.first?.name == "main" else {
                        return nil
                    }
                    return block.macros.first(where: { $0.name == "main" })?
                        .evaluatedStringValue
                }
                .first
        }.first
    }

    private func constructDeclarations(in declarationGraph: DeclarationGraph) -> [ConstructDeclaration] {
        declarationGraph.constructsByName.values.sorted { $0.name < $1.name }
    }

    private func scalarApplications(in declaration: ConstructDeclaration)
        -> [CapabilityScalarApplication]
    {
        declaration.macros.flatMap { application -> [CapabilityScalarApplication] in
            guard let payload = application.evaluatedStringValue else {
                return []
            }
            return payload
                .split(separator: "\n", omittingEmptySubsequences: true)
                .compactMap { line in
                    scalarApplication(
                        from: String(line),
                        targetName: declaration.name
                    )
                }
        }
    }

    private func scalarApplication(from line: String, targetName: String)
        -> CapabilityScalarApplication?
    {
        let parts = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard let macroName = parts.first, scalarMacroNames.contains(macroName) else {
            return nil
        }
        let fields = recordFields(in: parts)
        guard let llvmType = scalarLLVMType(macroName: macroName, fields: fields) else {
            return nil
        }
        return CapabilityScalarApplication(
            macroName: macroName,
            targetName: targetName,
            resolvedValue: llvmType,
            path: ""
        )
    }

    private func scalarLLVMType(macroName: String, fields: [String: String]) -> String? {
        switch macroName {
        case "integer":
            guard let bits = fields["bits"], !bits.isEmpty else { return nil }
            return "i\(bits)"
        case "bool", "boolean":
            return "i1"
        case "float":
            if let llvm = fields["llvm"], !llvm.isEmpty {
                return llvm
            }
            if fields["precision"] == "32" || fields["bits"] == "32" {
                return "float"
            }
            return "double"
        default:
            return nil
        }
    }

    private func recordFields(in parts: [String]) -> [String: String] {
        var fields: [String: String] = [:]
        for part in parts.dropFirst() {
            let pieces = part.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard pieces.count == 2 else {
                continue
            }
            fields[String(pieces[0])] = String(pieces[1])
        }
        return fields
    }

}
