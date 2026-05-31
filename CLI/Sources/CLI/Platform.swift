import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

enum Platform {
    static let standardInputFileDescriptor: Int32 = 0
    static let standardOutputFileDescriptor: Int32 = 1
    static let standardErrorFileDescriptor: Int32 = 2

    static var executableExtension: String {
        #if os(Windows)
        return ".exe"
        #else
        return ""
        #endif
    }

    static var defaultExecutableLookupTool: URL? {
        #if os(Windows)
        return nil
        #else
        return URL(fileURLWithPath: "/usr/bin/env")
        #endif
    }

    static func isTerminal(_ fileDescriptor: Int32) -> Bool {
        #if canImport(Darwin) || canImport(Glibc)
        return isatty(fileDescriptor) == 1
        #else
        return false
        #endif
    }

    static func machineArchitecture() -> String {
        #if canImport(Darwin) || canImport(Glibc)
        var systemInfo = utsname()
        uname(&systemInfo)

        return withUnsafePointer(to: &systemInfo.machine) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: 1) { charPointer in
                String(cString: charPointer)
            }
        }
        #elseif os(Windows)
        let environment = ProcessInfo.processInfo.environment
        return environment["PROCESSOR_ARCHITECTURE"]
            ?? environment["PROCESSOR_ARCHITEW6432"]
            ?? "windows"
        #else
        return "unknown"
        #endif
    }

    static func readByte(from fileDescriptor: Int32, into byte: inout UInt8) -> Int {
        #if canImport(Darwin) || canImport(Glibc)
        return DarwinCompat.read(fileDescriptor, &byte, 1)
        #else
        return -1
        #endif
    }
}

#if canImport(Darwin) || canImport(Glibc)
private enum DarwinCompat {
    static func read(_ fileDescriptor: Int32, _ byte: UnsafeMutablePointer<UInt8>, _ count: Int) -> Int {
        #if canImport(Darwin)
        return Darwin.read(fileDescriptor, byte, count)
        #else
        return Glibc.read(fileDescriptor, byte, count)
        #endif
    }
}
#endif
