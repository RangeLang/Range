import Foundation
import RangeCompiler

struct SwiftBackendEmitter {
    private struct LLVMCallableBridge {
        let symbolName: String
        let parameterCount: Int
    }

    private struct SwiftEmissionContext {
        var failableInitializersByConstructName: [String: [FailableInitializerSignature]] = [:]
        var genericParameterNames: Set<String> = []
        var constructsByName: [String: ConstructDeclaration] = [:]
        var macrosByName: [String: MacroDeclaration] = [:]
        var callableParameterLabelsByName: [String: [[String]]] = [:]
        var llvmBridgesByCallableName: [String: LLVMCallableBridge] = [:]

        init() {}

        init(program: LoweredProgram) {
            self.failableInitializersByConstructName = Self.collectFailableInitializers(
                from: Self.allDeclarations(in: program)
            )
            self.failableInitializersByConstructName.merge(
                Self.collectFailableInitializers(from: Self.allExtensions(in: program)),
                uniquingKeysWith: { lhs, rhs in lhs + rhs }
            )
            self.genericParameterNames = Self.collectGenericParameterNames(from: program)
            self.constructsByName = Self.allDeclarations(in: program).reduce(into: [:]) {
                result, declaration in
                result[declaration.name] = declaration
            }
            self.macrosByName = program.macrosByName
            self.callableParameterLabelsByName = Self.collectCallableParameterLabels(from: program)
            self.llvmBridgesByCallableName = Self.collectLLVMBridges(from: program)
        }

        private static func collectGenericParameterNames(from program: LoweredProgram) -> Set<
            String
        > {
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

        private static func collectCallableParameterLabels(
            from program: LoweredProgram
        ) -> [String: [[String]]] {
            var labelsByName: [String: [[String]]] = [:]

            func record(_ callable: CallableDeclaration) {
                let labels = callable.parameters.map(\.name)
                labelsByName[callable.name, default: []].append(labels)

                if let lastComponent = callable.name.split(separator: ".").last.map(String.init),
                    lastComponent != callable.name
                {
                    labelsByName[lastComponent, default: []].append(labels)
                }
            }

            func record(_ declaration: ConstructDeclaration) {
                declaration.callables.forEach(record)
                declaration.constructs.forEach(record)
            }

            program.callables.forEach(record)
            program.units.flatMap(\.callables).forEach(record)
            allDeclarations(in: program).forEach(record)
            allExtensions(in: program).flatMap(\.callables).forEach(record)

            return labelsByName
        }

        private static func collectLLVMBridges(from program: LoweredProgram) -> [String: LLVMCallableBridge] {
            let callables = program.callables + program.units.flatMap(\.callables)
            return callables.reduce(into: [:]) { result, callable in
                guard callable.targetType == nil,
                    LLVMLowerability.canLower(callable)
                else {
                    return
                }
                result[callable.name] = LLVMCallableBridge(
                    symbolName: LLVMLoweringEmitter.symbolName(for: callable),
                    parameterCount: callable.parameters.count
                )
            }
        }

        private static func allExtensions(in program: LoweredProgram) -> [ExtensionDeclaration] {
            var declarations = program.extensions
            for unit in program.units {
                declarations.append(contentsOf: unit.extensions)
            }
            return declarations
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
                            labels: initializer.parameters.map(\.name),
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
                            labels: initializer.parameters.map(\.name),
                            failureType: failureType
                        )
                    )
                }
            }

            return signatures
        }

        private static func resultSelfFailureType(_ typeReference: TypeReference) -> TypeReference?
        {
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
                    if copy.genericParameterConstraintsByName[name, default: []].contains(
                        constraint)
                    {
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
                if copy.genericParameterConstraintsByName[constraint.parameterName, default: []]
                    .contains(constraint.constraint)
                {
                    continue
                }
                copy.genericParameterConstraintsByName[constraint.parameterName, default: []]
                    .append(constraint.constraint)
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

    private typealias RangeExpression = RangeCompiler.Expression
    private typealias RangeStatement = RangeCompiler.Statement
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
            .filter { $0.targetType == nil && context.llvmBridgesByCallableName[$0.name] == nil }
            .map(emitFunction)
            .joined(separator: "\n\n")
        let enumerations = try program.enumerations.map(emitEnum).joined(separator: "\n\n")
        let declarations = try program.declarations.map(emitConstruct).joined(separator: "\n\n")
        let extensions = try program.extensions.map(emitExtension).joined(separator: "\n\n")

        let main = try emitMain(program.mainBlock)

        let sections = [
            emitRuntimeSupport(includeFoundationImport: false),
            emitLLVMBridgeDeclarations(),
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

        let llvmModule = try LLVMLoweringEmitter().emitModule(program: program)
        let llvmObjectPath = llvmModule.map { "LLVM/\($0.moduleName).o" }
        let linkerSettings = llvmObjectPath.map {
            """
                                linkerSettings: [
                                    .unsafeFlags(["\($0)"])
                                ]
            """
        } ?? ""
        let targetArgumentSuffix = linkerSettings.isEmpty ? "" : ","
        let packageSwift = """
            // swift-tools-version: 6.2
            import PackageDescription

            let package = Package(
                name: "RangeGenerated",
                platforms: [
                    .macOS(.v14)
                ],
                targets: [
                    .executableTarget(
                        name: "RangeGenerated"\(targetArgumentSuffix)
            \(linkerSettings)
                    )
                ]
            )
            """

        try packageSwift.write(
            to: root.appendingPathComponent("Package.swift"),
            atomically: true,
            encoding: .utf8
        )

        let runtimeSwift = [
            emitRuntimeSupport(includeFoundationImport: false),
            emitLLVMBridgeDeclarations(),
        ].filter { !$0.isEmpty }.joined(separator: "\n\n")

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

        if let llvmModule {
            let llvmDirectory = root.appendingPathComponent("LLVM", isDirectory: true)
            try FileManager.default.createDirectory(
                at: llvmDirectory, withIntermediateDirectories: true)
            let irURL = llvmDirectory.appendingPathComponent("\(llvmModule.moduleName).ll")
            let objectURL = llvmDirectory.appendingPathComponent("\(llvmModule.moduleName).o")
            try llvmModule.ir.write(
                to: irURL,
                atomically: true,
                encoding: .utf8
            )
            try compileLLVMIR(irURL: irURL, objectURL: objectURL)
        }
    }

    private func emitRuntimeSupport(includeFoundationImport: Bool) -> String {
        let support = """
            // Backend implementation for RangeCore's Promise, Result, memory, threads, ChannelStorage, and Logger surface.
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

            enum Range_POSIXMemory {
                static func allocate(byteCount: Int, alignment: Int) -> Range_Result<Range_MemoryRegion, Range_MemoryAccessError> {
                    guard byteCount >= 0 && alignment > 0 else {
                        return .failure(cause: .invalid)
                    }

                    let minimumAlignment = MemoryLayout<UnsafeRawPointer>.alignment
                    let normalizedAlignment = max(alignment, minimumAlignment)
                    guard normalizedAlignment > 0 && normalizedAlignment & (normalizedAlignment - 1) == 0 else {
                        return .failure(cause: .invalid)
                    }

                    var rawPointer: UnsafeMutableRawPointer?
                    let status = posix_memalign(&rawPointer, normalizedAlignment, byteCount)
                    guard status == 0, let allocated = rawPointer else {
                        return .failure(cause: .outOfMemory)
                    }

                    return .success(
                        result: Range_MemoryRegion(
                            address: Range_MemoryAddress(raw: Int(bitPattern: allocated)),
                            byteCount: byteCount,
                            alignment: normalizedAlignment
                        )
                    )
                }

                static func deallocate(region: Range_MemoryRegion) -> Range_Result<Void, Range_MemoryAccessError> {
                    guard region.address.raw != 0 else {
                        return .failure(cause: .invalid)
                    }

                    free(UnsafeMutableRawPointer(bitPattern: region.address.raw))
                    return .success(result: Void())
                }

                static func zero(region: Range_MemoryRegion) -> Range_Result<Void, Range_MemoryAccessError> {
                    return fill(region: region, byte: 0)
                }

                static func fill(region: Range_MemoryRegion, byte: UInt8) -> Range_Result<Void, Range_MemoryAccessError> {
                    guard let pointer = UnsafeMutableRawPointer(bitPattern: region.address.raw), region.byteCount >= 0 else {
                        return .failure(cause: .invalid)
                    }

                    memset(pointer, Int32(byte), region.byteCount)
                    return .success(result: Void())
                }

                static func copy(source: Range_MemoryRegion, destination: Range_MemoryRegion) -> Range_Result<Void, Range_MemoryAccessError> {
                    guard let sourcePointer = UnsafeRawPointer(bitPattern: source.address.raw),
                          let destinationPointer = UnsafeMutableRawPointer(bitPattern: destination.address.raw),
                          source.byteCount >= 0,
                          destination.byteCount >= source.byteCount
                    else {
                        return .failure(cause: .invalid)
                    }

                    memcpy(destinationPointer, sourcePointer, source.byteCount)
                    return .success(result: Void())
                }

                static func readByte(address: Range_MemoryAddress) -> Range_Result<UInt8, Range_MemoryAccessError> {
                    guard let pointer = UnsafeRawPointer(bitPattern: address.raw) else {
                        return .failure(cause: .invalid)
                    }

                    return .success(result: pointer.load(as: UInt8.self))
                }

                static func writeByte(address: Range_MemoryAddress, byte: UInt8) -> Range_Result<Void, Range_MemoryAccessError> {
                    guard let pointer = UnsafeMutableRawPointer(bitPattern: address.raw) else {
                        return .failure(cause: .invalid)
                    }

                    pointer.storeBytes(of: byte, as: UInt8.self)
                    return .success(result: Void())
                }

                static func pageSize() -> Int {
                    Int(sysconf(_SC_PAGESIZE))
                }
            }

            enum Range_Memory {
                static func allocate(byteCount: Int, alignment: Int) -> Range_Result<Range_MemoryRegion, Range_MemoryAccessError> {
                    return Range_POSIXMemory.allocate(byteCount: byteCount, alignment: alignment)
                }

                static func deallocate(region: Range_MemoryRegion) -> Range_Result<Void, Range_MemoryAccessError> {
                    return Range_POSIXMemory.deallocate(region: region)
                }

                static func zero(region: Range_MemoryRegion) -> Range_Result<Void, Range_MemoryAccessError> {
                    return Range_POSIXMemory.zero(region: region)
                }

                static func fill(region: Range_MemoryRegion, byte: UInt8) -> Range_Result<Void, Range_MemoryAccessError> {
                    return Range_POSIXMemory.fill(region: region, byte: byte)
                }

                static func copy(source: Range_MemoryRegion, destination: Range_MemoryRegion) -> Range_Result<Void, Range_MemoryAccessError> {
                    return Range_POSIXMemory.copy(source: source, destination: destination)
                }

                static func readByte(address: Range_MemoryAddress) -> Range_Result<UInt8, Range_MemoryAccessError> {
                    return Range_POSIXMemory.readByte(address: address)
                }

                static func writeByte(address: Range_MemoryAddress, byte: UInt8) -> Range_Result<Void, Range_MemoryAccessError> {
                    return Range_POSIXMemory.writeByte(address: address, byte: byte)
                }

                static func pageSize() -> Int {
                    return Range_POSIXMemory.pageSize()
                }
            }

            enum Range_CPU {
                static func logicalCoreCount() -> Int {
                    Int(sysconf(_SC_NPROCESSORS_ONLN))
                }

                static func cacheLineSize() -> Int {
                    #if os(macOS)
                    var value = 0
                    var size = MemoryLayout<Int>.size
                    if sysctlbyname("hw.cachelinesize", &value, &size, nil, 0) == 0 {
                        return value
                    }
                    #endif
                    return 64
                }
            }

            final class Range_ThreadStart {
                let body: () -> Void

                init(body: @escaping () -> Void) {
                    self.body = body
                }
            }

            enum Range_POSIXThread {
                static func spawn(_ body: @escaping () -> Void) -> Range_Result<Range_ThreadHandle, Range_ThreadError> {
                    var thread: pthread_t?
                    let context = Unmanaged.passRetained(Range_ThreadStart(body: body)).toOpaque()
                    let status = pthread_create(&thread, nil, { rawContext in
                        let start = Unmanaged<Range_ThreadStart>
                            .fromOpaque(rawContext)
                            .takeRetainedValue()
                        start.body()
                        return nil
                    }, context)

                    guard status == 0, let thread else {
                        Unmanaged<Range_ThreadStart>.fromOpaque(context).release()
                        return .failure(cause: .unavailable)
                    }

                    return .success(result: Range_ThreadHandle(raw: Int(bitPattern: thread)))
                }

                static func join(_ handle: Range_ThreadHandle) -> Range_Result<Void, Range_ThreadError> {
                    guard let thread = pthread_t(bitPattern: handle.raw) else {
                        return .failure(cause: .invalid)
                    }

                    return pthread_join(thread, nil) == 0
                        ? .success(result: Void())
                        : .failure(cause: .invalid)
                }

                static func detach(_ handle: Range_ThreadHandle) -> Range_Result<Void, Range_ThreadError> {
                    guard let thread = pthread_t(bitPattern: handle.raw) else {
                        return .failure(cause: .invalid)
                    }

                    return pthread_detach(thread) == 0
                        ? .success(result: Void())
                        : .failure(cause: .invalid)
                }

                static func current() -> Range_ThreadHandle {
                    Range_ThreadHandle(raw: Int(bitPattern: pthread_self()))
                }

                static func yield() {
                    sched_yield()
                }

                static func sleep(milliseconds: Int) {
                    guard milliseconds > 0 else {
                        return
                    }

                    let clamped = min(milliseconds, Int(UInt32.max / 1000))
                    usleep(useconds_t(clamped * 1000))
                }
            }

            enum Range_Thread {
                static func spawn(_ body: @escaping () -> Void) -> Range_Result<Range_ThreadHandle, Range_ThreadError> {
                    return Range_POSIXThread.spawn(body)
                }

                static func join(_ handle: Range_ThreadHandle) -> Range_Result<Void, Range_ThreadError> {
                    return Range_POSIXThread.join(handle)
                }

                static func detach(_ handle: Range_ThreadHandle) -> Range_Result<Void, Range_ThreadError> {
                    return Range_POSIXThread.detach(handle)
                }

                static func current() -> Range_ThreadHandle {
                    return Range_POSIXThread.current()
                }

                static func yield() {
                    Range_POSIXThread.yield()
                }

                static func sleep(milliseconds: Int) {
                    Range_POSIXThread.sleep(milliseconds: milliseconds)
                }
            }

            enum Range_POSIXFileSystem {
                static func readData(path: String) -> Range_Result<Data, Range_FileReadError> {
                    let descriptor = open(path, O_RDONLY)
                    guard descriptor >= 0 else {
                        return errno == ENOENT
                            ? .failure(cause: .missing)
                            : .failure(cause: .unreadable)
                    }
                    defer { close(descriptor) }

                    var metadata = stat()
                    guard fstat(descriptor, &metadata) == 0 else {
                        return .failure(cause: .unreadable)
                    }

                    let byteCount = Int(metadata.st_size)
                    guard byteCount >= 0 else {
                        return .failure(cause: .unreadable)
                    }

                    var bytes = [UInt8](repeating: 0, count: byteCount)
                    var offset = 0
                    while offset < byteCount {
                        let readCount = bytes.withUnsafeMutableBufferPointer { buffer in
                            read(descriptor, buffer.baseAddress! + offset, byteCount - offset)
                        }

                        if readCount < 0 {
                            if errno == EINTR {
                                continue
                            }
                            return .failure(cause: .unreadable)
                        }

                        if readCount == 0 {
                            return .failure(cause: .unreadable)
                        }

                        offset += readCount
                    }

                    return .success(result: Data(bytes))
                }

                static func writeData(path: String, data: Data) -> Range_Result<Void, Range_FileWriteError> {
                    switch createParentDirectory(for: path) {
                    case .success:
                        break
                    case .failure(let error):
                        return .failure(cause: error)
                    }

                    let descriptor = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
                    guard descriptor >= 0 else {
                        return .failure(cause: .unwritable)
                    }
                    defer { close(descriptor) }

                    let byteCount = data.bytes.count
                    var offset = 0
                    while offset < byteCount {
                        let writeCount = data.bytes.withUnsafeBufferPointer { buffer in
                            write(descriptor, buffer.baseAddress! + offset, byteCount - offset)
                        }

                        if writeCount < 0 {
                            if errno == EINTR {
                                continue
                            }
                            return .failure(cause: .unwritable)
                        }

                        if writeCount == 0 {
                            return .failure(cause: .unwritable)
                        }

                        offset += writeCount
                    }

                    return .success(result: Void())
                }

                static func createDirectory(path: String) -> Range_Result<Void, Range_FileWriteError> {
                    guard !path.isEmpty && path != "." else {
                        return .success(result: Void())
                    }

                    let normalizedPath = path.hasSuffix("/") && path.count > 1
                        ? String(path.dropLast())
                        : path
                    let components = normalizedPath.split(separator: "/", omittingEmptySubsequences: true)
                    var current = normalizedPath.hasPrefix("/") ? "/" : ""

                    for component in components {
                        if current.isEmpty || current == "/" {
                            current += component
                        } else {
                            current += "/\\(component)"
                        }

                        if mkdir(current, 0o755) == 0 {
                            continue
                        }

                        if errno == EEXIST {
                            var metadata = stat()
                            guard lstat(current, &metadata) == 0,
                                  (metadata.st_mode & S_IFMT) == S_IFDIR else {
                                return .failure(cause: .unwritable)
                            }
                            continue
                        }

                        return .failure(cause: .unwritable)
                    }

                    return .success(result: Void())
                }

                private static func createParentDirectory(for path: String) -> Range_Result<Void, Range_FileWriteError> {
                    guard let slashIndex = path.lastIndex(of: "/") else {
                        return .success(result: Void())
                    }

                    let parent = String(path[..<slashIndex])
                    guard !parent.isEmpty else {
                        return .success(result: Void())
                    }

                    return createDirectory(path: parent)
                }

                static func listEntries(path: String) -> Range_Result<[Range_FileSystemEntry], Range_FileReadError> {
                    guard let directory = opendir(path) else {
                        return errno == ENOENT
                            ? .failure(cause: .missing)
                            : .failure(cause: .unreadable)
                    }
                    defer { closedir(directory) }

                    var entries: [Range_FileSystemEntry] = []
                    while let entry = readdir(directory) {
                        let name = withUnsafePointer(to: entry.pointee.d_name) { pointer in
                            pointer.withMemoryRebound(to: CChar.self, capacity: MemoryLayout.size(ofValue: entry.pointee.d_name)) {
                                String(cString: $0)
                            }
                        }

                        if name == "." || name == ".." {
                            continue
                        }

                        let childPath: String
                        if path == "/" || path.hasSuffix("/") {
                            childPath = "\\(path)\\(name)"
                        } else {
                            childPath = "\\(path)/\\(name)"
                        }
                        var metadata = stat()
                        guard lstat(childPath, &metadata) == 0 else {
                            return .failure(cause: .unreadable)
                        }

                        let kind: Range_FileSystemEntryKind =
                            (metadata.st_mode & S_IFMT) == S_IFDIR ? .directory : .file
                        entries.append(
                            Range_FileSystemEntry(
                                path: childPath,
                                name: name,
                                kind: kind
                            )
                        )
                    }

                    return .success(result: entries)
                }
            }

            enum Range_HostFileSystem {
                static func readData(path: String) -> Range_Result<Data, Range_FileReadError> {
                    return Range_POSIXFileSystem.readData(path: path)
                }

                static func writeData(path: String, data: Data) -> Range_Result<Void, Range_FileWriteError> {
                    return Range_POSIXFileSystem.writeData(path: path, data: data)
                }

                static func createDirectory(path: String) -> Range_Result<Void, Range_FileWriteError> {
                    return Range_POSIXFileSystem.createDirectory(path: path)
                }

                static func listEntries(path: String) -> Range_Result<[Range_FileSystemEntry], Range_FileReadError> {
                    return Range_POSIXFileSystem.listEntries(path: path)
                }
            }

            enum Range_FileManager {
                static func readData(path: String) -> Range_Result<Data, Range_FileReadError> {
                    return Range_POSIXFileSystem.readData(path: path)
                }

                static func readFile(path: String) -> Range_Result<String, Range_FileReadError> {
                    switch readData(path: path) {
                    case .success(let data):
                        return .success(result: Range_UTF8.decode(data: data))
                    case .failure(let error):
                        return .failure(cause: error)
                    }
                }

                static func writeData(path: String, data: Data) -> Range_Result<Void, Range_FileWriteError> {
                    return Range_POSIXFileSystem.writeData(path: path, data: data)
                }

                static func createFile(path: String, text: String) -> Range_Result<Void, Range_FileWriteError> {
                    return writeData(path: path, data: Range_UTF8.encode(text: text))
                }

                static func createFolder(path: String) -> Range_Result<Void, Range_FileWriteError> {
                    return Range_POSIXFileSystem.createDirectory(path: path)
                }

                static func listEntries(path: String) -> Range_Result<[Range_FileSystemEntry], Range_FileReadError> {
                    return Range_POSIXFileSystem.listEntries(path: path)
                }
            }

            enum Range_UTF8 {
                static func decode(data: Data) -> String {
                    return String(decoding: data.bytes, as: UTF8.self)
                }

                static func encode(text: String) -> Data {
                    return Data(Array(text.utf8))
                }
            }

            enum Range_SHA256 {
                private static let initialHash: [UInt32] = [
                    0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
                    0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
                ]

                private static let roundConstants: [UInt32] = [
                    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5,
                    0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
                    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
                    0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
                    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
                    0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
                    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
                    0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
                    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
                    0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
                    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
                    0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
                    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
                    0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
                    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
                    0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
                ]

                static func digest(string: String) -> Data {
                    return digest(data: Range_UTF8.encode(text: string))
                }

                static func digest(data: Data) -> Data {
                    var message = data.bytes
                    let bitLength = UInt64(message.count) * 8
                    message.append(0x80)
                    while message.count % 64 != 56 {
                        message.append(0)
                    }
                    for shift in stride(from: 56, through: 0, by: -8) {
                        message.append(UInt8((bitLength >> UInt64(shift)) & 0xff))
                    }

                    var hash = initialHash

                    for chunkStart in stride(from: 0, to: message.count, by: 64) {
                        var words = Array(repeating: UInt32(0), count: 64)
                        for index in 0..<16 {
                            let offset = chunkStart + index * 4
                            words[index] =
                                (UInt32(message[offset]) << 24)
                                | (UInt32(message[offset + 1]) << 16)
                                | (UInt32(message[offset + 2]) << 8)
                                | UInt32(message[offset + 3])
                        }
                        for index in 16..<64 {
                            let s0 = rotateRight(words[index - 15], by: 7)
                                ^ rotateRight(words[index - 15], by: 18)
                                ^ (words[index - 15] >> 3)
                            let s1 = rotateRight(words[index - 2], by: 17)
                                ^ rotateRight(words[index - 2], by: 19)
                                ^ (words[index - 2] >> 10)
                            words[index] = words[index - 16]
                                &+ s0
                                &+ words[index - 7]
                                &+ s1
                        }

                        var a = hash[0]
                        var b = hash[1]
                        var c = hash[2]
                        var d = hash[3]
                        var e = hash[4]
                        var f = hash[5]
                        var g = hash[6]
                        var h = hash[7]

                        for index in 0..<64 {
                            let s1 = rotateRight(e, by: 6) ^ rotateRight(e, by: 11) ^ rotateRight(e, by: 25)
                            let ch = (e & f) ^ (~e & g)
                            let temp1 = h &+ s1 &+ ch &+ roundConstants[index] &+ words[index]
                            let s0 = rotateRight(a, by: 2) ^ rotateRight(a, by: 13) ^ rotateRight(a, by: 22)
                            let maj = (a & b) ^ (a & c) ^ (b & c)
                            let temp2 = s0 &+ maj

                            h = g
                            g = f
                            f = e
                            e = d &+ temp1
                            d = c
                            c = b
                            b = a
                            a = temp1 &+ temp2
                        }

                        hash[0] = hash[0] &+ a
                        hash[1] = hash[1] &+ b
                        hash[2] = hash[2] &+ c
                        hash[3] = hash[3] &+ d
                        hash[4] = hash[4] &+ e
                        hash[5] = hash[5] &+ f
                        hash[6] = hash[6] &+ g
                        hash[7] = hash[7] &+ h
                    }

                    var bytes: [UInt8] = []
                    for word in hash {
                        bytes.append(UInt8((word >> 24) & 0xff))
                        bytes.append(UInt8((word >> 16) & 0xff))
                        bytes.append(UInt8((word >> 8) & 0xff))
                        bytes.append(UInt8(word & 0xff))
                    }
                    return Data(bytes)
                }

                private static func rotateRight(_ value: UInt32, by amount: UInt32) -> UInt32 {
                    return (value >> amount) | (value << (32 - amount))
                }
            }

            final class Range_ChannelStorage<Element>: @unchecked Sendable {
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
                    precondition(!closed, "Cannot send to a closed channel.")
                    precondition(capacity == 0 || buffer.count < capacity, "Channel buffer is full.")
                    buffer.append(element)
                }

                func receive() -> Element {
                    if buffer.isEmpty {
                        preconditionFailure(
                            "Cannot receive from an empty channel in the single-threaded Swift backend."
                        )
                    }

                    return buffer.removeFirst()
                }

                func close() {
                    closed = true
                }
            }

            enum Range_Logger {
                static func log(_ value: String) {
                    print(value)
                }

                static func log(_ value: Int) {
                    print(value)
                }

                static func log(_ value: Bool) {
                    print(value ? "true" : "false")
                }

                static func log(_ value: Float) {
                    print(value)
                }

                static func log(_ value: Double) {
                    print(value)
                }

                static func debug(_ value: String) {
                    print(value)
                }

                static func info(_ value: String) {
                    print(value)
                }

                static func success(_ value: String) {
                    print(value)
                }

                static func warning(_ value: String) {
                    print(value)
                }

                static func error(_ value: String) {
                    print(value)
                }
            }

            struct Data: Hashable, Sendable {
                var bytes: [UInt8]

                init() {
                    self.bytes = []
                }

                init(_ bytes: [UInt8]) {
                    self.bytes = bytes
                }

            }

            struct UUID: Hashable, CustomStringConvertible, Sendable {
                let uuidString: String

                init() {
                    self.uuidString = "00000000-0000-0000-0000-000000000000"
                }

                init?(uuidString: String) {
                    guard !uuidString.isEmpty else {
                        return nil
                    }
                    self.uuidString = uuidString
                }

                var description: String {
                    uuidString
                }
            }

            extension String {
                func __rangeCharacter(index: Int) -> String {
                    let position = self.index(startIndex, offsetBy: index)
                    return String(self[position])
                }

                func __rangeSubstring(start: Int, end: Int) -> String {
                    let lowerBound = self.index(startIndex, offsetBy: start)
                    let upperBound = self.index(startIndex, offsetBy: end)
                    return String(self[lowerBound..<upperBound])
                }

                func __rangeSnakeCase() -> String {
                    var result = ""
                    var previousWasLowercaseOrDigit = false

                    for scalar in unicodeScalars {
                        let character = Character(scalar)
                        let string = String(character)
                        let isUppercase = string.uppercased() == string && string.lowercased() != string
                        let isLowercase = string.lowercased() == string && string.uppercased() != string
                        let isDigit = scalar.value >= 48 && scalar.value <= 57

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
                    self.init(posixTime: time(nil))
                }

                init(posixTime: time_t) {
                    var rawTime = posixTime
                    var utc = tm()
                    gmtime_r(&rawTime, &utc)
                    self.year = Int(utc.tm_year + 1900)
                    self.month = Int(utc.tm_mon + 1)
                    self.day = Int(utc.tm_mday)
                }

                init(iso8601String: String) throws {
                    let parts = iso8601String.split(separator: "-")
                    guard parts.count == 3,
                        let year = Int(parts[0]),
                        let month = Int(parts[1]),
                        let day = Int(parts[2])
                    else {
                        throw __RangeThrownFailure<Range_DecodingError>(failure: .failed)
                    }

                    self.year = year
                    self.month = month
                    self.day = day
                }

                var description: String {
                    "\\(Self.padded(year, width: 4))-\\(Self.padded(month, width: 2))-\\(Self.padded(day, width: 2))"
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

                private static func padded(_ value: Int, width: Int) -> String {
                    let string = String(value)
                    if string.count >= width {
                        return string
                    }
                    return String(repeating: "0", count: width - string.count) + string
                }
            }

            struct __RangeDateTime: Hashable, Comparable, CustomStringConvertible, Sendable {
                let storage: String

                init() {
                    self.init(posixTime: time(nil))
                }

                init(posixTime: time_t) {
                    var rawTime = posixTime
                    var utc = tm()
                    gmtime_r(&rawTime, &utc)
                    let year = Self.padded(Int(utc.tm_year + 1900), width: 4)
                    let month = Self.padded(Int(utc.tm_mon + 1), width: 2)
                    let day = Self.padded(Int(utc.tm_mday), width: 2)
                    let hour = Self.padded(Int(utc.tm_hour), width: 2)
                    let minute = Self.padded(Int(utc.tm_min), width: 2)
                    let second = Self.padded(Int(utc.tm_sec), width: 2)
                    self.storage = "\\(year)-\\(month)-\\(day)T\\(hour):\\(minute):\\(second)Z"
                }

                init(iso8601String: String) throws {
                    self.storage = iso8601String
                }

                var description: String {
                    storage
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

                private static func padded(_ value: Int, width: Int) -> String {
                    let string = String(value)
                    if string.count >= width {
                        return string
                    }
                    return String(repeating: "0", count: width - string.count) + string
                }
            }

            final class __RangeBinding<Value> {
                private var storedValue: Value?
                private let getter: () -> Value
                private let setter: (Value) -> Void

                init(get: @escaping () -> Value, set: @escaping (Value) -> Void) {
                    self.storedValue = nil
                    self.getter = get
                    self.setter = set
                }

                init(value: Value) {
                    self.storedValue = value
                    self.getter = { value }
                    self.setter = { _ in }
                }

                var value: Value {
                    get { storedValue ?? getter() }
                    set {
                        if storedValue != nil {
                            storedValue = newValue
                        } else {
                            setter(newValue)
                        }
                    }
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

        let hostIOImport = """
            #if os(Linux)
            import Glibc
            #else
            import Darwin
            #endif
            """
        let imports =
            includeFoundationImport ? "import Foundation\n\n\(hostIOImport)" : hostIOImport
        return "\(imports)\n\n\(support)"
    }

    private func emitLLVMBridgeDeclarations() -> String {
        let bridges = context.llvmBridgesByCallableName.sorted { $0.key < $1.key }.map {
            _, bridge in
            let parameters = (0..<bridge.parameterCount)
                .map { "_ argument\($0): Int64" }
                .joined(separator: ", ")
            return """
            @_silgen_name("\(bridge.symbolName)")
            func \(bridge.symbolName)(\(parameters)) -> Int64
            """
        }

        return bridges.joined(separator: "\n\n")
    }

    private func compileLLVMIR(irURL: URL, objectURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/clang")
        process.arguments = [
            "-O3",
            "-c",
            irURL.path,
            "-o",
            objectURL.path,
        ]

        let stderr = Pipe()
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let errorText =
                String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
                ?? ""
            throw SwiftBackendError("LLVM object emission failed: \(errorText)")
        }
    }

    private func emitSourceUnit(_ unit: LoweredSourceUnit) throws -> String {
        var sections: [String] = []

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
            .filter { $0.targetType == nil && context.llvmBridgesByCallableName[$0.name] == nil }
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

    private func emitMain(_ mainBlock: MainBlockNode) throws -> String {
        let body = try emitStatements(
            mainBlock.body, indent: 2, enclosingReturnType: .named("Void"))

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
            .filter { $0.body != nil }
            .map {
                try emitMethod(
                    $0,
                    constructGenericParameterNames: genericParameterNames,
                    constructGenericParameters: declaration.genericParameters,
                    isReferenceType: isReferenceType,
                    forceStatic: constructShouldEmitStaticMethods(declaration)
                )
            }
            .joined(separator: "\n\n")

        let memberSections = [
            storedValues,
            storedStates,
            storedBindings,
            deriveds,
            synthesizedInitializer,
            initializers,
            methods,
        ].filter { !$0.isEmpty }

        if memberSections.isEmpty {
            return
                "\(typeKeyword) \(emitSwiftSymbolName(declaration.name))\(genericClause) {\n}"
        }

        let body = memberSections.joined(separator: "\n\n")
        return """
            \(typeKeyword) \(emitSwiftSymbolName(declaration.name))\(genericClause) {
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

        for value in declaration.values
        where value.value == nil
            && propertyForwardsInitializer(macros: value.macros)
        {
            guard let forwardedConstruct = context.constructsByName[value.typeName] else {
                continue
            }
            let forwardedParameters = forwardedInitializerParameters(for: forwardedConstruct)
            parameters.append(
                contentsOf: try forwardedParameters.map {
                    try emitParameter($0, genericParameterNames: genericParameterNames)
                })
            let arguments = forwardedParameters.map { parameter in
                CallArgument(
                    label: parameter.name,
                    value: .identifier(parameter.name)
                )
            }
            assignments.append(
                "self.\(value.name) = \(try emitRawCall(name: value.typeName, arguments: arguments))"
            )
        }

        for state in declaration.states where propertyForwardsInitializer(macros: state.macros) {
            guard let forwardedConstruct = context.constructsByName[state.type.displayName] else {
                continue
            }
            let forwardedParameters = forwardedInitializerParameters(for: forwardedConstruct)
            parameters.append(
                contentsOf: try forwardedParameters.map {
                    try emitParameter($0, genericParameterNames: genericParameterNames)
                })
            let arguments = forwardedParameters.map { parameter in
                CallArgument(
                    label: parameter.name,
                    value: .identifier(parameter.name)
                )
            }
            assignments.append(
                "self.\(state.name) = \(try emitRawCall(name: state.type.displayName, arguments: arguments))"
            )
        }

        for value in declaration.values where value.value == nil {
            guard !propertyForwardsInitializer(macros: value.macros) else {
                continue
            }
            let typeName = emitDeclaredTypeName(
                value.typeName,
                genericParameterNames: genericParameterNames
            )
            parameters.append("\(value.name): \(typeName)")
            assignments.append("self.\(value.name) = \(value.name)")
        }

        for state in declaration.states {
            guard !propertyForwardsInitializer(macros: state.macros) else {
                continue
            }
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
            if let defaultValue = emitBindingDefaultValue(forDeclaredTypeName: binding.typeName) {
                parameters.append(
                    "\(binding.name): __RangeBinding<\(typeName)> = __RangeBinding(value: \(defaultValue))"
                )
            } else {
                parameters.append("\(binding.name): __RangeBinding<\(typeName)>")
            }
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

    private func emitBindingDefaultValue(forDeclaredTypeName name: String) -> String? {
        if name.hasPrefix("[") && name.hasSuffix("]") {
            return "[]"
        }
        if name.hasPrefix("Array<") && name.hasSuffix(">") {
            return "[]"
        }
        return nil
    }

    private func forwardedInitializerParameters(
        for construct: ConstructDeclaration,
        activeConstructs: Set<String> = []
    ) -> [RangeFunctionParameter] {
        let activeConstructs = activeConstructs.union([construct.name])
        let forwardedValues = construct.values.flatMap { value -> [RangeFunctionParameter] in
            guard propertyForwardsInitializer(macros: value.macros),
                !activeConstructs.contains(value.typeName),
                let nested = context.constructsByName[value.typeName]
            else {
                return []
            }
            return forwardedInitializerParameters(for: nested, activeConstructs: activeConstructs)
        }
        let forwardedStates = construct.states.flatMap { state -> [RangeFunctionParameter] in
            guard propertyForwardsInitializer(macros: state.macros),
                !activeConstructs.contains(state.type.displayName),
                let nested = context.constructsByName[state.type.displayName]
            else {
                return []
            }
            return forwardedInitializerParameters(for: nested, activeConstructs: activeConstructs)
        }
        let values = construct.values.compactMap { value -> RangeFunctionParameter? in
            guard !propertyForwardsInitializer(macros: value.macros) else { return nil }
            let defaultValue = value.value ?? (value.typeName.hasSuffix("?") ? .nilLiteral : nil)
            return RangeFunctionParameter(
                macros: [],
                name: value.name,
                typeReference: .named(value.typeName),
                defaultValue: defaultValue,
                slotName: nil
            )
        }
        let states = construct.states.compactMap { state -> RangeFunctionParameter? in
            guard !propertyForwardsInitializer(macros: state.macros) else { return nil }
            let defaultValue: RangeExpression?
            switch state.storage {
            case .stored(let expression):
                defaultValue = expression
            case .declared:
                defaultValue = nil
            }
            return RangeFunctionParameter(
                macros: [],
                name: state.name,
                typeReference: state.type,
                defaultValue: defaultValue,
                slotName: nil
            )
        }
        return forwardedValues + forwardedStates + values + states
    }

    private func propertyForwardsInitializer(macros applications: [MacroApplication]) -> Bool {
        applications.contains(where: { application in
            guard let macro = context.macrosByName[application.name],
                let targetBinding = macro.bindings?.target
            else {
                return false
            }
            return macroOperationExpressions(in: macro.body).contains { expression in
                guard case .call(let name, let arguments) = expression else {
                    return false
                }
                return name == "\(targetBinding).initializer.forward" && arguments.isEmpty
            }
        })
    }

    private func macroOperationExpressions(in statements: [RangeStatement]) -> [RangeExpression] {
        var expressions: [RangeExpression] = []
        for statement in statements {
            switch statement {
            case .expand:
                continue
            case .expression(let expression):
                expressions.append(expression)
            case .conditional(let branches):
                for branch in branches {
                    expressions.append(contentsOf: macroOperationExpressions(in: branch.body))
                }
            case .whileLoop(_, let body), .forEach(_, _, let body), .derived(_, _, let body):
                expressions.append(contentsOf: macroOperationExpressions(in: body))
            case .background(let background):
                expressions.append(contentsOf: macroOperationExpressions(in: background.body))
            case .deferBlock(let deferred):
                expressions.append(contentsOf: macroOperationExpressions(in: deferred.body))
            case .localCallable(let declaration):
                expressions.append(contentsOf: macroOperationExpressions(in: declaration.body))
            case .switchStatement(_, let cases, let defaultBody):
                for switchCase in cases {
                    expressions.append(contentsOf: macroOperationExpressions(in: switchCase.body))
                }
                if let defaultBody {
                    expressions.append(contentsOf: macroOperationExpressions(in: defaultBody))
                }
            case .localBinding, .assignment, .compoundAssignment, .return, .macroInvocation,
                .break, .continue:
                continue
            }
        }
        return expressions
    }

    private func emitExtension(_ declaration: ExtensionDeclaration) throws -> String {
        let extensionHeader = emitExtensionHeader(declaration)
        let nestedEnumerations = try declaration.enumerations.map(emitEnum).joined(
            separator: "\n\n")
        let nestedConstructs = try declaration.constructs.map(emitConstruct).joined(
            separator: "\n\n")
        let genericParameterNames = extensionGenericParameterNames(in: declaration)
        let initializers = try declaration.initializers.map {
            try emitInitializer(
                $0,
                genericParameterNames: genericParameterNames,
                bindingNames: [],
                scope: EmissionScope().adding(
                    extensionConstraints: declaration.genericArgumentConstraints)
            )
        }.joined(separator: "\n\n")
        let methods = try declaration.callables.filter { $0.body != nil }.map {
            try emitMethod(
                $0,
                inheritedScope: EmissionScope().adding(
                    extensionConstraints: declaration.genericArgumentConstraints)
            )
        }.joined(separator: "\n\n")

        let memberSections = [
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
            return "extension \(emitTypeName(declaration.targetType))"
        }

        let target = emitTypeName(base)
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
        return "extension \(target)\(whereClause)"
    }

    private func extensionGenericParameterNames(in declaration: ExtensionDeclaration) -> Set<String>
    {
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

        let local = parameter.name
        let renderedType = emitTypeName(typeReference, genericParameterNames: genericParameterNames)
        if parameter.isBinding {
            return "\(local): __RangeBinding<\(renderedType)>"
        }

        return "\(local): \(renderedType)"
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
            if isAnnotationHandleTypeName(name) {
                return "Any"
            }
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
            return
                "\(emitTypeName(base, genericParameterNames: genericParameterNames))<\(renderedArguments)>"
        case .array(let element):
            return "[\(emitTypeName(element, genericParameterNames: genericParameterNames))]"
        case .function(let parameters, let returnType):
            let renderedParameters = parameters.map {
                emitTypeName($0, genericParameterNames: genericParameterNames)
            }.joined(separator: ", ")
            return
                "(\(renderedParameters)) -> \(emitTypeName(returnType, genericParameterNames: genericParameterNames))"
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
            return
                "[\(emitDeclaredTypeName(elementName, genericParameterNames: genericParameterNames))]"
        }

        if name.hasSuffix("?"),
            name.count > 1
        {
            let wrappedName = String(name.dropLast())
            return
                "\(emitDeclaredTypeName(wrappedName, genericParameterNames: genericParameterNames))?"
        }

        if let genericName = emitGenericDeclaredTypeName(
            name,
            genericParameterNames: genericParameterNames
        ) {
            return genericName
        }

        return emitTypeName(.named(name), genericParameterNames: genericParameterNames)
    }

    private func emitGenericDeclaredTypeName(
        _ name: String,
        genericParameterNames: Set<String>
    ) -> String? {
        guard let genericStart = name.firstIndex(of: "<"),
            name.last == ">"
        else {
            return nil
        }

        let base = String(name[..<genericStart])
        let argumentStart = name.index(after: genericStart)
        let argumentEnd = name.index(before: name.endIndex)
        let arguments = splitGenericArgumentNames(String(name[argumentStart..<argumentEnd]))
        guard !arguments.isEmpty else {
            return nil
        }

        let renderedArguments = arguments.map {
            emitDeclaredTypeName($0, genericParameterNames: genericParameterNames)
        }.joined(separator: ", ")
        return
            "\(emitDeclaredTypeName(base, genericParameterNames: genericParameterNames))<\(renderedArguments)>"
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
                    return
                        "\(name): \(emitTypeName(constraint, genericParameterNames: genericParameterNames))"
                }
                return name
            case .value:
                return nil
            }
        }

        guard !rendered.isEmpty else { return "" }
        return "<\(rendered.joined(separator: ", "))>"
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
            return
                "let \(value.name): \(emitDeclaredTypeName(value.typeName, genericParameterNames: genericParameterNames)) = \(try emitExpression(expression))"
        }
        return
            "let \(value.name): \(emitDeclaredTypeName(value.typeName, genericParameterNames: genericParameterNames))"
    }

    private func storedValueEmissionOrder(for declaration: ConstructDeclaration)
        -> [ValueDeclaration]
    {
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
            return
                "var \(state.name): \(emitTypeName(state.type, genericParameterNames: genericParameterNames))"
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
    ) throws -> String {
        try emitExpression(declaration.expression, scope: scope)
    }

    private func emitDerivedMember(
        _ derived: DerivedDeclaration,
        genericParameterNames: Set<String> = []
    ) throws -> String {
        guard let body = derived.body else {
            return
                "var \(derived.name): \(emitDeclaredTypeName(derived.typeName, genericParameterNames: genericParameterNames))"
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
        isReferenceType: Bool = false,
        forceStatic: Bool = false
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
        let scope =
            inheritedScope
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
        let isStatic = forceStatic || callableShouldEmitStatic(callable)
        let staticPrefix = isStatic ? "static " : ""
        let mutatingPrefix =
            !isStatic && !isReferenceType && methodNeedsMutation(callable) ? "mutating " : ""

        return """
            \(staticPrefix)\(mutatingPrefix)func \(callable.name)\(genericClause)(\(parameters))\(returnClause) {
            \(functionBody)
            }
            """
    }

    private func constructShouldEmitStaticMethods(_ declaration: ConstructDeclaration) -> Bool {
        declaration.isCore
            && declaration.values.isEmpty
            && declaration.states.isEmpty
            && declaration.bindings.isEmpty
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
            guard let expression else {
                return false
            }
            return expressionReferencesInstanceSelf(expression)
        case .conditional(let branches):
            return branches.contains { branch in
                (branch.condition.map { expressionReferencesInstanceSelf($0) } ?? false)
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
            return
                "\(prefix)for \(name) in \(try emitExpression(sequence, scope: scope)) {\n\(bodyText)\n\(prefix)}"
        case .whileLoop(let condition, let body):
            let bodyText = try emitInitializerStatements(
                body,
                indent: indent + 1,
                bindingNames: bindingNames,
                bindingParameterNames: bindingParameterNames,
                initializerReturnType: initializerReturnType,
                scope: scope
            )
            return
                "\(prefix)while \(try emitExpression(condition, scope: scope)) {\n\(bodyText)\n\(prefix)}"
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
            lines.append(
                "\(prefix)    fatalError(\"Non-exhaustive Range switch reached at runtime.\")")
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

            return
                "\(prefix)throw __RangeThrownFailure<\(emitTypeName(failureType))>(failure: \(try emitExpression(failureExpression, scope: scope)))"
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
            throw SwiftBackendError(
                "Macro expansion statements must be expanded before Swift emission.")
        case .background(let background):
            let bodyText = try emitStatements(
                background.body,
                indent: indent + 1,
                enclosingReturnType: enclosingReturnType,
                scope: scope
            )
            return """
                \(prefix)switch Range_POSIXThread.spawn({
                \(bodyText)
                \(prefix)}) {
                \(prefix)case .success(let handle):
                \(prefix)    _ = Range_POSIXThread.detach(handle)
                \(prefix)case .failure:
                \(prefix)    Range_Logger.error("@background failed to spawn thread.")
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
            lines.append(
                "\(prefix)    fatalError(\"Non-exhaustive Range switch reached at runtime.\")")
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
            if let closure = try emitCoreClosureCall(name: name, arguments: arguments, scope: scope)
            {
                return closure
            }
            if let lowered = try emitKnownSystemCall(
                name: name,
                arguments: arguments,
                scope: scope
            ) {
                return lowered
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
            let rendered = try elements.map { try emitExpression($0, scope: scope) }.joined(
                separator: ", ")
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
        if isAnnotationHandleTypeName(name) {
            return "Any"
        }
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

    private func isAnnotationHandleTypeName(_ name: String) -> Bool {
        name.hasPrefix("@") || name.hasPrefix("#")
    }

    private func emitSwiftReferenceName(
        _ name: String,
        scope: EmissionScope = .empty
    ) -> String {
        if name.hasPrefix(".") {
            return name
        }

        if let genericName = emitGenericSwiftReferenceName(name, scope: scope) {
            return genericName
        }

        guard let dotIndex = name.firstIndex(of: ".") else {
            if scope.genericParameterNames.contains(name)
                || context.genericParameterNames.contains(name)
            {
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
        if scope.genericParameterNames.contains(base)
            || context.genericParameterNames.contains(base)
        {
            return name
        }
        return "\(emitSwiftSymbolName(base))\(suffix)"
    }

    private func emitGenericSwiftReferenceName(
        _ name: String,
        scope: EmissionScope
    ) -> String? {
        guard let genericStart = name.firstIndex(of: "<"),
            name.last == ">"
        else {
            return nil
        }

        let base = String(name[..<genericStart])
        let argumentStart = name.index(after: genericStart)
        let argumentEnd = name.index(before: name.endIndex)
        let arguments = splitGenericArgumentNames(String(name[argumentStart..<argumentEnd]))
        guard !arguments.isEmpty else {
            return nil
        }

        let renderedArguments = arguments.map {
            emitGenericSwiftReferenceArgument($0, scope: scope)
        }.joined(separator: ", ")
        return "\(emitSwiftReferenceName(base, scope: scope))<\(renderedArguments)>"
    }

    private func splitGenericArgumentNames(_ source: String) -> [String] {
        var arguments: [String] = []
        var current = ""
        var depth = 0

        for character in source {
            if character == "<" {
                depth += 1
                current.append(character)
                continue
            }
            if character == ">" {
                depth -= 1
                current.append(character)
                continue
            }
            if character == ",", depth == 0 {
                let argument = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !argument.isEmpty {
                    arguments.append(argument)
                }
                current = ""
                continue
            }
            current.append(character)
        }

        let finalArgument = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !finalArgument.isEmpty {
            arguments.append(finalArgument)
        }
        return arguments
    }

    private func emitGenericSwiftReferenceArgument(
        _ argument: String,
        scope: EmissionScope
    ) -> String {
        if isAnnotationHandleTypeName(argument) {
            return "Any"
        }
        if let nested = emitGenericSwiftReferenceName(argument, scope: scope) {
            return nested
        }
        return emitSwiftReferenceName(argument, scope: scope)
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
            return
                "{ \(parameterNames.joined(separator: ", ")) in \(try emitExpression(expression, scope: scope)) }"
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
        inferredLabel: String? = nil,
        scope: EmissionScope = .empty
    ) throws -> String {
        if let label = argument.label {
            return "\(label): \(try emitExpression(argument.value, scope: scope))"
        }
        if let inferredLabel {
            return "\(inferredLabel): \(try emitExpression(argument.value, scope: scope))"
        }
        return try emitExpression(argument.value, scope: scope)
    }

    private func emitCallArguments(
        _ arguments: [CallArgument],
        for callee: String,
        scope: EmissionScope = .empty
    ) throws -> String {
        let inferredLabels = inferredCallLabels(for: callee, arguments: arguments)
        return try arguments.enumerated().map { index, argument in
            try emitCallArgument(
                argument,
                inferredLabel: inferredLabels?[index],
                scope: scope
            )
        }.joined(separator: ", ")
    }

    private func inferredCallLabels(
        for callee: String,
        arguments: [CallArgument]
    ) -> [String]? {
        guard !arguments.isEmpty,
            arguments.allSatisfy({ $0.label == nil }),
            !callableNameIsOperator(callee)
        else {
            return nil
        }

        let lookupName = callee.split(separator: ".").last.map(String.init) ?? callee
        let candidates = context.callableParameterLabelsByName[callee, default: []]
            + context.callableParameterLabelsByName[lookupName, default: []]
        let matching = candidates.filter { $0.count == arguments.count }
        let unique = Set(matching)

        guard unique.count == 1,
            let labels = unique.first,
            labels.count == arguments.count
        else {
            return nil
        }

        return labels
    }

    private func emitKnownSystemCall(
        name: String,
        arguments: [CallArgument],
        scope: EmissionScope = .empty
    ) throws -> String? {
        let directPOSIXTargets: [String: String] = [
            "Memory.allocate": "Range_POSIXMemory.allocate",
            "Memory.deallocate": "Range_POSIXMemory.deallocate",
            "Memory.zero": "Range_POSIXMemory.zero",
            "Memory.fill": "Range_POSIXMemory.fill",
            "Memory.copy": "Range_POSIXMemory.copy",
            "Memory.readByte": "Range_POSIXMemory.readByte",
            "Memory.writeByte": "Range_POSIXMemory.writeByte",
            "Memory.pageSize": "Range_POSIXMemory.pageSize",
            "Thread.spawn": "Range_POSIXThread.spawn",
            "Thread.join": "Range_POSIXThread.join",
            "Thread.detach": "Range_POSIXThread.detach",
            "Thread.current": "Range_POSIXThread.current",
            "Thread.yield": "Range_POSIXThread.yield",
            "Thread.sleep": "Range_POSIXThread.sleep",
            "SHA256.digest": "Range_SHA256.digest",
        ]

        guard let target = directPOSIXTargets[name] else {
            return nil
        }

        let rendered = try emitCallArguments(arguments, for: name, scope: scope)
        return "\(target)(\(rendered))"
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

        func argument(_ label: String) -> RangeCompiler.Expression? {
            arguments.first(where: { $0.label == label })?.value
        }

        func unlabeledArgument() -> RangeCompiler.Expression? {
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
        case "character":
            guard let index = argument("index") else { return nil }
            return "\(base).__rangeCharacter(index: \(try emitExpression(index, scope: scope)))"
        case "substring":
            guard let start = argument("start"), let end = argument("end") else { return nil }
            return
                "\(base).__rangeSubstring(start: \(try emitExpression(start, scope: scope)), end: \(try emitExpression(end, scope: scope)))"
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
            throw SwiftBackendError(
                "Macro expansion statements must be expanded before Swift emission.")
        case .background(let background):
            let bodyText = try emitStatements(
                background.body,
                indent: indent + 1,
                enclosingReturnType: enclosingReturnType
            )
            return """
                \(prefix)switch Range_POSIXThread.spawn({
                \(bodyText)
                \(prefix)}) {
                \(prefix)case .success(let handle):
                \(prefix)    _ = Range_POSIXThread.detach(handle)
                \(prefix)case .failure:
                \(prefix)    Range_Logger.error("@background failed to spawn thread.")
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
                return
                    "\(prefix)throw __RangeDeferredControlFlow.returnValue(\(try emitExpression(expression)))"
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
            .map {
                try emitDeferredInnerStatement(
                    $0, indent: indent, enclosingReturnType: enclosingReturnType)
            }
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
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
    }

    private func emitRawCall(
        name: String,
        arguments: [CallArgument],
        scope: EmissionScope = .empty
    ) throws -> String {
        if let llvmCall = try emitLLVMBridgeCall(name: name, arguments: arguments, scope: scope) {
            return llvmCall
        }

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

    private func emitLLVMBridgeCall(
        name: String,
        arguments: [CallArgument],
        scope: EmissionScope
    ) throws -> String? {
        guard let bridge = context.llvmBridgesByCallableName[name] else {
            return nil
        }
        guard arguments.count == bridge.parameterCount else {
            throw SwiftBackendError(
                "LLVM bridge call \(name) expects \(bridge.parameterCount) arguments, got \(arguments.count)."
            )
        }

        let renderedArguments = try arguments.map {
            "Int64(\(try emitExpression($0.value, scope: scope)))"
        }.joined(separator: ", ")
        return "Int(\(bridge.symbolName)(\(renderedArguments)))"
    }

    private func emitKnownCoreStorageInitializer(
        name: String,
        arguments: [CallArgument],
        scope: EmissionScope = .empty
    ) throws -> String? {
        let baseName = name.split(separator: "<", maxSplits: 1).first.map(String.init) ?? name

        func singleArgument(label: String?) -> RangeCompiler.Expression? {
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
            if arguments.isEmpty {
                return "__RangeDateOnly()"
            }
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
            if arguments.isEmpty {
                return "__RangeDateTime()"
            }
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
        _ = scope
        guard let signatures = context.failableInitializersByConstructName[constructName] else {
            return nil
        }

        return matchingFailableInitializer(in: signatures, arguments: arguments)
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
