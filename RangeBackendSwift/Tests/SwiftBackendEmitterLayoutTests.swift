import RangeSyntax
import Testing
@testable import RangeBackendSwift

@Suite("Swift backend layout emission")
struct SwiftBackendEmitterLayoutTests {
    @Test("Runtime file system support lowers through POSIX descriptors")
    func runtimeFileSystemSupportLowersThroughPOSIXDescriptors() throws {
        let swift = try SwiftBackendEmitter().emit(
            program: LoweredProgram(
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
        #expect(swift.contains("open(path, O_RDONLY)"))
        #expect(swift.contains("fstat(descriptor, &metadata)"))
        #expect(swift.contains("read(descriptor,"))
        #expect(swift.contains("defer { close(descriptor) }"))
        #expect(!swift.contains("fopen("))
        #expect(!swift.contains("fread("))
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
}
