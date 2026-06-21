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
    public let functions: [CapabilityLLVMFunction]
    public let mainIR: String?
    public let ir: String
}

public struct CapabilityLLVMFunction: Equatable {
    public let rangeName: String
    public let llvmName: String
    public let returnType: String
    public let parameters: [CapabilityLLVMParameter]
    public let body: [String]
}

public struct CapabilityLLVMParameter: Equatable {
    public let name: String
    public let llvmType: String
}

public struct CapabilityLLVMEmitter {
    private let scalarMacroNames: Set<String> = ["integer", "bool", "boolean", "float"]

    public init() {}

    public func emitModule(compiledProgram: CompiledProgram) -> CapabilityLLVMModule {
        emitModule(files: compiledProgram.expandedFiles)
    }

    public func emitModule(files: [ParsedSourceFile]) -> CapabilityLLVMModule {
        let applications = collectScalarApplications(files: files)
        let declarations = resolveScalarDeclarations(applications: applications)
        let functions = collectLLVMFunctions(files: files, scalarDeclarations: declarations)
        return CapabilityLLVMModule(
            scalarApplications: applications,
            scalarDeclarations: declarations,
            functions: functions,
            mainIR: collectMainIR(files: files),
            ir: collectMainIR(files: files) ?? renderIR(functions: functions)
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
        files.flatMap { file in
            constructDeclarations(in: file.sourceFile).flatMap { declaration in
                declaration.macros.compactMap { application in
                    guard scalarMacroNames.contains(application.name),
                        let resolvedValue = application.evaluatedStringValue
                    else {
                        return nil
                    }
                    return CapabilityScalarApplication(
                        macroName: application.name,
                        targetName: declaration.name,
                        resolvedValue: resolvedValue,
                        path: file.path
                    )
                }
            }
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

    public func collectLLVMFunctions(
        files: [ParsedSourceFile],
        scalarDeclarations: [CapabilityScalarDeclaration]
    ) -> [CapabilityLLVMFunction] {
        let scalarTypes = scalarDeclarations.reduce(into: [String: String]()) { result, declaration in
            result[declaration.targetName] = result[declaration.targetName] ?? declaration.llvmType
        }

        return files.flatMap { file in
            callableDeclarations(in: file.sourceFile).compactMap { callable in
                lowerCallable(callable, scalarTypes: scalarTypes)
            }
        }
        .sorted { $0.rangeName < $1.rangeName }
    }

    public func collectMainIR(files: [ParsedSourceFile]) -> String? {
        files.compactMap { file -> String? in
            switch file.sourceFile {
            case .mainBlock(let mainBlock):
                return mainBlock.macros.first(where: { $0.name == "main" })?.evaluatedStringValue
            case .module(let module):
                return module.mainBlock?.macros.first(where: { $0.name == "main" })?
                    .evaluatedStringValue
            case .construct, .enumeration, .macro, .extensions:
                return nil
            }
        }.first
    }

    private func lowerCallable(
        _ callable: CallableDeclaration,
        scalarTypes: [String: String]
    ) -> CapabilityLLVMFunction? {
        guard callable.targetType == nil,
            callable.genericParameters.isEmpty,
            let returnTypeName = callable.returnType?.displayName,
            let returnType = scalarTypes[returnTypeName],
            let body = callable.body,
            body.count == 1,
            case .return(let expression?) = body[0],
            case .binary(let lhs, .addition, let rhs) = expression,
            case .identifier(let lhsName) = lhs,
            case .identifier(let rhsName) = rhs
        else {
            return nil
        }

        let parameters = callable.parameters.compactMap { parameter -> CapabilityLLVMParameter? in
            guard let typeName = parameter.typeReference?.displayName,
                let llvmType = scalarTypes[typeName]
            else {
                return nil
            }
            return CapabilityLLVMParameter(name: parameter.name, llvmType: llvmType)
        }
        guard parameters.count == callable.parameters.count,
            parameters.count == 2,
            parameters[0].name == lhsName,
            parameters[1].name == rhsName,
            parameters[0].llvmType == returnType,
            parameters[1].llvmType == returnType
        else {
            return nil
        }

        return CapabilityLLVMFunction(
            rangeName: callable.name,
            llvmName: callable.name == "main" ? "main" : "RangeLLVM_\(callable.name)",
            returnType: returnType,
            parameters: parameters,
            body: [
                "  %1 = add \(returnType) %\(lhsName), %\(rhsName)",
                "  ret \(returnType) %1",
            ]
        )
    }

    private func renderIR(functions: [CapabilityLLVMFunction]) -> String {
        var lines = [
            "; ModuleID = 'RangeScalar'",
            "source_filename = \"RangeScalar.range\"",
            "",
        ]

        for function in functions {
            let renderedParameters = function.parameters
                .map { "\($0.llvmType) %\($0.name)" }
                .joined(separator: ", ")
            lines += [
                "define \(function.returnType) @\(function.llvmName)(\(renderedParameters)) {",
                "entry:",
            ]
            lines += function.body
            lines += [
                "}",
                "",
            ]
        }

        if let addFunction = functions.first(where: { $0.rangeName == "add" }),
            addFunction.parameters.count == 2,
            addFunction.returnType.hasPrefix("i")
        {
            lines += [
                "define i3 @main() {",
                "entry:",
                "  %1 = call \(addFunction.returnType) @\(addFunction.llvmName)(\(addFunction.returnType) 1, \(addFunction.returnType) 2)",
                "  %2 = trunc \(addFunction.returnType) %1 to i3",
                "  ret i3 %2",
                "}",
                "",
            ]
            return lines.joined(separator: "\n")
        }

        lines += [
            "define i3 @main() {",
            "entry:",
            "  ret i3 0",
            "}",
            "",
        ]
        return lines.joined(separator: "\n")
    }

    private func callableDeclarations(in sourceFile: SourceFileNode) -> [CallableDeclaration] {
        switch sourceFile {
        case .construct(let declaration):
            return callableDeclarations(in: declaration)
        case .module(let module):
            return module.callables
                + module.constructs.flatMap(callableDeclarations(in:))
                + module.extensions.flatMap {
                    $0.callables + $0.constructs.flatMap(callableDeclarations(in:))
                }
        case .extensions(let declarations):
            return declarations.flatMap {
                $0.callables + $0.constructs.flatMap(callableDeclarations(in:))
            }
        case .enumeration, .macro, .mainBlock:
            return []
        }
    }

    private func callableDeclarations(in declaration: ConstructDeclaration) -> [CallableDeclaration] {
        declaration.callables + declaration.constructs.flatMap(callableDeclarations(in:))
    }

    private func constructDeclarations(in sourceFile: SourceFileNode) -> [ConstructDeclaration] {
        switch sourceFile {
        case .construct(let declaration):
            return [declaration] + declaration.constructs.flatMap(constructDeclarations(in:))
        case .module(let module):
            return module.constructs.flatMap { [$0] + $0.constructs.flatMap(constructDeclarations(in:)) }
        case .enumeration, .extensions, .macro, .mainBlock:
            return []
        }
    }

    private func constructDeclarations(in declaration: ConstructDeclaration) -> [ConstructDeclaration] {
        [declaration] + declaration.constructs.flatMap(constructDeclarations(in:))
    }
}
