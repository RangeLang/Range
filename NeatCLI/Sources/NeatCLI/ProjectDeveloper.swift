import ArgumentParser
import Darwin
import Foundation

struct ProjectRunner {
    private let path: String
    private let port: Int

    init(path: String, port: Int) {
        self.path = path
        self.port = port
    }

    func run() throws {
        let startedAt = Date()
        let root = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
        let packageFile = root.appendingPathComponent("Package.neat", isDirectory: false)
        let appFile = root.appendingPathComponent("App.neat", isDirectory: false)

        guard FileManager.default.fileExists(atPath: packageFile.path) else {
            throw ValidationError("Missing Package.neat in \(root.path)")
        }

        guard FileManager.default.fileExists(atPath: appFile.path) else {
            throw ValidationError("Missing App.neat in \(root.path)")
        }

        let compiler = ProjectCompiler(path: root.path)
        try compiler.run()

        let buildDirectory =
            root
            .appendingPathComponent(".neat", isDirectory: true)
            .appendingPathComponent("Build", isDirectory: true)

        let selectedPort = findAvailablePort(startingAt: port)
        if selectedPort != port {
            TerminalLog.out("Port \(port) is busy, using \(selectedPort) instead.", level: .warning)
        }
        let url = "http://127.0.0.1:\(selectedPort)"
        let startupDuration = formatDuration(since: startedAt)

        Swift.print(
            TerminalLog.style("Started server on ", level: .success)
                + TerminalLog.style(url, level: .success, bold: true)
                + " "
                + TerminalLog.style(startupDuration, level: .success, dimmed: true)
        )
        Swift.print(
            "\u{001B}[90mPress \u{001B}[1mCtrl+C\u{001B}[0m\u{001B}[90m to stop.\u{001B}[0m")

        startWatchThread(root: root)

        let server = LocalHTTPServer(root: buildDirectory, port: selectedPort)
        try server.start()
    }

    private func formatDuration(since startedAt: Date) -> String {
        let elapsedMS = Int((Date().timeIntervalSince(startedAt) * 1000.0).rounded())
        if elapsedMS >= 1000 {
            return String(format: "%.2fs", Double(elapsedMS) / 1000.0)
        }
        return "\(elapsedMS)ms"
    }

    private func findAvailablePort(startingAt preferredPort: Int, maxAttempts: Int = 25) -> Int {
        let lowerBound = max(1, preferredPort)
        for offset in 0..<maxAttempts {
            let candidate = lowerBound + offset
            if canBind(port: candidate) {
                return candidate
            }
        }
        return preferredPort
    }

    private func canBind(port: Int) -> Bool {
        let sock = socket(AF_INET, SOCK_STREAM, 0)
        if sock < 0 {
            return false
        }
        defer { close(sock) }

        var value: Int32 = 1
        _ = setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, &value, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(UInt16(port).bigEndian)
        addr.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        return withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                bind(sock, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
            }
        }
    }

    private func startWatchThread(root: URL) {
        let compiler = ProjectCompiler(path: root.path, showSummary: false)
        Thread.detachNewThread {
            var previous = fileSnapshot(root: root)
            while true {
                Thread.sleep(forTimeInterval: 0.8)
                let current = fileSnapshot(root: root)
                if current != previous {
                    previous = current
                    do {
                        let startedAt = Date()
                        try compiler.run()
                        let elapsed = Date().timeIntervalSince(startedAt)
                        let duration: String
                        if elapsed >= 1.0 {
                            duration = String(format: "%.2fs", elapsed)
                        } else {
                            duration = "\(Int((elapsed * 1000.0).rounded()))ms"
                        }
                        Swift.print(
                            TerminalLog.style("Recompiled due to source changes.", level: .change)
                                + " "
                                + TerminalLog.style(duration, level: .change, dimmed: true)
                        )
                    } catch {
                        ErrorPresenter.printError(error)
                    }
                }
            }
        }
    }

}

private func fileSnapshot(root: URL) -> [String: TimeInterval] {
    let fileManager = FileManager.default
    guard
        let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
            options: []
        )
    else {
        return [:]
    }

    var snapshot: [String: TimeInterval] = [:]

    while let fileURL = enumerator.nextObject() as? URL {
        let path = fileURL.path

        if path.contains("/.build/") || path.contains("/.git/") {
            if (try? fileURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                enumerator.skipDescendants()
            }
            continue
        }

        if path.contains("/.neat/") && !path.contains("/.neat/Core/") {
            if (try? fileURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                enumerator.skipDescendants()
            }
            continue
        }

        guard fileURL.pathExtension == "neat" else { continue }

        let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey])
        let timestamp = values?.contentModificationDate?.timeIntervalSince1970 ?? 0
        snapshot[path] = timestamp
    }

    return snapshot
}

private struct LocalHTTPServer {
    let root: URL
    let port: Int

    func start() throws {
        let serverFD = socket(AF_INET, SOCK_STREAM, 0)
        guard serverFD >= 0 else {
            throw ValidationError("Failed to create server socket.")
        }
        defer { close(serverFD) }

        var yes: Int32 = 1
        _ = setsockopt(
            serverFD, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(UInt16(port).bigEndian)
        addr.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                bind(serverFD, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            throw ValidationError("Failed to bind server port \(port).")
        }

        guard listen(serverFD, 64) == 0 else {
            throw ValidationError("Failed to listen on port \(port).")
        }

        while true {
            var clientAddr = sockaddr()
            var clientLen: socklen_t = socklen_t(MemoryLayout<sockaddr>.size)
            let clientFD = accept(serverFD, &clientAddr, &clientLen)
            if clientFD < 0 {
                continue
            }
            handleClient(clientFD)
            close(clientFD)
        }
    }

    private func handleClient(_ clientFD: Int32) {
        var buffer = [UInt8](repeating: 0, count: 65536)
        let readCount = recv(clientFD, &buffer, buffer.count, 0)
        guard readCount > 0 else { return }

        let request = String(decoding: buffer[0..<Int(readCount)], as: UTF8.self)
        let requestedPath = parsePath(from: request)
        let response = makeResponse(for: requestedPath)
        sendAll(response, to: clientFD)
    }

    private func parsePath(from request: String) -> String {
        guard let firstLine = request.components(separatedBy: "\r\n").first else { return "/" }
        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2 else { return "/" }
        let raw = String(parts[1])
        if let q = raw.firstIndex(of: "?") {
            return String(raw[..<q])
        }
        return raw
    }

    private func makeResponse(for path: String) -> Data {
        let safePath = sanitize(path)
        let directFile = root.appendingPathComponent(safePath, isDirectory: false)
        let wantsSPA = !safePath.contains(".")
        let target: URL?
        if fileExists(directFile) {
            target = directFile
        } else if wantsSPA {
            target = root.appendingPathComponent("index.html", isDirectory: false)
        } else {
            target = nil
        }

        guard let target, let body = try? Data(contentsOf: target) else {
            return rawResponse(
                status: "404 Not Found", contentType: "text/plain; charset=utf-8",
                body: Data("Not found".utf8))
        }

        return rawResponse(
            status: "200 OK",
            contentType: contentType(for: target.pathExtension),
            body: body
        )
    }

    private func sanitize(_ path: String) -> String {
        var clean = path
        if clean.isEmpty || clean == "/" { return "index.html" }
        if clean.hasPrefix("/") { clean.removeFirst() }
        clean = clean.replacingOccurrences(of: "..", with: "")
        return clean.isEmpty ? "index.html" : clean
    }

    private func fileExists(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return false
        }
        return !isDirectory.boolValue
    }

    private func contentType(for ext: String) -> String {
        switch ext.lowercased() {
        case "html":
            return "text/html; charset=utf-8"
        case "js":
            return "application/javascript; charset=utf-8"
        case "css":
            return "text/css; charset=utf-8"
        case "json":
            return "application/json; charset=utf-8"
        case "svg":
            return "image/svg+xml"
        case "png":
            return "image/png"
        case "jpg", "jpeg":
            return "image/jpeg"
        case "ico":
            return "image/x-icon"
        default:
            return "application/octet-stream"
        }
    }

    private func rawResponse(status: String, contentType: String, body: Data) -> Data {
        let headerLines = [
            "HTTP/1.1 \(status)",
            "Content-Type: \(contentType)",
            "Content-Length: \(body.count)",
            "Cache-Control: no-cache",
            "Connection: close",
        ]
        let header = headerLines.joined(separator: "\r\n") + "\r\n\r\n"
        var response = Data(header.utf8)
        response.append(body)
        return response
    }

    private func sendAll(_ data: Data, to socket: Int32) {
        data.withUnsafeBytes { rawBuffer in
            guard var base = rawBuffer.bindMemory(to: UInt8.self).baseAddress else { return }
            var remaining = rawBuffer.count
            while remaining > 0 {
                let sent = send(socket, base, remaining, 0)
                if sent <= 0 {
                    break
                }
                remaining -= sent
                base = base.advanced(by: sent)
            }
        }
    }
}
