import RangeCompiler
import Testing
@testable import RangeEmission

@Suite("Swift backend layout emission")
struct SwiftBackendEmitterLayoutTests {
    @Test("Runtime support omits old Swift-owned system surfaces")
    func runtimeSupportOmitsOldSwiftOwnedSystemSurfaces() throws {
        let swift = try SwiftBackendEmitter().emit(
            program: LoweredProgram(
                macrosByName: [:],
                callables: [],
                enumerations: [],
                declarations: [],
                extensions: [],
                mainBlock: BlockMacroNode(macros: [], body: []),
                units: []
            )
        )

        #expect(swift.contains("extension String"))
        #expect(swift.contains("struct __RangeLLVMString"))
        #expect(swift.contains("struct __RangeLLVMIntArray"))

        #expect(!swift.contains("enum Range_Result"))
        #expect(!swift.contains("enum Range_Promise"))
        #expect(!swift.contains("struct UUID"))
        #expect(!swift.contains("struct __RangeDateOnly"))
        #expect(!swift.contains("struct __RangeDateTime"))
        #expect(!swift.contains("struct __RangeThrownFailure"))
        #expect(!swift.contains("__rangeUUID"))
        #expect(!swift.contains("__rangeDate"))
        #expect(!swift.contains("enum Range_POSIXMemory"))
        #expect(!swift.contains("enum Range_Memory"))
        #expect(!swift.contains("enum Range_CPU"))
        #expect(!swift.contains("final class Range_ThreadStart"))
        #expect(!swift.contains("enum Range_POSIXThread"))
        #expect(!swift.contains("enum Range_Thread"))
        #expect(!swift.contains("enum Range_POSIXFileSystem"))
        #expect(!swift.contains("enum Range_HostFileSystem"))
        #expect(!swift.contains("enum Range_FileManager"))
        #expect(!swift.contains("enum Range_UTF8"))
        #expect(!swift.contains("enum Range_SHA256"))
        #expect(!swift.contains("final class Range_ChannelStorage"))
        #expect(!swift.contains("enum Range_Logger"))
        #expect(!swift.contains("struct Data"))
    }

    @Test("Old system facade calls are emitted as ordinary unresolved calls")
    func oldSystemFacadeCallsAreEmittedAsOrdinaryUnresolvedCalls() throws {
        let swift = try SwiftBackendEmitter().emit(
            program: LoweredProgram(
                macrosByName: [:],
                callables: [],
                enumerations: [],
                declarations: [],
                extensions: [],
                mainBlock: BlockMacroNode(
                    macros: [],
                    body: [
                        emittedExpression(.call(name: "Thread.yield", arguments: [])),
                        emittedExpression(.call(name: "Memory.pageSize", arguments: [])),
                    ]
                ),
                units: []
            )
        )

        #expect(swift.contains("Range_Thread.yield()"))
        #expect(swift.contains("Range_Memory.pageSize()"))
        #expect(!swift.contains("Range_POSIXThread.yield()"))
        #expect(!swift.contains("Range_POSIXMemory.pageSize()"))
    }

    private func emittedExpression(_ expression: Expression) -> Statement {
        switch expression {
        case .call(let name, let arguments):
            let renderedArguments = arguments.map { argument in
                let value: String
                switch argument.value {
                case .integer(let number):
                    value = "\(number)"
                case .string(let string):
                    value = "\"\(string)\""
                case .identifier(let identifier):
                    value = identifier
                default:
                    value = ""
                }
                if let label = argument.label {
                    return "\(label): \(value)"
                }
                return value
            }
            .joined(separator: ", ")
            return .emitted("statement|kind=expression|value=\(name)(\(renderedArguments))")
        default:
            return .emitted("statement|kind=expression|value=")
        }
    }
}
