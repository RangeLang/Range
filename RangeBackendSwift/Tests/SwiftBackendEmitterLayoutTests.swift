import RangeSyntax
import Testing
@testable import RangeBackendSwift

@Suite("Swift backend layout emission")
struct SwiftBackendEmitterLayoutTests {
    @Test("Runtime file system support lowers through POSIX descriptors")
    func runtimeFileSystemSupportLowersThroughPOSIXDescriptors() throws {
        let swift = try SwiftBackendEmitter().emit(
            program: LoweredProgram(
                macrosByName: [:],
                callables: [],
                protocols: [],
                enumerations: [],
                declarations: [],
                extensions: [],
                mainBlock: MainBlockNode(body: []),
                units: []
            )
        )

        #expect(swift.contains("enum Range_POSIXFileSystem"))
        #expect(swift.contains("enum Range_HostFileSystem"))
        #expect(swift.contains("enum Range_UTF8"))
        #expect(!swift.contains("enum Range_FileSystem"))
        #expect(swift.contains("open(path, O_RDONLY)"))
        #expect(swift.contains("open(path, O_WRONLY | O_CREAT | O_TRUNC, 0o644)"))
        #expect(swift.contains("fstat(descriptor, &metadata)"))
        #expect(swift.contains("read(descriptor,"))
        #expect(swift.contains("write(descriptor,"))
        #expect(swift.contains("opendir(path)"))
        #expect(swift.contains("readdir(directory)"))
        #expect(swift.contains("lstat(childPath, &metadata)"))
        #expect(swift.contains("defer { closedir(directory) }"))
        #expect(swift.contains("defer { close(descriptor) }"))
        #expect(swift.contains("return Range_POSIXFileSystem.readData(path: path)"))
        #expect(swift.contains("return Range_POSIXFileSystem.writeData(path: path, data: data)"))
        #expect(swift.contains("return Range_POSIXFileSystem.listEntries(path: path)"))
        #expect(swift.contains("return String(decoding: data.bytes, as: UTF8.self)"))
        #expect(swift.contains("return Data(Array(text.utf8))"))
        #expect(!swift.contains("fopen("))
        #expect(!swift.contains("fread("))
        #expect(!swift.contains("fwrite("))
    }

    @Test("Value construct fields emit in descending layout alignment")
    func valueConstructFieldsEmitInDescendingLayoutAlignment() throws {
        let source = """
        construct Packed {
            let a: Int<8, .unsigned>
            let b: Int<32>
            let c: Int<8, .unsigned>
        }
        """

        var parser = try Parser(source: source)
        let declaration = try parser.parseConstructDeclaration()
        let swift = try SwiftBackendEmitter().emit(
            program: LoweredProgram(
                macrosByName: [:],
                callables: [],
                protocols: [],
                enumerations: [],
                declarations: [declaration],
                extensions: [],
                mainBlock: MainBlockNode(body: []),
                units: []
            )
        )

        let bRange = try #require(swift.range(of: "let b: Int32"))
        let aRange = try #require(swift.range(of: "let a: UInt8"))
        let cRange = try #require(swift.range(of: "let c: UInt8"))
        #expect(bRange.lowerBound < aRange.lowerBound)
        #expect(aRange.lowerBound < cRange.lowerBound)

        #expect(swift.contains("init(a: UInt8, b: Int32, c: UInt8)"))
    }

    @Test("Initializer forwarding emits nested construction")
    func initializerForwardingEmitsNestedConstruction() throws {
        var pointParser = try Parser(source: """
        construct Point {
            let x: Int
            let y: Int
        }
        """)
        let point = try pointParser.parseConstructDeclaration()

        var metadataParser = try Parser(source: "construct Metadata { let title: String }")
        let metadata = try metadataParser.parseConstructDeclaration()

        var wrappedParser = try Parser(source: """
        construct PointWithMetadata {
            #initForwarded
            state point: Point

            let somethingElse: Metadata
        }
        """)
        let wrapped = try wrappedParser.parseConstructDeclaration()

        var macroParser = try Parser(source: """
        open macro initForwarded(): Let | State { target, diagnostics in
            target.initializer.forward()
        }
        """)
        let sourceFile = try macroParser.parseSourceFile()
        guard case .macro(let initForwarded) = sourceFile else {
            Issue.record("Expected initForwarded macro.")
            return
        }

        let swift = try SwiftBackendEmitter().emit(
            program: LoweredProgram(
                macrosByName: ["initForwarded": initForwarded],
                callables: [],
                protocols: [],
                enumerations: [],
                declarations: [point, metadata, wrapped],
                extensions: [],
                mainBlock: MainBlockNode(body: []),
                units: []
            )
        )

        #expect(swift.contains("init(x: Int, y: Int, somethingElse: Range_Metadata)"))
        #expect(swift.contains("self.point = Range_Point(x: x, y: y)"))
    }
}
