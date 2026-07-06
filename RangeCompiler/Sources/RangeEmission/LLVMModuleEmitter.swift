import Foundation
import RangeCompiler

public struct LLVMEmissionError: LocalizedError {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var errorDescription: String? {
        message
    }
}

public struct LLVMModuleEmitter {
    public init() {}

    public func emit(program: CompiledProgram) throws -> String {
        let mainBlock = try projectMainBlock(in: program)
        let callables = try projectCallables(in: program)
        let runtime = LLVMRuntime()
        let genericFunctionSpecializations = try concreteGenericFunctionSpecializations(
            callables: callables,
            mainBlock: mainBlock
        )
        let knownEnumStorageTypes = projectEnumStorageTypes(in: program)
        let constructLayouts = try projectConstructLayouts(
            in: program,
            genericFunctionSpecializations: genericFunctionSpecializations,
            knownEnumStorageTypes: knownEnumStorageTypes,
            runtime: runtime
        )
        let enumLayouts = try projectEnumLayouts(
            in: program,
            genericFunctionSpecializations: genericFunctionSpecializations,
            constructLayouts: constructLayouts,
            runtime: runtime
        )
        let signatures = try functionSignatures(
            for: callables,
            genericFunctionSpecializations: genericFunctionSpecializations,
            constructLayouts: constructLayouts,
            enumLayouts: enumLayouts,
            runtime: runtime
        )
        var modules: [String] = []

        modules.append(contentsOf: constructLayouts.values.sorted { $0.name < $1.name }.map { layout in
            "\(layout.storageType) = type { \(layout.fields.map(\.type).joined(separator: ", ")) }\n"
        })
        modules.append(contentsOf: enumLayouts.values.sorted { $0.name < $1.name }.compactMap { layout in
            guard layout.hasPayload else {
                return nil
            }
            let fields = (["i32"] + layout.payloadFields.map(\.type)).joined(separator: ", ")
            return "\(layout.storageType) = type { \(fields) }\n"
        })

        for callable in callables {
            guard callable.genericParameters.isEmpty else {
                continue
            }
            var emitter = FunctionEmitter(
                signatures: signatures,
                constructLayouts: constructLayouts,
                enumLayouts: enumLayouts,
                runtime: runtime
            )
            modules.append(try emitter.emit(callable: callable))
        }

        for specialization in genericFunctionSpecializations.sorted(by: { $0.callName < $1.callName }) {
            var emitter = FunctionEmitter(
                signatures: signatures,
                constructLayouts: constructLayouts,
                enumLayouts: enumLayouts,
                runtime: runtime
            )
            modules.append(try emitter.emit(specialization: specialization))
        }

        var mainEmitter = FunctionEmitter(
            signatures: signatures,
            constructLayouts: constructLayouts,
            enumLayouts: enumLayouts,
            runtime: runtime
        )
        modules.append(try mainEmitter.emitMain(mainBlock: mainBlock))

        let runtimeDeclarations = runtime.render()
        return ([runtimeDeclarations] + modules).filter { !$0.isEmpty }.joined(separator: "\n")
    }

    private func projectMainBlock(in program: CompiledProgram) throws -> MainBlockNode {
        let blocks = program.projectExpandedFiles.compactMap { file in
            mainBlock(in: file.sourceFile)
        }

        guard let block = blocks.first else {
            throw LLVMEmissionError("No @main block found in project source.")
        }

        guard blocks.count == 1 else {
            throw LLVMEmissionError("LLVM emission requires exactly one @main block.")
        }

        return block
    }

    private func mainBlock(in sourceFile: SourceFileNode) -> MainBlockNode? {
        switch sourceFile {
        case .mainBlock(let mainBlock):
            return mainBlock
        case .module(let module):
            return module.mainBlock
        default:
            return nil
        }
    }

    private func projectCallables(in program: CompiledProgram) throws -> [CallableDeclaration] {
        program.projectExpandedFiles.flatMap { file in
            callables(in: file.sourceFile)
        }
    }

    private func projectEnumStorageTypes(in program: CompiledProgram) -> [String: String] {
        let enumDeclarations = program.projectExpandedFiles.flatMap { file in
            self.enumerations(in: file.sourceFile)
        }
        var storageTypes: [String: String] = [:]
        for enumeration in enumDeclarations {
            guard enumeration.genericParameters.isEmpty else {
                continue
            }
            guard storageTypes[enumeration.name] == nil else {
                continue
            }
            let hasPayload = enumeration.cases.contains { !$0.associatedValues.isEmpty }
            storageTypes[enumeration.name] = hasPayload ? "%\(enumeration.name)" : "i32"
        }
        return storageTypes
    }

    private func projectConstructLayouts(
        in program: CompiledProgram,
        genericFunctionSpecializations: [GenericFunctionSpecialization],
        knownEnumStorageTypes: [String: String],
        runtime: LLVMRuntime
    ) throws
        -> [String: ConstructLayout]
    {
        var layouts: [String: ConstructLayout] = [:]
        let constructDeclarations = program.projectExpandedFiles.flatMap { file in
            self.constructs(in: file.sourceFile)
        }
        let constructNames = Set(constructDeclarations.map { $0.name })
        let constructDeclarationsByName = Dictionary(
            uniqueKeysWithValues: constructDeclarations.map { ($0.name, $0) }
        )
        for construct in constructDeclarations {
            guard construct.genericParameters.isEmpty else {
                continue
            }
            guard layouts[construct.name] == nil else {
                throw LLVMEmissionError("LLVM emission requires unique construct names. Duplicate: \(construct.name).")
            }
            let valueFields = try construct.values.map { value in
                let typeReference = parseRenderedTypeReference(value.typeName)
                return ConstructField(
                    name: value.name,
                    type: try llvmTypeInfo(
                        for: typeReference,
                        constructLayouts: layouts,
                        knownEnumStorageTypes: knownEnumStorageTypes,
                        knownConstructNames: constructNames,
                        runtime: runtime,
                        context: "field '\(value.name)'"
                    ).ir,
                    typeReference: typeReference,
                    defaultValue: value.value
                )
            }
            let stateFields = try construct.states.map { state in
                ConstructField(
                    name: state.name,
                    type: try llvmType(
                        for: state.type,
                        constructLayouts: layouts,
                        knownEnumStorageTypes: knownEnumStorageTypes,
                        knownConstructNames: constructNames,
                        runtime: runtime,
                        context: "field '\(state.name)'"
                    ),
                    typeReference: state.type,
                    defaultValue: {
                        guard case .stored(let expression) = state.storage else {
                            return nil
                        }
                        return expression
                    }()
                )
            }
            layouts[construct.name] = ConstructLayout(
                name: construct.name,
                storageType: "%\(construct.name)",
                fields: valueFields + stateFields
            )
        }

        let genericReferences = genericConstructReferences(
            in: program,
            genericFunctionSpecializations: genericFunctionSpecializations,
            constructDeclarationsByName: constructDeclarationsByName
        )
        var inProgressGenericConstructs: Set<String> = []

        func materializeGenericConstructDependencies(
            in typeReference: TypeReference
        ) throws {
            switch typeReference {
            case .generic(let base, let arguments):
                for argument in arguments {
                    try materializeGenericConstructDependencies(in: argument)
                }
                if case .named(let constructName) = base,
                    constructDeclarationsByName[constructName]?.genericParameters.isEmpty == false
                {
                    try materializeGenericConstruct(reference: typeReference)
                }
            case .array(let element), .optional(let element), .variadic(let element):
                try materializeGenericConstructDependencies(in: element)
            case .function(let parameters, let returnType):
                try parameters.forEach(materializeGenericConstructDependencies)
                try materializeGenericConstructDependencies(in: returnType)
            case .member(let base, _):
                try materializeGenericConstructDependencies(in: base)
            case .named:
                return
            }
        }

        func materializeGenericConstruct(reference: TypeReference) throws {
            guard case .generic(let base, let arguments) = reference,
                case .named(let constructName) = base,
                let construct = constructDeclarationsByName[constructName]
            else {
                return
            }
            guard layouts[reference.displayName] == nil else {
                return
            }
            guard !inProgressGenericConstructs.contains(reference.displayName) else {
                throw LLVMEmissionError(
                    "LLVM emission cannot materialize recursive generic construct '\(reference.displayName)'."
                )
            }
            inProgressGenericConstructs.insert(reference.displayName)
            defer { inProgressGenericConstructs.remove(reference.displayName) }

            let parameterNames = try construct.genericParameters.map { parameter in
                guard case .type(let name, _, _) = parameter else {
                    throw LLVMEmissionError(
                        "LLVM emission only supports type generic parameters for construct '\(construct.name)' yet."
                    )
                }
                return name
            }
            guard parameterNames.count == arguments.count else {
                throw LLVMEmissionError(
                    "LLVM emission requires concrete type arguments for generic construct '\(construct.name)'."
                )
            }
            let substitution = Dictionary(uniqueKeysWithValues: zip(parameterNames, arguments))
            for value in construct.values {
                let substitutedType = substitute(
                    parseRenderedTypeReference(value.typeName),
                    using: substitution
                )
                try materializeGenericConstructDependencies(in: substitutedType)
            }
            for state in construct.states {
                try materializeGenericConstructDependencies(
                    in: substitute(state.type, using: substitution)
                )
            }
            let valueFields = try construct.values.map { value in
                let substitutedType = substitute(
                    parseRenderedTypeReference(value.typeName),
                    using: substitution
                )
                return ConstructField(
                    name: value.name,
                    type: try llvmTypeInfo(
                        for: substitutedType,
                        constructLayouts: layouts,
                        knownEnumStorageTypes: knownEnumStorageTypes,
                        runtime: runtime,
                        context: "field '\(value.name)'"
                    ).ir,
                    typeReference: substitutedType,
                    defaultValue: value.value
                )
            }
            let stateFields = try construct.states.map { state in
                let substitutedType = substitute(state.type, using: substitution)
                return ConstructField(
                    name: state.name,
                    type: try llvmType(
                        for: substitutedType,
                        constructLayouts: layouts,
                        knownEnumStorageTypes: knownEnumStorageTypes,
                        runtime: runtime,
                        context: "field '\(state.name)'"
                    ),
                    typeReference: substitutedType,
                    defaultValue: {
                        guard case .stored(let expression) = state.storage else {
                            return nil
                        }
                        return expression
                    }()
                )
            }
            layouts[reference.displayName] = ConstructLayout(
                name: reference.displayName,
                storageType: "%\(llvmSanitizedTypeName(reference.displayName))",
                fields: valueFields + stateFields
            )
        }

        for reference in genericReferences.sorted(by: { $0.displayName < $1.displayName }) {
            try materializeGenericConstruct(reference: reference)
        }
        return layouts
    }

    private func projectEnumLayouts(
        in program: CompiledProgram,
        genericFunctionSpecializations: [GenericFunctionSpecialization],
        constructLayouts: [String: ConstructLayout],
        runtime: LLVMRuntime
    ) throws -> [String: EnumLayout] {
        var layouts: [String: EnumLayout] = [:]
        let enumDeclarations = program.projectExpandedFiles.flatMap { file in
            self.enumerations(in: file.sourceFile)
        }
        let extensions = program.projectExpandedFiles.flatMap { file in
            self.extensions(in: file.sourceFile)
        }
        let extensionCasesByTargetName = Dictionary(grouping: extensions, by: \.targetName)
            .mapValues { extensions in extensions.flatMap(\.enumCases) }
        let enumDeclarationsByName = Dictionary(uniqueKeysWithValues: enumDeclarations.map { ($0.name, $0) })

        for enumeration in enumDeclarations {
            guard enumeration.genericParameters.isEmpty else {
                continue
            }
            guard layouts[enumeration.name] == nil else {
                throw LLVMEmissionError("LLVM emission requires unique enum names. Duplicate: \(enumeration.name).")
            }

            var payloadFields: [EnumPayloadField] = []
            var caseLayouts: [String: EnumCaseLayout] = [:]
            let cases = enumeration.cases + extensionCasesByTargetName[enumeration.name, default: []]
            for (index, enumCase) in cases.enumerated() {
                guard caseLayouts[enumCase.name] == nil else {
                    throw LLVMEmissionError(
                        "LLVM emission requires unique enum case names. Duplicate: \(enumeration.name).\(enumCase.name)."
                    )
                }
                var associatedValues: [EnumAssociatedValueLayout] = []
                for (associatedIndex, associatedValue) in enumCase.associatedValues.enumerated() {
                    let typeInfo = try llvmTypeInfo(
                        for: associatedValue.typeReference,
                        constructLayouts: constructLayouts,
                        enumLayouts: layouts,
                        runtime: runtime,
                        context: "enum case '\(enumeration.name).\(enumCase.name)' associated value"
                    )
                    payloadFields.append(
                        EnumPayloadField(
                            type: typeInfo.ir,
                            array: typeInfo.array,
                            nominalName: typeInfo.nominalName
                        )
                    )
                    associatedValues.append(
                        EnumAssociatedValueLayout(
                            label: associatedValue.label,
                            type: typeInfo.ir,
                            array: typeInfo.array,
                            nominalName: typeInfo.nominalName,
                            fieldIndex: payloadFields.count
                        )
                    )
                    if associatedValue.label == nil, enumCase.associatedValues.count > 1 {
                        throw LLVMEmissionError(
                            "LLVM emission requires labels for multi-payload enum case '\(enumeration.name).\(enumCase.name)' value \(associatedIndex)."
                        )
                    }
                }
                caseLayouts[enumCase.name] = EnumCaseLayout(
                    tag: index,
                    associatedValues: associatedValues
                )
            }
            layouts[enumeration.name] = EnumLayout(
                name: enumeration.name,
                storageType: payloadFields.isEmpty ? "i32" : "%\(enumeration.name)",
                payloadFields: payloadFields,
                cases: caseLayouts
            )
        }

        let genericReferences = genericEnumReferences(
            in: program,
            genericFunctionSpecializations: genericFunctionSpecializations,
            enumDeclarationsByName: enumDeclarationsByName
        )
        for reference in genericReferences.sorted(by: { $0.displayName < $1.displayName }) {
            guard case .generic(let base, let arguments) = reference,
                case .named(let enumName) = base,
                let enumeration = enumDeclarationsByName[enumName]
            else {
                continue
            }
            guard layouts[reference.displayName] == nil else {
                continue
            }
            let parameterNames = enumeration.genericParameters.compactMap { parameter -> String? in
                switch parameter {
                case .type(let name, _, _):
                    return name
                case .value:
                    return nil
                }
            }
            guard parameterNames.count == arguments.count else {
                throw LLVMEmissionError(
                    "LLVM emission requires concrete type arguments for generic enum '\(enumName)'."
                )
            }
            let substitution = Dictionary(uniqueKeysWithValues: zip(parameterNames, arguments))
            let substitutedCases = enumeration.cases.map { enumCase in
                EnumCaseShape(
                    name: enumCase.name,
                    associatedValues: enumCase.associatedValues.map { associatedValue in
                        AssociatedValueShape(
                            label: associatedValue.label,
                            typeReference: substitute(
                                associatedValue.typeReference,
                                using: substitution
                            )
                        )
                    }
                )
            }
            let layout = try enumLayout(
                name: reference.displayName,
                storageType: "%\(llvmSanitizedTypeName(reference.displayName))",
                cases: substitutedCases,
                constructLayouts: constructLayouts,
                enumLayouts: layouts,
                runtime: runtime
            )
            layouts[reference.displayName] = layout
        }

        return layouts
    }

    private func enumLayout(
        name: String,
        storageType: String,
        cases: [EnumCaseShape],
        constructLayouts: [String: ConstructLayout],
        enumLayouts: [String: EnumLayout],
        runtime: LLVMRuntime
    ) throws -> EnumLayout {
        var payloadFields: [EnumPayloadField] = []
        var caseLayouts: [String: EnumCaseLayout] = [:]
        for (index, enumCase) in cases.enumerated() {
            guard caseLayouts[enumCase.name] == nil else {
                throw LLVMEmissionError(
                    "LLVM emission requires unique enum case names. Duplicate: \(name).\(enumCase.name)."
                )
            }
            var associatedValues: [EnumAssociatedValueLayout] = []
            for (associatedIndex, associatedValue) in enumCase.associatedValues.enumerated() {
                let typeInfo = try llvmTypeInfo(
                    for: associatedValue.typeReference,
                    constructLayouts: constructLayouts,
                    enumLayouts: enumLayouts,
                    runtime: runtime,
                    context: "enum case '\(name).\(enumCase.name)' associated value"
                )
                payloadFields.append(
                    EnumPayloadField(
                        type: typeInfo.ir,
                        array: typeInfo.array,
                        nominalName: typeInfo.nominalName
                    )
                )
                associatedValues.append(
                    EnumAssociatedValueLayout(
                        label: associatedValue.label,
                        type: typeInfo.ir,
                        array: typeInfo.array,
                        nominalName: typeInfo.nominalName,
                        fieldIndex: payloadFields.count
                    )
                )
                if associatedValue.label == nil, enumCase.associatedValues.count > 1 {
                    throw LLVMEmissionError(
                        "LLVM emission requires labels for multi-payload enum case '\(name).\(enumCase.name)' value \(associatedIndex)."
                    )
                }
            }
            caseLayouts[enumCase.name] = EnumCaseLayout(
                tag: index,
                associatedValues: associatedValues
            )
        }
        return EnumLayout(
            name: name,
            storageType: payloadFields.isEmpty ? "i32" : storageType,
            payloadFields: payloadFields,
            cases: caseLayouts
        )
    }

    private func callables(in sourceFile: SourceFileNode) -> [CallableDeclaration] {
        switch sourceFile {
        case .module(let module):
            return module.callables
        default:
            return []
        }
    }

    private func constructs(in sourceFile: SourceFileNode) -> [ConstructDeclaration] {
        switch sourceFile {
        case .construct(let construct):
            return [construct]
        case .module(let module):
            return module.constructs
        default:
            return []
        }
    }

    private func enumerations(in sourceFile: SourceFileNode) -> [EnumDeclaration] {
        switch sourceFile {
        case .enumeration(let enumeration):
            return [enumeration]
        case .module(let module):
            return module.enumerations
        default:
            return []
        }
    }

    private func extensions(in sourceFile: SourceFileNode) -> [ExtensionDeclaration] {
        switch sourceFile {
        case .extensions(let extensions):
            return extensions
        case .module(let module):
            return module.extensions
        default:
            return []
        }
    }

    private func genericConstructReferences(
        in program: CompiledProgram,
        genericFunctionSpecializations: [GenericFunctionSpecialization],
        constructDeclarationsByName: [String: ConstructDeclaration]
    ) -> [TypeReference] {
        var references: [String: TypeReference] = [:]

        func record(
            _ typeReference: TypeReference?,
            using substitution: [String: TypeReference] = [:]
        ) {
            guard let typeReference else {
                return
            }
            let substitutedTypeReference = substitute(typeReference, using: substitution)
            switch substitutedTypeReference {
            case .generic(let base, let arguments):
                if case .named(let name) = base,
                    constructDeclarationsByName[name]?.genericParameters.isEmpty == false
                {
                    references[substitutedTypeReference.displayName] = substitutedTypeReference
                }
                record(base)
                arguments.forEach { record($0) }
            case .array(let element), .optional(let element), .variadic(let element):
                record(element, using: substitution)
            case .function(let parameters, let returnType):
                parameters.forEach { record($0, using: substitution) }
                record(returnType, using: substitution)
            case .member(let base, _):
                record(base, using: substitution)
            case .named:
                return
            }
        }

        func recordCallName(
            _ name: String,
            using substitution: [String: TypeReference]
        ) {
            guard name.hasSuffix(">"),
                let genericStart = topLevelGenericArgumentStart(in: name)
            else {
                return
            }
            let baseName = String(name[..<genericStart])
            guard constructDeclarationsByName[baseName]?.genericParameters.isEmpty == false else {
                return
            }
            record(parseRenderedTypeReference(name), using: substitution)
        }

        func recordExpression(
            _ expression: RangeCompiler.Expression,
            using substitution: [String: TypeReference] = [:]
        ) {
            switch expression {
            case .macroInvocation(let name, let arguments),
                .call(let name, let arguments):
                recordCallName(name, using: substitution)
                arguments.forEach { recordExpression($0.value, using: substitution) }
            case .block(let statements):
                recordStatements(statements, using: substitution)
            case .array(let elements):
                elements.forEach { recordExpression($0, using: substitution) }
            case .indexed(let base, let index):
                recordExpression(base, using: substitution)
                recordExpression(index, using: substitution)
            case .member(let base, _):
                recordExpression(base, using: substitution)
            case .dictionary(let elements):
                elements.forEach {
                    recordExpression($0.key, using: substitution)
                    recordExpression($0.value, using: substitution)
                }
            case .ternary(let condition, let trueExpression, let falseExpression):
                recordExpression(condition, using: substitution)
                recordExpression(trueExpression, using: substitution)
                recordExpression(falseExpression, using: substitution)
            case .unary(_, let expression):
                recordExpression(expression, using: substitution)
            case .binary(let lhs, _, let rhs):
                recordExpression(lhs, using: substitution)
                recordExpression(rhs, using: substitution)
            case .interpolatedString(let interpolated):
                interpolated.segments.forEach { segment in
                    if case .expression(let expression) = segment {
                        recordExpression(expression, using: substitution)
                    }
                }
            case .integer, .double, .string, .boolean, .nilLiteral, .identifier, .bindingReference:
                return
            }
        }

        func recordStatements(
            _ statements: [Statement],
            using substitution: [String: TypeReference] = [:]
        ) {
            for statement in statements {
                switch statement {
                case .localBinding(let declaration):
                    record(declaration.type, using: substitution)
                    recordExpression(declaration.expression, using: substitution)
                case .localCallable(let declaration):
                    declaration.parameters.forEach { record($0.typeReference, using: substitution) }
                    record(declaration.returnType, using: substitution)
                    recordStatements(declaration.body, using: substitution)
                case .derived(_, let typeName, let body):
                    record(.named(typeName), using: substitution)
                    recordStatements(body, using: substitution)
                case .assignment(_, let expression), .expression(let expression):
                    recordExpression(expression, using: substitution)
                case .forEach(_, let sequence, let body):
                    recordExpression(sequence, using: substitution)
                    recordStatements(body, using: substitution)
                case .whileLoop(let condition, let body):
                    recordExpression(condition, using: substitution)
                    recordStatements(body, using: substitution)
                case .conditional(let branches):
                    branches.forEach { branch in
                        if let condition = branch.condition {
                            recordExpression(condition, using: substitution)
                        }
                        recordStatements(branch.body, using: substitution)
                    }
                case .return(let expression):
                    if let expression {
                        recordExpression(expression, using: substitution)
                    }
                case .switchStatement(let expression, let cases, let defaultBody):
                    recordExpression(expression, using: substitution)
                    cases.forEach { recordStatements($0.body, using: substitution) }
                    if let defaultBody {
                        recordStatements(defaultBody, using: substitution)
                    }
                case .macroInvocation(_, _, let body):
                    recordStatements(body, using: substitution)
                case .background(let background):
                    recordStatements(background.body, using: substitution)
                case .deferBlock(let deferred):
                    recordStatements(deferred.body, using: substitution)
                case .expand, .break, .continue:
                    continue
                }
            }
        }

        for file in program.projectExpandedFiles {
            switch file.sourceFile {
            case .construct(let construct):
                guard construct.genericParameters.isEmpty else {
                    continue
                }
                construct.states.forEach { record($0.type) }
            case .enumeration(let enumeration):
                enumeration.cases.forEach { enumCase in
                    enumCase.associatedValues.forEach { record($0.typeReference) }
                }
            case .mainBlock(let mainBlock):
                recordStatements(mainBlock.body)
            case .module(let module):
                module.states.forEach { record($0.type) }
                module.callables.forEach { callable in
                    guard callable.genericParameters.isEmpty else {
                        return
                    }
                    callable.parameters.forEach { record($0.typeReference) }
                    record(callable.returnType)
                    if let body = callable.body {
                        recordStatements(body)
                    }
                }
                module.constructs.forEach { construct in
                    guard construct.genericParameters.isEmpty else {
                        return
                    }
                    construct.states.forEach { record($0.type) }
                }
                module.enumerations.forEach { enumeration in
                    enumeration.cases.forEach { enumCase in
                        enumCase.associatedValues.forEach { record($0.typeReference) }
                    }
                }
                if let mainBlock = module.mainBlock {
                    recordStatements(mainBlock.body)
                }
            case .extensions(let extensions):
                extensions.forEach { extensionDeclaration in
                    record(extensionDeclaration.targetType)
                    extensionDeclaration.callables.forEach { callable in
                        guard callable.genericParameters.isEmpty else {
                            return
                        }
                        callable.parameters.forEach { record($0.typeReference) }
                        record(callable.returnType)
                        if let body = callable.body {
                            recordStatements(body)
                        }
                    }
                    extensionDeclaration.enumCases.forEach { enumCase in
                        enumCase.associatedValues.forEach { record($0.typeReference) }
                    }
                }
            case .protocolDefinition, .macro:
                continue
            }
        }

        for specialization in genericFunctionSpecializations {
            specialization.callable.parameters.forEach {
                record($0.typeReference, using: specialization.substitution)
            }
            record(specialization.callable.returnType, using: specialization.substitution)
            if let body = specialization.callable.body {
                recordStatements(body, using: specialization.substitution)
            }
        }

        return Array(references.values)
    }

    private func genericEnumReferences(
        in program: CompiledProgram,
        genericFunctionSpecializations: [GenericFunctionSpecialization],
        enumDeclarationsByName: [String: EnumDeclaration]
    ) -> [TypeReference] {
        var references: [String: TypeReference] = [:]
        func record(
            _ typeReference: TypeReference?,
            using substitution: [String: TypeReference] = [:]
        ) {
            guard let typeReference else {
                return
            }
            let substitutedTypeReference = substitute(typeReference, using: substitution)
            switch substitutedTypeReference {
            case .generic(let base, let arguments):
                if case .named(let name) = base,
                    enumDeclarationsByName[name]?.genericParameters.isEmpty == false
                {
                    references[substitutedTypeReference.displayName] = substitutedTypeReference
                }
                record(base)
                arguments.forEach { record($0) }
            case .array(let element), .optional(let element), .variadic(let element):
                record(element, using: substitution)
            case .function(let parameters, let returnType):
                parameters.forEach { record($0, using: substitution) }
                record(returnType, using: substitution)
            case .member(let base, _):
                record(base, using: substitution)
            case .named:
                return
            }
        }
        func recordExpression(
            _ expression: RangeCompiler.Expression,
            using substitution: [String: TypeReference] = [:]
        ) {
            switch expression {
            case .macroInvocation(_, let arguments),
                .call(_, let arguments):
                arguments.forEach { recordExpression($0.value, using: substitution) }
            case .block(let statements):
                recordStatements(statements, using: substitution)
            case .array(let elements):
                elements.forEach { recordExpression($0, using: substitution) }
            case .indexed(let base, let index):
                recordExpression(base, using: substitution)
                recordExpression(index, using: substitution)
            case .member(let base, _):
                recordExpression(base, using: substitution)
            case .dictionary(let elements):
                elements.forEach {
                    recordExpression($0.key, using: substitution)
                    recordExpression($0.value, using: substitution)
                }
            case .ternary(let condition, let trueExpression, let falseExpression):
                recordExpression(condition, using: substitution)
                recordExpression(trueExpression, using: substitution)
                recordExpression(falseExpression, using: substitution)
            case .unary(_, let expression):
                recordExpression(expression, using: substitution)
            case .binary(let lhs, _, let rhs):
                recordExpression(lhs, using: substitution)
                recordExpression(rhs, using: substitution)
            case .interpolatedString(let interpolated):
                interpolated.segments.forEach { segment in
                    if case .expression(let expression) = segment {
                        recordExpression(expression, using: substitution)
                    }
                }
            case .integer, .double, .string, .boolean, .nilLiteral, .identifier, .bindingReference:
                return
            }
        }
        func recordStatements(
            _ statements: [Statement],
            using substitution: [String: TypeReference] = [:]
        ) {
            for statement in statements {
                switch statement {
                case .localBinding(let declaration):
                    record(declaration.type, using: substitution)
                    recordExpression(declaration.expression, using: substitution)
                case .localCallable(let declaration):
                    declaration.parameters.forEach { record($0.typeReference, using: substitution) }
                    record(declaration.returnType, using: substitution)
                    recordStatements(declaration.body, using: substitution)
                case .derived(_, let typeName, let body):
                    record(.named(typeName), using: substitution)
                    recordStatements(body, using: substitution)
                case .assignment(_, let expression), .expression(let expression):
                    recordExpression(expression, using: substitution)
                case .forEach(_, let sequence, let body):
                    recordExpression(sequence, using: substitution)
                    recordStatements(body, using: substitution)
                case .whileLoop(let condition, let body):
                    recordExpression(condition, using: substitution)
                    recordStatements(body, using: substitution)
                case .conditional(let branches):
                    branches.forEach { branch in
                        if let condition = branch.condition {
                            recordExpression(condition, using: substitution)
                        }
                        recordStatements(branch.body, using: substitution)
                    }
                case .return(let expression):
                    if let expression {
                        recordExpression(expression, using: substitution)
                    }
                case .switchStatement(let expression, let cases, let defaultBody):
                    recordExpression(expression, using: substitution)
                    cases.forEach { recordStatements($0.body, using: substitution) }
                    if let defaultBody {
                        recordStatements(defaultBody, using: substitution)
                    }
                case .macroInvocation(_, _, let body):
                    recordStatements(body, using: substitution)
                case .background(let background):
                    recordStatements(background.body, using: substitution)
                case .deferBlock(let deferred):
                    recordStatements(deferred.body, using: substitution)
                case .expand, .break, .continue:
                    continue
                }
            }
        }

        for file in program.projectExpandedFiles {
            switch file.sourceFile {
            case .construct(let construct):
                construct.genericParameters.forEach { _ in }
                construct.states.forEach { record($0.type) }
            case .enumeration(let enumeration):
                enumeration.cases.forEach { enumCase in
                    enumCase.associatedValues.forEach { record($0.typeReference) }
                }
            case .mainBlock(let mainBlock):
                recordStatements(mainBlock.body)
            case .module(let module):
                module.states.forEach { record($0.type) }
                module.callables.forEach { callable in
                    guard callable.genericParameters.isEmpty else {
                        return
                    }
                    callable.parameters.forEach { record($0.typeReference) }
                    record(callable.returnType)
                    if let body = callable.body {
                        recordStatements(body)
                    }
                }
                module.constructs.forEach { construct in
                    construct.states.forEach { record($0.type) }
                }
                module.enumerations.forEach { enumeration in
                    enumeration.cases.forEach { enumCase in
                        enumCase.associatedValues.forEach { record($0.typeReference) }
                    }
                }
                mainBlock: do {
                    guard let mainBlock = module.mainBlock else { break mainBlock }
                    recordStatements(mainBlock.body)
                }
            case .extensions(let extensions):
                extensions.forEach { extensionDeclaration in
                    record(extensionDeclaration.targetType)
                    extensionDeclaration.callables.forEach { callable in
                        guard callable.genericParameters.isEmpty else {
                            return
                        }
                        callable.parameters.forEach { record($0.typeReference) }
                        record(callable.returnType)
                        if let body = callable.body {
                            recordStatements(body)
                        }
                    }
                    extensionDeclaration.enumCases.forEach { enumCase in
                        enumCase.associatedValues.forEach { record($0.typeReference) }
                    }
                }
            case .protocolDefinition, .macro:
                continue
            }
        }
        for specialization in genericFunctionSpecializations {
            specialization.callable.parameters.forEach {
                record($0.typeReference, using: specialization.substitution)
            }
            record(specialization.callable.returnType, using: specialization.substitution)
            if let body = specialization.callable.body {
                recordStatements(body, using: specialization.substitution)
            }
        }
        return Array(references.values)
    }

    private func concreteGenericFunctionSpecializations(
        callables: [CallableDeclaration],
        mainBlock: MainBlockNode
    ) throws -> [GenericFunctionSpecialization] {
        let genericCallablesByName = Dictionary(
            uniqueKeysWithValues: callables
                .filter { $0.targetType == nil && !$0.genericParameters.isEmpty }
                .map { ($0.name, $0) }
        )
        var specializations: [String: GenericFunctionSpecialization] = [:]
        var pendingSpecializations: [GenericFunctionSpecialization] = []

        func specializedCallName(
            _ name: String,
            using substitution: [String: TypeReference]
        ) -> String {
            guard let reference = genericFunctionReference(from: name) else {
                return name
            }
            let arguments = reference.arguments.map { substitute($0, using: substitution) }
            return "\(reference.baseName)<\(arguments.map(\.displayName).joined(separator: ", "))>"
        }

        func recordCall(
            named name: String,
            using substitution: [String: TypeReference]
        ) throws {
            let callName = specializedCallName(name, using: substitution)
            guard let reference = genericFunctionReference(from: callName),
                let callable = genericCallablesByName[reference.baseName]
            else {
                return
            }
            let typeParameterNames = try callable.genericParameters.map { parameter in
                guard case .type(let name, _, _) = parameter else {
                    throw LLVMEmissionError(
                        "LLVM emission only supports type generic parameters for function '\(callable.name)' yet."
                    )
                }
                return name
            }
            guard typeParameterNames.count == reference.arguments.count else {
                throw LLVMEmissionError(
                    "LLVM generic function '\(callable.name)' expects \(typeParameterNames.count) type arguments, got \(reference.arguments.count)."
                )
            }
            let specializationSubstitution = Dictionary(
                uniqueKeysWithValues: zip(typeParameterNames, reference.arguments)
            )
            guard specializations[callName] == nil else {
                return
            }
            let specialization = GenericFunctionSpecialization(
                callName: callName,
                llvmName: llvmSpecializedFunctionName(
                    baseName: reference.baseName,
                    arguments: reference.arguments
                ),
                callable: callable,
                substitution: specializationSubstitution
            )
            specializations[callName] = specialization
            pendingSpecializations.append(specialization)
        }

        func recordExpression(
            _ expression: RangeCompiler.Expression,
            using substitution: [String: TypeReference]
        ) throws {
            switch expression {
            case .call(let name, let arguments), .macroInvocation(let name, let arguments):
                try recordCall(named: name, using: substitution)
                try arguments.forEach { try recordExpression($0.value, using: substitution) }
            case .block(let statements):
                try recordStatements(statements, using: substitution)
            case .array(let elements):
                try elements.forEach { try recordExpression($0, using: substitution) }
            case .indexed(let base, let index):
                try recordExpression(base, using: substitution)
                try recordExpression(index, using: substitution)
            case .member(let base, _):
                try recordExpression(base, using: substitution)
            case .dictionary(let elements):
                for element in elements {
                    try recordExpression(element.key, using: substitution)
                    try recordExpression(element.value, using: substitution)
                }
            case .ternary(let condition, let trueExpression, let falseExpression):
                try recordExpression(condition, using: substitution)
                try recordExpression(trueExpression, using: substitution)
                try recordExpression(falseExpression, using: substitution)
            case .unary(_, let expression):
                try recordExpression(expression, using: substitution)
            case .binary(let lhs, _, let rhs):
                try recordExpression(lhs, using: substitution)
                try recordExpression(rhs, using: substitution)
            case .interpolatedString(let string):
                for segment in string.segments {
                    if case .expression(let expression) = segment {
                        try recordExpression(expression, using: substitution)
                    }
                }
            case .integer, .double, .string, .boolean, .nilLiteral, .identifier,
                .bindingReference:
                return
            }
        }

        func recordStatements(
            _ statements: [Statement],
            using substitution: [String: TypeReference]
        ) throws {
            for statement in statements {
                switch statement {
                case .localBinding(let declaration):
                    try recordExpression(declaration.expression, using: substitution)
                case .assignment(_, let expression):
                    try recordExpression(expression, using: substitution)
                case .expression(let expression):
                    try recordExpression(expression, using: substitution)
                case .forEach(_, let sequence, let body):
                    try recordExpression(sequence, using: substitution)
                    try recordStatements(body, using: substitution)
                case .whileLoop(let condition, let body):
                    try recordExpression(condition, using: substitution)
                    try recordStatements(body, using: substitution)
                case .conditional(let branches):
                    for branch in branches {
                        if let condition = branch.condition {
                            try recordExpression(condition, using: substitution)
                        }
                        try recordStatements(branch.body, using: substitution)
                    }
                case .return(let expression):
                    if let expression {
                        try recordExpression(expression, using: substitution)
                    }
                case .switchStatement(let expression, let cases, let defaultBody):
                    try recordExpression(expression, using: substitution)
                    for switchCase in cases {
                        if case .expression(let expression) = switchCase.pattern {
                            try recordExpression(expression, using: substitution)
                        }
                        try recordStatements(switchCase.body, using: substitution)
                    }
                    if let defaultBody {
                        try recordStatements(defaultBody, using: substitution)
                    }
                case .macroInvocation, .expand, .background, .deferBlock, .localCallable,
                    .derived, .break, .continue:
                    continue
                }
            }
        }

        try recordStatements(mainBlock.body, using: [:])
        for callable in callables where callable.genericParameters.isEmpty {
            if let body = callable.body {
                try recordStatements(body, using: [:])
            }
        }

        var pendingIndex = 0
        while pendingIndex < pendingSpecializations.count {
            let specialization = pendingSpecializations[pendingIndex]
            if let body = specialization.callable.body {
                try recordStatements(body, using: specialization.substitution)
            }
            pendingIndex += 1
        }

        return Array(specializations.values)
    }

    private func substitute(
        _ typeReference: TypeReference,
        using substitution: [String: TypeReference]
    ) -> TypeReference {
        switch typeReference {
        case .named(let name):
            return substitution[name] ?? typeReference
        case .member(let base, let name):
            return .member(base: substitute(base, using: substitution), name: name)
        case .generic(let base, let arguments):
            return .generic(
                base: substitute(base, using: substitution),
                arguments: arguments.map { substitute($0, using: substitution) }
            )
        case .array(let element):
            return .array(substitute(element, using: substitution))
        case .function(let parameters, let returnType):
            return .function(
                parameters: parameters.map { substitute($0, using: substitution) },
                returnType: substitute(returnType, using: substitution)
            )
        case .optional(let wrapped):
            return .optional(substitute(wrapped, using: substitution))
        case .variadic(let element):
            return .variadic(substitute(element, using: substitution))
        }
    }

    private func genericFunctionReference(from name: String) -> (
        baseName: String, arguments: [TypeReference]
    )? {
        guard name.hasSuffix(">"),
            let genericStart = topLevelGenericArgumentStart(in: name)
        else {
            return nil
        }
        let baseName = String(name[..<genericStart])
        let rawArguments = String(name[name.index(after: genericStart)..<name.index(before: name.endIndex)])
        let arguments = splitTopLevelCommaList(rawArguments).map(parseRenderedTypeReference)
        return (baseName, arguments)
    }

    private func topLevelGenericArgumentStart(in name: String) -> String.Index? {
        var depth = 0
        var candidate: String.Index?
        for index in name.indices {
            switch name[index] {
            case "<":
                if depth == 0 {
                    candidate = index
                }
                depth += 1
            case ">":
                depth -= 1
                if depth == 0 && name.index(after: index) != name.endIndex {
                    candidate = nil
                }
            default:
                continue
            }
        }
        return depth == 0 ? candidate : nil
    }

    private func splitTopLevelCommaList(_ raw: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var angleDepth = 0
        var bracketDepth = 0
        var parenDepth = 0
        for character in raw {
            switch character {
            case "<":
                angleDepth += 1
                current.append(character)
            case ">":
                angleDepth -= 1
                current.append(character)
            case "[":
                bracketDepth += 1
                current.append(character)
            case "]":
                bracketDepth -= 1
                current.append(character)
            case "(":
                parenDepth += 1
                current.append(character)
            case ")":
                parenDepth -= 1
                current.append(character)
            case "," where angleDepth == 0 && bracketDepth == 0 && parenDepth == 0:
                parts.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
                current = ""
            default:
                current.append(character)
            }
        }
        let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            parts.append(trimmed)
        }
        return parts
    }

    private func parseRenderedTypeReference(_ raw: String) -> TypeReference {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("["), trimmed.hasSuffix("]") {
            return .array(parseRenderedTypeReference(String(trimmed.dropFirst().dropLast())))
        }
        if trimmed.hasSuffix("?") {
            return .optional(parseRenderedTypeReference(String(trimmed.dropLast())))
        }
        if trimmed.hasSuffix(">"),
            let genericStart = topLevelGenericArgumentStart(in: trimmed)
        {
            let base = parseRenderedTypeReference(String(trimmed[..<genericStart]))
            let rawArguments = String(
                trimmed[trimmed.index(after: genericStart)..<trimmed.index(before: trimmed.endIndex)]
            )
            return .generic(
                base: base,
                arguments: splitTopLevelCommaList(rawArguments).map(parseRenderedTypeReference)
            )
        }
        return .named(trimmed)
    }

    private func llvmSpecializedFunctionName(
        baseName: String,
        arguments: [TypeReference]
    ) -> String {
        ([baseName] + arguments.map(\.displayName))
            .map(llvmSanitizedTypeName)
            .joined(separator: "__")
    }

    private func functionSignatures(
        for callables: [CallableDeclaration],
        genericFunctionSpecializations: [GenericFunctionSpecialization],
        constructLayouts: [String: ConstructLayout],
        enumLayouts: [String: EnumLayout],
        runtime: LLVMRuntime
    ) throws
        -> [String: FunctionSignature]
    {
        var signatures: [String: FunctionSignature] = [:]

        for callable in callables {
            guard callable.targetType == nil else {
                continue
            }
            guard callable.genericParameters.isEmpty else {
                continue
            }
            guard signatures[callable.name] == nil else {
                throw LLVMEmissionError("LLVM emission requires unique function names. Duplicate: \(callable.name).")
            }

            let parameters = try callable.parameters.map { parameter in
                let typeReference = parameter.typeReference
                return FunctionParameterSignature(
                    name: parameter.localName,
                    externalLabel: parameter.externalLabel,
                    typeReference: typeReference,
                    defaultValue: parameter.defaultValue,
                    type: try llvmTypeInfo(
                        for: typeReference,
                        constructLayouts: constructLayouts,
                        enumLayouts: enumLayouts,
                        runtime: runtime,
                        context: "parameter '\(parameter.localName)'"
                    )
                )
            }
            let returnType = try llvmReturnType(
                for: callable.returnType,
                constructLayouts: constructLayouts,
                enumLayouts: enumLayouts,
                runtime: runtime
            )
            signatures[callable.name] = FunctionSignature(
                name: callable.name,
                parameters: parameters,
                returnTypeReference: callable.returnType,
                returnType: returnType
            )
        }

        for specialization in genericFunctionSpecializations {
            guard signatures[specialization.callName] == nil else {
                continue
            }
            let callable = specialization.callable
            let parameters = try callable.parameters.map { parameter in
                let typeReference = parameter.typeReference.map {
                    substitute($0, using: specialization.substitution)
                }
                return FunctionParameterSignature(
                    name: parameter.localName,
                    externalLabel: parameter.externalLabel,
                    typeReference: typeReference,
                    defaultValue: parameter.defaultValue,
                    type: try llvmTypeInfo(
                        for: typeReference,
                        constructLayouts: constructLayouts,
                        enumLayouts: enumLayouts,
                        runtime: runtime,
                        context: "parameter '\(parameter.localName)'"
                    )
                )
            }
            let returnType = try llvmReturnType(
                for: callable.returnType.map {
                    substitute($0, using: specialization.substitution)
                },
                constructLayouts: constructLayouts,
                enumLayouts: enumLayouts,
                runtime: runtime
            )
            signatures[specialization.callName] = FunctionSignature(
                name: specialization.llvmName,
                parameters: parameters,
                returnTypeReference: callable.returnType.map {
                    substitute($0, using: specialization.substitution)
                },
                returnType: returnType
            )
        }

        return signatures
    }

    private func llvmReturnType(
        for typeReference: TypeReference?,
        constructLayouts: [String: ConstructLayout],
        enumLayouts: [String: EnumLayout],
        runtime: LLVMRuntime
    ) throws -> LLVMType {
        guard let typeReference else {
            return LLVMType(ir: "void", array: nil)
        }
        return try llvmTypeInfo(
            for: typeReference,
            constructLayouts: constructLayouts,
            enumLayouts: enumLayouts,
            runtime: runtime,
            context: "function return"
        )
    }

    private func llvmType(
        for typeReference: TypeReference?,
        constructLayouts: [String: ConstructLayout],
        enumLayouts: [String: EnumLayout] = [:],
        knownEnumStorageTypes: [String: String] = [:],
        knownConstructNames: Set<String> = [],
        runtime: LLVMRuntime,
        context: String
    ) throws -> String {
        try llvmTypeInfo(
            for: typeReference,
            constructLayouts: constructLayouts,
            enumLayouts: enumLayouts,
            knownEnumStorageTypes: knownEnumStorageTypes,
            knownConstructNames: knownConstructNames,
            runtime: runtime,
            context: context
        ).ir
    }

    private func llvmTypeInfo(
        for typeReference: TypeReference?,
        constructLayouts: [String: ConstructLayout],
        enumLayouts: [String: EnumLayout] = [:],
        knownEnumStorageTypes: [String: String] = [:],
        knownConstructNames: Set<String> = [],
        runtime: LLVMRuntime,
        context: String
    ) throws -> LLVMType {
        guard let typeReference else {
            throw LLVMEmissionError("LLVM emission requires an explicit type for \(context).")
        }
        switch typeReference {
        case .array(let element):
            let elementType = try llvmTypeInfo(
                for: element,
                constructLayouts: constructLayouts,
                enumLayouts: enumLayouts,
                knownEnumStorageTypes: knownEnumStorageTypes,
                knownConstructNames: knownConstructNames,
                runtime: runtime,
                context: "\(context) array element"
            )
            runtime.registerArray(elementType: elementType.ir)
            return LLVMType(
                ir: LLVMRuntime.arrayTypeName(for: elementType.ir),
                array: ArrayLayout(elementType: elementType.ir, count: nil),
                nominalName: nil
            )
        case .optional(let wrapped):
            let wrappedType = try llvmTypeInfo(
                for: wrapped,
                constructLayouts: constructLayouts,
                enumLayouts: enumLayouts,
                knownEnumStorageTypes: knownEnumStorageTypes,
                knownConstructNames: knownConstructNames,
                runtime: runtime,
                context: "\(context) optional wrapped value"
            )
            runtime.registerOptional(wrappedType: wrappedType.ir)
            return LLVMType(
                ir: LLVMRuntime.optionalTypeName(for: wrappedType.ir),
                array: nil,
                optional: OptionalLayout(wrappedType: wrappedType.ir),
                nominalName: nil
            )
        default:
            return try llvmTypeInfo(
                named: typeReference.displayName,
                constructLayouts: constructLayouts,
                enumLayouts: enumLayouts,
                knownEnumStorageTypes: knownEnumStorageTypes,
                knownConstructNames: knownConstructNames,
                context: context
            )
        }
    }

    private func llvmType(
        named typeName: String,
        constructLayouts: [String: ConstructLayout] = [:],
        enumLayouts: [String: EnumLayout] = [:],
        knownEnumStorageTypes: [String: String] = [:],
        knownConstructNames: Set<String> = [],
        context: String
    ) throws -> String {
        try llvmTypeInfo(
            named: typeName,
            constructLayouts: constructLayouts,
            enumLayouts: enumLayouts,
            knownEnumStorageTypes: knownEnumStorageTypes,
            knownConstructNames: knownConstructNames,
            context: context
        ).ir
    }

    private func llvmTypeInfo(
        renderedTypeName typeName: String,
        constructLayouts: [String: ConstructLayout] = [:],
        enumLayouts: [String: EnumLayout] = [:],
        knownEnumStorageTypes: [String: String] = [:],
        knownConstructNames: Set<String> = [],
        runtime: LLVMRuntime,
        context: String
    ) throws -> LLVMType {
        let trimmed = typeName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("["), trimmed.hasSuffix("]") {
            let inner = String(trimmed.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
            let elementType = try llvmTypeInfo(
                renderedTypeName: inner,
                constructLayouts: constructLayouts,
                enumLayouts: enumLayouts,
                knownEnumStorageTypes: knownEnumStorageTypes,
                knownConstructNames: knownConstructNames,
                runtime: runtime,
                context: "\(context) array element"
            )
            runtime.registerArray(elementType: elementType.ir)
            return LLVMType(
                ir: LLVMRuntime.arrayTypeName(for: elementType.ir),
                array: ArrayLayout(elementType: elementType.ir, count: nil),
                nominalName: nil
            )
        }
        if trimmed.hasSuffix("?") {
            let wrapped = try llvmTypeInfo(
                renderedTypeName: String(trimmed.dropLast()),
                constructLayouts: constructLayouts,
                enumLayouts: enumLayouts,
                knownEnumStorageTypes: knownEnumStorageTypes,
                knownConstructNames: knownConstructNames,
                runtime: runtime,
                context: "\(context) optional wrapped value"
            )
            runtime.registerOptional(wrappedType: wrapped.ir)
            return LLVMType(
                ir: LLVMRuntime.optionalTypeName(for: wrapped.ir),
                array: nil,
                optional: OptionalLayout(wrappedType: wrapped.ir),
                nominalName: nil
            )
        }
        return try llvmTypeInfo(
            named: trimmed,
            constructLayouts: constructLayouts,
            enumLayouts: enumLayouts,
            knownEnumStorageTypes: knownEnumStorageTypes,
            knownConstructNames: knownConstructNames,
            context: context
        )
    }

    private func llvmTypeInfo(
        named typeName: String,
        constructLayouts: [String: ConstructLayout] = [:],
        enumLayouts: [String: EnumLayout] = [:],
        knownEnumStorageTypes: [String: String] = [:],
        knownConstructNames: Set<String> = [],
        context: String
    ) throws -> LLVMType {
        switch typeName {
        case "Int":
            return LLVMType(ir: "i32", array: nil, nominalName: nil)
        case "Float":
            return LLVMType(ir: "double", array: nil, nominalName: nil)
        case "Bool":
            return LLVMType(ir: "i1", array: nil, nominalName: nil)
        case "String":
            return LLVMType(ir: "ptr", array: nil, nominalName: nil)
        case "Void":
            return LLVMType(ir: "void", array: nil, nominalName: nil)
        default:
            if let enumLayout = enumLayouts[typeName] {
                return LLVMType(ir: enumLayout.storageType, array: nil, nominalName: typeName)
            }
            if let enumStorageType = knownEnumStorageTypes[typeName] {
                return LLVMType(ir: enumStorageType, array: nil, nominalName: typeName)
            }
            if let constructLayout = constructLayouts[typeName] {
                return LLVMType(ir: constructLayout.storageType, array: nil, nominalName: typeName)
            }
            if knownConstructNames.contains(typeName) {
                return LLVMType(ir: "%\(typeName)", array: nil, nominalName: typeName)
            }
            throw LLVMEmissionError("LLVM emission does not support \(context) type '\(typeName)' yet.")
        }
    }

    private func llvmSanitizedTypeName(_ type: String) -> String {
        type.unicodeScalars.map { scalar in
            CharacterSet.alphanumerics.contains(scalar) ? String(scalar) : "_"
        }.joined()
    }

    private struct LLVMType {
        let ir: String
        let array: ArrayLayout?
        let optional: OptionalLayout?
        let nominalName: String?

        init(
            ir: String,
            array: ArrayLayout?,
            optional: OptionalLayout? = nil,
            nominalName: String? = nil
        ) {
            self.ir = ir
            self.array = array
            self.optional = optional
            self.nominalName = nominalName
        }
    }

    private struct ArrayLayout: Equatable {
        let elementType: String
        let count: Int?
    }

    private struct OptionalLayout: Equatable {
        let wrappedType: String
    }

    private struct ConstructLayout {
        let name: String
        let storageType: String
        let fields: [ConstructField]

        func field(named name: String) -> (index: Int, field: ConstructField)? {
            guard let index = fields.firstIndex(where: { $0.name == name }) else {
                return nil
            }
            return (index, fields[index])
        }
    }

    private struct ConstructField {
        let name: String
        let type: String
        let typeReference: TypeReference
        let defaultValue: RangeCompiler.Expression?
    }

    private struct EnumCaseShape {
        let name: String
        let associatedValues: [AssociatedValueShape]
    }

    private struct AssociatedValueShape {
        let label: String?
        let typeReference: TypeReference
    }

    private struct EnumLayout {
        let name: String
        let storageType: String
        let payloadFields: [EnumPayloadField]
        let cases: [String: EnumCaseLayout]

        var hasPayload: Bool {
            !payloadFields.isEmpty
        }

        func tag(for caseName: String) -> Int? {
            cases[caseName]?.tag
        }
    }

    private struct EnumPayloadField {
        let type: String
        let array: ArrayLayout?
        let nominalName: String?
    }

    private struct EnumCaseLayout {
        let tag: Int
        let associatedValues: [EnumAssociatedValueLayout]
    }

    private struct EnumAssociatedValueLayout {
        let label: String?
        let type: String
        let array: ArrayLayout?
        let nominalName: String?
        let fieldIndex: Int
    }

    private struct FunctionSignature {
        let name: String
        let parameters: [FunctionParameterSignature]
        let returnTypeReference: TypeReference?
        let returnType: LLVMType
    }

    private struct GenericFunctionSpecialization {
        let callName: String
        let llvmName: String
        let callable: CallableDeclaration
        let substitution: [String: TypeReference]
    }

    private struct FunctionParameterSignature {
        let name: String
        let externalLabel: String?
        let typeReference: TypeReference?
        let defaultValue: RangeCompiler.Expression?
        let type: LLVMType
    }

    private final class LLVMRuntime {
        private var stringGlobals: [(name: String, bytes: [UInt8])] = []
        private var stringGlobalsByValue: [String: String] = [:]
        private var arrayElementTypes: Set<String> = []
        private var optionalWrappedTypesByStorageType: [String: String] = [:]
        private(set) var usesPuts = false
        private(set) var usesPrintf = false
        private(set) var usesSnprintf = false
        private(set) var usesMalloc = false
        private(set) var usesMemcpy = false
        private(set) var usesAccess = false
        private(set) var usesFileRead = false
        private(set) var usesFileWrite = false
        private(set) var usesStrlen = false
        private(set) var usesStrcmp = false
        private(set) var usesRead = false
        private(set) var usesCommandLineArguments = false

        static func arrayTypeName(for elementType: String) -> String {
            "%Range.Array.\(sanitizedTypeName(elementType))"
        }

        static func optionalTypeName(for wrappedType: String) -> String {
            "%Range.Optional.\(sanitizedTypeName(wrappedType))"
        }

        func stringPointer(for value: String) -> String {
            if let existing = stringGlobalsByValue[value] {
                return stringPointer(globalName: existing, byteCount: Array(value.utf8).count + 1)
            }

            let globalName = ".str.\(stringGlobals.count)"
            let bytes = Array(value.utf8) + [0]
            stringGlobalsByValue[value] = globalName
            stringGlobals.append((name: globalName, bytes: bytes))
            return stringPointer(globalName: globalName, byteCount: bytes.count)
        }

        func markUsesPuts() {
            usesPuts = true
        }

        func markUsesPrintf() {
            usesPrintf = true
        }

        func markUsesSnprintf() {
            usesSnprintf = true
            usesMalloc = true
        }

        func markUsesMalloc() {
            usesMalloc = true
        }

        func markUsesMemcpy() {
            usesMemcpy = true
        }

        func markUsesAccess() {
            usesAccess = true
        }

        func markUsesFileRead() {
            usesFileRead = true
            usesMalloc = true
        }

        func markUsesFileWrite() {
            usesFileWrite = true
            usesStrlen = true
        }

        func markUsesRead() {
            usesRead = true
            usesMalloc = true
        }

        func markUsesCommandLineArguments() {
            usesCommandLineArguments = true
        }

        func markUsesStrlen() {
            usesStrlen = true
        }

        func markUsesStrcmp() {
            usesStrcmp = true
        }

        func registerArray(elementType: String) {
            arrayElementTypes.insert(elementType)
        }

        func registerOptional(wrappedType: String) {
            optionalWrappedTypesByStorageType[Self.optionalTypeName(for: wrappedType)] = wrappedType
        }

        func optionalWrappedType(forStorageType storageType: String) -> String? {
            optionalWrappedTypesByStorageType[storageType]
        }

        var optionalStorageTypes: [String] {
            Array(optionalWrappedTypesByStorageType.keys)
        }

        func render() -> String {
            var lines: [String] = []
            for storageType in optionalWrappedTypesByStorageType.keys.sorted() {
                guard let wrappedType = optionalWrappedTypesByStorageType[storageType] else {
                    continue
                }
                lines.append("\(storageType) = type { i1, \(wrappedType) }")
            }
            for elementType in arrayElementTypes.sorted() {
                lines.append("\(Self.arrayTypeName(for: elementType)) = type { i32, ptr }")
            }
            for stringGlobal in stringGlobals {
                lines.append(
                    "@\(stringGlobal.name) = private unnamed_addr constant [\(stringGlobal.bytes.count) x i8] c\"\(llvmEscapedBytes(stringGlobal.bytes))\""
                )
            }
            if usesPuts {
                lines.append("declare i32 @puts(ptr)")
            }
            if usesPrintf {
                lines.append("declare i32 @printf(ptr, ...)")
            }
            if usesSnprintf {
                lines.append("declare i32 @snprintf(ptr, i64, ptr, ...)")
            }
            if usesMalloc {
                lines.append("declare ptr @malloc(i64)")
            }
            if usesMemcpy {
                lines.append("declare void @llvm.memcpy.p0.p0.i64(ptr, ptr, i64, i1)")
            }
            if usesAccess {
                lines.append("declare i32 @access(ptr, i32)")
            }
            if usesFileRead {
                lines.append("declare ptr @fopen(ptr, ptr)")
                lines.append("declare i32 @fseek(ptr, i64, i32)")
                lines.append("declare i64 @ftell(ptr)")
                lines.append("declare void @rewind(ptr)")
                lines.append("declare i64 @fread(ptr, i64, i64, ptr)")
                lines.append("declare i32 @fclose(ptr)")
            }
            if usesFileWrite {
                if !usesFileRead {
                    lines.append("declare ptr @fopen(ptr, ptr)")
                    lines.append("declare i32 @fclose(ptr)")
                }
            }
            if usesStrlen {
                lines.append("declare i64 @strlen(ptr)")
            }
            if usesStrcmp {
                lines.append("declare i32 @strcmp(ptr, ptr)")
            }
            if usesFileWrite {
                lines.append("declare i64 @fwrite(ptr, i64, i64, ptr)")
            }
            if usesRead {
                lines.append("declare i64 @read(i32, ptr, i64)")
            }
            if usesCommandLineArguments {
                lines.append("declare ptr @_NSGetArgc()")
                lines.append("declare ptr @_NSGetArgv()")
            }
            guard !lines.isEmpty else {
                return ""
            }
            return lines.joined(separator: "\n") + "\n"
        }

        private func stringPointer(globalName: String, byteCount: Int) -> String {
            "getelementptr inbounds ([\(byteCount) x i8], ptr @\(globalName), i32 0, i32 0)"
        }

        private func llvmEscapedBytes(_ bytes: [UInt8]) -> String {
            bytes.map { byte in
                "\\\(String(format: "%02X", byte))"
            }.joined()
        }

        private static func sanitizedTypeName(_ type: String) -> String {
            type.unicodeScalars.map { scalar in
                CharacterSet.alphanumerics.contains(scalar) ? String(scalar) : "_"
            }.joined()
        }
    }

    private struct FunctionEmitter {
        private struct LLVMValue {
            let type: String
            let operand: String
            let array: ArrayLayout?
            let optional: OptionalLayout?
            let nominalName: String?

            init(
                type: String,
                operand: String,
                array: ArrayLayout?,
                optional: OptionalLayout? = nil,
                nominalName: String? = nil
            ) {
                self.type = type
                self.operand = operand
                self.array = array
                self.optional = optional
                self.nominalName = nominalName
            }
        }

        private struct LocalSlot {
            let pointer: String
            let type: String
            let array: ArrayLayout?
            let optional: OptionalLayout?
            let nominalName: String?

            init(
                pointer: String,
                type: String,
                array: ArrayLayout?,
                optional: OptionalLayout? = nil,
                nominalName: String? = nil
            ) {
                self.pointer = pointer
                self.type = type
                self.array = array
                self.optional = optional
                self.nominalName = nominalName
            }
        }

        private let signatures: [String: FunctionSignature]
        private let constructLayouts: [String: ConstructLayout]
        private let enumLayouts: [String: EnumLayout]
        private let runtime: LLVMRuntime
        private var instructions: [String] = []
        private var locals: [String: LocalSlot] = [:]
        private var temporaryIndex = 0
        private var labelIndex = 0
        private var returned = false
        private var blockTerminated = false
        private var loopStack: [(breakLabel: String, continueLabel: String)] = []
        private var currentReturnType = "i32"
        private var currentReturnTypeReference: TypeReference?
        private var currentReturnNominalName: String?
        private var genericSubstitution: [String: TypeReference] = [:]
        private var deferredBlocks: [[Statement]] = []
        private var isEmittingDeferredBlock = false
        private var nestedStatementDepth = 0

        init(
            signatures: [String: FunctionSignature],
            constructLayouts: [String: ConstructLayout],
            enumLayouts: [String: EnumLayout],
            runtime: LLVMRuntime
        ) {
            self.signatures = signatures
            self.constructLayouts = constructLayouts
            self.enumLayouts = enumLayouts
            self.runtime = runtime
        }

        mutating func emitMain(mainBlock: MainBlockNode) throws -> String {
            currentReturnType = "i32"
            currentReturnTypeReference = .named("Int")
            currentReturnNominalName = nil
            for statement in mainBlock.body {
                try emit(statement: statement)
                if returned || blockTerminated {
                    break
                }
            }

            if !returned {
                try emitDeferredBlocks()
                instructions.append("ret i32 0")
            }

            return renderFunction(name: "main", returnType: "i32", parameters: [])
        }

        mutating func emit(callable: CallableDeclaration) throws -> String {
            guard let signature = signatures[callable.name] else {
                throw LLVMEmissionError("Missing LLVM function signature for '\(callable.name)'.")
            }
            return try emit(callable: callable, signature: signature, signatureName: callable.name)
        }

        mutating func emit(specialization: GenericFunctionSpecialization) throws -> String {
            guard let signature = signatures[specialization.callName] else {
                throw LLVMEmissionError("Missing LLVM function signature for '\(specialization.callName)'.")
            }
            genericSubstitution = specialization.substitution
            defer { genericSubstitution = [:] }
            return try emit(
                callable: specialization.callable,
                signature: signature,
                signatureName: specialization.callName
            )
        }

        private mutating func emit(
            callable: CallableDeclaration,
            signature: FunctionSignature,
            signatureName: String
        ) throws -> String {
            guard let body = callable.body else {
                throw LLVMEmissionError("LLVM function '\(signatureName)' requires a body.")
            }
            currentReturnType = signature.returnType.ir
            currentReturnTypeReference = signature.returnTypeReference
            currentReturnNominalName = signature.returnType.nominalName

            var renderedParameters: [String] = []
            for parameter in signature.parameters {
                let pointer = try declareLocal(
                    named: parameter.name,
                    type: parameter.type.ir,
                    array: parameter.type.array,
                    optional: parameter.type.optional,
                    nominalName: parameter.type.nominalName
                )
                let parameterName = try llvmIdentifier(parameter.name)
                renderedParameters.append("\(parameter.type.ir) %\(parameterName).arg")
                instructions.append(
                    "store \(parameter.type.ir) %\(parameterName).arg, ptr \(pointer)"
                )
            }

            for statement in body {
                try emit(statement: statement)
                if returned || blockTerminated {
                    break
                }
            }

            if !returned {
                try emitDeferredBlocks()
                switch signature.returnType.ir {
                case "void":
                    instructions.append("ret void")
                case "i1":
                    instructions.append("ret i1 0")
                case "i32":
                    instructions.append("ret \(signature.returnType.ir) 0")
                case "double":
                    instructions.append("ret double 0.0")
                default:
                    throw LLVMEmissionError("LLVM function '\(signatureName)' must explicitly return \(signature.returnType.ir).")
                }
            }

            return renderFunction(
                name: signature.name,
                returnType: signature.returnType.ir,
                parameters: renderedParameters
            )
        }

        private mutating func emit(statement: Statement) throws {
            switch statement {
            case .localBinding(let declaration):
                let substitutedType = substituted(declaration.type)
                let expectedEnumName = enumName(for: substitutedType)
                let expectedArrayElementEnumName = arrayElementEnumName(for: substitutedType)
                let expectedArrayElementType = try arrayElementType(for: substitutedType)
                let value: LLVMValue
                if let optionalContext = try optionalContext(for: substitutedType) {
                    value = try emitOptionalValue(
                        from: declaration.expression,
                        optionalType: optionalContext.optional,
                        wrappedType: optionalContext.wrapped,
                        wrappedReference: optionalContext.wrappedReference
                    )
                } else {
                    value = try emitValue(
                        from: declaration.expression,
                        expectedEnumName: expectedEnumName,
                        expectedArrayElementEnumName: expectedArrayElementEnumName,
                        expectedArrayElementType: expectedArrayElementType
                    )
                }
                let pointer = try declareLocal(
                    named: declaration.name,
                    type: value.type,
                    array: value.array,
                    optional: value.optional,
                    nominalName: value.nominalName
                )
                instructions.append("store \(value.type) \(value.operand), ptr \(pointer)")

            case .assignment(let target, let expression):
                try emitAssignment(to: target, expression: expression)

            case .return(let expression):
                guard let expression else {
                    guard currentReturnType == "void" else {
                        throw LLVMEmissionError("LLVM return requires a value for \(currentReturnType) functions.")
                    }
                    try emitDeferredBlocks()
                    instructions.append("ret void")
                    returned = true
                    blockTerminated = true
                    return
                }
                let value: LLVMValue
                if let currentReturnTypeReference,
                    let optionalContext = try optionalContext(for: currentReturnTypeReference)
                {
                    value = try emitOptionalValue(
                        from: expression,
                        optionalType: optionalContext.optional,
                        wrappedType: optionalContext.wrapped,
                        wrappedReference: optionalContext.wrappedReference
                    )
                } else {
                    let expectedArrayElementType = try arrayElementType(for: currentReturnTypeReference)
                    value = try emitValue(
                        from: expression,
                        expectedEnumName: currentReturnNominalName,
                        expectedArrayElementType: expectedArrayElementType
                    )
                }
                let returnValue = try emitReturnValue(value)
                try emitDeferredBlocks()
                instructions.append("ret \(returnValue.type) \(returnValue.operand)")
                returned = true
                blockTerminated = true
            
            case .deferBlock(let deferred):
                guard !isEmittingDeferredBlock else {
                    throw LLVMEmissionError("LLVM defer blocks cannot contain nested defer blocks.")
                }
                guard nestedStatementDepth == 0 else {
                    throw LLVMEmissionError("LLVM defer blocks are currently supported only at function body scope.")
                }
                try validateDeferredBody(deferred.body)
                deferredBlocks.append(deferred.body)

            case .conditional(let branches):
                try emitConditional(branches)

            case .whileLoop(let condition, let body):
                try emitWhileLoop(condition: condition, body: body)

            case .forEach(let name, let sequence, let body):
                try emitForEach(name: name, sequence: sequence, body: body)

            case .switchStatement(let expression, let cases, let defaultBody):
                try emitSwitch(expression: expression, cases: cases, defaultBody: defaultBody)

            case .break:
                guard let loop = loopStack.last else {
                    throw LLVMEmissionError("LLVM break requires an enclosing loop.")
                }
                instructions.append("br label %\(loop.breakLabel)")
                blockTerminated = true

            case .continue:
                guard let loop = loopStack.last else {
                    throw LLVMEmissionError("LLVM continue requires an enclosing loop.")
                }
                instructions.append("br label %\(loop.continueLabel)")
                blockTerminated = true

            case .expression(let expression):
                try emitExpressionStatement(expression)

            default:
                throw LLVMEmissionError(
                    "LLVM emission currently supports locals, assignment, defer, control flow, calls, and returns."
                )
            }
        }

        private mutating func emitDeferredBlocks() throws {
            guard !deferredBlocks.isEmpty else {
                return
            }

            let blocks = Array(deferredBlocks.reversed())
            deferredBlocks.removeAll()

            let outerIsEmittingDeferredBlock = isEmittingDeferredBlock
            isEmittingDeferredBlock = true
            defer { isEmittingDeferredBlock = outerIsEmittingDeferredBlock }

            for block in blocks {
                let terminated = try emitNestedStatements(block)
                if terminated {
                    throw LLVMEmissionError("LLVM defer blocks cannot terminate control flow.")
                }
            }
        }

        private func validateDeferredBody(_ statements: [Statement]) throws {
            for statement in statements {
                switch statement {
                case .return:
                    throw LLVMEmissionError("LLVM defer blocks cannot return.")
                case .break:
                    throw LLVMEmissionError("LLVM defer blocks cannot break.")
                case .continue:
                    throw LLVMEmissionError("LLVM defer blocks cannot continue.")
                case .deferBlock:
                    throw LLVMEmissionError("LLVM defer blocks cannot contain nested defer blocks.")
                case .conditional(let branches):
                    for branch in branches {
                        try validateDeferredBody(branch.body)
                    }
                case .whileLoop(_, let body), .forEach(_, _, let body):
                    try validateDeferredBody(body)
                case .switchStatement(_, let cases, let defaultBody):
                    for switchCase in cases {
                        try validateDeferredBody(switchCase.body)
                    }
                    if let defaultBody {
                        try validateDeferredBody(defaultBody)
                    }
                case .background(let background):
                    try validateDeferredBody(background.body)
                case .macroInvocation(_, _, let body):
                    try validateDeferredBody(body)
                case .localBinding, .localCallable, .derived, .assignment, .expression, .expand:
                    continue
                }
            }
        }

        private mutating func emitConditional(_ branches: [StatementConditionalBranch]) throws {
            guard !branches.isEmpty else {
                return
            }

            let endLabel = nextLabel("if.end")
            let branchLabels = branches.map { _ in nextLabel("if.then") }
            let checkLabels = branches.indices.map { index -> String? in
                index == 0 || branches[index].condition == nil ? nil : nextLabel("if.check")
            }
            let hasElseBranch = branches.contains { $0.condition == nil }

            for index in branches.indices {
                let branch = branches[index]
                let branchLabel = branchLabels[index]
                let nextTarget = conditionalFallthroughLabel(
                    after: index,
                    branches: branches,
                    branchLabels: branchLabels,
                    checkLabels: checkLabels,
                    endLabel: endLabel
                )

                if let checkLabel = checkLabels[index] {
                    instructions.append("\(checkLabel):")
                }

                if let condition = branch.condition {
                    let conditionValue = try emitCondition(from: condition)
                    instructions.append(
                        "br i1 \(conditionValue), label %\(branchLabel), label %\(nextTarget)"
                    )
                } else if index == 0 {
                    instructions.append("br label %\(branchLabel)")
                }

                instructions.append("\(branchLabel):")
                let branchReturned = try emitNestedStatements(branch.body)
                if !branchReturned {
                    instructions.append("br label %\(endLabel)")
                }
            }

            if !hasElseBranch {
                instructions.append("\(endLabel):")
                returned = false
                return
            }

            let allBranchesReturned = branches.allSatisfy { branch in
                branch.body.contains { statement in
                    if case .return = statement {
                        return true
                    }
                    return false
                }
            }

            if allBranchesReturned {
                returned = true
                blockTerminated = true
            } else {
                instructions.append("\(endLabel):")
                returned = false
                blockTerminated = false
            }
        }

        private func conditionalFallthroughLabel(
            after index: Int,
            branches: [StatementConditionalBranch],
            branchLabels: [String],
            checkLabels: [String?],
            endLabel: String
        ) -> String {
            let nextIndex = index + 1
            guard nextIndex < branches.count else {
                return endLabel
            }
            if branches[nextIndex].condition == nil {
                return branchLabels[nextIndex]
            }
            return checkLabels[nextIndex] ?? branchLabels[nextIndex]
        }

        private mutating func emitNestedStatements(_ statements: [Statement]) throws -> Bool {
            let outerReturned = returned
            let outerBlockTerminated = blockTerminated
            let outerNestedStatementDepth = nestedStatementDepth
            returned = false
            blockTerminated = false
            nestedStatementDepth += 1
            defer { nestedStatementDepth = outerNestedStatementDepth }
            for statement in statements {
                try emit(statement: statement)
                if returned || blockTerminated {
                    break
                }
            }
            let nestedTerminated = returned || blockTerminated
            returned = outerReturned
            blockTerminated = outerBlockTerminated
            return nestedTerminated
        }

        private mutating func emitWhileLoop(
            condition: RangeCompiler.Expression,
            body: [Statement]
        ) throws {
            let conditionLabel = nextLabel("while.condition")
            let bodyLabel = nextLabel("while.body")
            let endLabel = nextLabel("while.end")

            instructions.append("br label %\(conditionLabel)")
            instructions.append("\(conditionLabel):")
            let conditionValue = try emitCondition(from: condition)
            instructions.append("br i1 \(conditionValue), label %\(bodyLabel), label %\(endLabel)")

            instructions.append("\(bodyLabel):")
            loopStack.append((breakLabel: endLabel, continueLabel: conditionLabel))
            let bodyTerminated = try emitNestedStatements(body)
            _ = loopStack.popLast()
            if !bodyTerminated {
                instructions.append("br label %\(conditionLabel)")
            }

            instructions.append("\(endLabel):")
            returned = false
            blockTerminated = false
        }

        private mutating func emitForEach(
            name: String,
            sequence: RangeCompiler.Expression,
            body: [Statement]
        ) throws {
            let sequenceValue = try emitValue(from: sequence)
            guard let array = sequenceValue.array else {
                throw LLVMEmissionError("LLVM for loop requires an array sequence.")
            }

            let indexPointer = "%\(nextRawName("for.index"))"
            instructions.append("\(indexPointer) = alloca i32")
            instructions.append("store i32 0, ptr \(indexPointer)")

            let bindingPointer = "%\(try llvmIdentifier(name)).\(nextRawName("for.element"))"
            let previousLocal = locals[name]
            guard previousLocal == nil else {
                throw LLVMEmissionError("LLVM for loop binding '\(name)' conflicts with an existing local.")
            }
            locals[name] = LocalSlot(
                pointer: bindingPointer,
                type: array.elementType,
                array: arrayLayout(for: array.elementType),
                optional: optionalLayout(forStorageType: array.elementType),
                nominalName: nominalName(forStorageType: array.elementType)
            )
            defer {
                locals[name] = previousLocal
            }
            instructions.append("\(bindingPointer) = alloca \(array.elementType)")

            let conditionLabel = nextLabel("for.condition")
            let bodyLabel = nextLabel("for.body")
            let continueLabel = nextLabel("for.continue")
            let endLabel = nextLabel("for.end")

            instructions.append("br label %\(conditionLabel)")
            instructions.append("\(conditionLabel):")
            let index = nextTemporary()
            instructions.append("\(index) = load i32, ptr \(indexPointer)")
            let count = nextTemporary()
            instructions.append("\(count) = extractvalue \(sequenceValue.type) \(sequenceValue.operand), 0")
            let shouldContinue = nextTemporary()
            instructions.append("\(shouldContinue) = icmp slt i32 \(index), \(count)")
            instructions.append("br i1 \(shouldContinue), label %\(bodyLabel), label %\(endLabel)")

            instructions.append("\(bodyLabel):")
            let storage = nextTemporary()
            instructions.append("\(storage) = extractvalue \(sequenceValue.type) \(sequenceValue.operand), 1")
            let elementPointer = nextTemporary()
            instructions.append(
                "\(elementPointer) = getelementptr inbounds \(array.elementType), ptr \(storage), i32 \(index)"
            )
            let element = nextTemporary()
            instructions.append("\(element) = load \(array.elementType), ptr \(elementPointer)")
            instructions.append("store \(array.elementType) \(element), ptr \(bindingPointer)")

            loopStack.append((breakLabel: endLabel, continueLabel: continueLabel))
            let bodyTerminated = try emitNestedStatements(body)
            _ = loopStack.popLast()
            if !bodyTerminated {
                instructions.append("br label %\(continueLabel)")
            }

            instructions.append("\(continueLabel):")
            let currentIndex = nextTemporary()
            instructions.append("\(currentIndex) = load i32, ptr \(indexPointer)")
            let nextIndex = nextTemporary()
            instructions.append("\(nextIndex) = add i32 \(currentIndex), 1")
            instructions.append("store i32 \(nextIndex), ptr \(indexPointer)")
            instructions.append("br label %\(conditionLabel)")

            instructions.append("\(endLabel):")
            returned = false
            blockTerminated = false
        }

        private mutating func emitSwitch(
            expression: RangeCompiler.Expression,
            cases: [SwitchCase],
            defaultBody: [Statement]?
        ) throws {
            let subject = try emitValue(from: expression)
            let endLabel = nextLabel("switch.end")
            let caseLabels = cases.map { _ in nextLabel("switch.case") }
            let checkLabels = cases.indices.map { nextLabel("switch.check.\($0)") }
            let defaultLabel = defaultBody == nil ? endLabel : nextLabel("switch.default")

            if cases.isEmpty {
                if let defaultBody {
                    let defaultTerminated = try emitNestedStatements(defaultBody)
                    if !defaultTerminated {
                        instructions.append("br label %\(endLabel)")
                    }
                }
                instructions.append("\(endLabel):")
                returned = false
                blockTerminated = false
                return
            }

            instructions.append("br label %\(checkLabels[0])")

            var hasFallthroughToEnd = defaultBody == nil
            var allBranchesTerminate = defaultBody != nil
            for index in cases.indices {
                let switchCase = cases[index]
                instructions.append("\(checkLabels[index]):")
                let condition = try emitSwitchCaseCondition(subject: subject, pattern: switchCase.pattern)
                let nextLabel = index + 1 < cases.count ? checkLabels[index + 1] : defaultLabel
                instructions.append(
                    "br i1 \(condition), label %\(caseLabels[index]), label %\(nextLabel)"
                )

                instructions.append("\(caseLabels[index]):")
                let previousBinding = try emitSwitchCaseBinding(
                    subject: subject,
                    pattern: switchCase.pattern
                )
                let caseTerminated = try emitNestedStatements(switchCase.body)
                if let previousBinding {
                    locals[previousBinding.name] = previousBinding.local
                }
                if !caseTerminated {
                    instructions.append("br label %\(endLabel)")
                    hasFallthroughToEnd = true
                    allBranchesTerminate = false
                }
            }

            if let defaultBody {
                instructions.append("\(defaultLabel):")
                let defaultTerminated = try emitNestedStatements(defaultBody)
                if !defaultTerminated {
                    instructions.append("br label %\(endLabel)")
                    hasFallthroughToEnd = true
                    allBranchesTerminate = false
                }
            }

            if hasFallthroughToEnd {
                instructions.append("\(endLabel):")
                returned = false
                blockTerminated = false
            } else if allBranchesTerminate {
                returned = true
                blockTerminated = true
            }
        }

        private mutating func emitSwitchCaseCondition(
            subject: LLVMValue,
            pattern: SwitchCasePattern
        ) throws -> String {
            switch pattern {
            case .expression(let expression):
                let patternValue = try emitValue(from: expression)
                guard subject.type == patternValue.type else {
                    throw LLVMEmissionError("LLVM switch pattern type \(patternValue.type) does not match subject type \(subject.type).")
                }
                return try emitEqualityComparison(left: subject, right: patternValue)
            case .enumCase:
                guard let enumName = subject.nominalName,
                    let layout = enumLayouts[enumName]
                else {
                    throw LLVMEmissionError("LLVM enum case switch pattern requires an enum subject.")
                }
                guard case .enumCase(let name, _) = pattern else {
                    throw LLVMEmissionError("LLVM enum case switch pattern is malformed.")
                }
                let caseName = normalizedEnumCaseName(name)
                guard let caseLayout = layout.cases[caseName] else {
                    throw LLVMEmissionError("Unknown LLVM enum case '\(layout.name).\(caseName)'.")
                }
                let subjectTag: String
                if layout.hasPayload {
                    subjectTag = nextTemporary()
                    instructions.append("\(subjectTag) = extractvalue \(subject.type) \(subject.operand), 0")
                } else {
                    subjectTag = subject.operand
                }
                let result = nextTemporary()
                instructions.append("\(result) = icmp eq i32 \(subjectTag), \(caseLayout.tag)")
                return result
            }
        }

        private mutating func emitSwitchCaseBinding(
            subject: LLVMValue,
            pattern: SwitchCasePattern
        ) throws -> (name: String, local: LocalSlot?)? {
            guard case .enumCase(let name, let binding?) = pattern else {
                return nil
            }
            guard let enumName = subject.nominalName,
                let layout = enumLayouts[enumName]
            else {
                throw LLVMEmissionError("LLVM enum case binding requires an enum subject.")
            }
            let caseName = normalizedEnumCaseName(name)
            guard let caseLayout = layout.cases[caseName] else {
                throw LLVMEmissionError("Unknown LLVM enum case '\(layout.name).\(caseName)'.")
            }
            guard caseLayout.associatedValues.count == 1 else {
                throw LLVMEmissionError(
                    "LLVM enum case binding currently requires exactly one associated value."
                )
            }
            guard layout.hasPayload else {
                throw LLVMEmissionError("LLVM enum case binding requires an associated value.")
            }

            let associatedValue = caseLayout.associatedValues[0]
            let payload = nextTemporary()
            instructions.append(
                "\(payload) = extractvalue \(subject.type) \(subject.operand), \(associatedValue.fieldIndex)"
            )
            let previousLocal = locals[binding.name]
            let pointer = "%\(try llvmIdentifier(binding.name)).\(nextRawName("switch.binding"))"
            locals[binding.name] = LocalSlot(
                pointer: pointer,
                type: associatedValue.type,
                array: associatedValue.array,
                nominalName: associatedValue.nominalName
            )
            instructions.append("\(pointer) = alloca \(associatedValue.type)")
            instructions.append("store \(associatedValue.type) \(payload), ptr \(pointer)")
            return (binding.name, previousLocal)
        }

        private mutating func emitEqualityComparison(left: LLVMValue, right: LLVMValue) throws -> String {
            if left.type == "ptr" {
                return try emitStringComparisonValue(
                    left: left,
                    operatorSymbol: .equal,
                    right: right
                ).operand
            }
            if left.type == "double" {
                let result = nextTemporary()
                instructions.append("\(result) = fcmp oeq double \(left.operand), \(right.operand)")
                return result
            }
            guard left.type == "i32" || left.type == "i1" else {
                throw LLVMEmissionError("LLVM equality comparison currently supports i32, i1, double, and String operands.")
            }
            let result = nextTemporary()
            instructions.append("\(result) = icmp eq \(left.type) \(left.operand), \(right.operand)")
            return result
        }

        private mutating func declareLocal(
            named name: String,
            type: String,
            array: ArrayLayout? = nil,
            optional: OptionalLayout? = nil,
            nominalName: String? = nil
        ) throws -> String {
            if locals[name] != nil {
                throw LLVMEmissionError("Duplicate LLVM local '\(name)'.")
            }
            let pointer = "%\(try llvmIdentifier(name))"
            locals[name] = LocalSlot(
                pointer: pointer,
                type: type,
                array: array,
                optional: optional,
                nominalName: nominalName
            )
            instructions.append("\(pointer) = alloca \(type)")
            return pointer
        }

        private mutating func emitAssignment(
            to target: AssignmentTarget,
            expression: RangeCompiler.Expression
        ) throws {
            switch target {
            case .local, .state, .binding:
                let name = try localAssignmentName(from: target)
                guard let local = locals[name] else {
                    throw LLVMEmissionError("Unknown LLVM local '\(name)'.")
                }
                let value = try emitAssignmentValue(expression, for: local)
                guard value.type == local.type else {
                    throw LLVMEmissionError("LLVM assignment to '\(name)' expected \(local.type), got \(value.type).")
                }
                instructions.append("store \(value.type) \(value.operand), ptr \(local.pointer)")

            case .member(let base, let fieldName):
                if let path = try indexedAssignmentPath(
                    from: .member(base: base, name: fieldName)
                ) {
                    try emitIndexedAssignment(path: path, expression: expression)
                    return
                }
                let path = try localAssignmentPath(from: .member(base: base, name: fieldName))
                guard let local = locals[path.root] else {
                    throw LLVMEmissionError("Unknown LLVM local '\(path.root)'.")
                }
                let destinationField = try constructField(at: path.fields, in: local.type)
                let value = try emitValue(from: expression, expected: destinationField.typeReference)
                let loaded = nextTemporary()
                instructions.append("\(loaded) = load \(local.type), ptr \(local.pointer)")
                let updated = try emitInsertedFieldValue(
                    aggregateType: local.type,
                    aggregateOperand: loaded,
                    fieldPath: path.fields,
                    value: value
                )
                instructions.append("store \(local.type) \(updated), ptr \(local.pointer)")

            case .indexed:
                guard let path = try indexedAssignmentPath(from: target) else {
                    throw LLVMEmissionError("LLVM indexed assignment requires an array local.")
                }
                try emitIndexedAssignment(path: path, expression: expression)

            }
        }

        private mutating func emitAssignmentValue(
            _ expression: RangeCompiler.Expression,
            for local: LocalSlot
        ) throws -> LLVMValue {
            guard let optional = local.optional else {
                return try emitValue(
                    from: expression,
                    expectedArrayElementType: local.array.map {
                        LLVMType(ir: $0.elementType, array: nil)
                    }
                )
            }

            let optionalType = LLVMType(
                ir: local.type,
                array: nil,
                optional: optional,
                nominalName: local.nominalName
            )
            if isNilLiteral(expression) {
                return emitNilOptionalValue(optionalType)
            }

            let expectedArrayElementType = arrayLayout(for: optional.wrappedType).map {
                LLVMType(
                    ir: $0.elementType,
                    array: arrayLayout(for: $0.elementType),
                    optional: optionalLayout(forStorageType: $0.elementType),
                    nominalName: nominalName(forStorageType: $0.elementType)
                )
            }
            let expectedArrayElementEnumName = expectedArrayElementType?.nominalName
            let value = try emitValue(
                from: expression,
                expectedEnumName: nominalName(forStorageType: optional.wrappedType),
                expectedArrayElementEnumName: expectedArrayElementEnumName,
                expectedArrayElementType: expectedArrayElementType
            )
            if value.type == local.type {
                return value
            }
            guard value.type == optional.wrappedType else {
                throw LLVMEmissionError("LLVM Optional assignment expected \(optional.wrappedType), got \(value.type).")
            }
            return try emitSomeOptionalValue(
                value,
                optionalType: optionalType,
                wrappedType: LLVMType(ir: optional.wrappedType, array: value.array)
            )
        }

        private func localAssignmentName(from target: AssignmentTarget) throws -> String {
            switch target {
            case .local(let name), .state(let name), .binding(let name):
                return name
            case .indexed:
                throw LLVMEmissionError("LLVM emission cannot assign to indexed targets here.")
            case .member:
                throw LLVMEmissionError("LLVM emission cannot assign to member targets yet.")
            }
        }

        private func localAssignmentPath(from target: AssignmentTarget) throws -> (root: String, fields: [String]) {
            switch target {
            case .local(let name), .state(let name), .binding(let name):
                return (name, [])
            case .indexed:
                throw LLVMEmissionError("LLVM emission cannot assign to indexed targets here.")
            case .member(let base, let name):
                let basePath = try localAssignmentPath(from: base)
                return (basePath.root, basePath.fields + [name])
            }
        }

        private func indexedAssignmentPath(
            from target: AssignmentTarget
        ) throws -> (root: String, index: RangeCompiler.Expression, fields: [String])? {
            switch target {
            case .indexed(let base, let index):
                return (try localAssignmentName(from: base), index, [])
            case .member(let base, let name):
                guard let path = try indexedAssignmentPath(from: base) else {
                    return nil
                }
                return (path.root, path.index, path.fields + [name])
            case .local, .state, .binding:
                return nil
            }
        }

        private mutating func emitIndexedAssignment(
            path: (root: String, index: RangeCompiler.Expression, fields: [String]),
            expression: RangeCompiler.Expression
        ) throws {
            guard let local = locals[path.root] else {
                throw LLVMEmissionError("Unknown LLVM array local '\(path.root)'.")
            }
            guard let array = local.array else {
                throw LLVMEmissionError("LLVM indexed assignment requires an array local.")
            }

            let indexValue = try emitValue(from: path.index)
            guard indexValue.type == "i32" else {
                throw LLVMEmissionError("LLVM array assignment index must be an Int value.")
            }

            let loadedArray = nextTemporary()
            instructions.append("\(loadedArray) = load \(local.type), ptr \(local.pointer)")
            let storage = nextTemporary()
            instructions.append("\(storage) = extractvalue \(local.type) \(loadedArray), 1")
            let elementPointer = nextTemporary()
            instructions.append(
                "\(elementPointer) = getelementptr inbounds \(array.elementType), ptr \(storage), i32 \(indexValue.operand)"
            )

            if path.fields.isEmpty {
                let value = try emitValue(from: expression)
                guard value.type == array.elementType else {
                    throw LLVMEmissionError("LLVM indexed assignment expected \(array.elementType), got \(value.type).")
                }
                instructions.append("store \(value.type) \(value.operand), ptr \(elementPointer)")
                return
            }

            let destinationField = try constructField(at: path.fields, in: array.elementType)
            let value = try emitValue(from: expression, expected: destinationField.typeReference)
            let loadedElement = nextTemporary()
            instructions.append("\(loadedElement) = load \(array.elementType), ptr \(elementPointer)")
            let updatedElement = try emitInsertedFieldValue(
                aggregateType: array.elementType,
                aggregateOperand: loadedElement,
                fieldPath: path.fields,
                value: value
            )
            instructions.append("store \(array.elementType) \(updatedElement), ptr \(elementPointer)")
        }

        private func enumName(for typeReference: TypeReference?) -> String? {
            guard let typeReference else {
                return nil
            }
            switch typeReference {
            case .named(let name) where enumLayouts[name] != nil:
                return name
            case .generic where enumLayouts[typeReference.displayName] != nil:
                return typeReference.displayName
            default:
                return nil
            }
        }

        private func arrayElementEnumName(for typeReference: TypeReference?) -> String? {
            guard case .array(let element) = typeReference else {
                return nil
            }
            return enumName(for: element)
        }

        private func normalizedEnumCaseName(_ name: String) -> String {
            if name.hasPrefix(".") {
                return String(name.dropFirst())
            }
            guard let dot = name.lastIndex(of: ".") else {
                return name
            }
            return String(name[name.index(after: dot)...])
        }

        private func enumName(fromQualifiedCaseName name: String) -> String? {
            guard !name.hasPrefix("."),
                let dot = name.lastIndex(of: ".")
            else {
                return nil
            }
            let enumName = String(name[..<dot])
            return enumLayouts[enumName] == nil ? nil : enumName
        }

        private mutating func enumCaseValue(
            named name: String,
            arguments: [CallArgument] = [],
            expectedEnumName: String?
        ) throws -> LLVMValue? {
            let resolvedEnumName = enumName(fromQualifiedCaseName: name) ?? expectedEnumName
            guard let resolvedEnumName,
                let layout = enumLayouts[resolvedEnumName]
            else {
                return nil
            }
            let caseName = normalizedEnumCaseName(name)
            guard let caseLayout = layout.cases[caseName] else {
                return nil
            }
            guard arguments.count == caseLayout.associatedValues.count else {
                throw LLVMEmissionError(
                    "LLVM enum case '\(resolvedEnumName).\(caseName)' expects \(caseLayout.associatedValues.count) associated values, got \(arguments.count)."
                )
            }
            guard layout.hasPayload else {
                return LLVMValue(
                    type: layout.storageType,
                    operand: "\(caseLayout.tag)",
                    array: nil,
                    nominalName: resolvedEnumName
                )
            }

            var aggregate = nextTemporary()
            instructions.append(
                "\(aggregate) = insertvalue \(layout.storageType) undef, i32 \(caseLayout.tag), 0"
            )
            for (index, associatedValue) in caseLayout.associatedValues.enumerated() {
                let argument = arguments[index]
                if let label = argument.label,
                    label != associatedValue.label
                {
                    throw LLVMEmissionError(
                        "LLVM enum case '\(resolvedEnumName).\(caseName)' argument label '\(label)' does not match associated value."
                    )
                }
                let value = try emitValue(
                    from: argument.value,
                    expectedEnumName: associatedValue.nominalName
                )
                guard value.type == associatedValue.type else {
                    throw LLVMEmissionError(
                        "LLVM enum case '\(resolvedEnumName).\(caseName)' associated value expected \(associatedValue.type), got \(value.type)."
                    )
                }
                let inserted = nextTemporary()
                instructions.append(
                    "\(inserted) = insertvalue \(layout.storageType) \(aggregate), \(value.type) \(value.operand), \(associatedValue.fieldIndex)"
                )
                aggregate = inserted
            }
            return LLVMValue(
                type: layout.storageType,
                operand: aggregate,
                array: nil,
                nominalName: resolvedEnumName
            )
        }

        private mutating func emitValue(
            from expression: RangeCompiler.Expression,
            expectedEnumName: String? = nil,
            expectedArrayElementEnumName: String? = nil,
            expectedArrayElementType: LLVMType? = nil
        ) throws -> LLVMValue {
            switch expression {
            case .integer(let value):
                return LLVMValue(type: "i32", operand: "\(value)", array: nil)

            case .double(let value):
                return LLVMValue(type: "double", operand: llvmDoubleLiteral(value), array: nil)

            case .boolean(let value):
                return LLVMValue(type: "i1", operand: value ? "1" : "0", array: nil)

            case .string(let value):
                return LLVMValue(type: "ptr", operand: runtime.stringPointer(for: value), array: nil)

            case .interpolatedString(let value):
                return try emitInterpolatedStringValue(value)

            case .nilLiteral:
                throw LLVMEmissionError("LLVM nil requires an expected Optional type.")

            case .identifier(let name):
                if let enumCase = try enumCaseValue(named: name, expectedEnumName: expectedEnumName) {
                    return enumCase
                }
                if let indexed = try emitArrayIndexRead(from: name) {
                    return indexed
                }
                if name.contains(".") {
                    return try emitDottedIdentifierRead(from: name)
                }
                guard let local = locals[name] else {
                    throw LLVMEmissionError("Unknown LLVM local '\(name)'.")
                }
                let result = nextTemporary()
                instructions.append("\(result) = load \(local.type), ptr \(local.pointer)")
                return LLVMValue(
                    type: local.type,
                    operand: result,
                    array: local.array,
                    optional: local.optional,
                    nominalName: local.nominalName
                )

            case .member(let base, let name):
                let value = try emitValue(from: base)
                return try emitExtractedFieldValue(
                    aggregateType: value.type,
                    aggregateOperand: value.operand,
                    fieldPath: [name]
                )

            case .call(let name, let arguments)
                where name == "Int" && arguments.count == 1 && arguments[0].label == nil:
                let value = try emitValue(from: arguments[0].value)
                guard value.type == "i32" else {
                    throw LLVMEmissionError("Int(...) expects an integer LLVM value.")
                }
                return value

            case .call(let name, let arguments)
                where name == "Bool" && arguments.count == 1 && arguments[0].label == nil:
                let value = try emitValue(from: arguments[0].value)
                guard value.type == "i1" else {
                    throw LLVMEmissionError("Bool(...) expects a boolean LLVM value.")
                }
                return value

            case .call(let name, let arguments)
                where name == "Float" && arguments.count == 1 && arguments[0].label == nil:
                let value = try emitValue(from: arguments[0].value)
                guard value.type == "double" else {
                    throw LLVMEmissionError("Float(...) expects a floating-point LLVM value.")
                }
                return value

            case .call(let name, let arguments)
                where name == "String" && arguments.count == 1 && arguments[0].label == nil:
                let value = try emitValue(from: arguments[0].value)
                guard value.type == "ptr" else {
                    throw LLVMEmissionError("String(...) expects a string LLVM value.")
                }
                return value

            case .unary(let operatorSymbol, let expression):
                return try emitUnaryValue(operatorSymbol: operatorSymbol, expression: expression)

            case .binary(let lhs, let operatorSymbol, let rhs):
                return try emitBinaryValue(lhs: lhs, operatorSymbol: operatorSymbol, rhs: rhs)

            case .array(let elements):
                return try emitArrayLiteral(
                    elements,
                    expectedElementEnumName: expectedArrayElementEnumName,
                    expectedElementType: expectedArrayElementType
                )

            case .indexed(let base, let index):
                return try emitArrayIndexRead(base: base, index: index)

            case .ternary(let condition, let trueExpression, let falseExpression):
                return try emitTernaryValue(
                    condition: condition,
                    trueExpression: trueExpression,
                    falseExpression: falseExpression
                )

            case .call(let name, let arguments) where constructLayouts[name] != nil:
                return try emitConstructInitialization(name: name, arguments: arguments)

            case .call(let name, let arguments)
                where name.hasSuffix(".character") || name.hasSuffix(".substring"):
                return try emitStringMemberCall(name: name, arguments: arguments)

            case .call(let name, let arguments) where name.hasSuffix(".element"):
                return try emitArrayElementCall(name: name, arguments: arguments)

            case .call(let name, let arguments) where name.hasSuffix(".first"):
                return try emitArrayFirstCall(name: name, arguments: arguments)

            case .call(let name, let arguments) where name.hasSuffix(".last"):
                return try emitArrayLastCall(name: name, arguments: arguments)

            case .call(let name, let arguments) where name.hasSuffix(".removeLast"):
                return try emitArrayRemoveLastCall(name: name, arguments: arguments)

            case .call(let name, let arguments) where name.hasSuffix(".remove"):
                return try emitArrayRemoveCall(name: name, arguments: arguments)

            case .call(let name, let arguments) where name == "fileExists":
                return try emitFileExistsCall(arguments: arguments)

            case .call(let name, let arguments) where name == "readFile":
                return try emitReadFileCall(arguments: arguments)

            case .call(let name, let arguments) where name == "readFileIfExists":
                return try emitReadFileIfExistsCall(arguments: arguments)

            case .call(let name, let arguments) where name == "readLine":
                return try emitReadLineCall(arguments: arguments)

            case .call(let name, let arguments) where name == "commandLineArgumentCount":
                return try emitCommandLineArgumentCountCall(arguments: arguments)

            case .call(let name, let arguments) where name == "commandLineArgument":
                return try emitCommandLineArgumentCall(arguments: arguments)

            case .call(let name, let arguments) where name == "stringLength":
                return try emitStringLengthCall(arguments: arguments)

            case .call(let name, let arguments):
                if let enumCase = try enumCaseValue(
                    named: name,
                    arguments: arguments,
                    expectedEnumName: expectedEnumName
                ) {
                    return enumCase
                }
                return try emitFunctionCall(name: name, arguments: arguments)

            default:
                throw LLVMEmissionError("LLVM emission currently supports integer and boolean values only.")
            }
        }

        private mutating func emitValue(
            from expression: RangeCompiler.Expression,
            expected typeReference: TypeReference
        ) throws -> LLVMValue {
            let substitutedType = substituted(typeReference)
            if let optionalContext = try optionalContext(for: substitutedType) {
                return try emitOptionalValue(
                    from: expression,
                    optionalType: optionalContext.optional,
                    wrappedType: optionalContext.wrapped,
                    wrappedReference: optionalContext.wrappedReference
                )
            }
            return try emitValue(
                from: expression,
                expectedEnumName: enumName(for: substitutedType),
                expectedArrayElementEnumName: arrayElementEnumName(for: substitutedType),
                expectedArrayElementType: try arrayElementType(for: substitutedType)
            )
        }

        private func constantInterpolatedString(_ value: InterpolatedString) throws -> String {
            var rendered = ""
            for segment in value.segments {
                switch segment {
                case .text(let text):
                    rendered += text
                case .expression(let expression):
                    rendered += try constantInterpolatedStringExpression(expression)
                }
            }
            return rendered
        }

        private mutating func emitInterpolatedStringValue(
            _ value: InterpolatedString
        ) throws -> LLVMValue {
            if let constant = try? constantInterpolatedString(value) {
                return LLVMValue(type: "ptr", operand: runtime.stringPointer(for: constant), array: nil)
            }

            runtime.markUsesSnprintf()
            var format = ""
            var arguments: [String] = []

            for segment in value.segments {
                switch segment {
                case .text(let text):
                    format += printfEscapedText(text)
                case .expression(let expression):
                    let value = try emitValue(from: expression)
                    switch value.type {
                    case "i32":
                        format += "%d"
                        arguments.append("i32 \(value.operand)")
                    case "double":
                        format += "%f"
                        arguments.append("double \(value.operand)")
                    case "ptr":
                        format += "%s"
                        arguments.append("ptr \(value.operand)")
                    case "i1":
                        format += "%s"
                        let trueText = runtime.stringPointer(for: "true")
                        let falseText = runtime.stringPointer(for: "false")
                        let selected = nextTemporary()
                        instructions.append(
                            "\(selected) = select i1 \(value.operand), ptr \(trueText), ptr \(falseText)"
                        )
                        arguments.append("ptr \(selected)")
                    default:
                        throw LLVMEmissionError(
                            "LLVM string interpolation currently supports String, Int, Float, and Bool values."
                        )
                    }
                }
            }

            let formatPointer = runtime.stringPointer(for: format)
            let renderedArguments = arguments.isEmpty ? "" : ", " + arguments.joined(separator: ", ")
            let measuredLength = nextTemporary()
            instructions.append(
                "\(measuredLength) = call i32 (ptr, i64, ptr, ...) @snprintf(ptr null, i64 0, ptr \(formatPointer)\(renderedArguments))"
            )
            let wideLength = nextTemporary()
            instructions.append("\(wideLength) = sext i32 \(measuredLength) to i64")
            let allocationSize = nextTemporary()
            instructions.append("\(allocationSize) = add i64 \(wideLength), 1")
            let buffer = nextTemporary()
            instructions.append("\(buffer) = call ptr @malloc(i64 \(allocationSize))")
            let ignored = nextTemporary()
            instructions.append(
                "\(ignored) = call i32 (ptr, i64, ptr, ...) @snprintf(ptr \(buffer), i64 \(allocationSize), ptr \(formatPointer)\(renderedArguments))"
            )
            return LLVMValue(type: "ptr", operand: buffer, array: nil)
        }

        private func printfEscapedText(_ text: String) -> String {
            text.replacingOccurrences(of: "%", with: "%%")
        }

        private func constantInterpolatedStringExpression(
            _ expression: RangeCompiler.Expression
        ) throws -> String {
            switch expression {
            case .integer(let value):
                return String(value)
            case .double(let value):
                return String(value)
            case .boolean(let value):
                return value ? "true" : "false"
            case .string(let value):
                return value
            case .interpolatedString(let value):
                return try constantInterpolatedString(value)
            default:
                throw LLVMEmissionError(
                    "LLVM string interpolation currently supports literal interpolations only."
                )
            }
        }

        private mutating func emitOptionalValue(
            from expression: RangeCompiler.Expression,
            optionalType: LLVMType,
            wrappedType: LLVMType,
            wrappedReference: TypeReference
        ) throws -> LLVMValue {
            if isNilLiteral(expression) {
                return emitNilOptionalValue(optionalType)
            }

            let value = try emitValue(
                from: expression,
                expectedEnumName: enumName(for: wrappedReference),
                expectedArrayElementEnumName: arrayElementEnumName(for: wrappedReference),
                expectedArrayElementType: try arrayElementType(for: wrappedReference)
            )
            if value.type == optionalType.ir {
                return value
            }
            guard value.type == wrappedType.ir else {
                throw LLVMEmissionError("LLVM Optional expected \(wrappedType.ir), got \(value.type).")
            }

            return try emitSomeOptionalValue(
                value,
                optionalType: optionalType,
                wrappedType: wrappedType
            )
        }

        private mutating func emitSomeOptionalValue(
            _ value: LLVMValue,
            optionalType: LLVMType,
            wrappedType: LLVMType
        ) throws -> LLVMValue {
            let validityInserted = nextTemporary()
            instructions.append(
                "\(validityInserted) = insertvalue \(optionalType.ir) undef, i1 1, 0"
            )
            let payloadInserted = nextTemporary()
            instructions.append(
                "\(payloadInserted) = insertvalue \(optionalType.ir) \(validityInserted), \(wrappedType.ir) \(value.operand), 1"
            )
            return LLVMValue(
                type: optionalType.ir,
                operand: payloadInserted,
                array: nil,
                optional: optionalType.optional
            )
        }

        private mutating func emitNilOptionalValue(_ optionalType: LLVMType) -> LLVMValue {
            let validityInserted = nextTemporary()
            instructions.append(
                "\(validityInserted) = insertvalue \(optionalType.ir) undef, i1 0, 0"
            )
            return LLVMValue(
                type: optionalType.ir,
                operand: validityInserted,
                array: nil,
                optional: optionalType.optional
            )
        }

        private func isNilLiteral(_ expression: RangeCompiler.Expression) -> Bool {
            if case .nilLiteral = expression {
                return true
            }
            return false
        }

        private mutating func emitArrayLiteral(
            _ elements: [RangeCompiler.Expression],
            expectedElementEnumName: String? = nil,
            expectedElementType: LLVMType? = nil
        ) throws
            -> LLVMValue
        {
            let values = try elements.map {
                try emitValue(from: $0, expectedEnumName: expectedElementEnumName)
            }
            guard let elementType = values.first?.type ?? expectedElementType?.ir else {
                throw LLVMEmissionError("LLVM empty array literals require an expected array type.")
            }
            guard values.allSatisfy({ $0.type == elementType }) else {
                throw LLVMEmissionError("LLVM array literal elements must have matching types.")
            }

            runtime.registerArray(elementType: elementType)
            runtime.markUsesMalloc()
            let arrayType = LLVMRuntime.arrayTypeName(for: elementType)
            let byteCount = try llvmByteSize(of: elementType) * values.count
            let elementStorage = nextTemporary()
            instructions.append("\(elementStorage) = call ptr @malloc(i64 \(byteCount))")

            for (index, value) in values.enumerated() {
                let elementPointer = nextTemporary()
                instructions.append(
                    "\(elementPointer) = getelementptr inbounds \(elementType), ptr \(elementStorage), i32 \(index)"
                )
                instructions.append(
                    "store \(elementType) \(value.operand), ptr \(elementPointer)"
                )
            }

            let countInserted = nextTemporary()
            instructions.append(
                "\(countInserted) = insertvalue \(arrayType) undef, i32 \(values.count), 0"
            )
            let storageInserted = nextTemporary()
            instructions.append(
                "\(storageInserted) = insertvalue \(arrayType) \(countInserted), ptr \(elementStorage), 1"
            )

            return LLVMValue(
                type: arrayType,
                operand: storageInserted,
                array: ArrayLayout(elementType: elementType, count: values.count)
            )
        }

        private mutating func emitArrayIndexRead(from name: String) throws -> LLVMValue? {
            guard let leftBracket = name.firstIndex(of: "["),
                name.hasSuffix("]")
            else {
                return nil
            }

            let baseName = String(name[..<leftBracket])
            let indexStart = name.index(after: leftBracket)
            let indexEnd = name.index(before: name.endIndex)
            guard let index = Int(name[indexStart..<indexEnd]) else {
                throw LLVMEmissionError("LLVM array index must be an integer literal.")
            }
            guard let local = locals[baseName] else {
                throw LLVMEmissionError("Unknown LLVM array local '\(baseName)'.")
            }
            guard let array = local.array else {
                throw LLVMEmissionError("LLVM indexed access requires an array local.")
            }
            if let count = array.count, index >= count {
                throw LLVMEmissionError("LLVM array index \(index) is out of bounds for '\(baseName)'.")
            }
            guard index >= 0 else {
                throw LLVMEmissionError("LLVM array index \(index) is out of bounds for '\(baseName)'.")
            }

            let loaded = nextTemporary()
            instructions.append("\(loaded) = load \(local.type), ptr \(local.pointer)")
            let storage = nextTemporary()
            instructions.append("\(storage) = extractvalue \(local.type) \(loaded), 1")
            let elementPointer = nextTemporary()
            instructions.append(
                "\(elementPointer) = getelementptr inbounds \(array.elementType), ptr \(storage), i32 \(index)"
            )
            let loadedElement = nextTemporary()
            instructions.append("\(loadedElement) = load \(array.elementType), ptr \(elementPointer)")
            return LLVMValue(
                type: array.elementType,
                operand: loadedElement,
                array: arrayLayout(for: array.elementType),
                optional: optionalLayout(forStorageType: array.elementType),
                nominalName: nominalName(forStorageType: array.elementType)
            )
        }

        private mutating func emitArrayIndexRead(
            base: RangeCompiler.Expression,
            index: RangeCompiler.Expression
        ) throws -> LLVMValue {
            let arrayValue = try emitValue(from: base)
            guard let array = arrayValue.array else {
                throw LLVMEmissionError("LLVM indexed access requires an array value.")
            }
            let indexValue = try emitValue(from: index)
            guard indexValue.type == "i32" else {
                throw LLVMEmissionError("LLVM array index must be an Int value.")
            }

            let storage = nextTemporary()
            instructions.append("\(storage) = extractvalue \(arrayValue.type) \(arrayValue.operand), 1")
            let elementPointer = nextTemporary()
            instructions.append(
                "\(elementPointer) = getelementptr inbounds \(array.elementType), ptr \(storage), i32 \(indexValue.operand)"
            )
            let loadedElement = nextTemporary()
            instructions.append("\(loadedElement) = load \(array.elementType), ptr \(elementPointer)")
            return LLVMValue(
                type: array.elementType,
                operand: loadedElement,
                array: arrayLayout(for: array.elementType),
                optional: optionalLayout(forStorageType: array.elementType),
                nominalName: nominalName(forStorageType: array.elementType)
            )
        }

        private mutating func emitArrayElementCall(
            name: String,
            arguments: [CallArgument]
        ) throws -> LLVMValue {
            guard arguments.count == 1 else {
                throw LLVMEmissionError("Array.element(index:) expects one argument.")
            }
            let argument = arguments[0]
            if let label = argument.label, label != "index" {
                throw LLVMEmissionError("Array.element(index:) argument label must be 'index'.")
            }

            let receiverName = String(name.dropLast(".element".count))
            return try emitArrayIndexRead(base: .identifier(receiverName), index: argument.value)
        }

        private mutating func emitTernaryValue(
            condition: RangeCompiler.Expression,
            trueExpression: RangeCompiler.Expression,
            falseExpression: RangeCompiler.Expression
        ) throws -> LLVMValue {
            let conditionValue = try emitCondition(from: condition)
            let trueValue = try emitValue(from: trueExpression)
            let falseValue = try emitValue(from: falseExpression)
            guard trueValue.type == falseValue.type else {
                throw LLVMEmissionError("LLVM ternary branches must have matching types.")
            }
            guard trueValue.array == falseValue.array else {
                throw LLVMEmissionError("LLVM ternary array branches must have matching array layouts.")
            }
            let result = nextTemporary()
            instructions.append(
                "\(result) = select i1 \(conditionValue), \(trueValue.type) \(trueValue.operand), \(trueValue.type) \(falseValue.operand)"
            )
            return LLVMValue(
                type: trueValue.type,
                operand: result,
                array: trueValue.array,
                optional: trueValue.optional,
                nominalName: trueValue.nominalName
            )
        }

        private mutating func emitDottedIdentifierRead(from dottedName: String) throws -> LLVMValue {
            if let arrayCount = try emitArrayCountRead(from: dottedName) {
                return arrayCount
            }
            if let stringCount = try emitStringCountRead(from: dottedName) {
                return stringCount
            }
            if let arrayIsEmpty = try emitArrayIsEmptyRead(from: dottedName) {
                return arrayIsEmpty
            }
            if let stringIsEmpty = try emitStringIsEmptyRead(from: dottedName) {
                return stringIsEmpty
            }
            return try emitFieldRead(from: dottedName)
        }

        private mutating func emitArrayCountRead(from dottedName: String) throws -> LLVMValue? {
            guard dottedName.hasSuffix(".count") else {
                return nil
            }
            let baseName = String(dottedName.dropLast(".count".count))
            guard let local = locals[baseName], local.array != nil else {
                return nil
            }
            let loaded = nextTemporary()
            instructions.append("\(loaded) = load \(local.type), ptr \(local.pointer)")
            let count = nextTemporary()
            instructions.append("\(count) = extractvalue \(local.type) \(loaded), 0")
            return LLVMValue(type: "i32", operand: count, array: nil)
        }

        private mutating func emitStringCountRead(from dottedName: String) throws -> LLVMValue? {
            guard dottedName.hasSuffix(".count") else {
                return nil
            }
            let baseName = String(dottedName.dropLast(".count".count))
            guard let local = locals[baseName], local.type == "ptr", local.array == nil else {
                return nil
            }

            let loaded = nextTemporary()
            instructions.append("\(loaded) = load ptr, ptr \(local.pointer)")
            runtime.markUsesStrlen()
            let wideLength = nextTemporary()
            instructions.append("\(wideLength) = call i64 @strlen(ptr \(loaded))")
            let length = nextTemporary()
            instructions.append("\(length) = trunc i64 \(wideLength) to i32")
            return LLVMValue(type: "i32", operand: length, array: nil)
        }

        private mutating func emitArrayIsEmptyRead(from dottedName: String) throws -> LLVMValue? {
            guard dottedName.hasSuffix(".isEmpty") else {
                return nil
            }
            let baseName = String(dottedName.dropLast(".isEmpty".count))
            guard let local = locals[baseName], local.array != nil else {
                return nil
            }
            let loaded = nextTemporary()
            instructions.append("\(loaded) = load \(local.type), ptr \(local.pointer)")
            let count = nextTemporary()
            instructions.append("\(count) = extractvalue \(local.type) \(loaded), 0")
            let result = nextTemporary()
            instructions.append("\(result) = icmp eq i32 \(count), 0")
            return LLVMValue(type: "i1", operand: result, array: nil)
        }

        private mutating func emitStringIsEmptyRead(from dottedName: String) throws -> LLVMValue? {
            guard dottedName.hasSuffix(".isEmpty") else {
                return nil
            }
            let baseName = String(dottedName.dropLast(".isEmpty".count))
            guard let local = locals[baseName], local.type == "ptr", local.array == nil else {
                return nil
            }

            let loaded = nextTemporary()
            instructions.append("\(loaded) = load ptr, ptr \(local.pointer)")
            runtime.markUsesStrlen()
            let wideLength = nextTemporary()
            instructions.append("\(wideLength) = call i64 @strlen(ptr \(loaded))")
            let result = nextTemporary()
            instructions.append("\(result) = icmp eq i64 \(wideLength), 0")
            return LLVMValue(type: "i1", operand: result, array: nil)
        }

        private mutating func emitFieldRead(from dottedName: String) throws -> LLVMValue {
            let pieces = dottedName.split(separator: ".").map(String.init)
            guard pieces.count >= 2 else {
                throw LLVMEmissionError("Invalid LLVM field access '\(dottedName)'.")
            }
            let baseName = pieces[0]
            if let indexedBase = try emitArrayIndexRead(from: baseName) {
                return try emitExtractedFieldValue(
                    aggregateType: indexedBase.type,
                    aggregateOperand: indexedBase.operand,
                    fieldPath: Array(pieces.dropFirst())
                )
            }
            guard let local = locals[baseName] else {
                throw LLVMEmissionError("Unknown LLVM local '\(baseName)'.")
            }
            let loaded = nextTemporary()
            instructions.append("\(loaded) = load \(local.type), ptr \(local.pointer)")
            return try emitExtractedFieldValue(
                aggregateType: local.type,
                aggregateOperand: loaded,
                fieldPath: Array(pieces.dropFirst())
            )
        }

        private mutating func emitExtractedFieldValue(
            aggregateType: String,
            aggregateOperand: String,
            fieldPath: [String]
        ) throws -> LLVMValue {
            guard let firstField = fieldPath.first else {
                return LLVMValue(
                    type: aggregateType,
                    operand: aggregateOperand,
                    array: arrayLayout(for: aggregateType),
                    optional: optionalLayout(forStorageType: aggregateType),
                    nominalName: nominalName(forStorageType: aggregateType)
                )
            }
            if firstField == "count", arrayLayout(for: aggregateType) != nil {
                guard fieldPath.count == 1 else {
                    throw LLVMEmissionError("LLVM array count access cannot have nested fields.")
                }
                let count = nextTemporary()
                instructions.append("\(count) = extractvalue \(aggregateType) \(aggregateOperand), 0")
                return LLVMValue(type: "i32", operand: count, array: nil)
            }
            if firstField == "count", aggregateType == "ptr" {
                guard fieldPath.count == 1 else {
                    throw LLVMEmissionError("LLVM string count access cannot have nested fields.")
                }
                runtime.markUsesStrlen()
                let wideLength = nextTemporary()
                instructions.append("\(wideLength) = call i64 @strlen(ptr \(aggregateOperand))")
                let length = nextTemporary()
                instructions.append("\(length) = trunc i64 \(wideLength) to i32")
                return LLVMValue(type: "i32", operand: length, array: nil)
            }
            if firstField == "isEmpty", arrayLayout(for: aggregateType) != nil {
                guard fieldPath.count == 1 else {
                    throw LLVMEmissionError("LLVM array isEmpty access cannot have nested fields.")
                }
                let count = nextTemporary()
                instructions.append("\(count) = extractvalue \(aggregateType) \(aggregateOperand), 0")
                let result = nextTemporary()
                instructions.append("\(result) = icmp eq i32 \(count), 0")
                return LLVMValue(type: "i1", operand: result, array: nil)
            }
            if firstField == "isEmpty", aggregateType == "ptr" {
                guard fieldPath.count == 1 else {
                    throw LLVMEmissionError("LLVM string isEmpty access cannot have nested fields.")
                }
                runtime.markUsesStrlen()
                let wideLength = nextTemporary()
                instructions.append("\(wideLength) = call i64 @strlen(ptr \(aggregateOperand))")
                let result = nextTemporary()
                instructions.append("\(result) = icmp eq i64 \(wideLength), 0")
                return LLVMValue(type: "i1", operand: result, array: nil)
            }
            let field = try constructField(named: firstField, in: aggregateType)
            let extracted = nextTemporary()
            instructions.append(
                "\(extracted) = extractvalue \(aggregateType) \(aggregateOperand), \(field.index)"
            )
            if fieldPath.count == 1 {
                return LLVMValue(
                    type: field.field.type,
                    operand: extracted,
                    array: arrayLayout(for: field.field.type),
                    optional: optionalLayout(forStorageType: field.field.type),
                    nominalName: nominalName(forStorageType: field.field.type)
                )
            }
            return try emitExtractedFieldValue(
                aggregateType: field.field.type,
                aggregateOperand: extracted,
                fieldPath: Array(fieldPath.dropFirst())
            )
        }

        private mutating func emitInsertedFieldValue(
            aggregateType: String,
            aggregateOperand: String,
            fieldPath: [String],
            value: LLVMValue
        ) throws -> String {
            guard let firstField = fieldPath.first else {
                guard aggregateType == value.type else {
                    throw LLVMEmissionError("LLVM field assignment expected \(aggregateType), got \(value.type).")
                }
                return value.operand
            }

            let field = try constructField(named: firstField, in: aggregateType)
            let insertedValue: LLVMValue
            if fieldPath.count == 1 {
                guard value.type == field.field.type else {
                    throw LLVMEmissionError("LLVM field assignment to '\(firstField)' expected \(field.field.type), got \(value.type).")
                }
                insertedValue = value
            } else {
                let extracted = nextTemporary()
                instructions.append(
                    "\(extracted) = extractvalue \(aggregateType) \(aggregateOperand), \(field.index)"
                )
                let nested = try emitInsertedFieldValue(
                    aggregateType: field.field.type,
                    aggregateOperand: extracted,
                    fieldPath: Array(fieldPath.dropFirst()),
                    value: value
                )
                insertedValue = LLVMValue(type: field.field.type, operand: nested, array: nil)
            }

            let updated = nextTemporary()
            instructions.append(
                "\(updated) = insertvalue \(aggregateType) \(aggregateOperand), \(insertedValue.type) \(insertedValue.operand), \(field.index)"
            )
            return updated
        }

        private func constructField(
            named fieldName: String,
            in aggregateType: String
        ) throws -> (index: Int, field: ConstructField) {
            guard aggregateType.hasPrefix("%") else {
                throw LLVMEmissionError("LLVM field access requires a construct value.")
            }
            guard let layout = constructLayout(forStorageType: aggregateType),
                let field = layout.field(named: fieldName)
            else {
                throw LLVMEmissionError("Unknown LLVM field '\(fieldName)' on construct '\(aggregateType)'.")
            }
            return field
        }

        private func constructField(
            at fieldPath: [String],
            in aggregateType: String
        ) throws -> ConstructField {
            guard let firstField = fieldPath.first else {
                throw LLVMEmissionError("LLVM field assignment requires a destination field.")
            }
            let field = try constructField(named: firstField, in: aggregateType)
            guard fieldPath.count > 1 else {
                return field.field
            }
            return try constructField(
                at: Array(fieldPath.dropFirst()),
                in: field.field.type
            )
        }

        private func constructLayout(forStorageType storageType: String) -> ConstructLayout? {
            constructLayouts.values.first { $0.storageType == storageType }
        }

        private func enumLayout(forStorageType storageType: String) -> EnumLayout? {
            enumLayouts.values.first { $0.storageType == storageType }
        }

        private func nominalName(forStorageType storageType: String) -> String? {
            constructLayout(forStorageType: storageType)?.name
                ?? enumLayout(forStorageType: storageType)?.name
        }

        private func arrayLayout(for type: String) -> ArrayLayout? {
            let knownElementTypes = ["i1", "i32", "double", "ptr"]
                + constructLayouts.values.map(\.storageType)
                + enumLayouts.values.map(\.storageType)
                + runtime.optionalStorageTypes
            for elementType in knownElementTypes {
                if type == LLVMRuntime.arrayTypeName(for: elementType) {
                    return ArrayLayout(elementType: elementType, count: nil)
                }
            }
            return nil
        }

        private func optionalLayout(forStorageType storageType: String) -> OptionalLayout? {
            runtime.optionalWrappedType(forStorageType: storageType).map {
                OptionalLayout(wrappedType: $0)
            }
        }

        private func optionalContext(
            for typeReference: TypeReference
        ) throws -> (optional: LLVMType, wrapped: LLVMType, wrappedReference: TypeReference)? {
            guard case .optional(let wrappedReference) = typeReference else {
                return nil
            }
            let wrappedType = try llvmTypeInfoForFunctionEmitter(
                for: wrappedReference,
                context: "Optional wrapped value"
            )
            runtime.registerOptional(wrappedType: wrappedType.ir)
            let optionalType = LLVMType(
                ir: LLVMRuntime.optionalTypeName(for: wrappedType.ir),
                array: nil,
                optional: OptionalLayout(wrappedType: wrappedType.ir)
            )
            return (optionalType, wrappedType, wrappedReference)
        }

        private func arrayElementType(for typeReference: TypeReference?) throws -> LLVMType? {
            guard let typeReference else {
                return nil
            }
            guard case .array(let elementReference) = typeReference else {
                return nil
            }
            return try llvmTypeInfoForFunctionEmitter(
                for: elementReference,
                context: "array element"
            )
        }

        private func llvmTypeInfoForFunctionEmitter(
            for typeReference: TypeReference,
            context: String
        ) throws -> LLVMType {
            switch typeReference {
            case .array(let element):
                let elementType = try llvmTypeInfoForFunctionEmitter(
                    for: element,
                    context: "\(context) array element"
                )
                runtime.registerArray(elementType: elementType.ir)
                return LLVMType(
                    ir: LLVMRuntime.arrayTypeName(for: elementType.ir),
                    array: ArrayLayout(elementType: elementType.ir, count: nil)
                )
            case .optional(let wrapped):
                let wrappedType = try llvmTypeInfoForFunctionEmitter(
                    for: wrapped,
                    context: "\(context) optional wrapped value"
                )
                runtime.registerOptional(wrappedType: wrappedType.ir)
                return LLVMType(
                    ir: LLVMRuntime.optionalTypeName(for: wrappedType.ir),
                    array: nil,
                    optional: OptionalLayout(wrappedType: wrappedType.ir)
                )
            case .named(let name):
                return try llvmNamedTypeInfoForFunctionEmitter(name: name, context: context)
            case .member, .generic, .function, .variadic:
                return try llvmNamedTypeInfoForFunctionEmitter(
                    name: typeReference.displayName,
                    context: context
                )
            }
        }

        private func llvmNamedTypeInfoForFunctionEmitter(name: String, context: String) throws
            -> LLVMType
        {
            switch name {
            case "Int":
                return LLVMType(ir: "i32", array: nil)
            case "Float":
                return LLVMType(ir: "double", array: nil)
            case "Bool":
                return LLVMType(ir: "i1", array: nil)
            case "String":
                return LLVMType(ir: "ptr", array: nil)
            case "Void":
                return LLVMType(ir: "void", array: nil)
            default:
                if let enumLayout = enumLayouts[name] {
                    return LLVMType(ir: enumLayout.storageType, array: nil, nominalName: name)
                }
                if let constructLayout = constructLayouts[name] {
                    return LLVMType(ir: constructLayout.storageType, array: nil, nominalName: name)
                }
                throw LLVMEmissionError("LLVM emission does not support \(context) type '\(name)' yet.")
            }
        }

        private mutating func emitConstructInitialization(name: String, arguments: [CallArgument]) throws
            -> LLVMValue
        {
            guard let layout = constructLayouts[name] else {
                throw LLVMEmissionError("Unknown LLVM construct '\(name)'.")
            }

            var aggregateOperand = "undef"
            var usedArgumentIndices: Set<Int> = []

            for (index, field) in layout.fields.enumerated() {
                let explicitArgumentIndex = arguments.indices.first { argumentIndex in
                    guard !usedArgumentIndices.contains(argumentIndex) else {
                        return false
                    }
                    return arguments[argumentIndex].label == field.name
                } ?? arguments.indices.first { argumentIndex in
                    guard !usedArgumentIndices.contains(argumentIndex) else {
                        return false
                    }
                    return arguments[argumentIndex].label == nil
                }
                let expression: RangeCompiler.Expression
                if let explicitArgumentIndex {
                    usedArgumentIndices.insert(explicitArgumentIndex)
                    expression = arguments[explicitArgumentIndex].value
                } else if let defaultValue = field.defaultValue {
                    expression = defaultValue
                } else {
                    throw LLVMEmissionError("LLVM construct '\(name)' missing field '\(field.name)'.")
                }

                let value = try emitValue(from: expression, expected: field.typeReference)
                guard value.type == field.type else {
                    throw LLVMEmissionError("LLVM construct '\(name)' field '\(field.name)' expected \(field.type), got \(value.type).")
                }
                let inserted = nextTemporary()
                instructions.append(
                    "\(inserted) = insertvalue \(layout.storageType) \(aggregateOperand), \(field.type) \(value.operand), \(index)"
                )
                aggregateOperand = inserted
            }

            if let unusedArgumentIndex = arguments.indices.first(where: { !usedArgumentIndices.contains($0) }) {
                if let label = arguments[unusedArgumentIndex].label {
                    throw LLVMEmissionError("LLVM construct '\(name)' has no field '\(label)'.")
                }
                throw LLVMEmissionError("LLVM construct '\(name)' received too many positional fields.")
            }

            return LLVMValue(
                type: layout.storageType,
                operand: aggregateOperand,
                array: nil,
                nominalName: layout.name
            )
        }

        private mutating func emitBinaryValue(
            lhs: RangeCompiler.Expression,
            operatorSymbol: BinaryOperator,
            rhs: RangeCompiler.Expression
        ) throws -> LLVMValue {
            switch operatorSymbol {
            case .and, .or:
                let left = try emitValue(from: lhs)
                let right = try emitValue(from: rhs)
                guard left.type == "i1", right.type == "i1" else {
                    throw LLVMEmissionError("LLVM boolean operators require i1 operands.")
                }
                let result = nextTemporary()
                instructions.append(
                    "\(result) = \(operatorSymbol == .and ? "and" : "or") i1 \(left.operand), \(right.operand)"
                )
                return LLVMValue(type: "i1", operand: result, array: nil)

            case .addition, .subtraction, .multiplication, .division, .remainder:
                let left = try emitValue(from: lhs)
                let right = try emitValue(from: rhs)
                if left.type == "double" || right.type == "double" {
                    guard left.type == "double", right.type == "double" else {
                        throw LLVMEmissionError("LLVM floating-point arithmetic requires double operands.")
                    }
                    let result = nextTemporary()
                    instructions.append(
                        "\(result) = \(try llvmFloatingPointInstruction(for: operatorSymbol)) double \(left.operand), \(right.operand)"
                    )
                    return LLVMValue(type: "double", operand: result, array: nil)
                }
                guard left.type == "i32", right.type == "i32" else {
                    throw LLVMEmissionError("LLVM integer arithmetic requires i32 operands.")
                }
                let result = nextTemporary()
                instructions.append(
                    "\(result) = \(try llvmIntegerInstruction(for: operatorSymbol)) i32 \(left.operand), \(right.operand)"
                )
                return LLVMValue(type: "i32", operand: result, array: nil)

            case .nilCoalescing:
                return try emitNilCoalescingValue(optionalExpression: lhs, fallbackExpression: rhs)

            case .equal, .notEqual, .less, .lessEqual, .greater, .greaterEqual:
                if operatorSymbol == .equal || operatorSymbol == .notEqual {
                    if isNilLiteral(rhs) {
                        let left = try emitValue(from: lhs)
                        return try emitOptionalNilComparisonValue(
                            value: left,
                            operatorSymbol: operatorSymbol
                        )
                    }
                    if isNilLiteral(lhs) {
                        let right = try emitValue(from: rhs)
                        return try emitOptionalNilComparisonValue(
                            value: right,
                            operatorSymbol: operatorSymbol
                        )
                    }
                    if let comparison = try emitNoPayloadEnumCaseComparisonValue(
                        subjectExpression: lhs,
                        caseExpression: rhs,
                        operatorSymbol: operatorSymbol
                    ) {
                        return comparison
                    }
                    if let comparison = try emitNoPayloadEnumCaseComparisonValue(
                        subjectExpression: rhs,
                        caseExpression: lhs,
                        operatorSymbol: operatorSymbol
                    ) {
                        return comparison
                    }
                }
                let left = try emitValue(from: lhs)
                let right = try emitValue(from: rhs, expectedEnumName: left.nominalName)
                guard left.type == right.type else {
                    throw LLVMEmissionError("LLVM comparison operands must have matching types.")
                }
                if left.type == "ptr" {
                    return try emitStringComparisonValue(
                        left: left,
                        operatorSymbol: operatorSymbol,
                        right: right
                    )
                }
                if left.type == "double" {
                    let result = nextTemporary()
                    instructions.append(
                        "\(result) = fcmp \(try llvmFloatingPointComparisonPredicate(for: operatorSymbol)) double \(left.operand), \(right.operand)"
                    )
                    return LLVMValue(type: "i1", operand: result, array: nil)
                }
                guard left.type == "i32" || left.type == "i1" else {
                    throw LLVMEmissionError("LLVM comparison currently supports i32, i1, double, and String operands.")
                }
                let result = nextTemporary()
                instructions.append(
                    "\(result) = icmp \(try llvmComparisonPredicate(for: operatorSymbol, operandType: left.type)) \(left.type) \(left.operand), \(right.operand)"
                )
                return LLVMValue(type: "i1", operand: result, array: nil)
            }
        }

        private mutating func emitNilCoalescingValue(
            optionalExpression: RangeCompiler.Expression,
            fallbackExpression: RangeCompiler.Expression
        ) throws -> LLVMValue {
            let optionalValue = try emitValue(from: optionalExpression)
            guard let expectedOptionalLayout = optionalLayout(forStorageType: optionalValue.type) else {
                throw LLVMEmissionError("LLVM nil coalescing requires an Optional value on the left side.")
            }

            let expectedFallbackArrayElementType = arrayLayout(
                for: expectedOptionalLayout.wrappedType
            ).map {
                LLVMType(ir: $0.elementType, array: nil)
            }
            let fallback = try emitValue(
                from: fallbackExpression,
                expectedArrayElementType: expectedFallbackArrayElementType
            )
            guard fallback.type == expectedOptionalLayout.wrappedType else {
                throw LLVMEmissionError(
                    "LLVM nil coalescing expected fallback \(expectedOptionalLayout.wrappedType), got \(fallback.type)."
                )
            }

            let validity = nextTemporary()
            instructions.append(
                "\(validity) = extractvalue \(optionalValue.type) \(optionalValue.operand), 0"
            )
            let payload = nextTemporary()
            instructions.append(
                "\(payload) = extractvalue \(optionalValue.type) \(optionalValue.operand), 1"
            )

            let resultPointer = "%\(nextRawName("coalesce.result"))"
            let payloadLabel = nextLabel("coalesce.payload")
            let fallbackLabel = nextLabel("coalesce.fallback")
            let endLabel = nextLabel("coalesce.end")
            instructions.append("\(resultPointer) = alloca \(fallback.type)")
            instructions.append("br i1 \(validity), label %\(payloadLabel), label %\(fallbackLabel)")
            instructions.append("\(payloadLabel):")
            instructions.append("store \(fallback.type) \(payload), ptr \(resultPointer)")
            instructions.append("br label %\(endLabel)")
            instructions.append("\(fallbackLabel):")
            instructions.append("store \(fallback.type) \(fallback.operand), ptr \(resultPointer)")
            instructions.append("br label %\(endLabel)")
            instructions.append("\(endLabel):")
            let loaded = nextTemporary()
            instructions.append("\(loaded) = load \(fallback.type), ptr \(resultPointer)")
            return LLVMValue(
                type: fallback.type,
                operand: loaded,
                array: fallback.array ?? arrayLayout(for: fallback.type),
                optional: fallback.optional ?? optionalLayout(forStorageType: fallback.type),
                nominalName: fallback.nominalName ?? nominalName(forStorageType: fallback.type)
            )
        }

        private mutating func emitOptionalNilComparisonValue(
            value: LLVMValue,
            operatorSymbol: BinaryOperator
        ) throws -> LLVMValue {
            guard optionalLayout(forStorageType: value.type) != nil else {
                throw LLVMEmissionError("LLVM nil comparison requires an Optional value.")
            }
            let validity = nextTemporary()
            instructions.append("\(validity) = extractvalue \(value.type) \(value.operand), 0")
            let result = nextTemporary()
            let predicate = operatorSymbol == .equal ? "eq" : "ne"
            instructions.append("\(result) = icmp \(predicate) i1 \(validity), 0")
            return LLVMValue(type: "i1", operand: result, array: nil)
        }

        private mutating func emitNoPayloadEnumCaseComparisonValue(
            subjectExpression: RangeCompiler.Expression,
            caseExpression: RangeCompiler.Expression,
            operatorSymbol: BinaryOperator
        ) throws -> LLVMValue? {
            guard isEnumCaseExpressionSyntax(caseExpression) else {
                return nil
            }
            let subject = try emitValue(from: subjectExpression)
            guard let enumName = subject.nominalName,
                let caseTag = noPayloadEnumCaseTag(
                    in: caseExpression,
                    expectedEnumName: enumName
                )
            else {
                return nil
            }
            let predicate = operatorSymbol == .equal ? "eq" : "ne"
            let subjectTag: String
            if enumLayouts[enumName]?.hasPayload == true {
                let extracted = nextTemporary()
                instructions.append("\(extracted) = extractvalue \(subject.type) \(subject.operand), 0")
                subjectTag = extracted
            } else {
                subjectTag = subject.operand
            }
            let result = nextTemporary()
            instructions.append("\(result) = icmp \(predicate) i32 \(subjectTag), \(caseTag)")
            return LLVMValue(type: "i1", operand: result, array: nil)
        }

        private func isEnumCaseExpressionSyntax(_ expression: RangeCompiler.Expression) -> Bool {
            switch expression {
            case .identifier(let name):
                return name.hasPrefix(".") || enumName(fromQualifiedCaseName: name) != nil
            case .call(let name, let arguments):
                return arguments.isEmpty
                    && (name.hasPrefix(".") || enumName(fromQualifiedCaseName: name) != nil)
            default:
                return false
            }
        }

        private func noPayloadEnumCaseTag(
            in expression: RangeCompiler.Expression,
            expectedEnumName: String
        ) -> Int? {
            let name: String
            switch expression {
            case .identifier(let identifier):
                name = identifier
            case .call(let callName, let arguments) where arguments.isEmpty:
                name = callName
            default:
                return nil
            }
            let enumName = enumName(fromQualifiedCaseName: name) ?? expectedEnumName
            guard enumName == expectedEnumName,
                let layout = enumLayouts[enumName]
            else {
                return nil
            }
            let caseName = normalizedEnumCaseName(name)
            guard let caseLayout = layout.cases[caseName],
                caseLayout.associatedValues.isEmpty
            else {
                return nil
            }
            return caseLayout.tag
        }

        private mutating func emitUnaryValue(
            operatorSymbol: UnaryOperator,
            expression: RangeCompiler.Expression
        ) throws -> LLVMValue {
            switch operatorSymbol {
            case .not:
                let value = try emitValue(from: expression)
                guard value.type == "i1" else {
                    throw LLVMEmissionError("LLVM boolean not requires an i1 operand.")
                }
                let result = nextTemporary()
                instructions.append("\(result) = xor i1 \(value.operand), true")
                return LLVMValue(type: "i1", operand: result, array: nil)
            }
        }

        private mutating func emitStringComparisonValue(
            left: LLVMValue,
            operatorSymbol: BinaryOperator,
            right: LLVMValue
        ) throws -> LLVMValue {
            runtime.markUsesStrcmp()
            let comparison = nextTemporary()
            instructions.append(
                "\(comparison) = call i32 @strcmp(ptr \(left.operand), ptr \(right.operand))"
            )
            let result = nextTemporary()
            let predicate = try llvmStringComparisonPredicate(for: operatorSymbol)
            instructions.append("\(result) = icmp \(predicate) i32 \(comparison), 0")
            return LLVMValue(type: "i1", operand: result, array: nil)
        }

        private func llvmStringComparisonPredicate(for operatorSymbol: BinaryOperator) throws -> String {
            switch operatorSymbol {
            case .equal:
                return "eq"
            case .notEqual:
                return "ne"
            case .less:
                return "slt"
            case .lessEqual:
                return "sle"
            case .greater:
                return "sgt"
            case .greaterEqual:
                return "sge"
            default:
                throw LLVMEmissionError("LLVM string comparison does not support this operator yet.")
            }
        }

        private func llvmIntegerInstruction(for operatorSymbol: BinaryOperator) throws -> String {
            switch operatorSymbol {
            case .addition:
                return "add"
            case .subtraction:
                return "sub"
            case .multiplication:
                return "mul"
            case .division:
                return "sdiv"
            case .remainder:
                return "srem"
            default:
                throw LLVMEmissionError("LLVM emission currently supports integer arithmetic only.")
            }
        }

        private func llvmFloatingPointInstruction(for operatorSymbol: BinaryOperator) throws -> String {
            switch operatorSymbol {
            case .addition:
                return "fadd"
            case .subtraction:
                return "fsub"
            case .multiplication:
                return "fmul"
            case .division:
                return "fdiv"
            case .remainder:
                return "frem"
            default:
                throw LLVMEmissionError("LLVM emission currently supports basic floating-point arithmetic only.")
            }
        }

        private func llvmFloatingPointComparisonPredicate(for operatorSymbol: BinaryOperator) throws -> String {
            switch operatorSymbol {
            case .equal:
                return "oeq"
            case .notEqual:
                return "one"
            case .less:
                return "olt"
            case .lessEqual:
                return "ole"
            case .greater:
                return "ogt"
            case .greaterEqual:
                return "oge"
            default:
                throw LLVMEmissionError("LLVM floating-point comparison does not support this operator yet.")
            }
        }

        private func llvmComparisonPredicate(
            for operatorSymbol: BinaryOperator,
            operandType: String
        ) throws -> String {
            switch operatorSymbol {
            case .equal:
                return "eq"
            case .notEqual:
                return "ne"
            case .less where operandType == "i32":
                return "slt"
            case .lessEqual where operandType == "i32":
                return "sle"
            case .greater where operandType == "i32":
                return "sgt"
            case .greaterEqual where operandType == "i32":
                return "sge"
            default:
                throw LLVMEmissionError("LLVM ordered comparison requires i32 operands.")
            }
        }

        private mutating func emitI32ReturnOperand(from value: LLVMValue) throws -> String {
            switch value.type {
            case "i32":
                return value.operand
            case "i1":
                let result = nextTemporary()
                instructions.append("\(result) = zext i1 \(value.operand) to i32")
                return result
            default:
                throw LLVMEmissionError("LLVM @main currently returns only i32-compatible values.")
            }
        }

        private mutating func emitExpressionStatement(_ expression: RangeCompiler.Expression) throws {
            switch expression {
            case .call(let name, let arguments):
                try emitFunctionCallStatement(name: name, arguments: arguments)
            default:
                _ = try emitValue(from: expression)
            }
        }

        private mutating func emitFunctionCallStatement(name: String, arguments: [CallArgument]) throws {
            if name == "print" {
                try emitPrintCall(arguments: arguments)
                return
            }
            if name == "writeFile" {
                try emitWriteFileCall(arguments: arguments)
                return
            }
            if name.hasSuffix(".append") {
                try emitArrayAppendCall(name: name, arguments: arguments)
                return
            }
            if name.hasSuffix(".insert") {
                try emitArrayInsertCall(name: name, arguments: arguments)
                return
            }
            if name.hasSuffix(".clear") {
                try emitArrayClearCall(name: name, arguments: arguments)
                return
            }

            let (signature, argumentText) = try emitFunctionCallArguments(
                name: name,
                arguments: arguments
            )
            let call = "call \(signature.returnType.ir) @\(try llvmIdentifier(signature.name))(\(argumentText))"
            if signature.returnType.ir == "void" {
                instructions.append(call)
            } else {
                let ignored = nextTemporary()
                instructions.append("\(ignored) = \(call)")
            }
        }

        private mutating func emitPrintCall(arguments: [CallArgument]) throws {
            guard arguments.count == 1 else {
                throw LLVMEmissionError("print(value:) expects one argument.")
            }
            let argument = arguments[0]
            if let label = argument.label, label != "value" {
                throw LLVMEmissionError("print(value:) argument label must be 'value'.")
            }
            let value = try emitValue(from: argument.value)
            switch value.type {
            case "ptr":
                runtime.markUsesPuts()
                let ignored = nextTemporary()
                instructions.append("\(ignored) = call i32 @puts(ptr \(value.operand))")
            case "i32":
                runtime.markUsesPrintf()
                let format = runtime.stringPointer(for: "%d\n")
                let ignored = nextTemporary()
                instructions.append("\(ignored) = call i32 (ptr, ...) @printf(ptr \(format), i32 \(value.operand))")
            case "double":
                runtime.markUsesPrintf()
                let format = runtime.stringPointer(for: "%f\n")
                let ignored = nextTemporary()
                instructions.append("\(ignored) = call i32 (ptr, ...) @printf(ptr \(format), double \(value.operand))")
            case "i1":
                runtime.markUsesPuts()
                let trueText = runtime.stringPointer(for: "true")
                let falseText = runtime.stringPointer(for: "false")
                let selected = nextTemporary()
                instructions.append(
                    "\(selected) = select i1 \(value.operand), ptr \(trueText), ptr \(falseText)"
                )
                let ignored = nextTemporary()
                instructions.append("\(ignored) = call i32 @puts(ptr \(selected))")
            default:
                throw LLVMEmissionError("print(value:) expects a String, Int, Float, or Bool value.")
            }
        }

        private mutating func emitArrayAppendCall(name: String, arguments: [CallArgument]) throws {
            guard arguments.count == 1 else {
                throw LLVMEmissionError("Array.append(element:) expects one argument.")
            }
            let argument = arguments[0]
            if let label = argument.label, label != "element" {
                throw LLVMEmissionError("Array.append(element:) argument label must be 'element'.")
            }

            let receiverName = String(name.dropLast(".append".count))
            let receiver = try emitArrayMutationReceiver(named: receiverName, operation: "append(element:)")
            guard let array = receiver.array else {
                throw LLVMEmissionError("Array.append(element:) receiver must be an Array.")
            }

            let value = try emitValue(
                from: argument.value,
                expectedEnumName: nominalName(forStorageType: array.elementType),
                expectedArrayElementType: arrayLayout(for: array.elementType).map {
                    LLVMType(ir: $0.elementType, array: arrayLayout(for: $0.elementType))
                }
            )
            guard value.type == array.elementType else {
                throw LLVMEmissionError("Array.append(element:) expected \(array.elementType), got \(value.type).")
            }

            let updated = try emitAppendedArrayValue(arrayValue: receiver.value, layout: array, element: value)
            try storeArrayMutationResult(updated, receiver: receiver)
        }

        private mutating func emitArrayInsertCall(name: String, arguments: [CallArgument]) throws {
            guard arguments.count == 2 else {
                throw LLVMEmissionError("Array.insert(element:index:) expects two arguments.")
            }
            let elementArgument = arguments[0]
            if let label = elementArgument.label, label != "element" {
                throw LLVMEmissionError("Array.insert(element:index:) first argument label must be 'element'.")
            }
            let indexArgument = arguments[1]
            if let label = indexArgument.label, label != "index" {
                throw LLVMEmissionError("Array.insert(element:index:) second argument label must be 'index'.")
            }

            let receiverName = String(name.dropLast(".insert".count))
            let receiver = try emitArrayMutationReceiver(named: receiverName, operation: "insert(element:index:)")
            guard let array = receiver.array else {
                throw LLVMEmissionError("Array.insert(element:index:) receiver must be an Array.")
            }
            let value = try emitValue(
                from: elementArgument.value,
                expectedEnumName: nominalName(forStorageType: array.elementType),
                expectedArrayElementType: arrayLayout(for: array.elementType).map {
                    LLVMType(ir: $0.elementType, array: arrayLayout(for: $0.elementType))
                }
            )
            guard value.type == array.elementType else {
                throw LLVMEmissionError("Array.insert(element:index:) expected \(array.elementType), got \(value.type).")
            }
            let index = try emitValue(from: indexArgument.value)
            guard index.type == "i32" else {
                throw LLVMEmissionError("Array.insert(element:index:) index must be Int.")
            }

            let updated = try emitInsertedArrayValue(
                arrayValue: receiver.value,
                layout: array,
                element: value,
                index: index
            )
            try storeArrayMutationResult(updated, receiver: receiver)
        }

        private mutating func emitArrayRemoveCall(name: String, arguments: [CallArgument]) throws -> LLVMValue {
            guard arguments.count == 1 else {
                throw LLVMEmissionError("Array.remove(index:) expects one argument.")
            }
            let argument = arguments[0]
            if let label = argument.label, label != "index" {
                throw LLVMEmissionError("Array.remove(index:) argument label must be 'index'.")
            }

            let receiverName = String(name.dropLast(".remove".count))
            let receiver = try emitArrayMutationReceiver(named: receiverName, operation: "remove(index:)")
            guard let array = receiver.array else {
                throw LLVMEmissionError("Array.remove(index:) receiver must be an Array.")
            }
            let index = try emitValue(from: argument.value)
            guard index.type == "i32" else {
                throw LLVMEmissionError("Array.remove(index:) index must be Int.")
            }

            let removed = try emitRemovedArrayValue(
                arrayValue: receiver.value,
                layout: array,
                index: index
            )
            try storeArrayMutationResult(removed.updatedArray, receiver: receiver)
            return removed.removedElement
        }

        private mutating func emitArrayFirstCall(name: String, arguments: [CallArgument]) throws -> LLVMValue {
            guard arguments.isEmpty else {
                throw LLVMEmissionError("Array.first() expects no arguments.")
            }
            let receiverName = String(name.dropLast(".first".count))
            return try emitArrayOptionalElementCall(
                receiverName: receiverName,
                operation: "first()",
                index: .integer(0)
            )
        }

        private mutating func emitArrayLastCall(name: String, arguments: [CallArgument]) throws -> LLVMValue {
            guard arguments.isEmpty else {
                throw LLVMEmissionError("Array.last() expects no arguments.")
            }
            let receiverName = String(name.dropLast(".last".count))
            let receiver = try emitArrayMutationReceiver(named: receiverName, operation: "last()")
            guard receiver.array != nil else {
                throw LLVMEmissionError("Array.last() receiver must be an Array.")
            }
            let count = nextTemporary()
            instructions.append("\(count) = extractvalue \(receiver.value.type) \(receiver.value.operand), 0")
            let lastIndex = nextTemporary()
            instructions.append("\(lastIndex) = sub i32 \(count), 1")
            return try emitArrayOptionalElementValue(
                receiver: receiver,
                index: LLVMValue(type: "i32", operand: lastIndex, array: nil),
                operation: "last()"
            )
        }

        private mutating func emitArrayOptionalElementCall(
            receiverName: String,
            operation: String,
            index expression: RangeCompiler.Expression
        ) throws -> LLVMValue {
            let receiver = try emitArrayMutationReceiver(named: receiverName, operation: operation)
            guard receiver.array != nil else {
                throw LLVMEmissionError("Array.\(operation) receiver must be an Array.")
            }
            let index = try emitValue(from: expression)
            guard index.type == "i32" else {
                throw LLVMEmissionError("Array.\(operation) index must be Int.")
            }
            return try emitArrayOptionalElementValue(
                receiver: receiver,
                index: index,
                operation: operation
            )
        }

        private mutating func emitArrayOptionalElementValue(
            receiver: ArrayMutationReceiver,
            index: LLVMValue,
            operation: String
        ) throws -> LLVMValue {
            guard let array = receiver.array else {
                throw LLVMEmissionError("Array.\(operation) receiver must be an Array.")
            }
            runtime.registerOptional(wrappedType: array.elementType)
            let optionalType = LLVMType(
                ir: LLVMRuntime.optionalTypeName(for: array.elementType),
                array: nil,
                optional: OptionalLayout(wrappedType: array.elementType)
            )
            let wrappedType = LLVMType(
                ir: array.elementType,
                array: arrayLayout(for: array.elementType),
                optional: optionalLayout(forStorageType: array.elementType),
                nominalName: nominalName(forStorageType: array.elementType)
            )

            let count = nextTemporary()
            instructions.append("\(count) = extractvalue \(receiver.value.type) \(receiver.value.operand), 0")
            let isEmpty = nextTemporary()
            instructions.append("\(isEmpty) = icmp eq i32 \(count), 0")
            let resultPointer = "%\(nextRawName("arrayOptionalElement.result"))"
            let emptyLabel = nextLabel("arrayOptionalElement.empty")
            let valueLabel = nextLabel("arrayOptionalElement.value")
            let endLabel = nextLabel("arrayOptionalElement.end")
            instructions.append("\(resultPointer) = alloca \(optionalType.ir)")
            instructions.append("br i1 \(isEmpty), label %\(emptyLabel), label %\(valueLabel)")
            instructions.append("\(emptyLabel):")
            let nilValue = emitNilOptionalValue(optionalType)
            instructions.append("store \(optionalType.ir) \(nilValue.operand), ptr \(resultPointer)")
            instructions.append("br label %\(endLabel)")
            instructions.append("\(valueLabel):")
            let storage = nextTemporary()
            instructions.append("\(storage) = extractvalue \(receiver.value.type) \(receiver.value.operand), 1")
            let elementPointer = nextTemporary()
            instructions.append(
                "\(elementPointer) = getelementptr inbounds \(array.elementType), ptr \(storage), i32 \(index.operand)"
            )
            let element = nextTemporary()
            instructions.append("\(element) = load \(array.elementType), ptr \(elementPointer)")
            let someValue = try emitSomeOptionalValue(
                LLVMValue(
                    type: array.elementType,
                    operand: element,
                    array: arrayLayout(for: array.elementType),
                    optional: optionalLayout(forStorageType: array.elementType),
                    nominalName: nominalName(forStorageType: array.elementType)
                ),
                optionalType: optionalType,
                wrappedType: wrappedType
            )
            instructions.append("store \(optionalType.ir) \(someValue.operand), ptr \(resultPointer)")
            instructions.append("br label %\(endLabel)")
            instructions.append("\(endLabel):")
            let loaded = nextTemporary()
            instructions.append("\(loaded) = load \(optionalType.ir), ptr \(resultPointer)")
            return LLVMValue(
                type: optionalType.ir,
                operand: loaded,
                array: nil,
                optional: optionalType.optional
            )
        }

        private mutating func emitArrayRemoveLastCall(name: String, arguments: [CallArgument]) throws -> LLVMValue {
            guard arguments.isEmpty else {
                throw LLVMEmissionError("Array.removeLast() expects no arguments.")
            }

            let receiverName = String(name.dropLast(".removeLast".count))
            let receiver = try emitArrayMutationReceiver(named: receiverName, operation: "removeLast()")
            guard let array = receiver.array else {
                throw LLVMEmissionError("Array.removeLast() receiver must be an Array.")
            }

            runtime.registerOptional(wrappedType: array.elementType)
            let optionalType = LLVMType(
                ir: LLVMRuntime.optionalTypeName(for: array.elementType),
                array: nil,
                optional: OptionalLayout(wrappedType: array.elementType)
            )
            let wrappedType = LLVMType(
                ir: array.elementType,
                array: arrayLayout(for: array.elementType),
                optional: optionalLayout(forStorageType: array.elementType),
                nominalName: nominalName(forStorageType: array.elementType)
            )

            let count = nextTemporary()
            instructions.append("\(count) = extractvalue \(receiver.value.type) \(receiver.value.operand), 0")
            let isEmpty = nextTemporary()
            instructions.append("\(isEmpty) = icmp eq i32 \(count), 0")
            let resultPointer = "%\(nextRawName("removeLast.result"))"
            let emptyLabel = nextLabel("removeLast.empty")
            let valueLabel = nextLabel("removeLast.value")
            let endLabel = nextLabel("removeLast.end")
            instructions.append("\(resultPointer) = alloca \(optionalType.ir)")
            instructions.append("br i1 \(isEmpty), label %\(emptyLabel), label %\(valueLabel)")
            instructions.append("\(emptyLabel):")
            let nilValue = emitNilOptionalValue(optionalType)
            instructions.append("store \(optionalType.ir) \(nilValue.operand), ptr \(resultPointer)")
            instructions.append("br label %\(endLabel)")
            instructions.append("\(valueLabel):")
            let lastIndex = nextTemporary()
            instructions.append("\(lastIndex) = sub i32 \(count), 1")
            let removed = try emitRemovedArrayValue(
                arrayValue: receiver.value,
                layout: array,
                index: LLVMValue(type: "i32", operand: lastIndex, array: nil)
            )
            try storeArrayMutationResult(removed.updatedArray, receiver: receiver)
            let someValue = try emitSomeOptionalValue(
                removed.removedElement,
                optionalType: optionalType,
                wrappedType: wrappedType
            )
            instructions.append("store \(optionalType.ir) \(someValue.operand), ptr \(resultPointer)")
            instructions.append("br label %\(endLabel)")
            instructions.append("\(endLabel):")
            let loaded = nextTemporary()
            instructions.append("\(loaded) = load \(optionalType.ir), ptr \(resultPointer)")
            return LLVMValue(
                type: optionalType.ir,
                operand: loaded,
                array: nil,
                optional: optionalType.optional
            )
        }

        private mutating func emitArrayClearCall(name: String, arguments: [CallArgument]) throws {
            guard arguments.isEmpty else {
                throw LLVMEmissionError("Array.clear() expects no arguments.")
            }

            let receiverName = String(name.dropLast(".clear".count))
            let receiver = try emitArrayMutationReceiver(named: receiverName, operation: "clear()")
            guard let array = receiver.array else {
                throw LLVMEmissionError("Array.clear() receiver must be an Array.")
            }
            let updated = try emitEmptyArrayValue(arrayValue: receiver.value, layout: array)
            try storeArrayMutationResult(updated, receiver: receiver)
        }

        private struct ArrayMutationReceiver {
            let rootName: String
            let rootLocal: LocalSlot
            let loadedRoot: String
            let fieldPath: [String]
            let value: LLVMValue

            var array: ArrayLayout? {
                value.array
            }
        }

        private mutating func emitArrayMutationReceiver(
            named receiverName: String,
            operation: String
        ) throws -> ArrayMutationReceiver {
            let path = receiverName.split(separator: ".").map(String.init)
            guard let rootName = path.first else {
                throw LLVMEmissionError("Array.\(operation) receiver cannot be empty.")
            }
            guard let local = locals[rootName] else {
                throw LLVMEmissionError("Unknown LLVM array local '\(rootName)'.")
            }

            let loadedRoot = nextTemporary()
            instructions.append("\(loadedRoot) = load \(local.type), ptr \(local.pointer)")
            let fieldPath = Array(path.dropFirst())
            let value: LLVMValue
            if fieldPath.isEmpty {
                value = LLVMValue(
                    type: local.type,
                    operand: loadedRoot,
                    array: local.array,
                    optional: local.optional,
                    nominalName: local.nominalName
                )
            } else {
                value = try emitExtractedFieldValue(
                    aggregateType: local.type,
                    aggregateOperand: loadedRoot,
                    fieldPath: fieldPath
                )
            }
            return ArrayMutationReceiver(
                rootName: rootName,
                rootLocal: local,
                loadedRoot: loadedRoot,
                fieldPath: fieldPath,
                value: value
            )
        }

        private mutating func storeArrayMutationResult(
            _ updated: LLVMValue,
            receiver: ArrayMutationReceiver
        ) throws {
            if receiver.fieldPath.isEmpty {
                instructions.append("store \(updated.type) \(updated.operand), ptr \(receiver.rootLocal.pointer)")
                locals[receiver.rootName] = LocalSlot(
                    pointer: receiver.rootLocal.pointer,
                    type: receiver.rootLocal.type,
                    array: updated.array,
                    optional: receiver.rootLocal.optional,
                    nominalName: receiver.rootLocal.nominalName
                )
                return
            }

            let updatedRoot = try emitInsertedFieldValue(
                aggregateType: receiver.rootLocal.type,
                aggregateOperand: receiver.loadedRoot,
                fieldPath: receiver.fieldPath,
                value: updated
            )
            instructions.append("store \(receiver.rootLocal.type) \(updatedRoot), ptr \(receiver.rootLocal.pointer)")
        }

        private mutating func emitAppendedArrayValue(
            arrayValue: LLVMValue,
            layout array: ArrayLayout,
            element value: LLVMValue
        ) throws -> LLVMValue {
            runtime.markUsesMalloc()
            runtime.markUsesMemcpy()
            let elementByteSize = try llvmByteSize(of: array.elementType)
            let oldCount = nextTemporary()
            instructions.append("\(oldCount) = extractvalue \(arrayValue.type) \(arrayValue.operand), 0")
            let oldStorage = nextTemporary()
            instructions.append("\(oldStorage) = extractvalue \(arrayValue.type) \(arrayValue.operand), 1")
            let newCount = nextTemporary()
            instructions.append("\(newCount) = add i32 \(oldCount), 1")
            let wideOldCount = nextTemporary()
            instructions.append("\(wideOldCount) = sext i32 \(oldCount) to i64")
            let oldByteCount = nextTemporary()
            instructions.append("\(oldByteCount) = mul i64 \(wideOldCount), \(elementByteSize)")
            let wideNewCount = nextTemporary()
            instructions.append("\(wideNewCount) = sext i32 \(newCount) to i64")
            let newByteCount = nextTemporary()
            instructions.append("\(newByteCount) = mul i64 \(wideNewCount), \(elementByteSize)")
            let newStorage = nextTemporary()
            instructions.append("\(newStorage) = call ptr @malloc(i64 \(newByteCount))")
            instructions.append(
                "call void @llvm.memcpy.p0.p0.i64(ptr \(newStorage), ptr \(oldStorage), i64 \(oldByteCount), i1 false)"
            )
            let elementPointer = nextTemporary()
            instructions.append(
                "\(elementPointer) = getelementptr inbounds \(array.elementType), ptr \(newStorage), i32 \(oldCount)"
            )
            instructions.append("store \(array.elementType) \(value.operand), ptr \(elementPointer)")
            let countInserted = nextTemporary()
            instructions.append("\(countInserted) = insertvalue \(arrayValue.type) undef, i32 \(newCount), 0")
            let storageInserted = nextTemporary()
            instructions.append("\(storageInserted) = insertvalue \(arrayValue.type) \(countInserted), ptr \(newStorage), 1")
            return LLVMValue(
                type: arrayValue.type,
                operand: storageInserted,
                array: ArrayLayout(
                    elementType: array.elementType,
                    count: array.count.map { $0 + 1 }
                ),
                optional: arrayValue.optional,
                nominalName: arrayValue.nominalName
            )
        }

        private mutating func emitInsertedArrayValue(
            arrayValue: LLVMValue,
            layout array: ArrayLayout,
            element value: LLVMValue,
            index: LLVMValue
        ) throws -> LLVMValue {
            runtime.markUsesMalloc()
            runtime.markUsesMemcpy()
            let elementByteSize = try llvmByteSize(of: array.elementType)
            let oldCount = nextTemporary()
            instructions.append("\(oldCount) = extractvalue \(arrayValue.type) \(arrayValue.operand), 0")
            let oldStorage = nextTemporary()
            instructions.append("\(oldStorage) = extractvalue \(arrayValue.type) \(arrayValue.operand), 1")
            let newCount = nextTemporary()
            instructions.append("\(newCount) = add i32 \(oldCount), 1")
            let wideIndex = nextTemporary()
            instructions.append("\(wideIndex) = sext i32 \(index.operand) to i64")
            let prefixByteCount = nextTemporary()
            instructions.append("\(prefixByteCount) = mul i64 \(wideIndex), \(elementByteSize)")
            let wideOldCount = nextTemporary()
            instructions.append("\(wideOldCount) = sext i32 \(oldCount) to i64")
            let suffixCount = nextTemporary()
            instructions.append("\(suffixCount) = sub i64 \(wideOldCount), \(wideIndex)")
            let suffixByteCount = nextTemporary()
            instructions.append("\(suffixByteCount) = mul i64 \(suffixCount), \(elementByteSize)")
            let wideNewCount = nextTemporary()
            instructions.append("\(wideNewCount) = sext i32 \(newCount) to i64")
            let newByteCount = nextTemporary()
            instructions.append("\(newByteCount) = mul i64 \(wideNewCount), \(elementByteSize)")
            let newStorage = nextTemporary()
            instructions.append("\(newStorage) = call ptr @malloc(i64 \(newByteCount))")
            instructions.append(
                "call void @llvm.memcpy.p0.p0.i64(ptr \(newStorage), ptr \(oldStorage), i64 \(prefixByteCount), i1 false)"
            )
            let insertedPointer = nextTemporary()
            instructions.append(
                "\(insertedPointer) = getelementptr inbounds \(array.elementType), ptr \(newStorage), i32 \(index.operand)"
            )
            instructions.append("store \(array.elementType) \(value.operand), ptr \(insertedPointer)")
            let oldTailPointer = nextTemporary()
            instructions.append(
                "\(oldTailPointer) = getelementptr inbounds \(array.elementType), ptr \(oldStorage), i32 \(index.operand)"
            )
            let newTailIndex = nextTemporary()
            instructions.append("\(newTailIndex) = add i32 \(index.operand), 1")
            let newTailPointer = nextTemporary()
            instructions.append(
                "\(newTailPointer) = getelementptr inbounds \(array.elementType), ptr \(newStorage), i32 \(newTailIndex)"
            )
            instructions.append(
                "call void @llvm.memcpy.p0.p0.i64(ptr \(newTailPointer), ptr \(oldTailPointer), i64 \(suffixByteCount), i1 false)"
            )
            let countInserted = nextTemporary()
            instructions.append("\(countInserted) = insertvalue \(arrayValue.type) undef, i32 \(newCount), 0")
            let storageInserted = nextTemporary()
            instructions.append("\(storageInserted) = insertvalue \(arrayValue.type) \(countInserted), ptr \(newStorage), 1")
            return LLVMValue(
                type: arrayValue.type,
                operand: storageInserted,
                array: ArrayLayout(
                    elementType: array.elementType,
                    count: array.count.map { $0 + 1 }
                ),
                optional: arrayValue.optional,
                nominalName: arrayValue.nominalName
            )
        }

        private mutating func emitRemovedArrayValue(
            arrayValue: LLVMValue,
            layout array: ArrayLayout,
            index: LLVMValue
        ) throws -> (removedElement: LLVMValue, updatedArray: LLVMValue) {
            runtime.markUsesMalloc()
            runtime.markUsesMemcpy()
            let elementByteSize = try llvmByteSize(of: array.elementType)
            let oldCount = nextTemporary()
            instructions.append("\(oldCount) = extractvalue \(arrayValue.type) \(arrayValue.operand), 0")
            let oldStorage = nextTemporary()
            instructions.append("\(oldStorage) = extractvalue \(arrayValue.type) \(arrayValue.operand), 1")
            let removedPointer = nextTemporary()
            instructions.append(
                "\(removedPointer) = getelementptr inbounds \(array.elementType), ptr \(oldStorage), i32 \(index.operand)"
            )
            let removedElement = nextTemporary()
            instructions.append("\(removedElement) = load \(array.elementType), ptr \(removedPointer)")
            let newCount = nextTemporary()
            instructions.append("\(newCount) = sub i32 \(oldCount), 1")
            let wideIndex = nextTemporary()
            instructions.append("\(wideIndex) = sext i32 \(index.operand) to i64")
            let prefixByteCount = nextTemporary()
            instructions.append("\(prefixByteCount) = mul i64 \(wideIndex), \(elementByteSize)")
            let wideOldCount = nextTemporary()
            instructions.append("\(wideOldCount) = sext i32 \(oldCount) to i64")
            let tailStart = nextTemporary()
            instructions.append("\(tailStart) = add i64 \(wideIndex), 1")
            let suffixCount = nextTemporary()
            instructions.append("\(suffixCount) = sub i64 \(wideOldCount), \(tailStart)")
            let suffixByteCount = nextTemporary()
            instructions.append("\(suffixByteCount) = mul i64 \(suffixCount), \(elementByteSize)")
            let wideNewCount = nextTemporary()
            instructions.append("\(wideNewCount) = sext i32 \(newCount) to i64")
            let newByteCount = nextTemporary()
            instructions.append("\(newByteCount) = mul i64 \(wideNewCount), \(elementByteSize)")
            let newStorage = nextTemporary()
            instructions.append("\(newStorage) = call ptr @malloc(i64 \(newByteCount))")
            instructions.append(
                "call void @llvm.memcpy.p0.p0.i64(ptr \(newStorage), ptr \(oldStorage), i64 \(prefixByteCount), i1 false)"
            )
            let oldTailIndex = nextTemporary()
            instructions.append("\(oldTailIndex) = add i32 \(index.operand), 1")
            let oldTailPointer = nextTemporary()
            instructions.append(
                "\(oldTailPointer) = getelementptr inbounds \(array.elementType), ptr \(oldStorage), i32 \(oldTailIndex)"
            )
            let newTailPointer = nextTemporary()
            instructions.append(
                "\(newTailPointer) = getelementptr inbounds \(array.elementType), ptr \(newStorage), i32 \(index.operand)"
            )
            instructions.append(
                "call void @llvm.memcpy.p0.p0.i64(ptr \(newTailPointer), ptr \(oldTailPointer), i64 \(suffixByteCount), i1 false)"
            )
            let countInserted = nextTemporary()
            instructions.append("\(countInserted) = insertvalue \(arrayValue.type) undef, i32 \(newCount), 0")
            let storageInserted = nextTemporary()
            instructions.append("\(storageInserted) = insertvalue \(arrayValue.type) \(countInserted), ptr \(newStorage), 1")
            let updatedArray = LLVMValue(
                type: arrayValue.type,
                operand: storageInserted,
                array: ArrayLayout(
                    elementType: array.elementType,
                    count: array.count.map { max(0, $0 - 1) }
                ),
                optional: arrayValue.optional,
                nominalName: arrayValue.nominalName
            )
            let removedValue = LLVMValue(
                type: array.elementType,
                operand: removedElement,
                array: arrayLayout(for: array.elementType),
                optional: optionalLayout(forStorageType: array.elementType),
                nominalName: nominalName(forStorageType: array.elementType)
            )
            return (removedValue, updatedArray)
        }

        private mutating func emitEmptyArrayValue(
            arrayValue: LLVMValue,
            layout array: ArrayLayout
        ) throws -> LLVMValue {
            runtime.markUsesMalloc()
            let emptyStorage = nextTemporary()
            instructions.append("\(emptyStorage) = call ptr @malloc(i64 0)")
            let countInserted = nextTemporary()
            instructions.append("\(countInserted) = insertvalue \(arrayValue.type) undef, i32 0, 0")
            let storageInserted = nextTemporary()
            instructions.append("\(storageInserted) = insertvalue \(arrayValue.type) \(countInserted), ptr \(emptyStorage), 1")
            return LLVMValue(
                type: arrayValue.type,
                operand: storageInserted,
                array: ArrayLayout(elementType: array.elementType, count: 0),
                optional: arrayValue.optional,
                nominalName: arrayValue.nominalName
            )
        }

        private mutating func emitFileExistsCall(arguments: [CallArgument]) throws -> LLVMValue {
            guard arguments.count == 1 else {
                throw LLVMEmissionError("fileExists(path:) expects one argument.")
            }
            let argument = arguments[0]
            if let label = argument.label, label != "path" {
                throw LLVMEmissionError("fileExists(path:) argument label must be 'path'.")
            }
            let path = try emitValue(from: argument.value)
            guard path.type == "ptr" else {
                throw LLVMEmissionError("fileExists(path:) expects a String path.")
            }
            runtime.markUsesAccess()
            let result = nextTemporary()
            instructions.append("\(result) = call i32 @access(ptr \(path.operand), i32 0)")
            let exists = nextTemporary()
            instructions.append("\(exists) = icmp eq i32 \(result), 0")
            return LLVMValue(type: "i1", operand: exists, array: nil)
        }

        private mutating func emitReadFileCall(arguments: [CallArgument]) throws -> LLVMValue {
            guard arguments.count == 1 else {
                throw LLVMEmissionError("readFile(path:) expects one argument.")
            }
            let argument = arguments[0]
            if let label = argument.label, label != "path" {
                throw LLVMEmissionError("readFile(path:) argument label must be 'path'.")
            }
            let path = try emitValue(from: argument.value)
            guard path.type == "ptr" else {
                throw LLVMEmissionError("readFile(path:) expects a String path.")
            }

            runtime.markUsesFileRead()
            let mode = runtime.stringPointer(for: "rb")
            let file = nextTemporary()
            instructions.append("\(file) = call ptr @fopen(ptr \(path.operand), ptr \(mode))")
            return try emitReadOpenedFileValue(file)
        }

        private mutating func emitReadFileIfExistsCall(arguments: [CallArgument]) throws -> LLVMValue {
            guard arguments.count == 1 else {
                throw LLVMEmissionError("readFileIfExists(path:) expects one argument.")
            }
            let argument = arguments[0]
            if let label = argument.label, label != "path" {
                throw LLVMEmissionError("readFileIfExists(path:) argument label must be 'path'.")
            }
            let path = try emitValue(from: argument.value)
            guard path.type == "ptr" else {
                throw LLVMEmissionError("readFileIfExists(path:) expects a String path.")
            }

            runtime.markUsesFileRead()
            runtime.registerOptional(wrappedType: "ptr")
            let optionalType = LLVMType(
                ir: LLVMRuntime.optionalTypeName(for: "ptr"),
                array: nil,
                optional: OptionalLayout(wrappedType: "ptr")
            )
            let wrappedType = LLVMType(ir: "ptr", array: nil)
            let resultPointer = "%\(nextRawName("readFileIfExists.result"))"
            instructions.append("\(resultPointer) = alloca \(optionalType.ir)")
            let nilValue = emitNilOptionalValue(optionalType)
            instructions.append("store \(optionalType.ir) \(nilValue.operand), ptr \(resultPointer)")
            let mode = runtime.stringPointer(for: "rb")
            let file = nextTemporary()
            instructions.append("\(file) = call ptr @fopen(ptr \(path.operand), ptr \(mode))")
            let hasFile = nextTemporary()
            instructions.append("\(hasFile) = icmp ne ptr \(file), null")
            let valueLabel = nextLabel("readFileIfExists.value")
            let endLabel = nextLabel("readFileIfExists.end")
            instructions.append("br i1 \(hasFile), label %\(valueLabel), label %\(endLabel)")
            instructions.append("\(valueLabel):")
            let text = try emitReadOpenedFileValue(file)
            let someValue = try emitSomeOptionalValue(
                text,
                optionalType: optionalType,
                wrappedType: wrappedType
            )
            instructions.append("store \(optionalType.ir) \(someValue.operand), ptr \(resultPointer)")
            instructions.append("br label %\(endLabel)")
            instructions.append("\(endLabel):")
            let loaded = nextTemporary()
            instructions.append("\(loaded) = load \(optionalType.ir), ptr \(resultPointer)")
            return LLVMValue(
                type: optionalType.ir,
                operand: loaded,
                array: nil,
                optional: optionalType.optional
            )
        }

        private mutating func emitReadOpenedFileValue(_ file: String) throws -> LLVMValue {
            let seek = nextTemporary()
            instructions.append("\(seek) = call i32 @fseek(ptr \(file), i64 0, i32 2)")
            let size = nextTemporary()
            instructions.append("\(size) = call i64 @ftell(ptr \(file))")
            instructions.append("call void @rewind(ptr \(file))")
            let allocationSize = nextTemporary()
            instructions.append("\(allocationSize) = add i64 \(size), 1")
            let buffer = nextTemporary()
            instructions.append("\(buffer) = call ptr @malloc(i64 \(allocationSize))")
            let readCount = nextTemporary()
            instructions.append("\(readCount) = call i64 @fread(ptr \(buffer), i64 1, i64 \(size), ptr \(file))")
            let terminatorPointer = nextTemporary()
            instructions.append("\(terminatorPointer) = getelementptr inbounds i8, ptr \(buffer), i64 \(readCount)")
            instructions.append("store i8 0, ptr \(terminatorPointer)")
            let close = nextTemporary()
            instructions.append("\(close) = call i32 @fclose(ptr \(file))")
            return LLVMValue(type: "ptr", operand: buffer, array: nil)
        }

        private mutating func emitReadLineCall(arguments: [CallArgument]) throws -> LLVMValue {
            guard arguments.isEmpty else {
                throw LLVMEmissionError("readLine() expects no arguments.")
            }

            runtime.markUsesRead()
            let bufferSize = 4096
            let maxReadSize = bufferSize - 1
            let buffer = nextTemporary()
            instructions.append("\(buffer) = call ptr @malloc(i64 \(bufferSize))")
            let indexPointer = "%\(nextRawName("readLine.index"))"
            instructions.append("\(indexPointer) = alloca i64")
            instructions.append("store i64 0, ptr \(indexPointer)")
            let loopLabel = nextLabel("readLine.loop")
            let readLabel = nextLabel("readLine.read")
            let byteLabel = nextLabel("readLine.byte")
            let continueLabel = nextLabel("readLine.continue")
            let endLabel = nextLabel("readLine.end")
            instructions.append("br label %\(loopLabel)")
            instructions.append("\(loopLabel):")
            let index = nextTemporary()
            instructions.append("\(index) = load i64, ptr \(indexPointer)")
            let hasSpace = nextTemporary()
            instructions.append("\(hasSpace) = icmp slt i64 \(index), \(maxReadSize)")
            instructions.append("br i1 \(hasSpace), label %\(readLabel), label %\(endLabel)")
            instructions.append("\(readLabel):")
            let characterPointer = nextTemporary()
            instructions.append("\(characterPointer) = getelementptr inbounds i8, ptr \(buffer), i64 \(index)")
            let readCount = nextTemporary()
            instructions.append("\(readCount) = call i64 @read(i32 0, ptr \(characterPointer), i64 1)")
            let hasByte = nextTemporary()
            instructions.append("\(hasByte) = icmp eq i64 \(readCount), 1")
            instructions.append("br i1 \(hasByte), label %\(byteLabel), label %\(endLabel)")
            instructions.append("\(byteLabel):")
            let character = nextTemporary()
            instructions.append("\(character) = load i8, ptr \(characterPointer)")
            let isNewline = nextTemporary()
            instructions.append("\(isNewline) = icmp eq i8 \(character), 10")
            instructions.append("br i1 \(isNewline), label %\(endLabel), label %\(continueLabel)")
            instructions.append("\(continueLabel):")
            let nextIndex = nextTemporary()
            instructions.append("\(nextIndex) = add i64 \(index), 1")
            instructions.append("store i64 \(nextIndex), ptr \(indexPointer)")
            instructions.append("br label %\(loopLabel)")
            instructions.append("\(endLabel):")
            let terminatorIndex = nextTemporary()
            instructions.append("\(terminatorIndex) = load i64, ptr \(indexPointer)")
            let terminatorPointer = nextTemporary()
            instructions.append("\(terminatorPointer) = getelementptr inbounds i8, ptr \(buffer), i64 \(terminatorIndex)")
            instructions.append("store i8 0, ptr \(terminatorPointer)")
            return LLVMValue(type: "ptr", operand: buffer, array: nil)
        }

        private mutating func emitCommandLineArgumentCountCall(arguments: [CallArgument]) throws -> LLVMValue {
            guard arguments.isEmpty else {
                throw LLVMEmissionError("commandLineArgumentCount() expects no arguments.")
            }

            runtime.markUsesCommandLineArguments()
            let argcPointer = nextTemporary()
            instructions.append("\(argcPointer) = call ptr @_NSGetArgc()")
            let argc = nextTemporary()
            instructions.append("\(argc) = load i32, ptr \(argcPointer)")
            let userArgumentCount = nextTemporary()
            instructions.append("\(userArgumentCount) = sub i32 \(argc), 1")
            return LLVMValue(type: "i32", operand: userArgumentCount, array: nil)
        }

        private mutating func emitCommandLineArgumentCall(arguments: [CallArgument]) throws -> LLVMValue {
            guard arguments.count == 1 else {
                throw LLVMEmissionError("commandLineArgument(index:) expects one argument.")
            }
            let argument = arguments[0]
            if let label = argument.label, label != "index" {
                throw LLVMEmissionError("commandLineArgument(index:) argument label must be 'index'.")
            }
            let requestedIndex = try emitValue(from: argument.value)
            guard requestedIndex.type == "i32" else {
                throw LLVMEmissionError("commandLineArgument(index:) index must be Int.")
            }

            runtime.markUsesCommandLineArguments()
            runtime.registerOptional(wrappedType: "ptr")
            let optionalType = LLVMType(
                ir: LLVMRuntime.optionalTypeName(for: "ptr"),
                array: nil,
                optional: OptionalLayout(wrappedType: "ptr")
            )
            let wrappedType = LLVMType(ir: "ptr", array: nil)

            let resultPointer = "%\(nextRawName("commandLineArgument.result"))"
            instructions.append("\(resultPointer) = alloca \(optionalType.ir)")
            let nilValue = emitNilOptionalValue(optionalType)
            instructions.append("store \(optionalType.ir) \(nilValue.operand), ptr \(resultPointer)")

            let argcPointer = nextTemporary()
            instructions.append("\(argcPointer) = call ptr @_NSGetArgc()")
            let argc = nextTemporary()
            instructions.append("\(argc) = load i32, ptr \(argcPointer)")
            let isNonNegative = nextTemporary()
            instructions.append("\(isNonNegative) = icmp sge i32 \(requestedIndex.operand), 0")
            let actualArgvIndex = nextTemporary()
            instructions.append("\(actualArgvIndex) = add i32 \(requestedIndex.operand), 1")
            let isInBounds = nextTemporary()
            instructions.append("\(isInBounds) = icmp slt i32 \(actualArgvIndex), \(argc)")
            let canRead = nextTemporary()
            instructions.append("\(canRead) = and i1 \(isNonNegative), \(isInBounds)")
            let valueLabel = nextLabel("commandLineArgument.value")
            let endLabel = nextLabel("commandLineArgument.end")
            instructions.append("br i1 \(canRead), label %\(valueLabel), label %\(endLabel)")
            instructions.append("\(valueLabel):")
            let argvPointerPointer = nextTemporary()
            instructions.append("\(argvPointerPointer) = call ptr @_NSGetArgv()")
            let argvPointer = nextTemporary()
            instructions.append("\(argvPointer) = load ptr, ptr \(argvPointerPointer)")
            let argumentPointerPointer = nextTemporary()
            instructions.append(
                "\(argumentPointerPointer) = getelementptr inbounds ptr, ptr \(argvPointer), i32 \(actualArgvIndex)"
            )
            let argumentPointer = nextTemporary()
            instructions.append("\(argumentPointer) = load ptr, ptr \(argumentPointerPointer)")
            let someValue = try emitSomeOptionalValue(
                LLVMValue(type: "ptr", operand: argumentPointer, array: nil),
                optionalType: optionalType,
                wrappedType: wrappedType
            )
            instructions.append("store \(optionalType.ir) \(someValue.operand), ptr \(resultPointer)")
            instructions.append("br label %\(endLabel)")
            instructions.append("\(endLabel):")
            let loaded = nextTemporary()
            instructions.append("\(loaded) = load \(optionalType.ir), ptr \(resultPointer)")
            return LLVMValue(
                type: optionalType.ir,
                operand: loaded,
                array: nil,
                optional: optionalType.optional
            )
        }

        private mutating func emitWriteFileCall(arguments: [CallArgument]) throws {
            guard arguments.count == 2 else {
                throw LLVMEmissionError("writeFile(path:text:) expects two arguments.")
            }
            let pathArgument = arguments[0]
            if let label = pathArgument.label, label != "path" {
                throw LLVMEmissionError("writeFile(path:text:) first argument label must be 'path'.")
            }
            let textArgument = arguments[1]
            if let label = textArgument.label, label != "text" {
                throw LLVMEmissionError("writeFile(path:text:) second argument label must be 'text'.")
            }
            let path = try emitValue(from: pathArgument.value)
            guard path.type == "ptr" else {
                throw LLVMEmissionError("writeFile(path:text:) expects a String path.")
            }
            let text = try emitValue(from: textArgument.value)
            guard text.type == "ptr" else {
                throw LLVMEmissionError("writeFile(path:text:) expects String text.")
            }

            runtime.markUsesFileWrite()
            let mode = runtime.stringPointer(for: "wb")
            let file = nextTemporary()
            instructions.append("\(file) = call ptr @fopen(ptr \(path.operand), ptr \(mode))")
            let length = nextTemporary()
            instructions.append("\(length) = call i64 @strlen(ptr \(text.operand))")
            let written = nextTemporary()
            instructions.append("\(written) = call i64 @fwrite(ptr \(text.operand), i64 1, i64 \(length), ptr \(file))")
            let close = nextTemporary()
            instructions.append("\(close) = call i32 @fclose(ptr \(file))")
        }

        private mutating func emitStringLengthCall(arguments: [CallArgument]) throws -> LLVMValue {
            guard arguments.count == 1 else {
                throw LLVMEmissionError("stringLength(value:) expects one argument.")
            }
            let argument = arguments[0]
            if let label = argument.label, label != "value" {
                throw LLVMEmissionError("stringLength(value:) argument label must be 'value'.")
            }
            let value = try emitValue(from: argument.value)
            guard value.type == "ptr" else {
                throw LLVMEmissionError("stringLength(value:) expects a String value.")
            }
            runtime.markUsesStrlen()
            let wideLength = nextTemporary()
            instructions.append("\(wideLength) = call i64 @strlen(ptr \(value.operand))")
            let length = nextTemporary()
            instructions.append("\(length) = trunc i64 \(wideLength) to i32")
            return LLVMValue(type: "i32", operand: length, array: nil)
        }

        private mutating func emitStringMemberCall(
            name: String,
            arguments: [CallArgument]
        ) throws -> LLVMValue {
            if name.hasSuffix(".character") {
                let receiverName = String(name.dropLast(".character".count))
                return try emitStringCharacterCall(receiverName: receiverName, arguments: arguments)
            }
            if name.hasSuffix(".substring") {
                let receiverName = String(name.dropLast(".substring".count))
                return try emitStringSubstringCall(receiverName: receiverName, arguments: arguments)
            }
            throw LLVMEmissionError("Unknown LLVM String member call '\(name)'.")
        }

        private mutating func emitStringCharacterCall(
            receiverName: String,
            arguments: [CallArgument]
        ) throws -> LLVMValue {
            guard arguments.count == 1 else {
                throw LLVMEmissionError("String.character(index:) expects one argument.")
            }
            let argument = arguments[0]
            if let label = argument.label, label != "index" {
                throw LLVMEmissionError("String.character(index:) argument label must be 'index'.")
            }

            let receiver = try emitValue(from: .identifier(receiverName))
            guard receiver.type == "ptr", receiver.array == nil else {
                throw LLVMEmissionError("String.character(index:) receiver must be a String.")
            }
            let index = try emitValue(from: argument.value)
            guard index.type == "i32" else {
                throw LLVMEmissionError("String.character(index:) index must be Int.")
            }

            runtime.markUsesMalloc()
            let wideIndex = nextTemporary()
            instructions.append("\(wideIndex) = sext i32 \(index.operand) to i64")
            let sourcePointer = nextTemporary()
            instructions.append("\(sourcePointer) = getelementptr inbounds i8, ptr \(receiver.operand), i64 \(wideIndex)")
            let character = nextTemporary()
            instructions.append("\(character) = load i8, ptr \(sourcePointer)")
            let buffer = nextTemporary()
            instructions.append("\(buffer) = call ptr @malloc(i64 2)")
            instructions.append("store i8 \(character), ptr \(buffer)")
            let terminatorPointer = nextTemporary()
            instructions.append("\(terminatorPointer) = getelementptr inbounds i8, ptr \(buffer), i64 1")
            instructions.append("store i8 0, ptr \(terminatorPointer)")
            return LLVMValue(type: "ptr", operand: buffer, array: nil)
        }

        private mutating func emitStringSubstringCall(
            receiverName: String,
            arguments: [CallArgument]
        ) throws -> LLVMValue {
            guard arguments.count == 2 else {
                throw LLVMEmissionError("String.substring(start:end:) expects two arguments.")
            }
            let startArgument = arguments[0]
            if let label = startArgument.label, label != "start" {
                throw LLVMEmissionError("String.substring(start:end:) first argument label must be 'start'.")
            }
            let endArgument = arguments[1]
            if let label = endArgument.label, label != "end" {
                throw LLVMEmissionError("String.substring(start:end:) second argument label must be 'end'.")
            }

            let receiver = try emitValue(from: .identifier(receiverName))
            guard receiver.type == "ptr", receiver.array == nil else {
                throw LLVMEmissionError("String.substring(start:end:) receiver must be a String.")
            }
            let start = try emitValue(from: startArgument.value)
            guard start.type == "i32" else {
                throw LLVMEmissionError("String.substring(start:end:) start must be Int.")
            }
            let end = try emitValue(from: endArgument.value)
            guard end.type == "i32" else {
                throw LLVMEmissionError("String.substring(start:end:) end must be Int.")
            }

            runtime.markUsesMalloc()
            runtime.markUsesMemcpy()
            let length = nextTemporary()
            instructions.append("\(length) = sub i32 \(end.operand), \(start.operand)")
            let wideStart = nextTemporary()
            instructions.append("\(wideStart) = sext i32 \(start.operand) to i64")
            let wideLength = nextTemporary()
            instructions.append("\(wideLength) = sext i32 \(length) to i64")
            let allocationSize = nextTemporary()
            instructions.append("\(allocationSize) = add i64 \(wideLength), 1")
            let buffer = nextTemporary()
            instructions.append("\(buffer) = call ptr @malloc(i64 \(allocationSize))")
            let sourcePointer = nextTemporary()
            instructions.append("\(sourcePointer) = getelementptr inbounds i8, ptr \(receiver.operand), i64 \(wideStart)")
            instructions.append(
                "call void @llvm.memcpy.p0.p0.i64(ptr \(buffer), ptr \(sourcePointer), i64 \(wideLength), i1 false)"
            )
            let terminatorPointer = nextTemporary()
            instructions.append("\(terminatorPointer) = getelementptr inbounds i8, ptr \(buffer), i64 \(wideLength)")
            instructions.append("store i8 0, ptr \(terminatorPointer)")
            return LLVMValue(type: "ptr", operand: buffer, array: nil)
        }

        private mutating func emitFunctionCallArguments(name: String, arguments: [CallArgument]) throws
            -> (signature: FunctionSignature, argumentText: String)
        {
            let resolvedName = substitutedCallName(name)
            guard let signature = signatures[resolvedName] else {
                throw LLVMEmissionError("Unknown LLVM function '\(resolvedName)'.")
            }

            var emittedArguments: [String] = []
            var argumentIndex = 0
            for parameter in signature.parameters {
                let argumentExpression: RangeCompiler.Expression
                if argumentIndex < arguments.count,
                    callArgument(arguments[argumentIndex], matches: parameter)
                {
                    argumentExpression = arguments[argumentIndex].value
                    argumentIndex += 1
                } else if let defaultValue = parameter.defaultValue {
                    argumentExpression = defaultValue
                } else {
                    throw LLVMEmissionError(
                        "LLVM function '\(resolvedName)' missing argument '\(parameter.name)'."
                    )
                }

                let value = try emitFunctionArgumentValue(
                    from: argumentExpression,
                    parameter: parameter,
                    functionName: resolvedName
                )
                guard value.type == parameter.type.ir else {
                    throw LLVMEmissionError("LLVM function '\(resolvedName)' argument '\(parameter.name)' expected \(parameter.type.ir), got \(value.type).")
                }
                emittedArguments.append("\(value.type) \(value.operand)")
            }
            guard argumentIndex == arguments.count else {
                let argument = arguments[argumentIndex]
                let rendered = argument.label ?? "_"
                throw LLVMEmissionError(
                    "LLVM function '\(resolvedName)' has no parameter matching argument '\(rendered)'."
                )
            }

            return (signature, emittedArguments.joined(separator: ", "))
        }

        private func callArgument(
            _ argument: CallArgument,
            matches parameter: FunctionParameterSignature
        ) -> Bool {
            guard let label = argument.label else {
                return true
            }
            return label == parameter.externalLabel || label == parameter.name
        }

        private mutating func emitFunctionArgumentValue(
            from expression: RangeCompiler.Expression,
            parameter: FunctionParameterSignature,
            functionName: String
        ) throws -> LLVMValue {
            if let typeReference = parameter.typeReference,
                let optionalContext = try optionalContext(for: typeReference)
            {
                return try emitOptionalValue(
                    from: expression,
                    optionalType: optionalContext.optional,
                    wrappedType: optionalContext.wrapped,
                    wrappedReference: optionalContext.wrappedReference
                )
            }

            let value = try emitValue(
                from: expression,
                expectedEnumName: parameter.type.nominalName,
                expectedArrayElementType: parameter.type.array.map {
                    LLVMType(ir: $0.elementType, array: nil)
                }
            )
            guard let expectedArray = parameter.type.array else {
                return value
            }
            guard let valueArray = value.array else {
                throw LLVMEmissionError("LLVM function '\(functionName)' argument '\(parameter.name)' expects an array value.")
            }
            guard valueArray.elementType == expectedArray.elementType else {
                throw LLVMEmissionError(
                    "LLVM function '\(functionName)' argument '\(parameter.name)' expected array element \(expectedArray.elementType), got \(valueArray.elementType)."
                )
            }
            return value
        }

        private mutating func emitFunctionCall(name: String, arguments: [CallArgument]) throws -> LLVMValue {
            let (signature, argumentText) = try emitFunctionCallArguments(
                name: name,
                arguments: arguments
            )
            if signature.returnType.ir == "void" {
                throw LLVMEmissionError("Void function calls are not values yet.")
            }

            let result = nextTemporary()
            instructions.append(
                "\(result) = call \(signature.returnType.ir) @\(try llvmIdentifier(signature.name))(\(argumentText))"
            )
            return LLVMValue(
                type: signature.returnType.ir,
                operand: result,
                array: signature.returnType.array,
                optional: signature.returnType.optional,
                nominalName: signature.returnType.nominalName
            )
        }

        private mutating func emitReturnValue(_ value: LLVMValue) throws -> LLVMValue {
            switch (currentReturnType, value.type) {
            case let (expected, actual) where expected == actual:
                return value
            case ("i32", "i1"):
                let result = nextTemporary()
                instructions.append("\(result) = zext i1 \(value.operand) to i32")
                return LLVMValue(type: "i32", operand: result, array: nil)
            case ("void", _):
                throw LLVMEmissionError("LLVM void functions cannot return a value.")
            default:
                throw LLVMEmissionError("LLVM return expected \(currentReturnType), got \(value.type).")
            }
        }

        private mutating func emitCondition(from expression: RangeCompiler.Expression) throws -> String {
            let value = try emitValue(from: expression)
            switch value.type {
            case "i1":
                return value.operand
            case "i32":
                let result = nextTemporary()
                instructions.append("\(result) = icmp ne i32 \(value.operand), 0")
                return result
            case "double":
                let result = nextTemporary()
                instructions.append("\(result) = fcmp one double \(value.operand), 0.0")
                return result
            default:
                if optionalLayout(forStorageType: value.type) != nil {
                    let result = nextTemporary()
                    instructions.append("\(result) = extractvalue \(value.type) \(value.operand), 0")
                    return result
                }
                throw LLVMEmissionError("LLVM branch conditions must be i1, i32, or double.")
            }
        }

        private func llvmByteSize(of type: String) throws -> Int {
            switch type {
            case "i1":
                return 1
            case "i32":
                return 4
            case "double":
                return 8
            case "ptr":
                return 8
            case _ where arrayLayout(for: type) != nil:
                return 16
            case _ where optionalLayout(forStorageType: type) != nil:
                guard let layout = optionalLayout(forStorageType: type) else {
                    throw LLVMEmissionError("LLVM array literals do not support element type '\(type)' yet.")
                }
                return try 1 + llvmByteSize(of: layout.wrappedType)
            case _ where constructLayout(forStorageType: type) != nil:
                guard let layout = constructLayout(forStorageType: type) else {
                    throw LLVMEmissionError("LLVM array literals do not support element type '\(type)' yet.")
                }
                return try layout.fields.reduce(0) { size, field in
                    try size + llvmByteSize(of: field.type)
                }
            case _ where enumLayout(forStorageType: type) != nil:
                guard let layout = enumLayout(forStorageType: type) else {
                    throw LLVMEmissionError("LLVM array literals do not support element type '\(type)' yet.")
                }
                return try layout.payloadFields.reduce(4) { size, field in
                    try size + llvmByteSize(of: field.type)
                }
            default:
                throw LLVMEmissionError("LLVM array literals do not support element type '\(type)' yet.")
            }
        }

        private mutating func nextTemporary() -> String {
            defer { temporaryIndex += 1 }
            return "%\(temporaryIndex)"
        }

        private mutating func nextRawName(_ prefix: String) -> String {
            defer { temporaryIndex += 1 }
            return "\(prefix).\(temporaryIndex)"
        }

        private func llvmDoubleLiteral(_ value: Double) -> String {
            if value.isFinite {
                return String(value)
            }
            return String(format: "0x%016llX", value.bitPattern)
        }

        private mutating func nextLabel(_ prefix: String) -> String {
            defer { labelIndex += 1 }
            return "\(prefix).\(labelIndex)"
        }

        private func renderFunction(
            name: String,
            returnType: String,
            parameters: [String]
        ) -> String {
            let body = instructions.map { line in
                line.hasSuffix(":") ? line : "  \(line)"
            }.joined(separator: "\n")
            return """
            define \(returnType) @\(name)(\(parameters.joined(separator: ", "))) {
            entry:
            \(body)
            }

            """
        }

        private func substituted(_ typeReference: TypeReference) -> TypeReference {
            switch typeReference {
            case .named(let name):
                return genericSubstitution[name] ?? typeReference
            case .member(let base, let name):
                return .member(base: substituted(base), name: name)
            case .generic(let base, let arguments):
                return .generic(
                    base: substituted(base),
                    arguments: arguments.map(substituted)
                )
            case .array(let element):
                return .array(substituted(element))
            case .function(let parameters, let returnType):
                return .function(
                    parameters: parameters.map(substituted),
                    returnType: substituted(returnType)
                )
            case .optional(let wrapped):
                return .optional(substituted(wrapped))
            case .variadic(let element):
                return .variadic(substituted(element))
            }
        }

        private func substitutedCallName(_ name: String) -> String {
            guard !genericSubstitution.isEmpty,
                name.hasSuffix(">"),
                let genericStart = topLevelGenericArgumentStart(in: name)
            else {
                return name
            }
            let baseName = String(name[..<genericStart])
            let rawArguments = String(
                name[name.index(after: genericStart)..<name.index(before: name.endIndex)]
            )
            let arguments = splitTopLevelCommaList(rawArguments)
                .map(parseRenderedTypeReference)
                .map(substituted)
            return "\(baseName)<\(arguments.map(\.displayName).joined(separator: ", "))>"
        }

        private func topLevelGenericArgumentStart(in name: String) -> String.Index? {
            var depth = 0
            var candidate: String.Index?
            for index in name.indices {
                switch name[index] {
                case "<":
                    if depth == 0 {
                        candidate = index
                    }
                    depth += 1
                case ">":
                    depth -= 1
                    if depth == 0 && name.index(after: index) != name.endIndex {
                        candidate = nil
                    }
                default:
                    continue
                }
            }
            return depth == 0 ? candidate : nil
        }

        private func splitTopLevelCommaList(_ raw: String) -> [String] {
            var parts: [String] = []
            var current = ""
            var angleDepth = 0
            var bracketDepth = 0
            var parenDepth = 0
            for character in raw {
                switch character {
                case "<":
                    angleDepth += 1
                    current.append(character)
                case ">":
                    angleDepth -= 1
                    current.append(character)
                case "[":
                    bracketDepth += 1
                    current.append(character)
                case "]":
                    bracketDepth -= 1
                    current.append(character)
                case "(":
                    parenDepth += 1
                    current.append(character)
                case ")":
                    parenDepth -= 1
                    current.append(character)
                case "," where angleDepth == 0 && bracketDepth == 0 && parenDepth == 0:
                    parts.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
                    current = ""
                default:
                    current.append(character)
                }
            }
            let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                parts.append(trimmed)
            }
            return parts
        }

        private func parseRenderedTypeReference(_ raw: String) -> TypeReference {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("["), trimmed.hasSuffix("]") {
                return .array(parseRenderedTypeReference(String(trimmed.dropFirst().dropLast())))
            }
            if trimmed.hasSuffix("?") {
                return .optional(parseRenderedTypeReference(String(trimmed.dropLast())))
            }
            if trimmed.hasSuffix(">"),
                let genericStart = topLevelGenericArgumentStart(in: trimmed)
            {
                let base = parseRenderedTypeReference(String(trimmed[..<genericStart]))
                let rawArguments = String(
                    trimmed[trimmed.index(after: genericStart)..<trimmed.index(before: trimmed.endIndex)]
                )
                return .generic(
                    base: base,
                    arguments: splitTopLevelCommaList(rawArguments).map(parseRenderedTypeReference)
                )
            }
            return .named(trimmed)
        }

        private func llvmIdentifier(_ name: String) throws -> String {
            guard !name.isEmpty else {
                throw LLVMEmissionError("LLVM local names cannot be empty.")
            }
            let scalars = name.unicodeScalars
            let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_$.-"))
            guard scalars.allSatisfy({ allowed.contains($0) }) else {
                throw LLVMEmissionError("Unsupported LLVM local name '\(name)'.")
            }
            guard let first = scalars.first,
                !CharacterSet.decimalDigits.contains(first)
            else {
                throw LLVMEmissionError("LLVM local names cannot start with a digit.")
            }
            return name
        }
    }
}
