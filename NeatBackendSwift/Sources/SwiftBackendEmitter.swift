import Foundation
import NeatSyntax

struct SwiftBackendEmitter {
    private struct SwiftEmissionContext {
        var failableInitializersByConstructName: [String: [FailableInitializerSignature]] = [:]
        var genericParameterNames: Set<String> = []

        init() {}

        init(program: LoweredProgram) {
            self.failableInitializersByConstructName = Self.collectFailableInitializers(
                from: Self.allDeclarations(in: program)
            )
            self.failableInitializersByConstructName.merge(
                Self.collectFailableInitializers(from: Self.allExtensions(in: program)),
                uniquingKeysWith: { lhs, rhs in lhs + rhs }
            )
            if Self.programIncludesProtocol(named: "Decodable", in: program) {
                self.failableInitializersByConstructName.merge(
                    Self.nativeScalarDecodableInitializers(),
                    uniquingKeysWith: { lhs, rhs in lhs + rhs }
                )
            }
            self.genericParameterNames = Self.collectGenericParameterNames(from: program)
        }

        private static func collectGenericParameterNames(from program: LoweredProgram) -> Set<String> {
            var names: Set<String> = []

            func record(_ parameters: [GenericParameter]) {
                for parameter in parameters {
                    switch parameter {
                    case .type(let name, _, _), .value(let name, _, _):
                        names.insert(name)
                    }
                }
            }

            func record(_ declaration: ConstructDeclaration) {
                record(declaration.genericParameters)
                for callable in declaration.callables {
                    record(callable.genericParameters)
                }
                for nested in declaration.constructs {
                    record(nested)
                }
            }

            for declaration in allDeclarations(in: program) {
                record(declaration)
            }
            for protocolDeclaration in program.protocols + program.units.flatMap(\.protocols) {
                record(protocolDeclaration.genericParameters)
                for callable in protocolDeclaration.callables {
                    record(callable.genericParameters)
                }
            }
            for extensionDeclaration in allExtensions(in: program) {
                for callable in extensionDeclaration.callables {
                    record(callable.genericParameters)
                }
            }

            return names
        }

        private static func allDeclarations(in program: LoweredProgram) -> [ConstructDeclaration] {
            var declarations = program.declarations
            for unit in program.units {
                declarations.append(contentsOf: unit.declarations)
            }
            return declarations
        }

        private static func allExtensions(in program: LoweredProgram) -> [ExtensionDeclaration] {
            var declarations = program.extensions
            for unit in program.units {
                declarations.append(contentsOf: unit.extensions)
            }
            return declarations
        }

        private static func programIncludesProtocol(
            named name: String,
            in program: LoweredProgram
        ) -> Bool {
            if program.protocols.contains(where: { $0.name == name }) {
                return true
            }

            return program.units.contains { unit in
                unit.protocols.contains(where: { $0.name == name })
            }
        }

        private static func nativeScalarDecodableInitializers()
            -> [String: [FailableInitializerSignature]]
        {
            let failureType = TypeReference.named("DecodingError")
            let signature = { (constructName: String) in
                FailableInitializerSignature(
                    constructName: constructName,
                    labels: ["from"],
                    failureType: failureType
                )
            }

            return [
                "Bool": [signature("Bool")],
                "Float": [signature("Float")],
                "Int": [signature("Int")],
                "String": [signature("String")],
            ]
        }

        private static func collectFailableInitializers(
            from declarations: [ConstructDeclaration]
        ) -> [String: [FailableInitializerSignature]] {
            var signatures: [String: [FailableInitializerSignature]] = [:]

            for declaration in declarations {
                for initializer in declaration.initializers {
                    guard let returnType = initializer.returnType,
                        let failureType = resultSelfFailureType(returnType)
                    else {
                        continue
                    }

                    signatures[declaration.name, default: []].append(
                        FailableInitializerSignature(
                            constructName: declaration.name,
                            labels: initializer.parameters.map(\.externalLabel),
                            failureType: failureType
                        )
                    )
                }
            }

            return signatures
        }

        private static func collectFailableInitializers(
            from extensions: [ExtensionDeclaration]
        ) -> [String: [FailableInitializerSignature]] {
            var signatures: [String: [FailableInitializerSignature]] = [:]

            for declaration in extensions {
                for initializer in declaration.initializers {
                    guard let returnType = initializer.returnType,
                        let failureType = resultSelfFailureType(returnType)
                    else {
                        continue
                    }

                    signatures[declaration.targetName, default: []].append(
                        FailableInitializerSignature(
                            constructName: declaration.targetName,
                            labels: initializer.parameters.map(\.externalLabel),
                            failureType: failureType
                        )
                    )
                }
            }

            return signatures
        }

        private static func resultSelfFailureType(_ typeReference: TypeReference) -> TypeReference? {
            guard case .generic(let base, let arguments) = typeReference,
                case .named("Result") = base,
                arguments.count == 2,
                case .named("Self") = arguments[0]
            else {
                return nil
            }

            return arguments[1]
        }
    }

    private struct FailableInitializerSignature {
        var constructName: String
        var labels: [String?]
        var failureType: TypeReference
    }

    private let swiftNativeTypeNames: Set<String> = [
        "Any",
        "Array",
        "Bool",
        "Data",
        "Dictionary",
        "Double",
        "Float",
        "Int",
        "Never",
        "Optional",
        "Set",
        "String",
        "Void",
    ]

    private typealias NeatExpression = NeatSyntax.Expression
    private typealias NeatStatement = NeatSyntax.Statement
    private let context: SwiftEmissionContext

    init() {
        self.context = SwiftEmissionContext()
    }

    private init(context: SwiftEmissionContext) {
        self.context = context
    }

    func emit(program: LoweredProgram) throws -> String {
        try SwiftBackendEmitter(context: SwiftEmissionContext(program: program))
            .emitProgramWithContext(program)
    }

    private func emitProgramWithContext(_ program: LoweredProgram) throws -> String {
        let allCallables = program.callables + program.declarations.flatMap(\.callables)
        let functions =
            try allCallables
            .filter { $0.targetType == nil }
            .map(emitFunction)
            .joined(separator: "\n\n")
        let protocols = try program.protocols.map(emitProtocol).joined(separator: "\n\n")
        let enumerations = try program.enumerations.map(emitEnum).joined(separator: "\n\n")
        let declarations = try program.declarations.map(emitConstruct).joined(separator: "\n\n")
        let extensions = try program.extensions.map(emitExtension).joined(separator: "\n\n")

        let main = try emitMain(program.mainBlock)

        let sections = [
            "import Foundation",
            emitRuntimeSupport(includeFoundationImport: false),
            protocols,
            program.protocols.contains(where: { $0.name == "Encodable" })
                ? emitNativeEncodingConformances() : "",
            program.protocols.contains(where: { $0.name == "Decodable" })
                ? emitNativeDecodingConformances() : "",
            enumerations,
            declarations,
            extensions,
            functions,
            main,
        ].filter { !$0.isEmpty }

        return sections.joined(separator: "\n\n") + "\n"
    }

    func emitWorkspace(program: LoweredProgram, at root: URL) throws {
        try SwiftBackendEmitter(context: SwiftEmissionContext(program: program))
            .emitWorkspaceWithContext(program: program, at: root)
    }

    private func emitWorkspaceWithContext(program: LoweredProgram, at root: URL) throws {
        let sourcesDirectory = root.appendingPathComponent("Sources", isDirectory: true)
        try FileManager.default.createDirectory(
            at: sourcesDirectory, withIntermediateDirectories: true)

        let packageSwift = """
            // swift-tools-version: 6.2
            import PackageDescription

            let package = Package(
                name: "NeatGenerated",
                platforms: [
                    .macOS(.v13)
                ],
                targets: [
                    .executableTarget(
                        name: "NeatGenerated"
                    )
                ]
            )
            """

        try packageSwift.write(
            to: root.appendingPathComponent("Package.swift"),
            atomically: true,
            encoding: .utf8
        )

        let runtimeSwift = emitRuntimeSupport(includeFoundationImport: true)

        try runtimeSwift.write(
            to: sourcesDirectory.appendingPathComponent("Runtime.swift"),
            atomically: true,
            encoding: .utf8
        )

        for unit in program.units {
            let content = try emitSourceUnit(unit)
            try content.write(
                to: sourcesDirectory.appendingPathComponent(unit.outputFileName),
                atomically: true,
                encoding: .utf8
            )
        }
    }

    private func emitRuntimeSupport(includeFoundationImport: Bool) -> String {
        let support = """
            // Backend implementation for NeatCore's Promise, Result, ChannelStorage, and Logger surface.
            // NeatCore declares the language-visible API; Swift runtime support lives here.
            enum Neat_Promise<Success, Failure> {
                case loading
                case success(result: Success)
                case failure(cause: Failure)
            }

            enum Neat_Result<Success, Failure> {
                case success(result: Success)
                case failure(cause: Failure)
            }

            final class Neat_ChannelStorage<Element>: @unchecked Sendable {
                private let condition = NSCondition()
                private var buffer: [Element] = []
                private let capacity: Int
                private var closed = false

                init() {
                    self.capacity = 0
                }

                init(capacity: Int) {
                    self.capacity = max(0, capacity)
                }

                func send(element: Element) {
                    condition.lock()
                    defer { condition.unlock() }

                    precondition(!closed, "Cannot send to a closed channel.")

                    if capacity == 0 {
                        while !closed && !buffer.isEmpty {
                            condition.wait()
                        }

                        precondition(!closed, "Cannot send to a closed channel.")

                        buffer.append(element)
                        condition.broadcast()

                        while !closed && !buffer.isEmpty {
                            condition.wait()
                        }
                        return
                    }

                    while !closed && buffer.count >= capacity {
                        condition.wait()
                    }

                    precondition(!closed, "Cannot send to a closed channel.")

                    buffer.append(element)
                    condition.broadcast()
                }

                func receive() -> Element {
                    condition.lock()
                    defer { condition.unlock() }

                    while buffer.isEmpty {
                        if closed {
                            preconditionFailure(
                                "Cannot receive from a closed channel with no remaining elements."
                            )
                        }
                        condition.wait()
                    }

                    let element = buffer.removeFirst()
                    condition.broadcast()
                    return element
                }

                func close() {
                    condition.lock()
                    closed = true
                    condition.broadcast()
                    condition.unlock()
                }
            }

            enum Neat_Logger {
                static func log(_ value: Any) {
                    print(String(describing: value))
                }

                static func debug(_ value: Any) {
                    print(String(describing: value))
                }

                static func info(_ value: Any) {
                    print(String(describing: value))
                }

                static func success(_ value: Any) {
                    print(String(describing: value))
                }

                static func warning(_ value: Any) {
                    print(String(describing: value))
                }

                static func error(_ value: Any) {
                    fputs("\\(String(describing: value))\\n", stderr)
                }
            }

            final class __NeatBinding<Value> {
                private let getter: () -> Value
                private let setter: (Value) -> Void

                init(get: @escaping () -> Value, set: @escaping (Value) -> Void) {
                    self.getter = get
                    self.setter = set
                }

                var value: Value {
                    get { getter() }
                    set { setter(newValue) }
                }
            }

            struct __NeatThrownFailure<Failure>: Error, @unchecked Sendable {
                let failure: Failure
            }

            enum __NeatDeferredControlFlow: Error {
                case returnValue(Any)
                case returnVoid
                case breakLoop
                case continueLoop
            }
            """

        guard includeFoundationImport else {
            return support
        }

        return "import Foundation\n\n\(support)"
    }

    private func emitSourceUnit(_ unit: LoweredSourceUnit) throws -> String {
        var sections: [String] = ["import Foundation"]

        let protocols = try unit.protocols.map(emitProtocol).joined(separator: "\n\n")
        if !protocols.isEmpty {
            sections.append(protocols)
        }

        if unit.protocols.contains(where: { $0.name == "Encodable" }) {
            sections.append(emitNativeEncodingConformances())
        }

        if unit.protocols.contains(where: { $0.name == "Decodable" }) {
            sections.append(emitNativeDecodingConformances())
        }

        let enumerations = try unit.enumerations.map(emitEnum).joined(separator: "\n\n")
        if !enumerations.isEmpty {
            sections.append(enumerations)
        }

        let declarations = try unit.declarations.map(emitConstruct).joined(separator: "\n\n")
        if !declarations.isEmpty {
            sections.append(declarations)
        }

        let extensions = try unit.extensions.map(emitExtension).joined(separator: "\n\n")
        if !extensions.isEmpty {
            sections.append(extensions)
        }

        let functions = try unit.callables
            .filter { $0.targetType == nil }
            .map(emitFunction)
            .joined(separator: "\n\n")

        if !functions.isEmpty {
            sections.append(functions)
        }

        if let mainBlock = unit.mainBlock {
            sections.append(try emitMain(mainBlock))
        }

        return sections.joined(separator: "\n\n") + "\n"
    }

    private func emitNativeEncodingConformances() -> String {
        """
        extension Bool: Neat_Encodable {
            func encode<Output>(to encoder: Neat_Encoder<Output>) -> Neat_Result<Void, Neat_EncodingError> {
                var container = encoder.singleValueContainer()
                return container.encode(self)
            }
        }

        extension Data: Neat_Encodable {
            func encode<Output>(to encoder: Neat_Encoder<Output>) -> Neat_Result<Void, Neat_EncodingError> {
                var container = encoder.singleValueContainer()
                return container.encode(self)
            }
        }

        extension Float: Neat_Encodable {
            func encode<Output>(to encoder: Neat_Encoder<Output>) -> Neat_Result<Void, Neat_EncodingError> {
                var container = encoder.singleValueContainer()
                return container.encode(self)
            }
        }

        extension Int: Neat_Encodable {
            func encode<Output>(to encoder: Neat_Encoder<Output>) -> Neat_Result<Void, Neat_EncodingError> {
                var container = encoder.singleValueContainer()
                return container.encode(self)
            }
        }

        extension String: Neat_Encodable {
            func encode<Output>(to encoder: Neat_Encoder<Output>) -> Neat_Result<Void, Neat_EncodingError> {
                var container = encoder.singleValueContainer()
                return container.encode(self)
            }
        }

        private struct __NeatStringCodingKey: Neat_CodingKey {
            let value: String

            func stringValue() -> String {
                value
            }
        }

        extension Array: Neat_Encodable where Element: Neat_Encodable {
            func encode<Output>(to encoder: Neat_Encoder<Output>) -> Neat_Result<Void, Neat_EncodingError> {
                var container = encoder.unkeyedContainer()

                for element in self {
                    switch container.encode(element) {
                    case .success:
                        continue
                    case .failure(let error):
                        return .failure(cause: error)
                    }
                }

                return .success(result: Void())
            }
        }

        extension Optional: Neat_Encodable where Wrapped: Neat_Encodable {
            func encode<Output>(to encoder: Neat_Encoder<Output>) -> Neat_Result<Void, Neat_EncodingError> {
                switch self {
                case .some(let value):
                    return value.encode(to: encoder)
                case .none:
                    var container = encoder.singleValueContainer()
                    return container.encodeNil()
                }
            }
        }

        extension Dictionary: Neat_Encodable where Key == String, Value: Neat_Encodable {
            func encode<Output>(to encoder: Neat_Encoder<Output>) -> Neat_Result<Void, Neat_EncodingError> {
                var container = encoder.container(keyedBy: __NeatStringCodingKey.self)

                for key in keys.sorted() {
                    guard let value = self[key] else {
                        continue
                    }

                    switch container.encode(value, forKey: __NeatStringCodingKey(value: key)) {
                    case .success:
                        continue
                    case .failure(let error):
                        return .failure(cause: error)
                    }
                }

                return .success(result: Void())
            }
        }

        extension Set: Neat_Encodable where Element: Neat_Encodable {
            func encode<Output>(to encoder: Neat_Encoder<Output>) -> Neat_Result<Void, Neat_EncodingError> {
                var container = encoder.unkeyedContainer()

                for element in self {
                    switch container.encode(element) {
                    case .success:
                        continue
                    case .failure(let error):
                        return .failure(cause: error)
                    }
                }

                return .success(result: Void())
            }
        }
        """
    }

    private func emitNativeDecodingConformances() -> String {
        """
        extension Bool: Neat_Decodable {
            init(from decoder: Neat_Decoder<Neat_JSONValue>) throws {
                let container = decoder.singleValueContainer()
                switch container.decode(Bool.self) {
                case .success(let value):
                    self = value
                case .failure(let error):
                    throw __NeatThrownFailure<Neat_DecodingError>(failure: error)
                }
            }
        }

        extension Float: Neat_Decodable {
            init(from decoder: Neat_Decoder<Neat_JSONValue>) throws {
                let container = decoder.singleValueContainer()
                switch container.decode(Float.self) {
                case .success(let value):
                    self = value
                case .failure(let error):
                    throw __NeatThrownFailure<Neat_DecodingError>(failure: error)
                }
            }
        }

        extension Int: Neat_Decodable {
            init(from decoder: Neat_Decoder<Neat_JSONValue>) throws {
                let container = decoder.singleValueContainer()
                switch container.decode(Int.self) {
                case .success(let value):
                    self = value
                case .failure(let error):
                    throw __NeatThrownFailure<Neat_DecodingError>(failure: error)
                }
            }
        }

        extension String: Neat_Decodable {
            init(from decoder: Neat_Decoder<Neat_JSONValue>) throws {
                let container = decoder.singleValueContainer()
                switch container.decode(String.self) {
                case .success(let value):
                    self = value
                case .failure(let error):
                    throw __NeatThrownFailure<Neat_DecodingError>(failure: error)
                }
            }
        }
        """
    }

    private func emitMain(_ mainBlock: MainBlockNode) throws -> String {
        let body = try emitStatements(mainBlock.body, indent: 2, enclosingReturnType: .named("Void"))

        return """
            @main
            struct NeatMain {
                static func main() throws {
            \(body)
                }
            }
            """
    }

    private func emitFunction(_ callable: CallableDeclaration) throws -> String {
        guard let body = callable.body else {
            throw SwiftBackendError(
                "Swift backend requires function \(callable.name) to have a body.")
        }

        let genericClause = emitGenericClause(callable.genericParameters)
        let genericParameterNames = genericParameterNames(callable.genericParameters)
        let parameters = try callable.parameters.map {
            try emitParameter($0, genericParameterNames: genericParameterNames)
        }.joined(separator: ", ")
        let returnClause = try emitReturnClause(
            callable.returnType,
            genericParameterNames: genericParameterNames
        )
        let functionBody = try emitStatements(
            body,
            indent: 1,
            enclosingReturnType: callable.returnType ?? .named("Void")
        )

        return """
            func \(callable.name)\(genericClause)(\(parameters))\(returnClause) {
            \(functionBody)
            }
            """
    }

    private func emitLocalCallableDeclaration(
        _ declaration: LocalCallableDeclaration,
        indent: Int
    ) throws -> String {
        let callable = CallableDeclaration(
            macros: declaration.macros,
            attribute: declaration.attribute,
            targetType: nil,
            receiverType: nil,
            name: declaration.name,
            genericParameters: declaration.genericParameters,
            hasExplicitParameterClause: declaration.hasExplicitParameterClause,
            parameters: declaration.parameters,
            returnType: declaration.returnType,
            body: declaration.body
        )

        return indentBlock(try emitFunction(callable), level: indent)
    }



    private func emitProtocol(_ declaration: ProtocolDeclaration) throws -> String {
        let genericClause = emitProtocolPrimaryAssociatedTypeClause(declaration.genericParameters)
        let genericParameterNames = genericParameterNames(declaration.genericParameters)
        let conformanceClause = emitConformanceClause(
            declaration.conformances,
            genericParameterNames: genericParameterNames
        )
        let associatedTypeRequirements = declaration.genericParameters.compactMap {
            emitAssociatedTypeRequirement($0, genericParameterNames: genericParameterNames)
        }.joined(separator: "\n")
        let valueRequirements = declaration.values.map {
            "var \($0.name): \(emitDeclaredTypeName($0.typeName, genericParameterNames: genericParameterNames)) { get }"
        }.joined(separator: "\n")
        let stateRequirements = declaration.states.map {
            "var \($0.name): \(emitTypeName($0.type, genericParameterNames: genericParameterNames)) { get set }"
        }.joined(separator: "\n")
        let bindingRequirements = declaration.bindings.map {
            "var \($0.name): \(emitDeclaredTypeName($0.typeName, genericParameterNames: genericParameterNames)) { get set }"
        }.joined(separator: "\n")
        let initializerRequirements = try declaration.initializers.map {
            try emitInitializerRequirement($0, genericParameterNames: genericParameterNames)
        }.joined(separator: "\n")
        let callableRequirements = try declaration.callables.map {
            try emitCallableRequirement(
                $0,
                enclosingProtocolName: declaration.name,
                enclosingGenericParameterNames: genericParameterNames
            )
        }.joined(separator: "\n")

        let memberSections = [
            associatedTypeRequirements,
            valueRequirements,
            stateRequirements,
            bindingRequirements,
            initializerRequirements,
            callableRequirements,
        ].filter { !$0.isEmpty }

        if memberSections.isEmpty {
            return "protocol \(emitSwiftSymbolName(declaration.name))\(genericClause)\(conformanceClause) {}"
        }

        return """
            protocol \(emitSwiftSymbolName(declaration.name))\(genericClause)\(conformanceClause) {
            \(indentBlock(memberSections.joined(separator: "\n"), level: 1))
            }
            """
    }

    private func emitEnum(_ declaration: EnumDeclaration) throws -> String {
        let genericClause = emitGenericClause(declaration.genericParameters)
        let renderedCases = try declaration.cases.map(emitEnumCase).joined(separator: "\n")

        if renderedCases.isEmpty {
            return "enum \(emitSwiftSymbolName(declaration.name))\(genericClause) {}"
        }

        return """
            enum \(emitSwiftSymbolName(declaration.name))\(genericClause) {
            \(indentBlock(renderedCases, level: 1))
            }
            """
    }

    private func emitEnumCase(_ declaration: EnumCaseDeclaration) throws -> String {
        guard !declaration.associatedValues.isEmpty else {
            return "case \(declaration.name)"
        }

        let associatedValues = declaration.associatedValues.map { associatedValue in
            if let label = associatedValue.label {
                return "\(label): \(emitTypeName(associatedValue.typeReference))"
            }
            return emitTypeName(associatedValue.typeReference)
        }.joined(separator: ", ")

        return "case \(declaration.name)(\(associatedValues))"
    }

    private func emitConstruct(_ declaration: ConstructDeclaration) throws -> String {
        let genericClause = emitGenericClause(declaration.genericParameters)
        let genericParameterNames = genericParameterNames(declaration.genericParameters)
        let bindingNames = Set(declaration.bindings.map(\.name))
        let isReferenceType = !declaration.states.isEmpty || !declaration.bindings.isEmpty
        let typeKeyword = isReferenceType ? "final class" : "struct"
        let conformanceClause = emitConformanceClause(
            declaration.conformances,
            genericParameterNames: genericParameterNames
        )
        let conformanceAssociatedTypeAliases = declaration.conformances.compactMap {
            emitConformanceAssociatedTypeAlias(
                $0,
                genericParameterNames: genericParameterNames
            )
        }.joined(separator: "\n")
        let storedValues = try declaration.values.map {
            try emitStoredValue($0, genericParameterNames: genericParameterNames)
        }.joined(separator: "\n")
        let storedStates = try declaration.states.map {
            try emitStoredState($0, genericParameterNames: genericParameterNames)
        }.joined(separator: "\n")
        let storedBindings = try declaration.bindings.map {
            try emitStoredBinding($0, genericParameterNames: genericParameterNames)
        }.joined(separator: "\n")
        let deriveds = try declaration.deriveds.map {
            try emitDerivedMember($0, genericParameterNames: genericParameterNames)
        }.joined(separator: "\n\n")
        let initializers = try declaration.initializers.map {
            try emitInitializer(
                $0,
                genericParameterNames: genericParameterNames,
                bindingNames: bindingNames
            )
        }.joined(
            separator: "\n\n")
        let methods = try declaration.callables
            .filter { $0.targetType == nil }
            .map {
                try emitMethod(
                    $0,
                    constructGenericParameterNames: genericParameterNames,
                    isReferenceType: isReferenceType
                )
            }
            .joined(separator: "\n\n")

        let memberSections = [
            conformanceAssociatedTypeAliases,
            storedValues,
            storedStates,
            storedBindings,
            deriveds,
            initializers,
            methods,
        ].filter { !$0.isEmpty }

        if memberSections.isEmpty {
            return "\(typeKeyword) \(emitSwiftSymbolName(declaration.name))\(genericClause)\(conformanceClause) {\n}"
        }

        let body = memberSections.joined(separator: "\n\n")
        return """
            \(typeKeyword) \(emitSwiftSymbolName(declaration.name))\(genericClause)\(conformanceClause) {
            \(indentBlock(body, level: 1))
            }
            """
    }

    private func emitExtension(_ declaration: ExtensionDeclaration) throws -> String {
        let extensionHeader = emitExtensionHeader(declaration)
        let nestedEnumerations = try declaration.enumerations.map(emitEnum).joined(separator: "\n\n")
        let nestedConstructs = try declaration.constructs.map(emitConstruct).joined(separator: "\n\n")
        let nestedProtocols = try declaration.protocols.map(emitProtocol).joined(separator: "\n\n")
        let genericParameterNames = extensionGenericParameterNames(in: declaration)
        let initializers = try declaration.initializers.map {
            try emitInitializer(
                $0,
                genericParameterNames: genericParameterNames,
                bindingNames: []
            )
        }.joined(separator: "\n\n")
        let methods = try declaration.callables.map {
            try emitMethod($0)
        }.joined(separator: "\n\n")

        let memberSections = [
            nestedProtocols,
            nestedEnumerations,
            nestedConstructs,
            initializers,
            methods,
        ].filter { !$0.isEmpty }

        if memberSections.isEmpty {
            return "\(extensionHeader) {}"
        }

        return """
            \(extensionHeader) {
            \(indentBlock(memberSections.joined(separator: "\n\n"), level: 1))
            }
            """
    }

    private func emitExtensionHeader(_ declaration: ExtensionDeclaration) -> String {
        guard declaration.usesSpecializedTarget,
            case .generic(let base, let arguments) = declaration.targetType
        else {
            return
                "extension \(emitTypeName(declaration.targetType))\(emitConformanceClause(declaration.conformances))"
        }

        let target = emitTypeName(base)
        let conformanceClause = emitConformanceClause(declaration.conformances)
        let genericParameterNames = extensionGenericParameterNames(in: declaration)
        var constraints: [String] = []
        let baseGenericNames = extensionBaseGenericNames(for: base, argumentCount: arguments.count)

        for (index, argument) in arguments.enumerated() {
            guard index < baseGenericNames.count else {
                continue
            }

            let baseGenericName = baseGenericNames[index]
            if case .named(let name) = argument, genericParameterNames.contains(name) {
                if name != baseGenericName {
                    constraints.append("\(baseGenericName) == \(name)")
                }
                continue
            }

            constraints.append("\(baseGenericName) == \(emitTypeName(argument))")
        }

        for constraint in declaration.genericArgumentConstraints {
            constraints.append(
                "\(constraint.parameterName): \(emitTypeName(constraint.constraint))"
            )
        }

        let whereClause = constraints.isEmpty ? "" : " where \(constraints.joined(separator: ", "))"
        return "extension \(target)\(conformanceClause)\(whereClause)"
    }

    private func extensionGenericParameterNames(in declaration: ExtensionDeclaration) -> Set<String> {
        Set(declaration.genericArgumentConstraints.map(\.parameterName))
    }

    private func extensionBaseGenericNames(
        for base: TypeReference,
        argumentCount: Int
    ) -> [String] {
        let targetName = base.displayName
        switch targetName {
        case "Array":
            return ["Element"]
        case "Dictionary":
            return ["Key", "Value"]
        case "Optional":
            return ["Wrapped"]
        case "Result":
            return ["Success", "Failure"]
        case "Set":
            return ["Element"]
        default:
            return (0..<argumentCount).map { "T\($0)" }
        }
    }

    private func emitParameter(
        _ parameter: NeatFunctionParameter,
        genericParameterNames: Set<String> = []
    ) throws -> String {
        guard let typeReference = parameter.typeReference else {
            throw SwiftBackendError("Swift backend requires explicit parameter types.")
        }

        let local = parameter.localName
        let renderedType = emitTypeName(typeReference, genericParameterNames: genericParameterNames)
        if parameter.isBinding {
            switch parameter.externalLabel {
            case .none:
                return "_ \(local): __NeatBinding<\(renderedType)>"
            case .some(let external) where external == local:
                return "\(local): __NeatBinding<\(renderedType)>"
            case .some(let external):
                return "\(external) \(local): __NeatBinding<\(renderedType)>"
            }
        }

        switch parameter.externalLabel {
        case .none:
            return "_ \(local): \(renderedType)"
        case .some(let external) where external == local:
            return "\(local): \(renderedType)"
        case .some(let external):
            return "\(external) \(local): \(renderedType)"
        }
    }

    private func emitReturnClause(
        _ typeReference: TypeReference?,
        genericParameterNames: Set<String> = []
    ) throws -> String {
        guard let typeReference else {
            return ""
        }
        return " -> \(emitTypeName(typeReference, genericParameterNames: genericParameterNames))"
    }

    private func emitTypeName(
        _ typeReference: TypeReference,
        genericParameterNames: Set<String> = []
    ) -> String {
        switch typeReference {
        case .named(let name):
            if swiftNativeTypeNames.contains(name) || genericParameterNames.contains(name) {
                return name
            }
            return emitSwiftSymbolName(name)
        case .member(let base, let name):
            if name == "Type" {
                return "\(emitTypeName(base, genericParameterNames: genericParameterNames)).Type"
            }
            return "\(emitTypeName(base, genericParameterNames: genericParameterNames)).\(name)"
        case .generic(let base, let arguments):
            let renderedArguments = arguments.map {
                emitTypeName($0, genericParameterNames: genericParameterNames)
            }.joined(separator: ", ")
            return "\(emitTypeName(base, genericParameterNames: genericParameterNames))<\(renderedArguments)>"
        case .array(let element):
            return "[\(emitTypeName(element, genericParameterNames: genericParameterNames))]"
        case .function(let parameters, let returnType):
            let renderedParameters = parameters.map {
                emitTypeName($0, genericParameterNames: genericParameterNames)
            }.joined(separator: ", ")
            return "(\(renderedParameters)) -> \(emitTypeName(returnType, genericParameterNames: genericParameterNames))"
        case .optional(let wrapped):
            return "\(emitTypeName(wrapped, genericParameterNames: genericParameterNames))?"
        case .variadic(let element):
            return "\(emitTypeName(element, genericParameterNames: genericParameterNames))..."
        }
    }

    private func emitDeclaredTypeName(
        _ name: String,
        genericParameterNames: Set<String> = []
    ) -> String {
        if name.hasPrefix("["),
            name.hasSuffix("]"),
            name.count > 2
        {
            let elementName = String(name.dropFirst().dropLast())
            return "[\(emitDeclaredTypeName(elementName, genericParameterNames: genericParameterNames))]"
        }

        if name.hasSuffix("?"),
            name.count > 1
        {
            let wrappedName = String(name.dropLast())
            return "\(emitDeclaredTypeName(wrappedName, genericParameterNames: genericParameterNames))?"
        }

        return emitTypeName(.named(name), genericParameterNames: genericParameterNames)
    }

    private func emitGenericClause(
        _ parameters: [GenericParameter],
        inheritedGenericParameterNames: Set<String> = []
    ) -> String {
        guard !parameters.isEmpty else { return "" }
        let localGenericParameterNames = genericParameterNames(parameters)
        let genericParameterNames = inheritedGenericParameterNames.union(localGenericParameterNames)

        let rendered = parameters.compactMap { parameter -> String? in
            switch parameter {
            case .type(let name, let constraint, _):
                if let constraint {
                    return "\(name): \(emitTypeName(constraint, genericParameterNames: genericParameterNames))"
                }
                return name
            case .value:
                return nil
            }
        }

        guard !rendered.isEmpty else { return "" }
        return "<\(rendered.joined(separator: ", "))>"
    }

    private func emitConformanceClause(
        _ conformances: [TypeReference],
        genericParameterNames: Set<String> = []
    ) -> String {
        guard !conformances.isEmpty else { return "" }
        let rendered = conformances.map {
            emitConformanceTypeName($0, genericParameterNames: genericParameterNames)
        }.joined(separator: ", ")
        return ": \(rendered)"
    }

    private func emitConformanceTypeName(
        _ typeReference: TypeReference,
        genericParameterNames: Set<String> = []
    ) -> String {
        switch typeReference {
        case .generic(let base, _):
            return emitTypeName(base, genericParameterNames: genericParameterNames)
        default:
            return emitTypeName(typeReference, genericParameterNames: genericParameterNames)
        }
    }

    private func emitConformanceAssociatedTypeAlias(
        _ typeReference: TypeReference,
        genericParameterNames: Set<String>
    ) -> String? {
        switch typeReference {
        case .generic(.named("Encoder"), let arguments) where arguments.count == 1:
            return
                "typealias Output = \(emitTypeName(arguments[0], genericParameterNames: genericParameterNames))"
        case .generic(.named("Decoder"), let arguments) where arguments.count == 1:
            return
                "typealias Input = \(emitTypeName(arguments[0], genericParameterNames: genericParameterNames))"
        default:
            return nil
        }
    }

    private func emitProtocolPrimaryAssociatedTypeClause(_ parameters: [GenericParameter]) -> String {
        let names = parameters.compactMap { parameter -> String? in
            guard case .type(let name, _, _) = parameter else {
                return nil
            }
            return name
        }

        guard !names.isEmpty else { return "" }
        return "<\(names.joined(separator: ", "))>"
    }

    private func emitAssociatedTypeRequirement(
        _ parameter: GenericParameter,
        genericParameterNames: Set<String>
    ) -> String? {
        guard case .type(let name, let constraint, _) = parameter else {
            return nil
        }

        if let constraint {
            return "associatedtype \(name): \(emitTypeName(constraint, genericParameterNames: genericParameterNames))"
        }

        return "associatedtype \(name)"
    }

    private func emitInitializerRequirement(
        _ initializer: InitializerDeclaration,
        genericParameterNames: Set<String> = []
    ) throws -> String {
        let parameters = try initializer.parameters.map {
            try emitParameter($0, genericParameterNames: genericParameterNames)
        }.joined(separator: ", ")
        let throwsClause = isFailableInitializerReturnType(initializer.returnType) ? " throws" : ""
        return "init(\(parameters))\(throwsClause)"
    }

    private func emitCallableRequirement(
        _ callable: CallableDeclaration,
        enclosingProtocolName: String,
        enclosingGenericParameterNames: Set<String> = []
    ) throws -> String {
        let genericClause = emitGenericClause(
            callable.genericParameters,
            inheritedGenericParameterNames: enclosingGenericParameterNames
        )
        let genericParameterNames = enclosingGenericParameterNames.union(
            genericParameterNames(callable.genericParameters)
        )
        let parameters = try callable.parameters.map {
            try emitParameter($0, genericParameterNames: genericParameterNames)
        }.joined(separator: ", ")
        let returnClause = try emitReturnClause(
            callable.returnType,
            genericParameterNames: genericParameterNames
        )
        let mutatingPrefix = protocolRequirementNeedsMutation(
            callable,
            enclosingProtocolName: enclosingProtocolName
        ) ? "mutating " : ""
        return "\(mutatingPrefix)func \(callable.name)\(genericClause)(\(parameters))\(returnClause)"
    }

    private func protocolRequirementNeedsMutation(
        _ callable: CallableDeclaration,
        enclosingProtocolName: String
    ) -> Bool {
        _ = callable
        return enclosingProtocolName.contains("EncodingContainer")
    }

    private func genericParameterNames(_ parameters: [GenericParameter]) -> Set<String> {
        Set(
            parameters.compactMap { parameter in
                switch parameter {
                case .type(let name, _, _):
                    return name
                case .value:
                    return nil
                }
            }
        )
    }

    private func emitStoredValue(
        _ value: ValueDeclaration,
        genericParameterNames: Set<String> = []
    ) throws -> String {
        if let expression = value.value {
            return "let \(value.name): \(emitDeclaredTypeName(value.typeName, genericParameterNames: genericParameterNames)) = \(try emitExpression(expression))"
        }
        return "let \(value.name): \(emitDeclaredTypeName(value.typeName, genericParameterNames: genericParameterNames))"
    }

    private func emitStoredState(
        _ state: StateDeclaration,
        genericParameterNames: Set<String> = []
    ) throws -> String {
        switch state.storage {
        case .stored(let expression):
            return
                "var \(state.name): \(emitTypeName(state.type, genericParameterNames: genericParameterNames)) = \(try emitExpression(expression))"
        case .declared:
            return "var \(state.name): \(emitTypeName(state.type, genericParameterNames: genericParameterNames))"
        }
    }

    private func emitStoredBinding(
        _ binding: BindingDeclaration,
        genericParameterNames: Set<String> = []
    ) throws -> String {
        switch binding.storage {
        case .plain:
            let typeName = emitDeclaredTypeName(
                binding.typeName,
                genericParameterNames: genericParameterNames
            )
            return """
                private let __binding_\(binding.name): __NeatBinding<\(typeName)>
                var \(binding.name): \(typeName) {
                    get { __binding_\(binding.name).value }
                    set { __binding_\(binding.name).value = newValue }
                }
                """
        case .derived:
            throw SwiftBackendError("Swift backend does not support derived binding storage yet.")
        }
    }

    private func emitLocalBindingExpression(_ declaration: LocalBindingDeclaration) throws -> String
    {
        try emitExpression(declaration.expression)
    }

    private func emitDerivedMember(
        _ derived: DerivedDeclaration,
        genericParameterNames: Set<String> = []
    ) throws -> String {
        guard let body = derived.body else {
            return "var \(derived.name): \(emitDeclaredTypeName(derived.typeName, genericParameterNames: genericParameterNames))"
        }

        if body.count == 1, case .expression(let expression) = body[0] {
            return
                "var \(derived.name): \(emitDeclaredTypeName(derived.typeName, genericParameterNames: genericParameterNames)) { \(try emitExpression(expression)) }"
        }

        let bodyText = try emitStatements(
            body,
            indent: 2,
            enclosingReturnType: .named(derived.typeName)
        )
        return """
            var \(derived.name): \(emitDeclaredTypeName(derived.typeName, genericParameterNames: genericParameterNames)) {
            \(bodyText)
            }
            """
    }

    private func emitInitializer(
        _ initializer: InitializerDeclaration,
        genericParameterNames: Set<String> = [],
        bindingNames: Set<String> = []
    ) throws -> String {
        let parameters = try initializer.parameters.map {
            try emitParameter($0, genericParameterNames: genericParameterNames)
        }.joined(separator: ", ")
        let throwsClause = isFailableInitializerReturnType(initializer.returnType) ? " throws" : ""
        guard let body = initializer.body else {
            return "init(\(parameters))\(throwsClause) {}"
        }

        let bindingParameterNames = Set(initializer.parameters.filter(\.isBinding).map(\.name))
        let functionBody = try emitInitializerStatements(
            body,
            indent: 2,
            bindingNames: bindingNames,
            bindingParameterNames: bindingParameterNames,
            initializerReturnType: initializer.returnType
        )
        return """
            init(\(parameters))\(throwsClause) {
            \(functionBody)
            }
            """
    }

    private func emitMethod(
        _ callable: CallableDeclaration,
        constructGenericParameterNames: Set<String> = [],
        isReferenceType: Bool = false
    ) throws -> String {
        guard let body = callable.body else {
            throw SwiftBackendError(
                "Swift backend requires function \(callable.name) to have a body.")
        }

        let genericClause = emitGenericClause(
            callable.genericParameters,
            inheritedGenericParameterNames: constructGenericParameterNames
        )
        let genericParameterNames = constructGenericParameterNames.union(
            genericParameterNames(callable.genericParameters)
        )
        let parameters = try callable.parameters.map {
            try emitParameter($0, genericParameterNames: genericParameterNames)
        }.joined(separator: ", ")
        let returnClause = try emitReturnClause(
            callable.returnType,
            genericParameterNames: genericParameterNames
        )
        let functionBody = try emitStatements(
            body,
            indent: 2,
            enclosingReturnType: callable.returnType ?? .named("Void")
        )
        let mutatingPrefix = !isReferenceType && methodNeedsMutation(callable) ? "mutating " : ""

        return """
            \(mutatingPrefix)func \(callable.name)\(genericClause)(\(parameters))\(returnClause) {
            \(functionBody)
            }
            """
    }

    private func methodNeedsMutation(_ callable: CallableDeclaration) -> Bool {
        guard let body = callable.body else { return false }
        return statementsContainMutation(body) || statementsCallKnownMutatingMember(body)
    }

    private func statementsContainMutation(_ statements: [NeatStatement]) -> Bool {
        for statement in statements {
            switch statement {
            case .assignment, .compoundAssignment:
                return true
            case .expand:
                continue
            case .macroInvocation(_, _, let body),
                .forEach(_, _, let body),
                .whileLoop(_, let body),
                .derived(_, _, let body):
                if statementsContainMutation(body) {
                    return true
                }
            case .background(let background):
                if statementsContainMutation(background.body) {
                    return true
                }
            case .deferBlock(let deferred):
                if statementsContainMutation(deferred.body) {
                    return true
                }
            case .conditional(let branches):
                if branches.contains(where: { statementsContainMutation($0.body) }) {
                    return true
                }
            case .switchStatement(_, let cases, let defaultBody):
                if cases.contains(where: { statementsContainMutation($0.body) }) {
                    return true
                }
                if let defaultBody, statementsContainMutation(defaultBody) {
                    return true
                }
            case .localBinding, .localCallable, .environmentProvision, .expression, .return, .break, .continue:
                continue
            }
        }

        return false
    }

    private func statementsCallKnownMutatingMember(_ statements: [NeatStatement]) -> Bool {
        for statement in statements {
            switch statement {
            case .expression(let expression), .return(let expression?):
                if expressionCallsKnownMutatingMember(expression) {
                    return true
                }
            case .localBinding(let declaration):
                if expressionCallsKnownMutatingMember(declaration.expression) {
                    return true
                }
            case .assignment(_, let expression), .compoundAssignment(_, _, let expression):
                if expressionCallsKnownMutatingMember(expression) {
                    return true
                }
            case .conditional(let branches):
                if branches.contains(where: { statementsCallKnownMutatingMember($0.body) }) {
                    return true
                }
            case .switchStatement(let expression, let cases, let defaultBody):
                if expressionCallsKnownMutatingMember(expression) {
                    return true
                }
                if cases.contains(where: { statementsCallKnownMutatingMember($0.body) }) {
                    return true
                }
                if let defaultBody, statementsCallKnownMutatingMember(defaultBody) {
                    return true
                }
            case .forEach(_, let sequence, let body):
                if expressionCallsKnownMutatingMember(sequence)
                    || statementsCallKnownMutatingMember(body)
                {
                    return true
                }
            case .whileLoop(let condition, let body):
                if expressionCallsKnownMutatingMember(condition)
                    || statementsCallKnownMutatingMember(body)
                {
                    return true
                }
            case .background(let background):
                if statementsCallKnownMutatingMember(background.body) {
                    return true
                }
            case .deferBlock(let deferred):
                if statementsCallKnownMutatingMember(deferred.body) {
                    return true
                }
            case .derived(_, _, let body):
                if statementsCallKnownMutatingMember(body) {
                    return true
                }
            case .localCallable, .macroInvocation, .expand, .return(nil), .break, .continue,
                .environmentProvision:
                continue
            }
        }

        return false
    }

    private func expressionCallsKnownMutatingMember(_ expression: NeatExpression) -> Bool {
        switch expression {
        case .call(let name, let arguments):
            if name == "appendField" || name.hasSuffix(".appendField") {
                return true
            }
            return arguments.contains { expressionCallsKnownMutatingMember($0.value) }
        case .block(let statements):
            return statementsCallKnownMutatingMember(statements)
        case .array(let elements):
            return elements.contains(where: expressionCallsKnownMutatingMember)
        case .dictionary(let elements):
            return elements.contains {
                expressionCallsKnownMutatingMember($0.key)
                    || expressionCallsKnownMutatingMember($0.value)
            }
        case .ternary(let condition, let trueExpression, let falseExpression):
            return expressionCallsKnownMutatingMember(condition)
                || expressionCallsKnownMutatingMember(trueExpression)
                || expressionCallsKnownMutatingMember(falseExpression)
        case .unary(_, let nested):
            return expressionCallsKnownMutatingMember(nested)
        case .binary(let lhs, _, let rhs):
            return expressionCallsKnownMutatingMember(lhs)
                || expressionCallsKnownMutatingMember(rhs)
        case .integer, .double, .string, .interpolatedString, .boolean, .nilLiteral,
            .macroInvocation, .identifier, .bindingReference:
            return false
        }
    }

    private func indentBlock(_ text: String, level: Int) -> String {
        let prefix = String(repeating: "    ", count: level)
        return
            text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { prefix + $0 }
            .joined(separator: "\n")
    }

    private func emitStatements(
        _ statements: [NeatStatement],
        indent: Int,
        enclosingReturnType: TypeReference? = nil
    ) throws -> String {
        try statements
            .map { try emitStatement($0, indent: indent, enclosingReturnType: enclosingReturnType) }
            .joined(separator: "\n")
    }

    private func emitInitializerStatements(
        _ statements: [NeatStatement],
        indent: Int,
        bindingNames: Set<String>,
        bindingParameterNames: Set<String>,
        initializerReturnType: TypeReference?
    ) throws -> String {
        try statements
            .map {
                try emitInitializerStatement(
                    $0,
                    indent: indent,
                    bindingNames: bindingNames,
                    bindingParameterNames: bindingParameterNames,
                    initializerReturnType: initializerReturnType
                )
            }
            .joined(separator: "\n")
    }

    private func emitInitializerStatement(
        _ statement: NeatStatement,
        indent: Int,
        bindingNames: Set<String>,
        bindingParameterNames: Set<String>,
        initializerReturnType: TypeReference?
    ) throws -> String {
        let prefix = String(repeating: "    ", count: indent)

        if case .assignment(let target, let expression) = statement,
            let bindingName = selfBindingAssignmentName(target),
            bindingNames.contains(bindingName),
            case .identifier(let parameterName) = expression,
            bindingParameterNames.contains(parameterName)
        {
            return "\(prefix)self.__binding_\(bindingName) = \(parameterName)"
        }

        if isFailableInitializerReturnType(initializerReturnType),
            case .return(let expression) = statement
        {
            return try emitFailableInitializerReturn(
                expression,
                initializerReturnType: initializerReturnType,
                indent: indent
            )
        }

        switch statement {
        case .conditional(let branches):
            return try emitInitializerConditional(
                branches,
                indent: indent,
                bindingNames: bindingNames,
                bindingParameterNames: bindingParameterNames,
                initializerReturnType: initializerReturnType
            )
        case .switchStatement(let expression, let cases, let defaultBody):
            return try emitInitializerSwitch(
                subject: expression,
                cases: cases,
                defaultBody: defaultBody,
                indent: indent,
                bindingNames: bindingNames,
                bindingParameterNames: bindingParameterNames,
                initializerReturnType: initializerReturnType
            )
        case .forEach(let name, let sequence, let body):
            let bodyText = try emitInitializerStatements(
                body,
                indent: indent + 1,
                bindingNames: bindingNames,
                bindingParameterNames: bindingParameterNames,
                initializerReturnType: initializerReturnType
            )
            return "\(prefix)for \(name) in \(try emitExpression(sequence)) {\n\(bodyText)\n\(prefix)}"
        case .whileLoop(let condition, let body):
            let bodyText = try emitInitializerStatements(
                body,
                indent: indent + 1,
                bindingNames: bindingNames,
                bindingParameterNames: bindingParameterNames,
                initializerReturnType: initializerReturnType
            )
            return "\(prefix)while \(try emitExpression(condition)) {\n\(bodyText)\n\(prefix)}"
        default:
            break
        }

        return try emitStatement(statement, indent: indent, enclosingReturnType: .named("Void"))
    }

    private func emitInitializerConditional(
        _ branches: [StatementConditionalBranch],
        indent: Int,
        bindingNames: Set<String>,
        bindingParameterNames: Set<String>,
        initializerReturnType: TypeReference?
    ) throws -> String {
        let prefix = String(repeating: "    ", count: indent)
        var rendered: [String] = []

        for (index, branch) in branches.enumerated() {
            let bodyText = try emitInitializerStatements(
                branch.body,
                indent: indent + 1,
                bindingNames: bindingNames,
                bindingParameterNames: bindingParameterNames,
                initializerReturnType: initializerReturnType
            )
            if let condition = branch.condition {
                let keyword = index == 0 ? "if" : "else if"
                rendered.append(
                    "\(prefix)\(keyword) \(try emitExpression(condition)) {\n\(bodyText)\n\(prefix)}"
                )
            } else {
                rendered.append("\(prefix)else {\n\(bodyText)\n\(prefix)}")
            }
        }

        return rendered.joined(separator: " ")
    }

    private func emitInitializerSwitch(
        subject: NeatExpression,
        cases: [SwitchCase],
        defaultBody: [NeatStatement]?,
        indent: Int,
        bindingNames: Set<String>,
        bindingParameterNames: Set<String>,
        initializerReturnType: TypeReference?
    ) throws -> String {
        let prefix = String(repeating: "    ", count: indent)
        var lines: [String] = ["\(prefix)switch \(try emitExpression(subject)) {"]

        for switchCase in cases {
            lines.append("\(prefix)case \(try emitSwitchCasePattern(switchCase.pattern)):")
            lines.append(
                try emitInitializerStatements(
                    switchCase.body,
                    indent: indent + 1,
                    bindingNames: bindingNames,
                    bindingParameterNames: bindingParameterNames,
                    initializerReturnType: initializerReturnType
                )
            )
        }

        if let defaultBody {
            lines.append("\(prefix)default:")
            lines.append(
                try emitInitializerStatements(
                    defaultBody,
                    indent: indent + 1,
                    bindingNames: bindingNames,
                    bindingParameterNames: bindingParameterNames,
                    initializerReturnType: initializerReturnType
                )
            )
        } else {
            lines.append("\(prefix)default:")
            lines.append("\(prefix)    fatalError(\"Non-exhaustive Neat switch reached at runtime.\")")
        }

        lines.append("\(prefix)}")
        return lines.joined(separator: "\n")
    }

    private func emitFailableInitializerReturn(
        _ expression: NeatExpression?,
        initializerReturnType: TypeReference?,
        indent: Int
    ) throws -> String {
        let prefix = String(repeating: "    ", count: indent)
        guard let expression else {
            return "\(prefix)return"
        }

        if let failureExpression = resultFailurePayloadExpression(expression) {
            guard let failureType = resultSelfFailureType(initializerReturnType) else {
                throw SwiftBackendError(
                    "Swift backend requires Result<Self, Failure> for failable initializer lowering."
                )
            }

            return "\(prefix)throw __NeatThrownFailure<\(emitTypeName(failureType))>(failure: \(try emitExpression(failureExpression)))"
        }

        if isResultSuccessExpression(expression) {
            return "\(prefix)return"
        }

        throw SwiftBackendError(
            "Swift backend can only lower failable initializer returns as .success(...) or .failure(...)."
        )
    }

    private func selfBindingAssignmentName(_ target: AssignmentTarget) -> String? {
        guard case .member(let base, let name) = target else {
            return nil
        }

        switch base {
        case .local("self"), .state("self"), .binding("self"):
            return name
        default:
            return nil
        }
    }

    private func emitStatement(
        _ statement: NeatStatement,
        indent: Int,
        enclosingReturnType: TypeReference? = nil
    ) throws -> String {
        let prefix = String(repeating: "    ", count: indent)

        switch statement {
        case .macroInvocation:
            throw SwiftBackendError("Macro invocations must be expanded before Swift emission.")
        case .expand:
            throw SwiftBackendError("Macro expansion statements must be expanded before Swift emission.")
        case .background(let background):
            let bodyText = try emitStatements(
                background.body,
                indent: indent + 1,
                enclosingReturnType: enclosingReturnType
            )
            return """
                \(prefix)Task.detached {
                \(bodyText)
                \(prefix)}
                """
        case .deferBlock(let deferred):
            return try emitDeferredBlock(
                deferred.body,
                indent: indent,
                enclosingReturnType: enclosingReturnType
            )
        case .localCallable(let declaration):
            return try emitLocalCallableDeclaration(declaration, indent: indent)
        case .localBinding(let declaration):
            let keyword = declaration.kind == .constant ? "let" : "var"
            let typeAnnotation =
                declaration.hasExplicitTypeAnnotation ? ": \(emitTypeName(declaration.type))" : ""
            return
                "\(prefix)\(keyword) \(declaration.name)\(typeAnnotation) = \(try emitLocalBindingExpression(declaration))"
        case .derived(let name, let typeName, let body):
            let bodyText = try emitStatements(
                body,
                indent: indent + 2,
                enclosingReturnType: .named(typeName)
            )
            return """
                \(prefix)let \(name): \(typeName) = {
                \(bodyText)
                \(prefix)}()
                """
        case .assignment(let target, let expression):
            return
                "\(prefix)\(try emitAssignmentTarget(target)) = \(try emitExpression(expression))"
        case .compoundAssignment(let target, .plusEquals, let expression):
            return
                "\(prefix)\(try emitAssignmentTarget(target)) += \(try emitExpression(expression))"
        case .expression(let expression):
            return "\(prefix)\(try emitExpression(expression))"
        case .return(let expression):
            if let expression {
                return "\(prefix)return \(try emitExpression(expression))"
            }
            return "\(prefix)return"
        case .conditional(let branches):
            return try emitConditional(
                branches,
                indent: indent,
                enclosingReturnType: enclosingReturnType
            )
        case .forEach(let name, let sequence, let body):
            let header = "\(prefix)for \(name) in \(try emitExpression(sequence)) {"
            let bodyText = try emitStatements(
                body,
                indent: indent + 1,
                enclosingReturnType: enclosingReturnType
            )
            return "\(header)\n\(bodyText)\n\(prefix)}"
        case .whileLoop(let condition, let body):
            let header = "\(prefix)while \(try emitExpression(condition)) {"
            let bodyText = try emitStatements(
                body,
                indent: indent + 1,
                enclosingReturnType: enclosingReturnType
            )
            return "\(header)\n\(bodyText)\n\(prefix)}"
        case .break:
            return "\(prefix)break"
        case .continue:
            return "\(prefix)continue"
        case .switchStatement(let expression, let cases, let defaultBody):
            return try emitSwitch(
                subject: expression,
                cases: cases,
                defaultBody: defaultBody,
                indent: indent,
                enclosingReturnType: enclosingReturnType
            )
        case .environmentProvision:
            throw SwiftBackendError(
                "Swift backend does not support environment provision statements yet.")
        }
    }

    private func emitConditional(
        _ branches: [StatementConditionalBranch],
        indent: Int,
        enclosingReturnType: TypeReference? = nil
    ) throws
        -> String
    {
        let prefix = String(repeating: "    ", count: indent)
        var rendered: [String] = []

        for (index, branch) in branches.enumerated() {
            let bodyText = try emitStatements(
                branch.body,
                indent: indent + 1,
                enclosingReturnType: enclosingReturnType
            )
            if let condition = branch.condition {
                let keyword = index == 0 ? "if" : "else if"
                rendered.append(
                    "\(prefix)\(keyword) \(try emitExpression(condition)) {\n\(bodyText)\n\(prefix)}"
                )
            } else {
                rendered.append("\(prefix)else {\n\(bodyText)\n\(prefix)}")
            }
        }

        return rendered.joined(separator: " ")
    }

    private func emitSwitch(
        subject: NeatExpression,
        cases: [SwitchCase],
        defaultBody: [NeatStatement]?,
        indent: Int,
        enclosingReturnType: TypeReference? = nil
    ) throws -> String {
        let prefix = String(repeating: "    ", count: indent)
        var lines: [String] = ["\(prefix)switch \(try emitExpression(subject)) {"]

        for switchCase in cases {
            lines.append("\(prefix)case \(try emitSwitchCasePattern(switchCase.pattern)):")
            lines.append(
                try emitStatements(
                    switchCase.body,
                    indent: indent + 1,
                    enclosingReturnType: enclosingReturnType
                )
            )
        }

        if let defaultBody {
            lines.append("\(prefix)default:")
            lines.append(
                try emitStatements(
                    defaultBody,
                    indent: indent + 1,
                    enclosingReturnType: enclosingReturnType
                )
            )
        } else {
            lines.append("\(prefix)default:")
            lines.append("\(prefix)    fatalError(\"Non-exhaustive Neat switch reached at runtime.\")")
        }

        lines.append("\(prefix)}")
        return lines.joined(separator: "\n")
    }

    private func emitSwitchCasePattern(_ pattern: SwitchCasePattern) throws -> String {
        switch pattern {
        case .expression(let expression):
            return try emitExpression(expression)
        case .enumCase(let name, let binding):
            let caseName = normalizedEnumCaseName(name)
            if let binding {
                let bindingKeyword = binding.kind == .constant ? "let" : "state"
                return ".\(caseName)(\(bindingKeyword) \(binding.name))"
            }
            return ".\(caseName)"
        }
    }

    private func normalizedEnumCaseName(_ name: String) -> String {
        name.hasPrefix(".") ? String(name.dropFirst()) : name
    }

    private func emitAssignmentTarget(_ target: AssignmentTarget) throws -> String {
        switch target {
        case .state(let name), .binding(let name), .environment(let name), .local(let name):
            return name
        case .member(let base, let name):
            return "\(try emitAssignmentTarget(base)).\(name)"
        }
    }

    private func emitExpression(
        _ expression: NeatExpression
    ) throws -> String {
        return try emitRawExpression(expression)
    }

    private func emitRawExpression(
        _ expression: NeatExpression
    ) throws -> String {
        switch expression {
        case .integer(let value):
            return "\(value)"
        case .double(let value):
            return "\(value)"
        case .string(let value):
            return "\"\(escapeString(decodeNeatStringEscapes(value)))\""
        case .interpolatedString(let value):
            return "\"\(try emitInterpolatedString(value))\""
        case .boolean(let value):
            return value ? "true" : "false"
        case .nilLiteral:
            return "nil"
        case .macroInvocation(let name, _):
            throw SwiftBackendError(
                "Expression macro invocation #\(name) must be expanded before Swift emission.")
        case .block(let body):
            return try emitClosureExpression(body)
        case .identifier(let name):
            return emitSwiftReferenceName(name)
        case .call(let name, let arguments):
            if let closure = try emitCoreClosureCall(name: name, arguments: arguments) {
                return closure
            }
            if let lowered = try emitKnownCollectionCall(
                name: name,
                arguments: arguments
            ) {
                return lowered
            }
            if let failableInitializer = failableInitializerSignature(
                forConstructorCallName: name,
                arguments: arguments
            ) {
                return try emitFailableInitializerCall(
                    failableInitializer,
                    name: name,
                    arguments: arguments
                )
            }
            return try emitRawCall(name: name, arguments: arguments)
        case .bindingReference(let name):
            return "__NeatBinding(get: { \(name) }, set: { \(name) = $0 })"
        case .array(let elements):
            let rendered = try elements.map { try emitExpression($0) }.joined(separator: ", ")
            return "[\(rendered)]"
        case .dictionary(let elements):
            let rendered = try elements.map { element in
                "\(try emitExpression(element.key)): \(try emitExpression(element.value))"
            }.joined(separator: ", ")
            return "[\(rendered)]"
        case .ternary(let condition, let trueExpression, let falseExpression):
            return
                "\(try emitExpression(condition)) ? \(try emitExpression(trueExpression)) : \(try emitExpression(falseExpression))"
        case .unary(let operatorSymbol, let nested):
            return "\(operatorSymbol.rawValue)\(try emitExpression(nested))"
        case .binary(let lhs, let operatorSymbol, let rhs):
            return
                "\(try emitExpression(lhs)) \(operatorSymbol.rawValue) \(try emitExpression(rhs))"
        }
    }

    private func normalizedSwiftTypeName(_ rawName: String) -> String {
        guard rawName.hasPrefix("Channel<"), rawName.hasSuffix(">") else {
            return rawName
        }

        let start = rawName.index(rawName.startIndex, offsetBy: "Channel<".count)
        let end = rawName.index(before: rawName.endIndex)
        let argumentsText = String(rawName[start..<end])

        var depth = 0
        for character in argumentsText {
            switch character {
            case "<":
                depth += 1
            case ">":
                depth -= 1
            case "," where depth == 0:
                return rawName
            default:
                break
            }
        }

        return rawName
    }

    private func emitSwiftSymbolName(_ name: String) -> String {
        if swiftNativeTypeNames.contains(name) {
            return name
        }
        if name.hasPrefix("Neat_") || name.hasPrefix("__Neat") {
            return name
        }
        return "Neat_\(name.replacingOccurrences(of: ".", with: "_"))"
    }

    private func emitSwiftReferenceName(_ name: String) -> String {
        if name.hasPrefix(".") {
            return name
        }

        guard let dotIndex = name.firstIndex(of: ".") else {
            if context.genericParameterNames.contains(name) {
                return name
            }
            guard name.first?.isUppercase == true else {
                return name
            }
            return emitSwiftSymbolName(name)
        }

        let base = String(name[..<dotIndex])
        let suffix = String(name[dotIndex...])
        guard base.first?.isUppercase == true else {
            return name
        }
        return "\(emitSwiftSymbolName(base))\(suffix)"
    }

    private func emitCoreClosureCall(
        name: String,
        arguments: [CallArgument]
    ) throws -> String? {
        guard name == "Closure",
            let parameters = arguments.first(where: { $0.label == "parameters" })?.value,
            let body = arguments.first(where: { $0.label == "body" })?.value
        else {
            return nil
        }

        guard case .array(let parameterExpressions) = parameters else {
            return nil
        }

        let parameterNames = parameterExpressions.compactMap { expression -> String? in
            guard case .identifier(let name) = expression else {
                return nil
            }
            return name
        }

        guard parameterNames.count == parameterExpressions.count,
            case .block(let statements) = body
        else {
            return nil
        }

        if statements.count == 1, case .expression(let expression) = statements[0] {
            return "{ \(parameterNames.joined(separator: ", ")) in \(try emitExpression(expression)) }"
        }

        let bodyText = try emitStatements(statements, indent: 1, enclosingReturnType: nil)
        return """
            { \(parameterNames.joined(separator: ", ")) in
            \(bodyText)
            }
            """
    }

    private func emitCallArgument(
        _ argument: CallArgument
    ) throws -> String {
        if let label = argument.label {
            return "\(label): \(try emitExpression(argument.value))"
        }
        return try emitExpression(argument.value)
    }

    private func emitCallArguments(
        _ arguments: [CallArgument],
        for callee: String
    ) throws -> String {
        _ = callee
        return try arguments.map { try emitCallArgument($0) }.joined(separator: ", ")
    }

    private func emitKnownCollectionCall(
        name: String,
        arguments: [CallArgument]
    ) throws -> String? {
        guard let dot = name.lastIndex(of: ".") else {
            return nil
        }

        let base = String(name[..<dot])
        let member = String(name[name.index(after: dot)...])

        func argument(_ label: String) -> NeatSyntax.Expression? {
            arguments.first(where: { $0.label == label })?.value
        }

        func unlabeledArgument() -> NeatSyntax.Expression? {
            guard arguments.count == 1, arguments[0].label == nil else {
                return nil
            }
            return arguments[0].value
        }

        switch member {
        case "append":
            guard let element = argument("element") else { return nil }
            return "\(base).append(\(try emitExpression(element)))"
        case "element":
            guard let index = argument("index") else { return nil }
            return "\(base)[\(try emitExpression(index))]"
        case "update":
            guard let element = argument("element"), let index = argument("index") else {
                return nil
            }
            return
                "\(base)[\(try emitExpression(index))] = \(try emitExpression(element))"
        case "insert":
            guard let element = argument("element") else { return nil }
            if let index = argument("index") {
                return
                    "\(base).insert(\(try emitExpression(element)), at: \(try emitExpression(index)))"
            }
            return "\(base).insert(\(try emitExpression(element)))"
        case "remove":
            if let index = argument("index") {
                return "\(base).remove(at: \(try emitExpression(index)))"
            }
            guard let element = argument("element") else { return nil }
            return "\(base).remove(\(try emitExpression(element)))"
        case "removeLast":
            guard arguments.isEmpty else { return nil }
            return "\(base).popLast()"
        case "clear":
            guard arguments.isEmpty else { return nil }
            return "\(base).removeAll()"
        case "first":
            guard arguments.isEmpty else { return nil }
            return "\(base).first"
        case "last":
            guard arguments.isEmpty else { return nil }
            return "\(base).last"
        case "filter":
            guard let include = argument("include") else { return nil }
            return "\(base).filter(\(try emitExpression(include)))"
        case "map", "compactMap", "flatMap", "forEach":
            guard let transform = unlabeledArgument() else { return nil }
            return "\(base).\(member)(\(try emitExpression(transform)))"
        case "value":
            guard let key = argument("key") else { return nil }
            return "\(base)[\(try emitExpression(key))]"
        case "updateValue":
            guard let value = argument("value"), let key = argument("key") else { return nil }
            return
                "\(base).updateValue(\(try emitExpression(value)), forKey: \(try emitExpression(key)))"
        case "removeValue":
            guard let key = argument("key") else { return nil }
            return "\(base).removeValue(forKey: \(try emitExpression(key)))"
        case "contains":
            if let key = argument("key") {
                return "\(base).keys.contains(\(try emitExpression(key)))"
            }
            guard let element = argument("element") else { return nil }
            return "\(base).contains(\(try emitExpression(element)))"
        default:
            return nil
        }
    }

    private func emitClosureExpression(_ body: [NeatStatement]) throws -> String {
        if body.count == 1, case .expression(let expression) = body[0] {
            return "{ \(try emitExpression(expression)) }"
        }

        let bodyText = try emitStatements(body, indent: 1, enclosingReturnType: nil)
        return "{\n\(bodyText)\n}"
    }

    private func emitDeferredBlock(
        _ statements: [NeatStatement],
        indent: Int,
        enclosingReturnType: TypeReference?
    ) throws -> String {
        let prefix = String(repeating: "    ", count: indent)
        let bodyPrefix = String(repeating: "    ", count: indent + 1)
        var lines: [String] = [
            "\(prefix)do {",
            "\(bodyPrefix)var __neatDeferredControlFlow: __NeatDeferredControlFlow?",
        ]

        for statement in statements {
            lines.append(
                try emitDeferredProtectedStatement(
                    statement,
                    indent: indent + 1,
                    enclosingReturnType: enclosingReturnType
                )
            )
        }

        lines.append(
            try emitDeferredFlowResume(
                indent: indent + 1,
                enclosingReturnType: enclosingReturnType
            )
        )
        lines.append("\(prefix)}")
        return lines.joined(separator: "\n")
    }

    private func emitDeferredProtectedStatement(
        _ statement: NeatStatement,
        indent: Int,
        enclosingReturnType: TypeReference?
    ) throws -> String {
        let prefix = String(repeating: "    ", count: indent)
        let bodyText = try emitDeferredInnerStatement(
            statement,
            indent: indent + 2,
            enclosingReturnType: enclosingReturnType
        )

        return """
            \(prefix)do {
            \(prefix)    try ({ () throws in
            \(bodyText)
            \(prefix)    })()
            \(prefix)} catch let flow as __NeatDeferredControlFlow {
            \(prefix)    if __neatDeferredControlFlow == nil {
            \(prefix)        __neatDeferredControlFlow = flow
            \(prefix)    }
            \(prefix)}
            """
    }

    private func emitDeferredInnerStatement(
        _ statement: NeatStatement,
        indent: Int,
        enclosingReturnType: TypeReference?
    ) throws -> String {
        let prefix = String(repeating: "    ", count: indent)

        switch statement {
        case .macroInvocation:
            throw SwiftBackendError("Macro invocations must be expanded before Swift emission.")
        case .expand:
            throw SwiftBackendError("Macro expansion statements must be expanded before Swift emission.")
        case .background(let background):
            let bodyText = try emitStatements(
                background.body,
                indent: indent + 1,
                enclosingReturnType: enclosingReturnType
            )
            return """
                \(prefix)Task.detached {
                \(bodyText)
                \(prefix)}
                """
        case .deferBlock(let deferred):
            return try emitDeferredBlock(
                deferred.body,
                indent: indent,
                enclosingReturnType: enclosingReturnType
            )
        case .localCallable(let declaration):
            return try emitLocalCallableDeclaration(declaration, indent: indent)
        case .localBinding(let declaration):
            let keyword = declaration.kind == .constant ? "let" : "var"
            let typeAnnotation =
                declaration.hasExplicitTypeAnnotation ? ": \(emitTypeName(declaration.type))" : ""
            return
                "\(prefix)\(keyword) \(declaration.name)\(typeAnnotation) = \(try emitLocalBindingExpression(declaration))"
        case .derived(let name, let typeName, let body):
            let bodyText = try emitStatements(
                body,
                indent: indent + 2,
                enclosingReturnType: .named(typeName)
            )
            return """
                \(prefix)let \(name): \(typeName) = {
                \(bodyText)
                \(prefix)}()
                """
        case .assignment(let target, let expression):
            return
                "\(prefix)\(try emitAssignmentTarget(target)) = \(try emitExpression(expression))"
        case .compoundAssignment(let target, .plusEquals, let expression):
            return
                "\(prefix)\(try emitAssignmentTarget(target)) += \(try emitExpression(expression))"
        case .expression(let expression):
            return "\(prefix)\(try emitExpression(expression))"
        case .return(let expression):
            if let expression {
                return "\(prefix)throw __NeatDeferredControlFlow.returnValue(\(try emitExpression(expression)))"
            }
            return "\(prefix)throw __NeatDeferredControlFlow.returnVoid"
        case .conditional(let branches):
            return try emitDeferredConditional(
                branches,
                indent: indent,
                enclosingReturnType: enclosingReturnType
            )
        case .forEach(let name, let sequence, let body):
            let header = "\(prefix)for \(name) in \(try emitExpression(sequence)) {"
            let bodyText = try emitDeferredInnerStatements(
                body,
                indent: indent + 1,
                enclosingReturnType: enclosingReturnType
            )
            return "\(header)\n\(bodyText)\n\(prefix)}"
        case .whileLoop(let condition, let body):
            let header = "\(prefix)while \(try emitExpression(condition)) {"
            let bodyText = try emitDeferredInnerStatements(
                body,
                indent: indent + 1,
                enclosingReturnType: enclosingReturnType
            )
            return "\(header)\n\(bodyText)\n\(prefix)}"
        case .break:
            return "\(prefix)throw __NeatDeferredControlFlow.breakLoop"
        case .continue:
            return "\(prefix)throw __NeatDeferredControlFlow.continueLoop"
        case .switchStatement(let expression, let cases, let defaultBody):
            return try emitDeferredSwitch(
                subject: expression,
                cases: cases,
                defaultBody: defaultBody,
                indent: indent,
                enclosingReturnType: enclosingReturnType
            )
        case .environmentProvision:
            throw SwiftBackendError(
                "Swift backend does not support environment provision statements yet.")
        }
    }

    private func emitDeferredInnerStatements(
        _ statements: [NeatStatement],
        indent: Int,
        enclosingReturnType: TypeReference?
    ) throws -> String {
        try statements
            .map { try emitDeferredInnerStatement($0, indent: indent, enclosingReturnType: enclosingReturnType) }
            .joined(separator: "\n")
    }

    private func emitDeferredConditional(
        _ branches: [StatementConditionalBranch],
        indent: Int,
        enclosingReturnType: TypeReference?
    ) throws -> String {
        let prefix = String(repeating: "    ", count: indent)
        var rendered: [String] = []

        for (index, branch) in branches.enumerated() {
            let bodyText = try emitDeferredInnerStatements(
                branch.body,
                indent: indent + 1,
                enclosingReturnType: enclosingReturnType
            )
            if let condition = branch.condition {
                let keyword = index == 0 ? "if" : "else if"
                rendered.append(
                    "\(prefix)\(keyword) \(try emitExpression(condition)) {\n\(bodyText)\n\(prefix)}"
                )
            } else {
                rendered.append("\(prefix)else {\n\(bodyText)\n\(prefix)}")
            }
        }

        return rendered.joined(separator: " ")
    }

    private func emitDeferredSwitch(
        subject: NeatExpression,
        cases: [SwitchCase],
        defaultBody: [NeatStatement]?,
        indent: Int,
        enclosingReturnType: TypeReference?
    ) throws -> String {
        let prefix = String(repeating: "    ", count: indent)
        var lines: [String] = ["\(prefix)switch \(try emitExpression(subject)) {"]

        for switchCase in cases {
            lines.append("\(prefix)case \(try emitSwitchCasePattern(switchCase.pattern)):")
            lines.append(
                try emitDeferredInnerStatements(
                    switchCase.body,
                    indent: indent + 1,
                    enclosingReturnType: enclosingReturnType
                )
            )
        }

        if let defaultBody {
            lines.append("\(prefix)default:")
            lines.append(
                try emitDeferredInnerStatements(
                    defaultBody,
                    indent: indent + 1,
                    enclosingReturnType: enclosingReturnType
                )
            )
        }

        lines.append("\(prefix)}")
        return lines.joined(separator: "\n")
    }

    private func emitDeferredFlowResume(
        indent: Int,
        enclosingReturnType: TypeReference?
    ) throws -> String {
        let prefix = String(repeating: "    ", count: indent)
        var lines: [String] = [
            "\(prefix)if let __neatDeferredControlFlow {",
            "\(prefix)    switch __neatDeferredControlFlow {",
        ]

        if let enclosingReturnType, emitTypeName(enclosingReturnType) != "Void" {
            lines.append(
                "\(prefix)    case .returnValue(let value): return value as! \(emitTypeName(enclosingReturnType))"
            )
            lines.append("\(prefix)    case .returnVoid: return")
        } else {
            lines.append("\(prefix)    case .returnValue: return")
            lines.append("\(prefix)    case .returnVoid: return")
        }

        lines.append("\(prefix)    case .breakLoop: break")
        lines.append("\(prefix)    case .continueLoop: continue")
        lines.append("\(prefix)    }")
        lines.append("\(prefix)}")
        return lines.joined(separator: "\n")
    }

    private func emitInterpolatedString(_ string: InterpolatedString) throws -> String {
        var result = ""

        for segment in string.segments {
            switch segment {
            case .text(let text):
                result += escapeString(decodeNeatStringEscapes(text))
            case .expression(let expression):
                result += "\\(\(try emitExpression(expression)))"
            }
        }

        return result
    }

    private func escapeString(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    private func decodeNeatStringEscapes(_ value: String) -> String {
        var result = ""
        var index = value.startIndex

        while index < value.endIndex {
            let character = value[index]
            guard character == "\\" else {
                result.append(character)
                index = value.index(after: index)
                continue
            }

            let nextIndex = value.index(after: index)
            guard nextIndex < value.endIndex else {
                result.append(character)
                index = nextIndex
                continue
            }

            let escaped = value[nextIndex]
            switch escaped {
            case "\"":
                result.append("\"")
            case "\\":
                result.append("\\")
            case "n":
                result.append("\n")
            case "r":
                result.append("\r")
            case "t":
                result.append("\t")
            default:
                result.append(character)
                result.append(escaped)
            }

            index = value.index(after: nextIndex)
        }

        return result
    }

    private func emitRawCall(
        name: String,
        arguments: [CallArgument]
    ) throws -> String {
        let rendered = try emitCallArguments(arguments, for: name)
        return "\(emitSwiftReferenceName(name))(\(rendered))"
    }

    private func emitFailableInitializerCall(
        _ signature: FailableInitializerSignature,
        name: String,
        arguments: [CallArgument]
    ) throws -> String {
        let constructedType = emitSwiftReferenceName(signature.constructName)
        let failureType = emitTypeName(signature.failureType)
        let call = try emitRawCall(name: name, arguments: arguments)

        return """
            ({ () -> Neat_Result<\(constructedType), \(failureType)> in
                do {
                    return .success(result: try \(call))
                } catch let failure as __NeatThrownFailure<\(failureType)> {
                    return .failure(cause: failure.failure)
                } catch {
                    fatalError("Unexpected Swift error thrown from Neat failable initializer: \\(error)")
                }
            })()
            """
    }

    private func failableInitializerSignature(
        forConstructorCallName name: String,
        arguments: [CallArgument]
    ) -> FailableInitializerSignature? {
        let constructName = constructorConstructName(from: name)
        if context.genericParameterNames.contains(constructName),
            arguments.count == 1,
            arguments[0].label == "from"
        {
            return FailableInitializerSignature(
                constructName: constructName,
                labels: ["from"],
                failureType: .named("DecodingError")
            )
        }
        guard let signatures = context.failableInitializersByConstructName[constructName] else {
            return nil
        }

        return signatures.first { signature in
            guard signature.labels.count == arguments.count else {
                return false
            }

            return zip(signature.labels, arguments).allSatisfy { expectedLabel, argument in
                expectedLabel == argument.label
            }
        }
    }

    private func constructorConstructName(from callName: String) -> String {
        guard let genericStart = callName.firstIndex(of: "<") else {
            return callName
        }

        return String(callName[..<genericStart])
    }

    private func isFailableInitializerReturnType(_ typeReference: TypeReference?) -> Bool {
        resultSelfFailureType(typeReference) != nil
    }

    private func resultSelfFailureType(_ typeReference: TypeReference?) -> TypeReference? {
        guard let typeReference else {
            return nil
        }

        guard case .generic(let base, let arguments) = typeReference,
            case .named("Result") = base,
            arguments.count == 2,
            case .named("Self") = arguments[0]
        else {
            return nil
        }

        return arguments[1]
    }

    private func resultFailurePayloadExpression(_ expression: NeatExpression) -> NeatExpression? {
        guard case .call(let name, let arguments) = expression,
            enumCaseTail(name) == "failure"
        else {
            return nil
        }

        if let cause = arguments.first(where: { $0.label == "cause" }) {
            return cause.value
        }

        guard arguments.count == 1, arguments[0].label == nil else {
            return nil
        }

        return arguments[0].value
    }

    private func isResultSuccessExpression(_ expression: NeatExpression) -> Bool {
        guard case .call(let name, _) = expression else {
            return false
        }

        return enumCaseTail(name) == "success"
    }

    private func enumCaseTail(_ name: String) -> String {
        let normalized = normalizedEnumCaseName(name)
        guard let dot = normalized.lastIndex(of: ".") else {
            return normalized
        }

        return String(normalized[normalized.index(after: dot)...])
    }
}
