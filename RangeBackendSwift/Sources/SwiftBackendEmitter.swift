import Foundation
import RangeSyntax

struct SwiftBackendEmitter {
    private struct SwiftEmissionContext {
        var failableInitializersByConstructName: [String: [FailableInitializerSignature]] = [:]
        var failableInitializersByProtocolName: [String: [FailableInitializerSignature]] = [:]
        var genericParameterNames: Set<String> = []

        init() {}

        init(program: LoweredProgram) {
            let protocols = Self.allProtocols(in: program)
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
            self.failableInitializersByProtocolName = Self.collectFailableInitializers(
                fromProtocols: protocols
            )
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

        private static func allProtocols(in program: LoweredProgram) -> [ProtocolDeclaration] {
            var declarations = program.protocols
            for unit in program.units {
                declarations.append(contentsOf: unit.protocols)
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
            allProtocols(in: program).contains { $0.name == name }
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
                "Date": [
                    signature("Date"),
                    FailableInitializerSignature(
                        constructName: "Date",
                        labels: ["iso8601String"],
                        failureType: failureType
                    ),
                ],
                "DateStorage": [
                    FailableInitializerSignature(
                        constructName: "DateStorage",
                        labels: ["iso8601String"],
                        failureType: failureType
                    )
                ],
                "DateTime": [
                    signature("DateTime"),
                    FailableInitializerSignature(
                        constructName: "DateTime",
                        labels: ["iso8601String"],
                        failureType: failureType
                    ),
                ],
                "DateTimeStorage": [
                    FailableInitializerSignature(
                        constructName: "DateTimeStorage",
                        labels: ["iso8601String"],
                        failureType: failureType
                    )
                ],
                "Float": [signature("Float")],
                "Int": [signature("Int")],
                "String": [signature("String")],
                "UUID": [
                    signature("UUID"),
                    FailableInitializerSignature(
                        constructName: "UUID",
                        labels: ["uuidString"],
                        failureType: failureType
                    ),
                ],
                "UUIDStorage": [
                    FailableInitializerSignature(
                        constructName: "UUIDStorage",
                        labels: ["uuidString"],
                        failureType: failureType
                    )
                ],
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

        private static func collectFailableInitializers(
            fromProtocols protocols: [ProtocolDeclaration]
        ) -> [String: [FailableInitializerSignature]] {
            var signatures: [String: [FailableInitializerSignature]] = [:]

            for declaration in protocols {
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

    private struct EmissionScope {
        static let empty = EmissionScope()

        var genericParameterNames: Set<String> = []
        var genericParameterConstraintsByName: [String: [TypeReference]] = [:]

        init() {}

        init(genericParameters: [GenericParameter]) {
            self = Self.empty.adding(genericParameters: genericParameters)
        }

        func adding(genericParameters: [GenericParameter]) -> EmissionScope {
            var copy = self
            for parameter in genericParameters {
                switch parameter {
                case .type(let name, let constraint?, _):
                    copy.genericParameterNames.insert(name)
                    if copy.genericParameterConstraintsByName[name, default: []].contains(constraint) {
                        continue
                    }
                    copy.genericParameterConstraintsByName[name, default: []].append(constraint)
                case .type(let name, nil, _), .value(let name, _, _):
                    copy.genericParameterNames.insert(name)
                }
            }
            return copy
        }

        func adding(extensionConstraints: [ExtensionGenericArgumentConstraint]) -> EmissionScope {
            var copy = self
            for constraint in extensionConstraints {
                copy.genericParameterNames.insert(constraint.parameterName)
                if copy.genericParameterConstraintsByName[constraint.parameterName, default: []].contains(constraint.constraint) {
                    continue
                }
                copy.genericParameterConstraintsByName[constraint.parameterName, default: []].append(constraint.constraint)
            }
            return copy
        }
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
        "ClosedRange",
        "Range",
        "Self",
        "Set",
        "String",
        "UUID",
        "Void",
    ]

    private let swiftNativeStorageTypeNames: [String: String] = [
        "BoolStorage": "Bool",
        "DataStorage": "Data",
        "Date": "__RangeDateOnly",
        "DateStorage": "__RangeDateOnly",
        "DateTime": "__RangeDateTime",
        "DateTimeStorage": "__RangeDateTime",
        "FloatStorage": "Float",
        "IntStorage": "Int",
        "StringStorage": "String",
        "UUIDStorage": "UUID",
    ]

    private typealias RangeExpression = RangeSyntax.Expression
    private typealias RangeStatement = RangeSyntax.Statement
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
                name: "RangeGenerated",
                platforms: [
                    .macOS(.v13)
                ],
                targets: [
                    .executableTarget(
                        name: "RangeGenerated",
                        swiftSettings: [
                            .enableExperimentalFeature("Embedded")
                        ]
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
            // Backend implementation for RangeCore's Promise, Result, ChannelStorage, and Logger surface.
            // RangeCore declares the language-visible API; Swift runtime support lives here.
            enum Range_Promise<Success, Failure> {
                case loading
                case success(result: Success)
                case failure(cause: Failure)
            }

            enum Range_Result<Success, Failure> {
                case success(result: Success)
                case failure(cause: Failure)
            }

            final class Range_ChannelStorage<Element>: @unchecked Sendable {
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

            enum Range_Logger {
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

            extension String {
                func __rangeSnakeCase() -> String {
                    var result = ""
                    var previousWasLowercaseOrDigit = false

                    for scalar in unicodeScalars {
                        let character = Character(scalar)
                        let string = String(character)
                        let isUppercase = string.uppercased() == string && string.lowercased() != string
                        let isLowercase = string.lowercased() == string && string.uppercased() != string
                        let isDigit = CharacterSet.decimalDigits.contains(scalar)

                        if isUppercase && previousWasLowercaseOrDigit && !result.isEmpty {
                            result.append("_")
                        }

                        result.append(string.lowercased())
                        previousWasLowercaseOrDigit = isLowercase || isDigit
                    }

                    return result
                }
            }

            struct __RangeDateOnly: Hashable, Comparable, CustomStringConvertible, Sendable {
                let year: Int
                let month: Int
                let day: Int

                init() {
                    let calendar = Calendar(identifier: .gregorian)
                    let components = calendar.dateComponents(in: TimeZone(secondsFromGMT: 0)!, from: Foundation.Date())
                    self.year = components.year!
                    self.month = components.month!
                    self.day = components.day!
                }

                init(iso8601String: String) throws {
                    let formatter = DateFormatter()
                    formatter.calendar = Calendar(identifier: .gregorian)
                    formatter.locale = Locale(identifier: "en_US_POSIX")
                    formatter.timeZone = TimeZone(secondsFromGMT: 0)
                    formatter.dateFormat = "yyyy-MM-dd"

                    guard let date = formatter.date(from: iso8601String),
                        formatter.string(from: date) == iso8601String
                    else {
                        throw __RangeThrownFailure<Range_DecodingError>(failure: .failed)
                    }

                    let components = formatter.calendar.dateComponents([.year, .month, .day], from: date)
                    self.year = components.year!
                    self.month = components.month!
                    self.day = components.day!
                }

                var description: String {
                    String(format: "%04d-%02d-%02d", year, month, day)
                }

                static func < (lhs: Self, rhs: Self) -> Bool {
                    (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
                }

                static func parse(iso8601String: String) -> Range_Result<Self, Range_DecodingError> {
                    do {
                        return .success(result: try Self(iso8601String: iso8601String))
                    } catch {
                        return .failure(cause: .failed)
                    }
                }
            }

            struct __RangeDateTime: Hashable, Comparable, CustomStringConvertible, Sendable {
                let storage: Foundation.Date

                init() {
                    self.storage = Foundation.Date()
                }

                init(iso8601String: String) throws {
                    if let value = Self.makeFormatter(fractionalSeconds: false).date(from: iso8601String) {
                        self.storage = value
                        return
                    }

                    if let value = Self.makeFormatter(fractionalSeconds: true).date(from: iso8601String) {
                        self.storage = value
                        return
                    }

                    throw __RangeThrownFailure<Range_DecodingError>(failure: .failed)
                }

                var description: String {
                    Self.makeFormatter(fractionalSeconds: false).string(from: storage)
                }

                static func < (lhs: Self, rhs: Self) -> Bool {
                    lhs.storage < rhs.storage
                }

                static func parse(iso8601String: String) -> Range_Result<Self, Range_DecodingError> {
                    do {
                        return .success(result: try Self(iso8601String: iso8601String))
                    } catch {
                        return .failure(cause: .failed)
                    }
                }

                private static func makeFormatter(fractionalSeconds: Bool) -> ISO8601DateFormatter {
                    let formatter = ISO8601DateFormatter()
                    formatter.formatOptions = fractionalSeconds
                        ? [.withInternetDateTime, .withFractionalSeconds]
                        : [.withInternetDateTime]
                    formatter.timeZone = TimeZone(secondsFromGMT: 0)
                    return formatter
                }
            }

            final class __RangeBinding<Value> {
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

            struct __RangeThrownFailure<Failure>: Error, @unchecked Sendable {
                let failure: Failure
            }

            func __rangeUUID(uuidString: String) throws -> UUID {
                guard let value = UUID(uuidString: uuidString) else {
                    throw __RangeThrownFailure<Range_DecodingError>(failure: .failed)
                }

                return value
            }

            func __rangeDate(iso8601String: String) throws -> __RangeDateOnly {
                try __RangeDateOnly(iso8601String: iso8601String)
            }

            func __rangeDateTime(iso8601String: String) throws -> __RangeDateTime {
                try __RangeDateTime(iso8601String: iso8601String)
            }

            extension UUID {
                static func parse(uuidString: String) -> Range_Result<UUID, Range_DecodingError> {
                    guard let value = UUID(uuidString: uuidString) else {
                        return .failure(cause: .failed)
                    }
                    return .success(result: value)
                }
            }

            enum __RangeDeferredControlFlow: Error {
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
        extension Bool: Range_Encodable {
            func encode(to encoder: Range_Encoder) -> Range_Result<Void, Range_EncodingError> {
                var container = encoder.singleValueContainer()
                return container.encode(self)
            }
        }

        extension Data: Range_Encodable {
            func encode(to encoder: Range_Encoder) -> Range_Result<Void, Range_EncodingError> {
                var container = encoder.singleValueContainer()
                return container.encode(self)
            }
        }

        extension __RangeDateOnly: Range_Encodable {
            func encode(to encoder: Range_Encoder) -> Range_Result<Void, Range_EncodingError> {
                var container = encoder.singleValueContainer()
                return container.encode(self)
            }
        }

        extension __RangeDateTime: Range_Encodable {
            func encode(to encoder: Range_Encoder) -> Range_Result<Void, Range_EncodingError> {
                var container = encoder.singleValueContainer()
                return container.encode(self)
            }
        }

        extension Float: Range_Encodable {
            func encode(to encoder: Range_Encoder) -> Range_Result<Void, Range_EncodingError> {
                var container = encoder.singleValueContainer()
                return container.encode(self)
            }
        }

        extension Int: Range_Encodable {
            func encode(to encoder: Range_Encoder) -> Range_Result<Void, Range_EncodingError> {
                var container = encoder.singleValueContainer()
                return container.encode(self)
            }
        }

        extension String: Range_Encodable {
            func encode(to encoder: Range_Encoder) -> Range_Result<Void, Range_EncodingError> {
                var container = encoder.singleValueContainer()
                return container.encode(self)
            }
        }

        extension UUID: Range_Encodable {
            func encode(to encoder: Range_Encoder) -> Range_Result<Void, Range_EncodingError> {
                var container = encoder.singleValueContainer()
                return container.encode(self)
            }
        }

        extension Array: Range_Encodable where Element: Range_Encodable {
            func encode(to encoder: Range_Encoder) -> Range_Result<Void, Range_EncodingError> {
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

        extension Optional: Range_Encodable where Wrapped: Range_Encodable {
            func encode(to encoder: Range_Encoder) -> Range_Result<Void, Range_EncodingError> {
                switch self {
                case .some(let value):
                    return value.encode(to: encoder)
                case .none:
                    var container = encoder.singleValueContainer()
                    return container.encodeNil()
                }
            }
        }

        extension Dictionary: Range_Encodable where Key == String, Value: Range_Encodable {
            func encode(to encoder: Range_Encoder) -> Range_Result<Void, Range_EncodingError> {
                var container = encoder.keyedContainer()

                for key in keys.sorted() {
                    guard let value = self[key] else {
                        continue
                    }

                    switch container.encode(value, forKey: key) {
                    case .success:
                        continue
                    case .failure(let error):
                        return .failure(cause: error)
                    }
                }

                return .success(result: Void())
            }
        }

        extension Set: Range_Encodable where Element: Range_Encodable {
            func encode(to encoder: Range_Encoder) -> Range_Result<Void, Range_EncodingError> {
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
        extension Bool: Range_Decodable {
            static func decode(from decoder: Range_Decoder) -> Range_Result<Bool, Range_DecodingError> {
                let container = decoder.singleValueContainer()
                return container.decode(Bool.self)
            }
        }

        extension __RangeDateOnly: Range_Decodable {
            static func decode(from decoder: Range_Decoder) -> Range_Result<__RangeDateOnly, Range_DecodingError> {
                let container = decoder.singleValueContainer()
                return container.decode(__RangeDateOnly.self)
            }
        }

        extension __RangeDateTime: Range_Decodable {
            static func decode(from decoder: Range_Decoder) -> Range_Result<__RangeDateTime, Range_DecodingError> {
                let container = decoder.singleValueContainer()
                return container.decode(__RangeDateTime.self)
            }
        }

        extension Float: Range_Decodable {
            static func decode(from decoder: Range_Decoder) -> Range_Result<Float, Range_DecodingError> {
                let container = decoder.singleValueContainer()
                return container.decode(Float.self)
            }
        }

        extension Int: Range_Decodable {
            static func decode(from decoder: Range_Decoder) -> Range_Result<Int, Range_DecodingError> {
                let container = decoder.singleValueContainer()
                return container.decode(Int.self)
            }
        }

        extension String: Range_Decodable {
            static func decode(from decoder: Range_Decoder) -> Range_Result<String, Range_DecodingError> {
                let container = decoder.singleValueContainer()
                return container.decode(String.self)
            }
        }

        extension UUID: Range_Decodable {
            static func decode(from decoder: Range_Decoder) -> Range_Result<UUID, Range_DecodingError> {
                let container = decoder.singleValueContainer()
                return container.decode(UUID.self)
            }
        }
        """
    }

    private func emitMain(_ mainBlock: MainBlockNode) throws -> String {
        let body = try emitStatements(mainBlock.body, indent: 2, enclosingReturnType: .named("Void"))

        return """
            @main
            struct RangeMain {
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
            enclosingReturnType: callable.returnType ?? .named("Void"),
            scope: EmissionScope(genericParameters: callable.genericParameters)
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
        let storedValues = try storedValueEmissionOrder(for: declaration).map {
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
                bindingNames: bindingNames,
                scope: EmissionScope(genericParameters: declaration.genericParameters)
            )
        }.joined(
            separator: "\n\n")
        let synthesizedInitializer = try emitSynthesizedDataShapeInitializer(
            declaration,
            genericParameterNames: genericParameterNames
        )
        let methods = try declaration.callables
            .filter { $0.targetType == nil }
            .map {
                try emitMethod(
                    $0,
                    constructGenericParameterNames: genericParameterNames,
                    constructGenericParameters: declaration.genericParameters,
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
            synthesizedInitializer,
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

    private func emitSynthesizedDataShapeInitializer(
        _ declaration: ConstructDeclaration,
        genericParameterNames: Set<String>
    ) throws -> String {
        var parameters: [String] = []
        var assignments: [String] = []

        for value in declaration.values where value.value == nil {
            let typeName = emitDeclaredTypeName(
                value.typeName,
                genericParameterNames: genericParameterNames
            )
            parameters.append("\(value.name): \(typeName)")
            assignments.append("self.\(value.name) = \(value.name)")
        }

        for state in declaration.states {
            guard case .declared = state.storage else {
                continue
            }
            let typeName = emitTypeName(state.type, genericParameterNames: genericParameterNames)
            parameters.append("\(state.name): \(typeName)")
            assignments.append("self.\(state.name) = \(state.name)")
        }

        for binding in declaration.bindings {
            guard case .plain = binding.storage else {
                continue
            }
            let typeName = emitDeclaredTypeName(
                binding.typeName,
                genericParameterNames: genericParameterNames
            )
            parameters.append("\(binding.name): __RangeBinding<\(typeName)>")
            assignments.append("self.__binding_\(binding.name) = \(binding.name)")
        }

        guard !parameters.isEmpty else {
            return ""
        }

        return """
            init(\(parameters.joined(separator: ", "))) {
            \(indentBlock(assignments.joined(separator: "\n"), level: 1))
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
                bindingNames: [],
                scope: EmissionScope().adding(extensionConstraints: declaration.genericArgumentConstraints)
            )
        }.joined(separator: "\n\n")
        let methods = try declaration.callables.map {
            try emitMethod(
                $0,
                inheritedScope: EmissionScope().adding(extensionConstraints: declaration.genericArgumentConstraints)
            )
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
        _ parameter: RangeFunctionParameter,
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
                return "_ \(local): __RangeBinding<\(renderedType)>"
            case .some(let external) where external == local:
                return "\(local): __RangeBinding<\(renderedType)>"
            case .some(let external):
                return "\(external) \(local): __RangeBinding<\(renderedType)>"
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
            if let storageTypeName = swiftNativeStorageTypeNames[name] {
                return storageTypeName
            }
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
        if let specializedTypeName = emitSpecializedScalarTypeName(name) {
            return specializedTypeName
        }

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

    private struct SwiftLayoutEstimate {
        let size: Int
        let alignment: Int
    }

    private func swiftLayoutEstimate(forDeclaredTypeName name: String) -> SwiftLayoutEstimate? {
        if name.hasPrefix("["),
            name.hasSuffix("]"),
            name.count > 2
        {
            return SwiftLayoutEstimate(size: 8, alignment: 8)
        }

        if name.hasSuffix("?"),
            name.count > 1
        {
            return SwiftLayoutEstimate(size: 8, alignment: 8)
        }

        let swiftTypeName = emitSpecializedScalarTypeName(name) ?? name
        switch swiftTypeName {
        case "Bool", "BoolStorage", "Int8", "UInt8":
            return SwiftLayoutEstimate(size: 1, alignment: 1)
        case "Int16", "UInt16":
            return SwiftLayoutEstimate(size: 2, alignment: 2)
        case "Int32", "UInt32", "Float", "FloatStorage":
            return SwiftLayoutEstimate(size: 4, alignment: 4)
        case "Int", "IntStorage", "UInt", "Int64", "UInt64", "Double":
            return SwiftLayoutEstimate(size: 8, alignment: 8)
        case "String", "StringStorage":
            return SwiftLayoutEstimate(size: 16, alignment: 8)
        case "Data", "Date", "DateStorage", "DateTime", "DateTimeStorage", "UUID", "UUIDStorage":
            return SwiftLayoutEstimate(size: 16, alignment: 8)
        default:
            return nil
        }
    }

    private func emitSpecializedScalarTypeName(_ name: String) -> String? {
        guard let genericStart = name.firstIndex(of: "<"),
            name.hasSuffix(">")
        else {
            return nil
        }

        let baseName = String(name[..<genericStart])
        let argumentText = String(
            name[name.index(after: genericStart)..<name.index(before: name.endIndex)]
        )
        let arguments = argumentText.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        switch baseName {
        case "Int":
            guard let bits = arguments.first else {
                return nil
            }
            let isUnsigned = arguments.dropFirst().contains {
                $0 == ".unsigned" || $0.hasSuffix(".unsigned")
            }
            switch (bits, isUnsigned) {
            case ("8", false): return "Int8"
            case ("8", true): return "UInt8"
            case ("16", false): return "Int16"
            case ("16", true): return "UInt16"
            case ("32", false): return "Int32"
            case ("32", true): return "UInt32"
            case ("64", false): return "Int64"
            case ("64", true): return "UInt64"
            default: return nil
            }
        case "Float":
            guard let width = arguments.first else {
                return nil
            }
            if width == ".f32" || width == "32" || width.hasSuffix(".f32") {
                return "Float"
            }
            if width == ".f64" || width == "64" || width.hasSuffix(".f64") {
                return "Double"
            }
            return nil
        default:
            return nil
        }
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
        let isStatic = callableShouldEmitStatic(callable)
        let mutatingPrefix = !isStatic && protocolRequirementNeedsMutation(
            callable,
            enclosingProtocolName: enclosingProtocolName
        ) ? "mutating " : ""
        let staticPrefix = isStatic ? "static " : ""
        return "\(staticPrefix)\(mutatingPrefix)func \(callable.name)\(genericClause)(\(parameters))\(returnClause)"
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

    private func storedValueEmissionOrder(for declaration: ConstructDeclaration) -> [ValueDeclaration] {
        guard declaration.states.isEmpty,
            declaration.bindings.isEmpty,
            declaration.values.count > 1
        else {
            return declaration.values
        }

        let rankedValues = declaration.values.enumerated().map { index, value in
            (
                index: index,
                value: value,
                layout: swiftLayoutEstimate(forDeclaredTypeName: value.typeName)
            )
        }

        guard rankedValues.allSatisfy({ $0.layout != nil }) else {
            return declaration.values
        }

        return rankedValues.sorted { lhs, rhs in
            guard let lhsLayout = lhs.layout,
                let rhsLayout = rhs.layout
            else {
                return lhs.index < rhs.index
            }

            if lhsLayout.alignment != rhsLayout.alignment {
                return lhsLayout.alignment > rhsLayout.alignment
            }
            if lhsLayout.size != rhsLayout.size {
                return lhsLayout.size > rhsLayout.size
            }
            return lhs.index < rhs.index
        }.map(\.value)
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
                private let __binding_\(binding.name): __RangeBinding<\(typeName)>
                var \(binding.name): \(typeName) {
                    get { __binding_\(binding.name).value }
                    set { __binding_\(binding.name).value = newValue }
                }
                """
        case .derived:
            throw SwiftBackendError("Swift backend does not support derived binding storage yet.")
        }
    }

    private func emitLocalBindingExpression(
        _ declaration: LocalBindingDeclaration,
        scope: EmissionScope = .empty
    ) throws -> String
    {
        try emitExpression(declaration.expression, scope: scope)
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
        bindingNames: Set<String> = [],
        scope: EmissionScope = .empty
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
            initializerReturnType: initializer.returnType,
            scope: scope
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
        constructGenericParameters: [GenericParameter] = [],
        inheritedScope: EmissionScope = .empty,
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
        let scope = inheritedScope
            .adding(genericParameters: constructGenericParameters)
            .adding(genericParameters: callable.genericParameters)
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
            enclosingReturnType: callable.returnType ?? .named("Void"),
            scope: scope
        )
        let isStatic = callableShouldEmitStatic(callable)
        let staticPrefix = isStatic ? "static " : ""
        let mutatingPrefix = !isStatic && !isReferenceType && methodNeedsMutation(callable) ? "mutating " : ""

        return """
            \(staticPrefix)\(mutatingPrefix)func \(callable.name)\(genericClause)(\(parameters))\(returnClause) {
            \(functionBody)
            }
            """
    }

    private func callableShouldEmitStatic(_ callable: CallableDeclaration) -> Bool {
        if callableNameIsOperator(callable.name) {
            return true
        }

        if let body = callable.body {
            return callableSignatureMentionsSelf(callable)
                && !statementsReferenceInstanceSelf(body)
        }

        return callableSignatureMentionsSelf(callable)
    }

    private func callableSignatureMentionsSelf(_ callable: CallableDeclaration) -> Bool {
        if let returnType = callable.returnType, typeReferenceMentionsSelf(returnType) {
            return true
        }

        return callable.parameters.contains { parameter in
            guard let typeReference = parameter.typeReference else {
                return false
            }
            return typeReferenceMentionsSelf(typeReference)
        }
    }

    private func callableNameIsOperator(_ name: String) -> Bool {
        name.contains { character in
            "+-*/%=!<>&|".contains(character)
        }
    }

    private func typeReferenceMentionsSelf(_ typeReference: TypeReference) -> Bool {
        switch typeReference {
        case .named("Self"):
            return true
        case .named:
            return false
        case .member(let base, _):
            return typeReferenceMentionsSelf(base)
        case .generic(let base, let arguments):
            return typeReferenceMentionsSelf(base)
                || arguments.contains(where: typeReferenceMentionsSelf)
        case .array(let element), .optional(let element), .variadic(let element):
            return typeReferenceMentionsSelf(element)
        case .function(let parameters, let returnType):
            return parameters.contains(where: typeReferenceMentionsSelf)
                || typeReferenceMentionsSelf(returnType)
        }
    }

    private func statementsReferenceInstanceSelf(_ statements: [RangeStatement]) -> Bool {
        statements.contains(where: statementReferencesInstanceSelf)
    }

    private func statementReferencesInstanceSelf(_ statement: RangeStatement) -> Bool {
        switch statement {
        case .localBinding(let declaration):
            return expressionReferencesInstanceSelf(declaration.expression)
        case .derived(_, _, let body):
            return statementsReferenceInstanceSelf(body)
        case .assignment(let target, let expression):
            return assignmentTargetReferencesInstanceSelf(target)
                || expressionReferencesInstanceSelf(expression)
        case .compoundAssignment(let target, _, let expression):
            return assignmentTargetReferencesInstanceSelf(target)
                || expressionReferencesInstanceSelf(expression)
        case .expression(let expression):
            return expressionReferencesInstanceSelf(expression)
        case .return(let expression):
            return expression.map(expressionReferencesInstanceSelf) ?? false
        case .conditional(let branches):
            return branches.contains { branch in
                (branch.condition.map(expressionReferencesInstanceSelf) ?? false)
                    || statementsReferenceInstanceSelf(branch.body)
            }
        case .forEach(_, let sequence, let body):
            return expressionReferencesInstanceSelf(sequence)
                || statementsReferenceInstanceSelf(body)
        case .whileLoop(let condition, let body):
            return expressionReferencesInstanceSelf(condition)
                || statementsReferenceInstanceSelf(body)
        case .switchStatement(let expression, let cases, let defaultBody):
            return expressionReferencesInstanceSelf(expression)
                || cases.contains { statementsReferenceInstanceSelf($0.body) }
                || (defaultBody.map(statementsReferenceInstanceSelf) ?? false)
        case .background(let background):
            return statementsReferenceInstanceSelf(background.body)
        case .deferBlock(let deferred):
            return statementsReferenceInstanceSelf(deferred.body)
        case .localCallable(let declaration):
            return statementsReferenceInstanceSelf(declaration.body)
        case .macroInvocation(_, _, let body):
            return statementsReferenceInstanceSelf(body)
        case .expand, .break, .continue:
            return false
        }
    }

    private func expressionReferencesInstanceSelf(_ expression: RangeExpression) -> Bool {
        switch expression {
        case .identifier("self"):
            return true
        case .call(let name, let arguments):
            return name == "self" || name.hasPrefix("self.")
                || arguments.contains { expressionReferencesInstanceSelf($0.value) }
        case .block(let body):
            return statementsReferenceInstanceSelf(body)
        case .array(let elements):
            return elements.contains(where: expressionReferencesInstanceSelf)
        case .dictionary(let elements):
            return elements.contains {
                expressionReferencesInstanceSelf($0.key)
                    || expressionReferencesInstanceSelf($0.value)
            }
        case .interpolatedString(let string):
            return string.segments.contains { segment in
                guard case .expression(let expression) = segment else {
                    return false
                }
                return expressionReferencesInstanceSelf(expression)
            }
        case .ternary(let condition, let trueExpression, let falseExpression):
            return expressionReferencesInstanceSelf(condition)
                || expressionReferencesInstanceSelf(trueExpression)
                || expressionReferencesInstanceSelf(falseExpression)
        case .unary(_, let nested):
            return expressionReferencesInstanceSelf(nested)
        case .binary(let lhs, _, let rhs):
            return expressionReferencesInstanceSelf(lhs)
                || expressionReferencesInstanceSelf(rhs)
        case .integer, .double, .string, .boolean, .nilLiteral, .macroInvocation,
            .identifier, .bindingReference:
            return false
        }
    }

    private func assignmentTargetReferencesInstanceSelf(_ target: AssignmentTarget) -> Bool {
        switch target {
        case .local("self"), .state("self"), .binding("self"):
            return true
        case .member(let base, _):
            return assignmentTargetReferencesInstanceSelf(base)
        case .local, .state, .binding:
            return false
        }
    }

    private func methodNeedsMutation(_ callable: CallableDeclaration) -> Bool {
        guard let body = callable.body else { return false }
        return statementsContainMutation(body) || statementsCallKnownMutatingMember(body)
    }

    private func statementsContainMutation(_ statements: [RangeStatement]) -> Bool {
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
            case .localBinding, .localCallable, .expression, .return, .break, .continue:
                continue
            }
        }

        return false
    }

    private func statementsCallKnownMutatingMember(_ statements: [RangeStatement]) -> Bool {
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
            case .localCallable, .macroInvocation, .expand, .return(nil), .break, .continue:
                continue
            }
        }

        return false
    }

    private func expressionCallsKnownMutatingMember(_ expression: RangeExpression) -> Bool {
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
        _ statements: [RangeStatement],
        indent: Int,
        enclosingReturnType: TypeReference? = nil,
        scope: EmissionScope = .empty
    ) throws -> String {
        try statements
            .map {
                try emitStatement(
                    $0,
                    indent: indent,
                    enclosingReturnType: enclosingReturnType,
                    scope: scope
                )
            }
            .joined(separator: "\n")
    }

    private func emitInitializerStatements(
        _ statements: [RangeStatement],
        indent: Int,
        bindingNames: Set<String>,
        bindingParameterNames: Set<String>,
        initializerReturnType: TypeReference?,
        scope: EmissionScope = .empty
    ) throws -> String {
        try statements
            .map {
                try emitInitializerStatement(
                    $0,
                    indent: indent,
                    bindingNames: bindingNames,
                    bindingParameterNames: bindingParameterNames,
                    initializerReturnType: initializerReturnType,
                    scope: scope
                )
            }
            .joined(separator: "\n")
    }

    private func emitInitializerStatement(
        _ statement: RangeStatement,
        indent: Int,
        bindingNames: Set<String>,
        bindingParameterNames: Set<String>,
        initializerReturnType: TypeReference?,
        scope: EmissionScope = .empty
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
                indent: indent,
                scope: scope
            )
        }

        switch statement {
        case .conditional(let branches):
            return try emitInitializerConditional(
                branches,
                indent: indent,
                bindingNames: bindingNames,
                bindingParameterNames: bindingParameterNames,
                initializerReturnType: initializerReturnType,
                scope: scope
            )
        case .switchStatement(let expression, let cases, let defaultBody):
            return try emitInitializerSwitch(
                subject: expression,
                cases: cases,
                defaultBody: defaultBody,
                indent: indent,
                bindingNames: bindingNames,
                bindingParameterNames: bindingParameterNames,
                initializerReturnType: initializerReturnType,
                scope: scope
            )
        case .forEach(let name, let sequence, let body):
            let bodyText = try emitInitializerStatements(
                body,
                indent: indent + 1,
                bindingNames: bindingNames,
                bindingParameterNames: bindingParameterNames,
                initializerReturnType: initializerReturnType,
                scope: scope
            )
            return "\(prefix)for \(name) in \(try emitExpression(sequence, scope: scope)) {\n\(bodyText)\n\(prefix)}"
        case .whileLoop(let condition, let body):
            let bodyText = try emitInitializerStatements(
                body,
                indent: indent + 1,
                bindingNames: bindingNames,
                bindingParameterNames: bindingParameterNames,
                initializerReturnType: initializerReturnType,
                scope: scope
            )
            return "\(prefix)while \(try emitExpression(condition, scope: scope)) {\n\(bodyText)\n\(prefix)}"
        default:
            break
        }

        return try emitStatement(
            statement,
            indent: indent,
            enclosingReturnType: .named("Void"),
            scope: scope
        )
    }

    private func emitInitializerConditional(
        _ branches: [StatementConditionalBranch],
        indent: Int,
        bindingNames: Set<String>,
        bindingParameterNames: Set<String>,
        initializerReturnType: TypeReference?,
        scope: EmissionScope = .empty
    ) throws -> String {
        let prefix = String(repeating: "    ", count: indent)
        var rendered: [String] = []

        for (index, branch) in branches.enumerated() {
            let bodyText = try emitInitializerStatements(
                branch.body,
                indent: indent + 1,
                bindingNames: bindingNames,
                bindingParameterNames: bindingParameterNames,
                initializerReturnType: initializerReturnType,
                scope: scope
            )
            if let condition = branch.condition {
                let keyword = index == 0 ? "if" : "else if"
                rendered.append(
                    "\(prefix)\(keyword) \(try emitExpression(condition, scope: scope)) {\n\(bodyText)\n\(prefix)}"
                )
            } else {
                rendered.append("\(prefix)else {\n\(bodyText)\n\(prefix)}")
            }
        }

        return rendered.joined(separator: " ")
    }

    private func emitInitializerSwitch(
        subject: RangeExpression,
        cases: [SwitchCase],
        defaultBody: [RangeStatement]?,
        indent: Int,
        bindingNames: Set<String>,
        bindingParameterNames: Set<String>,
        initializerReturnType: TypeReference?,
        scope: EmissionScope = .empty
    ) throws -> String {
        let prefix = String(repeating: "    ", count: indent)
        var lines: [String] = ["\(prefix)switch \(try emitExpression(subject, scope: scope)) {"]

        for switchCase in cases {
            lines.append("\(prefix)case \(try emitSwitchCasePattern(switchCase.pattern)):")
            lines.append(
                try emitInitializerStatements(
                    switchCase.body,
                    indent: indent + 1,
                    bindingNames: bindingNames,
                    bindingParameterNames: bindingParameterNames,
                    initializerReturnType: initializerReturnType,
                    scope: scope
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
                    initializerReturnType: initializerReturnType,
                    scope: scope
                )
            )
        } else {
            lines.append("\(prefix)default:")
            lines.append("\(prefix)    fatalError(\"Non-exhaustive Range switch reached at runtime.\")")
        }

        lines.append("\(prefix)}")
        return lines.joined(separator: "\n")
    }

    private func emitFailableInitializerReturn(
        _ expression: RangeExpression?,
        initializerReturnType: TypeReference?,
        indent: Int,
        scope: EmissionScope = .empty
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

            return "\(prefix)throw __RangeThrownFailure<\(emitTypeName(failureType))>(failure: \(try emitExpression(failureExpression, scope: scope)))"
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
        _ statement: RangeStatement,
        indent: Int,
        enclosingReturnType: TypeReference? = nil,
        scope: EmissionScope = .empty
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
                enclosingReturnType: enclosingReturnType,
                scope: scope
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
                "\(prefix)\(keyword) \(declaration.name)\(typeAnnotation) = \(try emitLocalBindingExpression(declaration, scope: scope))"
        case .derived(let name, let typeName, let body):
            let bodyText = try emitStatements(
                body,
                indent: indent + 2,
                enclosingReturnType: .named(typeName),
                scope: scope
            )
            return """
                \(prefix)let \(name): \(typeName) = {
                \(bodyText)
                \(prefix)}()
                """
        case .assignment(let target, let expression):
            return
                "\(prefix)\(try emitAssignmentTarget(target)) = \(try emitExpression(expression, scope: scope))"
        case .compoundAssignment(let target, .plusEquals, let expression):
            return
                "\(prefix)\(try emitAssignmentTarget(target)) += \(try emitExpression(expression, scope: scope))"
        case .expression(let expression):
            return "\(prefix)\(try emitExpression(expression, scope: scope))"
        case .return(let expression):
            if let expression {
                return "\(prefix)return \(try emitExpression(expression, scope: scope))"
            }
            return "\(prefix)return"
        case .conditional(let branches):
            return try emitConditional(
                branches,
                indent: indent,
                enclosingReturnType: enclosingReturnType,
                scope: scope
            )
        case .forEach(let name, let sequence, let body):
            let header = "\(prefix)for \(name) in \(try emitExpression(sequence, scope: scope)) {"
            let bodyText = try emitStatements(
                body,
                indent: indent + 1,
                enclosingReturnType: enclosingReturnType,
                scope: scope
            )
            return "\(header)\n\(bodyText)\n\(prefix)}"
        case .whileLoop(let condition, let body):
            let header = "\(prefix)while \(try emitExpression(condition, scope: scope)) {"
            let bodyText = try emitStatements(
                body,
                indent: indent + 1,
                enclosingReturnType: enclosingReturnType,
                scope: scope
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
                enclosingReturnType: enclosingReturnType,
                scope: scope
            )
        }
    }

    private func emitConditional(
        _ branches: [StatementConditionalBranch],
        indent: Int,
        enclosingReturnType: TypeReference? = nil,
        scope: EmissionScope = .empty
    ) throws
        -> String
    {
        let prefix = String(repeating: "    ", count: indent)
        var rendered: [String] = []

        for (index, branch) in branches.enumerated() {
            let bodyText = try emitStatements(
                branch.body,
                indent: indent + 1,
                enclosingReturnType: enclosingReturnType,
                scope: scope
            )
            if let condition = branch.condition {
                let keyword = index == 0 ? "if" : "else if"
                rendered.append(
                    "\(prefix)\(keyword) \(try emitExpression(condition, scope: scope)) {\n\(bodyText)\n\(prefix)}"
                )
            } else {
                rendered.append("\(prefix)else {\n\(bodyText)\n\(prefix)}")
            }
        }

        return rendered.joined(separator: " ")
    }

    private func emitSwitch(
        subject: RangeExpression,
        cases: [SwitchCase],
        defaultBody: [RangeStatement]?,
        indent: Int,
        enclosingReturnType: TypeReference? = nil,
        scope: EmissionScope = .empty
    ) throws -> String {
        let prefix = String(repeating: "    ", count: indent)
        var lines: [String] = ["\(prefix)switch \(try emitExpression(subject, scope: scope)) {"]

        for switchCase in cases {
            lines.append("\(prefix)case \(try emitSwitchCasePattern(switchCase.pattern)):")
            lines.append(
                try emitStatements(
                    switchCase.body,
                    indent: indent + 1,
                    enclosingReturnType: enclosingReturnType,
                    scope: scope
                )
            )
        }

        if let defaultBody {
            lines.append("\(prefix)default:")
            lines.append(
                try emitStatements(
                    defaultBody,
                    indent: indent + 1,
                    enclosingReturnType: enclosingReturnType,
                    scope: scope
                )
            )
        } else {
            lines.append("\(prefix)default:")
            lines.append("\(prefix)    fatalError(\"Non-exhaustive Range switch reached at runtime.\")")
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
        case .state(let name), .binding(let name), .local(let name):
            return name
        case .member(let base, let name):
            return "\(try emitAssignmentTarget(base)).\(name)"
        }
    }

    private func emitExpression(
        _ expression: RangeExpression,
        scope: EmissionScope = .empty
    ) throws -> String {
        return try emitRawExpression(expression, scope: scope)
    }

    private func emitRawExpression(
        _ expression: RangeExpression,
        scope: EmissionScope = .empty
    ) throws -> String {
        switch expression {
        case .integer(let value):
            return "\(value)"
        case .double(let value):
            return "\(value)"
        case .string(let value):
            return "\"\(escapeString(StringLiteral.decodeEscapes(value)))\""
        case .interpolatedString(let value):
            return "\"\(try emitInterpolatedString(value, scope: scope))\""
        case .boolean(let value):
            return value ? "true" : "false"
        case .nilLiteral:
            return "nil"
        case .macroInvocation(let name, _):
            throw SwiftBackendError(
                "Expression macro invocation #\(name) must be expanded before Swift emission.")
        case .block(let body):
            return try emitClosureExpression(body, scope: scope)
        case .identifier(let name):
            return emitSwiftReferenceName(name, scope: scope)
        case .call(let name, let arguments):
            if let closure = try emitCoreClosureCall(name: name, arguments: arguments, scope: scope) {
                return closure
            }
            if let lowered = try emitKnownCollectionCall(
                name: name,
                arguments: arguments,
                scope: scope
            ) {
                return lowered
            }
            if let failableInitializer = failableInitializerSignature(
                forConstructorCallName: name,
                arguments: arguments,
                scope: scope
            ) {
                return try emitFailableInitializerCall(
                    failableInitializer,
                    name: name,
                    arguments: arguments,
                    scope: scope
                )
            }
            return try emitRawCall(name: name, arguments: arguments, scope: scope)
        case .bindingReference(let name):
            return "__RangeBinding(get: { \(name) }, set: { \(name) = $0 })"
        case .array(let elements):
            let rendered = try elements.map { try emitExpression($0, scope: scope) }.joined(separator: ", ")
            return "[\(rendered)]"
        case .dictionary(let elements):
            let rendered = try elements.map { element in
                "\(try emitExpression(element.key, scope: scope)): \(try emitExpression(element.value, scope: scope))"
            }.joined(separator: ", ")
            return "[\(rendered)]"
        case .ternary(let condition, let trueExpression, let falseExpression):
            return
                "\(try emitExpression(condition, scope: scope)) ? \(try emitExpression(trueExpression, scope: scope)) : \(try emitExpression(falseExpression, scope: scope))"
        case .unary(let operatorSymbol, let nested):
            return "\(operatorSymbol.rawValue)\(try emitExpression(nested, scope: scope))"
        case .binary(let lhs, let operatorSymbol, let rhs):
            return
                "(\(try emitExpression(lhs, scope: scope)) \(operatorSymbol.rawValue) \(try emitExpression(rhs, scope: scope)))"
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
        if let storageTypeName = swiftNativeStorageTypeNames[name] {
            return storageTypeName
        }
        if swiftNativeTypeNames.contains(name) {
            return name
        }
        if name.hasPrefix("Range_") || name.hasPrefix("__Range") {
            return name
        }
        return "Range_\(name.replacingOccurrences(of: ".", with: "_"))"
    }

    private func emitSwiftReferenceName(
        _ name: String,
        scope: EmissionScope = .empty
    ) -> String {
        if name.hasPrefix(".") {
            return name
        }

        guard let dotIndex = name.firstIndex(of: ".") else {
            if scope.genericParameterNames.contains(name) || context.genericParameterNames.contains(name) {
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
        if scope.genericParameterNames.contains(base) || context.genericParameterNames.contains(base) {
            return name
        }
        return "\(emitSwiftSymbolName(base))\(suffix)"
    }

    private func emitCoreClosureCall(
        name: String,
        arguments: [CallArgument],
        scope: EmissionScope = .empty
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
            return "{ \(parameterNames.joined(separator: ", ")) in \(try emitExpression(expression, scope: scope)) }"
        }

        let bodyText = try emitStatements(
            statements,
            indent: 1,
            enclosingReturnType: nil,
            scope: scope
        )
        return """
            { \(parameterNames.joined(separator: ", ")) in
            \(bodyText)
            }
            """
    }

    private func emitCallArgument(
        _ argument: CallArgument,
        scope: EmissionScope = .empty
    ) throws -> String {
        if let label = argument.label {
            return "\(label): \(try emitExpression(argument.value, scope: scope))"
        }
        return try emitExpression(argument.value, scope: scope)
    }

    private func emitCallArguments(
        _ arguments: [CallArgument],
        for callee: String,
        scope: EmissionScope = .empty
    ) throws -> String {
        _ = callee
        return try arguments.map { try emitCallArgument($0, scope: scope) }.joined(separator: ", ")
    }

    private func emitKnownCollectionCall(
        name: String,
        arguments: [CallArgument],
        scope: EmissionScope = .empty
    ) throws -> String? {
        guard let dot = name.lastIndex(of: ".") else {
            return nil
        }

        let base = String(name[..<dot])
        let member = String(name[name.index(after: dot)...])

        func argument(_ label: String) -> RangeSyntax.Expression? {
            arguments.first(where: { $0.label == label })?.value
        }

        func unlabeledArgument() -> RangeSyntax.Expression? {
            guard arguments.count == 1, arguments[0].label == nil else {
                return nil
            }
            return arguments[0].value
        }

        switch member {
        case "append":
            guard let element = argument("element") else { return nil }
            return "\(base).append(\(try emitExpression(element, scope: scope)))"
        case "element":
            guard let index = argument("index") else { return nil }
            return "\(base)[\(try emitExpression(index, scope: scope))]"
        case "update":
            guard let element = argument("element"), let index = argument("index") else {
                return nil
            }
            return
                "\(base)[\(try emitExpression(index, scope: scope))] = \(try emitExpression(element, scope: scope))"
        case "insert":
            guard let element = argument("element") else { return nil }
            if let index = argument("index") {
                return
                    "\(base).insert(\(try emitExpression(element, scope: scope)), at: \(try emitExpression(index, scope: scope)))"
            }
            return "\(base).insert(\(try emitExpression(element, scope: scope)))"
        case "remove":
            if let index = argument("index") {
                return "\(base).remove(at: \(try emitExpression(index, scope: scope)))"
            }
            guard let element = argument("element") else { return nil }
            return "\(base).remove(\(try emitExpression(element, scope: scope)))"
        case "removeLast":
            guard arguments.isEmpty else { return nil }
            return "\(base).popLast()"
        case "clear":
            guard arguments.isEmpty else { return nil }
            return "\(base).removeAll()"
        case "first":
            if arguments.isEmpty {
                return "\(base).first"
            }
            guard let include = argument("where") else { return nil }
            return "\(base).first(where: \(try emitExpression(include, scope: scope)))"
        case "last":
            guard arguments.isEmpty else { return nil }
            return "\(base).last"
        case "filter":
            guard let include = argument("include") ?? unlabeledArgument() else { return nil }
            return "\(base).filter(\(try emitExpression(include, scope: scope)))"
        case "snakeCase":
            guard arguments.isEmpty else { return nil }
            return "\(base).__rangeSnakeCase()"
        case "map", "compactMap", "flatMap", "forEach":
            guard let transform = unlabeledArgument() else { return nil }
            return "\(base).\(member)(\(try emitExpression(transform, scope: scope)))"
        case "value":
            guard let key = argument("key") else { return nil }
            return "\(base)[\(try emitExpression(key, scope: scope))]"
        case "updateValue":
            guard let value = argument("value"), let key = argument("key") else { return nil }
            return
                "\(base).updateValue(\(try emitExpression(value, scope: scope)), forKey: \(try emitExpression(key, scope: scope)))"
        case "removeValue":
            guard let key = argument("key") else { return nil }
            return "\(base).removeValue(forKey: \(try emitExpression(key, scope: scope)))"
        case "contains":
            if let key = argument("key") {
                return "\(base).keys.contains(\(try emitExpression(key, scope: scope)))"
            }
            guard let element = argument("element") else { return nil }
            return "\(base).contains(\(try emitExpression(element, scope: scope)))"
        default:
            return nil
        }
    }

    private func emitClosureExpression(
        _ body: [RangeStatement],
        scope: EmissionScope = .empty
    ) throws -> String {
        if body.count == 1, case .expression(let expression) = body[0] {
            return "{ \(try emitExpression(expression, scope: scope)) }"
        }

        let bodyText = try emitStatements(
            body,
            indent: 1,
            enclosingReturnType: nil,
            scope: scope
        )
        return "{\n\(bodyText)\n}"
    }

    private func emitDeferredBlock(
        _ statements: [RangeStatement],
        indent: Int,
        enclosingReturnType: TypeReference?
    ) throws -> String {
        let prefix = String(repeating: "    ", count: indent)
        let bodyPrefix = String(repeating: "    ", count: indent + 1)
        var lines: [String] = [
            "\(prefix)do {",
            "\(bodyPrefix)var __rangeDeferredControlFlow: __RangeDeferredControlFlow?",
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
        _ statement: RangeStatement,
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
            \(prefix)} catch let flow as __RangeDeferredControlFlow {
            \(prefix)    if __rangeDeferredControlFlow == nil {
            \(prefix)        __rangeDeferredControlFlow = flow
            \(prefix)    }
            \(prefix)}
            """
    }

    private func emitDeferredInnerStatement(
        _ statement: RangeStatement,
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
                return "\(prefix)throw __RangeDeferredControlFlow.returnValue(\(try emitExpression(expression)))"
            }
            return "\(prefix)throw __RangeDeferredControlFlow.returnVoid"
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
            return "\(prefix)throw __RangeDeferredControlFlow.breakLoop"
        case .continue:
            return "\(prefix)throw __RangeDeferredControlFlow.continueLoop"
        case .switchStatement(let expression, let cases, let defaultBody):
            return try emitDeferredSwitch(
                subject: expression,
                cases: cases,
                defaultBody: defaultBody,
                indent: indent,
                enclosingReturnType: enclosingReturnType
            )
        }
    }

    private func emitDeferredInnerStatements(
        _ statements: [RangeStatement],
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
        subject: RangeExpression,
        cases: [SwitchCase],
        defaultBody: [RangeStatement]?,
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
            "\(prefix)if let __rangeDeferredControlFlow {",
            "\(prefix)    switch __rangeDeferredControlFlow {",
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

    private func emitInterpolatedString(
        _ string: InterpolatedString,
        scope: EmissionScope = .empty
    ) throws -> String {
        var result = ""

        for segment in string.segments {
            switch segment {
            case .text(let text):
                result += escapeString(StringLiteral.decodeEscapes(text))
            case .expression(let expression):
                result += "\\(\(try emitExpression(expression, scope: scope)))"
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

    private func emitRawCall(
        name: String,
        arguments: [CallArgument],
        scope: EmissionScope = .empty
    ) throws -> String {
        if let knownInitializer = try emitKnownCoreStorageInitializer(
            name: name,
            arguments: arguments,
            scope: scope
        ) {
            return knownInitializer
        }

        let rendered = try emitCallArguments(arguments, for: name, scope: scope)
        return "\(emitSwiftReferenceName(name, scope: scope))(\(rendered))"
    }

    private func emitKnownCoreStorageInitializer(
        name: String,
        arguments: [CallArgument],
        scope: EmissionScope = .empty
    ) throws -> String? {
        let baseName = name.split(separator: "<", maxSplits: 1).first.map(String.init) ?? name

        func singleArgument(label: String?) -> RangeSyntax.Expression? {
            guard arguments.count == 1, arguments[0].label == label else {
                return nil
            }
            return arguments[0].value
        }

        switch baseName {
        case "DataStorage":
            guard arguments.isEmpty else { return nil }
            return "Data()"
        case "Data":
            guard let storage = singleArgument(label: "storage") else { return nil }
            return try emitExpression(storage, scope: scope)
        case "Range":
            guard arguments.count == 2,
                let lowerBound = arguments.first(where: { $0.label == "lowerBound" })?.value,
                let upperBound = arguments.first(where: { $0.label == "upperBound" })?.value
            else { return nil }
            return
                "\(try emitExpression(lowerBound, scope: scope)) ..< \(try emitExpression(upperBound, scope: scope))"
        case "ClosedRange":
            guard arguments.count == 2,
                let lowerBound = arguments.first(where: { $0.label == "lowerBound" })?.value,
                let upperBound = arguments.first(where: { $0.label == "upperBound" })?.value
            else { return nil }
            return
                "\(try emitExpression(lowerBound, scope: scope)) ... \(try emitExpression(upperBound, scope: scope))"
        case "DateStorage":
            if arguments.isEmpty {
                return "__RangeDateOnly()"
            }
            guard let string = singleArgument(label: "iso8601String") else { return nil }
            return "__rangeDate(iso8601String: \(try emitExpression(string, scope: scope)))"
        case "Date":
            if let storage = singleArgument(label: "storage") {
                return try emitExpression(storage, scope: scope)
            }
            guard let string = singleArgument(label: "iso8601String") else { return nil }
            return "__rangeDate(iso8601String: \(try emitExpression(string, scope: scope)))"
        case "DateTimeStorage":
            if arguments.isEmpty {
                return "__RangeDateTime()"
            }
            guard let string = singleArgument(label: "iso8601String") else { return nil }
            return "__rangeDateTime(iso8601String: \(try emitExpression(string, scope: scope)))"
        case "DateTime":
            if let storage = singleArgument(label: "storage") {
                return try emitExpression(storage, scope: scope)
            }
            guard let string = singleArgument(label: "iso8601String") else { return nil }
            return "__rangeDateTime(iso8601String: \(try emitExpression(string, scope: scope)))"
        case "UUIDStorage":
            if arguments.isEmpty {
                return "UUID()"
            }
            guard let string = singleArgument(label: "uuidString") else { return nil }
            return "__rangeUUID(uuidString: \(try emitExpression(string, scope: scope)))"
        case "UUID":
            if let storage = singleArgument(label: "storage") {
                return try emitExpression(storage, scope: scope)
            }
            guard let string = singleArgument(label: "uuidString") else { return nil }
            return "__rangeUUID(uuidString: \(try emitExpression(string, scope: scope)))"
        default:
            return nil
        }
    }

    private func emitFailableInitializerCall(
        _ signature: FailableInitializerSignature,
        name: String,
        arguments: [CallArgument],
        scope: EmissionScope = .empty
    ) throws -> String {
        let constructedType = emitSwiftReferenceName(signature.constructName, scope: scope)
        let failureType = emitTypeName(signature.failureType)
        let call = try emitRawCall(name: name, arguments: arguments, scope: scope)

        return """
            ({ () -> Range_Result<\(constructedType), \(failureType)> in
                do {
                    return .success(result: try \(call))
                } catch let failure as __RangeThrownFailure<\(failureType)> {
                    return .failure(cause: failure.failure)
                } catch {
                    fatalError("Unexpected Swift error thrown from Range failable initializer: \\(error)")
                }
            })()
            """
    }

    private func failableInitializerSignature(
        forConstructorCallName name: String,
        arguments: [CallArgument],
        scope: EmissionScope = .empty
    ) -> FailableInitializerSignature? {
        let constructName = constructorConstructName(from: name)
        if context.genericParameterNames.contains(constructName),
            let signature = genericFailableInitializerSignature(
                forGenericParameter: constructName,
                arguments: arguments,
                scope: scope
            )
        {
            return FailableInitializerSignature(
                constructName: constructName,
                labels: signature.labels,
                failureType: signature.failureType
            )
        }
        guard let signatures = context.failableInitializersByConstructName[constructName] else {
            return nil
        }

        return matchingFailableInitializer(in: signatures, arguments: arguments)
    }

    private func genericFailableInitializerSignature(
        forGenericParameter name: String,
        arguments: [CallArgument],
        scope: EmissionScope = .empty
    ) -> FailableInitializerSignature? {
        let matches = scope.genericParameterConstraintsByName[name, default: []].compactMap {
            constraint -> FailableInitializerSignature? in
            guard let constraintName = nominalTypeName(constraint),
                let signatures = context.failableInitializersByProtocolName[constraintName]
            else {
                return nil
            }
            return matchingFailableInitializer(in: signatures, arguments: arguments)
        }

        guard matches.count == 1 else {
            return nil
        }
        return matches[0]
    }

    private func matchingFailableInitializer(
        in signatures: [FailableInitializerSignature],
        arguments: [CallArgument]
    ) -> FailableInitializerSignature? {
        signatures.first { signature in
            guard signature.labels.count == arguments.count else {
                return false
            }

            return zip(signature.labels, arguments).allSatisfy { expectedLabel, argument in
                expectedLabel == argument.label
            }
        }
    }

    private func nominalTypeName(_ typeReference: TypeReference) -> String? {
        switch typeReference {
        case .named(let name):
            return name
        case .member(_, let name):
            return name
        case .generic(let base, _):
            return nominalTypeName(base)
        case .array, .function, .optional, .variadic:
            return nil
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

    private func resultFailurePayloadExpression(_ expression: RangeExpression) -> RangeExpression? {
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

    private func isResultSuccessExpression(_ expression: RangeExpression) -> Bool {
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
