import Foundation
import NeatSyntax

struct NeatLanguageServer {
    private var documents: [String: DocumentState] = [:]
    private var navigationIndexesByDocumentURI: [String: NavigationIndexCacheEntry] = [:]
    private var navigationIndexGeneration = 0
    private var shutdownRequested = false
    private var shouldExit = false

    mutating func run() throws {
        let input = FileHandle.standardInput

        while let payload = try readMessage(from: input) {
            guard
                let object = try JSONSerialization.jsonObject(with: payload) as? [String: Any]
            else {
                continue
            }

            try handle(message: object)

            if shouldExit {
                break
            }
        }
    }

    private mutating func handle(message: [String: Any]) throws {
        let id = message["id"]
        let method = message["method"] as? String
        debugLog("handle method=\(method ?? "<response>") id=\(jsonScalarDescription(id))")

        switch method {
        case "initialize":
            try sendResponse(
                id: id,
                result: [
                    "capabilities": [
                        "textDocumentSync": 1,
                        "hoverProvider": true,
                        "definitionProvider": true,
                        "renameProvider": true,
                        "documentSymbolProvider": true,
                        "documentFormattingProvider": true,
                        "completionProvider": [
                            "resolveProvider": false,
                            "triggerCharacters": [".", "@", "#"],
                        ],
                        "semanticTokensProvider": [
                            "legend": [
                                "tokenTypes": SemanticTokenType.allCases.map(\.rawValue),
                                "tokenModifiers": SemanticTokenModifier.allCases.map(\.rawValue),
                            ],
                            "range": false,
                            "full": true,
                        ],
                    ],
                    "serverInfo": [
                        "name": "neat-lsp",
                        "version": "0.2.0",
                    ],
                ]
            )
        case "initialized":
            return
        case "shutdown":
            shutdownRequested = true
            try sendResponse(id: id, result: NSNull())
        case "exit":
            shouldExit = true
        case "textDocument/didOpen":
            try storeDocument(from: message)
        case "textDocument/didChange":
            try applyDocumentChange(from: message)
        case "textDocument/didSave":
            try refreshSavedDocument(from: message)
        case "textDocument/didClose":
            closeDocument(from: message)
        case "textDocument/hover":
            let result = hoverResult(for: message)
            try sendResponse(id: id, result: result ?? NSNull())
        case "textDocument/definition":
            let result = definitionResult(for: message)
            try sendResponse(id: id, result: result ?? NSNull())
        case "textDocument/references":
            let result = referencesResult(for: message)
            try sendResponse(id: id, result: result)
        case "textDocument/rename":
            let result = renameResult(for: message)
            try sendResponse(id: id, result: result ?? NSNull())
        case "textDocument/documentSymbol":
            let result = documentSymbolResult(for: message)
            try sendResponse(id: id, result: result)
        case "textDocument/completion":
            let result = completionResult(for: message)
            try sendResponse(id: id, result: result)
        case "textDocument/formatting":
            let result = formattingResult(for: message)
            try sendResponse(id: id, result: result)
        case "textDocument/semanticTokens/full":
            debugLog("semanticTokens/full requested")
            let result = semanticTokensResult(for: message)
            try sendResponse(id: id, result: result)
        default:
            if id != nil {
                try sendResponse(id: id, result: NSNull())
            }
        }
    }

    private mutating func storeDocument(from message: [String: Any]) throws {
        guard
            let params = message["params"] as? [String: Any],
            let textDocument = params["textDocument"] as? [String: Any],
            let uri = textDocument["uri"] as? String,
            let text = textDocument["text"] as? String
        else {
            return
        }

        try updateDocument(uri: uri, text: text, diagnosticsMode: .validated)
    }

    private mutating func applyDocumentChange(from message: [String: Any]) throws {
        guard
            let params = message["params"] as? [String: Any],
            let textDocument = params["textDocument"] as? [String: Any],
            let uri = textDocument["uri"] as? String,
            let contentChanges = params["contentChanges"] as? [[String: Any]],
            let latest = contentChanges.last?["text"] as? String
        else {
            return
        }

        try updateDocument(uri: uri, text: latest, diagnosticsMode: .validated)
    }

    private mutating func refreshSavedDocument(from message: [String: Any]) throws {
        guard
            let params = message["params"] as? [String: Any],
            let textDocument = params["textDocument"] as? [String: Any],
            let uri = textDocument["uri"] as? String,
            let existingState = documents[uri]
        else {
            return
        }

        let state = buildDocumentState(
            uri: uri,
            text: existingState.text,
            diagnosticsMode: .validated
        )
        documents[uri] = state
        rebuildNavigationIndex(for: uri, text: state.text)
        try publishDiagnostics(for: uri, diagnostics: state.diagnostics)
    }

    private mutating func closeDocument(from message: [String: Any]) {
        guard
            let params = message["params"] as? [String: Any],
            let textDocument = params["textDocument"] as? [String: Any],
            let uri = textDocument["uri"] as? String
        else {
            return
        }

        documents.removeValue(forKey: uri)
        invalidateNavigationIndexes()
        navigationIndexesByDocumentURI.removeValue(forKey: uri)
    }

    private mutating func updateDocument(
        uri: String,
        text: String,
        diagnosticsMode: DiagnosticMode
    ) throws {
        let state = buildDocumentState(uri: uri, text: text, diagnosticsMode: diagnosticsMode)
        documents[uri] = state
        rebuildNavigationIndex(for: uri, text: state.text)
        try publishDiagnostics(for: uri, diagnostics: state.diagnostics)
    }

    private func hoverResult(for message: [String: Any]) -> [String: Any]? {
        guard
            let request = requestContext(from: message),
            let symbol = request.state.symbol(at: request.position)
        else {
            return nil
        }

        let description = hoverDescription(for: symbol)
        return [
            "contents": [
                "kind": "markdown",
                "value": "**\(symbol.name)**\n\n\(description)",
            ],
            "range": symbol.range.json,
        ]
    }

    private mutating func definitionResult(for message: [String: Any]) -> [String: Any]? {
        guard
            let request = requestContext(from: message),
            let definition = graphDefinition(
                for: request.state,
                position: request.position
            )
        else {
            return nil
        }

        return location(uri: definition.uri, range: definition.range)
    }

    private func referencesResult(for message: [String: Any]) -> [[String: Any]] {
        guard
            let request = requestContext(from: message),
            let word = request.state.word(at: request.position),
            !word.isEmpty
        else {
            return []
        }

        return documents.values
            .flatMap { state in
                state.references(named: word).map { location(uri: state.uri, range: $0.range) }
            }
    }

    private func renameResult(for message: [String: Any]) -> [String: Any]? {
        guard
            let request = requestContext(from: message),
            let params = message["params"] as? [String: Any],
            let newName = params["newName"] as? String,
            let word = request.state.word(at: request.position),
            !word.isEmpty,
            isIdentifier(newName)
        else {
            return nil
        }

        var changes: [String: [[String: Any]]] = [:]
        for state in documents.values {
            let edits = state.references(named: word).map { reference in
                [
                    "range": reference.range.json,
                    "newText": newName,
                ]
            }

            if !edits.isEmpty {
                changes[state.uri] = edits
            }
        }

        return ["changes": changes]
    }

    private func documentSymbolResult(for message: [String: Any]) -> [[String: Any]] {
        guard let request = requestContext(from: message) else {
            return []
        }

        return request.state.symbols.map { symbol in
            [
                "name": symbol.name,
                "kind": symbol.kind.lspKind,
                "range": symbol.range.json,
                "selectionRange": symbol.selectionRange.json,
                "detail": symbol.detail,
            ]
        }
    }

    private func completionResult(for message: [String: Any]) -> [String: Any] {
        guard let request = requestContext(from: message) else {
            return ["isIncomplete": false, "items": []]
        }

        let word = request.state.wordPrefix(at: request.position)
        let previousCharacter = request.state.character(before: request.position)

        let items: [[String: Any]]
        if previousCharacter == "." {
            items = modifierCompletions()
        } else if previousCharacter == "@" {
            items = attributeCompletions()
        } else if previousCharacter == "#" {
            items = macroCompletions()
        } else {
            items =
                keywordCompletions()
                + request.state.symbols.map { symbol in
                    completionItem(
                        label: symbol.name,
                        kind: symbol.kind.completionKind,
                        detail: symbol.detail
                    )
                }
        }

        let filtered =
            word.isEmpty
            ? items
            : items.filter { ($0["label"] as? String)?.hasPrefix(word) == true }

        return [
            "isIncomplete": false,
            "items": uniqueCompletionItems(filtered),
        ]
    }

    private func formattingResult(for message: [String: Any]) -> [[String: Any]] {
        guard let request = requestContext(from: message) else {
            return []
        }

        let formatted = Self.formatDocument(request.state.text)
        guard formatted != request.state.text else {
            return []
        }

        return [
            [
                "range": request.state.fullDocumentRange.json,
                "newText": formatted,
            ]
        ]
    }

    private func semanticTokensResult(for message: [String: Any]) -> [String: Any] {
        guard let state = documentState(from: message) else {
            debugLog("semanticTokens/full -> no document state")
            return ["data": []]
        }

        debugLog("semanticTokens/full -> \(state.semanticTokens.count / 5) tokens")
        return ["data": state.semanticTokens]
    }

    private func hoverDescription(for symbol: Symbol) -> String {
        switch symbol.kind {
        case .attribute:
            return "Neat callable sigil"
        case .macro:
            return "Neat macro"
        case .declaration:
            return "Neat declaration"
        case .callable:
            return "Neat callable"
        case .variable:
            return "Neat variable"
        case .state:
            return "Neat state property"
        case .styleModifier:
            return "Neat style modifier"
        case .typeExtension:
            return "Neat type extension"
        case .view:
            return "Neat built-in view"
        case .modifier:
            return "Neat modifier"
        case .keyword:
            return "Neat language keyword"
        }
    }

    private func buildDocumentState(
        uri: String,
        text: String,
        diagnosticsMode: DiagnosticMode
    ) -> DocumentState {
        let index = DocumentIndex(text: text, uri: uri)
        let diagnostics: [[String: Any]]
        switch diagnosticsMode {
        case .none:
            diagnostics = []
        case .validated:
            diagnostics = diagnosticPayload(for: uri, text: text, index: index)
        }
        return DocumentState(uri: uri, text: text, index: index, diagnostics: diagnostics)
    }

    private func publishDiagnostics(for uri: String, diagnostics: [[String: Any]]) throws {
        try sendNotification(
            method: "textDocument/publishDiagnostics",
            params: [
                "uri": uri,
                "diagnostics": diagnostics,
            ]
        )
    }

    private func diagnosticPayload(for uri: String, text: String, index: DocumentIndex) -> [[String: Any]] {
        let inputs: [SourceInput]
        do {
            inputs = try diagnosticInputs(for: uri, text: text)
        } catch {
            return [
                lspDiagnostic(
                    from: NeatDiagnosticConverter.diagnostic(from: error),
                    index: index
                )
            ]
        }

        return CompilerPipeline()
            .diagnostics(inputs: inputs, fallbackPath: documentPath(for: uri))
            .filter { diagnosticAppliesToDocument($0, uri: uri) }
            .map { lspDiagnostic(from: $0, index: index) }
    }

    private func documentPath(for uri: String) -> String? {
        guard let fileURL = URL(string: uri),
            fileURL.isFileURL
        else {
            return nil
        }
        return fileURL.standardizedFileURL.path
    }

    private func diagnosticAppliesToDocument(_ diagnostic: NeatDiagnostic, uri: String) -> Bool {
        guard let path = diagnostic.path,
            let fileURL = URL(string: uri),
            fileURL.isFileURL
        else {
            return true
        }
        return URL(fileURLWithPath: path).standardizedFileURL.path
            == fileURL.standardizedFileURL.path
    }

    private func lspDiagnostic(
        from diagnostic: NeatDiagnostic,
        index: DocumentIndex
    ) -> [String: Any] {
        let range = lspRange(for: diagnostic, fallback: index.firstNonWhitespaceRange ?? index.fullDocumentRange)
        var payload: [String: Any] = [
            "range": range.json,
            "severity": lspSeverity(for: diagnostic.severity),
            "source": diagnostic.source,
            "message": diagnostic.message,
        ]
        if let code = diagnostic.code {
            payload["code"] = code
        }
        return payload
    }

    private func lspRange(for diagnostic: NeatDiagnostic, fallback: RangePosition) -> RangePosition {
        guard let range = diagnostic.range else {
            return fallback
        }
        return RangePosition(
            start: Position(line: range.start.line, character: range.start.character),
            end: Position(line: range.end.line, character: range.end.character)
        )
    }

    private func lspSeverity(for severity: NeatDiagnosticSeverity) -> Int {
        switch severity {
        case .error:
            return 1
        case .warning:
            return 2
        case .information:
            return 3
        case .hint:
            return 4
        }
    }

    private mutating func graphDefinition(for state: DocumentState, position: Position) -> DefinitionLocation? {
        guard let word = state.word(at: position), !word.isEmpty else {
            return nil
        }
        if state.isArgumentLabel(at: position) {
            return nil
        }

        let occurrence = state.semanticTokenOccurrence(at: position)
        guard let navigationIndex = navigationIndex(for: state) else {
            return nil
        }
        return navigationIndex.definition(named: word, occurrence: occurrence)
    }

    private mutating func navigationIndex(for state: DocumentState) -> ProjectNavigationIndex? {
        if let entry = navigationIndexesByDocumentURI[state.uri],
            entry.generation == navigationIndexGeneration
        {
            return entry.index
        }

        rebuildNavigationIndex(for: state.uri, text: state.text, invalidating: false)
        return navigationIndexesByDocumentURI[state.uri]?.index
    }

    private mutating func invalidateNavigationIndexes() {
        navigationIndexGeneration += 1
    }

    private mutating func rebuildNavigationIndex(
        for uri: String,
        text: String,
        invalidating: Bool = true
    ) {
        if invalidating {
            invalidateNavigationIndexes()
        }
        do {
            let inputs = try diagnosticInputs(for: uri, text: text)
            navigationIndexesByDocumentURI[uri] = NavigationIndexCacheEntry(
                generation: navigationIndexGeneration,
                index: try ProjectNavigationIndex(inputs: inputs)
            )
        } catch {
            navigationIndexesByDocumentURI.removeValue(forKey: uri)
            debugLog("navigation index failed for \(uri): \(ErrorDescription.message(for: error))")
        }
    }

    private func diagnosticInputs(for uri: String, text: String) throws -> [SourceInput] {
        guard
            let fileURL = URL(string: uri),
            fileURL.isFileURL
        else {
            return uniqueSourceInputs(try NeatCoreLoader.sourceInputs() + [
                SourceInput(path: uri, source: text, role: .project)
            ])
        }

        let standardizedFileURL = fileURL.standardizedFileURL
        let openedFileRole: SourceInputRole =
            (try? NeatCoreLoader.isCoreFile(standardizedFileURL)) == true ? .core : .project
        let loadedProject: LoadedProject
        do {
            loadedProject = try ProjectLoader.load(at: standardizedFileURL.path)
        } catch {
            return uniqueSourceInputs(try NeatCoreLoader.sourceInputs() + [
                SourceInput(path: standardizedFileURL.path, source: text, role: openedFileRole)
            ])
        }

        let openDocumentSources = Dictionary(
            uniqueKeysWithValues: documents.compactMap { uri, state -> (String, String)? in
                guard let url = URL(string: uri), url.isFileURL else { return nil }
                return (url.standardizedFileURL.path, state.text)
            }
        )

        return uniqueSourceInputs(loadedProject.sourceInputs.map { input in
            if input.path == standardizedFileURL.path {
                return SourceInput(path: input.path, source: text, role: input.role)
            }
            if let override = openDocumentSources[input.path] {
                return SourceInput(path: input.path, source: override, role: input.role)
            }
            return input
        })
    }

    private func uniqueSourceInputs(_ inputs: [SourceInput]) -> [SourceInput] {
        var seen: Set<String> = []
        var unique: [SourceInput] = []

        for input in inputs.reversed() {
            guard seen.insert(input.path).inserted else {
                continue
            }
            unique.append(input)
        }

        return unique.reversed()
    }

    private func requestContext(from message: [String: Any]) -> RequestContext? {
        guard
            let params = message["params"] as? [String: Any],
            let textDocument = params["textDocument"] as? [String: Any],
            let uri = textDocument["uri"] as? String,
            let positionJSON = params["position"] as? [String: Any],
            let line = positionJSON["line"] as? Int,
            let character = positionJSON["character"] as? Int,
            let state = documents[uri]
        else {
            return nil
        }

        return RequestContext(state: state, position: Position(line: line, character: character))
    }

    private func documentState(from message: [String: Any]) -> DocumentState? {
        guard
            let params = message["params"] as? [String: Any],
            let textDocument = params["textDocument"] as? [String: Any],
            let uri = textDocument["uri"] as? String
        else {
            return nil
        }

        return documents[uri]
    }

    private func location(uri: String, range: RangePosition) -> [String: Any] {
        [
            "uri": uri,
            "range": range.json,
        ]
    }

    private func keywordCompletions() -> [[String: Any]] {
        [
            "case", "construct", "derived", "enum", "environment", "extension", "macro",
            "namespace", "protocol", "state", "switch", "let",
        ].map { completionItem(label: $0, kind: 14, detail: "keyword") }
    }

    private func attributeCompletions() -> [[String: Any]] {
        let builtinAttributes = [
            "#main", "@background", "@language", "@syntax", "@package",
        ].map { completionItem(label: $0, kind: 14, detail: "attribute") }
        let namespaceAttributes = documents.values
            .flatMap(\.symbols)
            .filter { $0.kind == .declaration && $0.detail == "namespace" }
            .map { completionItem(label: "@\($0.name)", kind: 14, detail: "namespace attribute") }

        return uniqueCompletionItems(builtinAttributes + namespaceAttributes)
    }

    private func macroCompletions() -> [[String: Any]] {
        uniqueCompletionItems(
            documents.values
                .flatMap(\.symbols)
                .filter { $0.kind == .macro }
                .map { symbol in
                    completionItem(label: "@\(symbol.name)", kind: symbol.kind.completionKind, detail: symbol.detail)
                }
        )
    }

    private func modifierCompletions() -> [[String: Any]] {
        [
            "backgroundColor", "buttonStyle", "cornerRadius", "fontFamily", "fontSize",
            "fontWeight", "foregroundColor", "frame", "italic", "lineHeight", "offset",
            "opacity", "padding", "shadow", "textFieldStyle", "zIndex",
        ].map { completionItem(label: $0, kind: 2, detail: "modifier") }
    }

    private func completionItem(label: String, kind: Int, detail: String) -> [String: Any] {
        [
            "label": label,
            "kind": kind,
            "detail": detail,
        ]
    }

    private func uniqueCompletionItems(_ items: [[String: Any]]) -> [[String: Any]] {
        var seen: Set<String> = []
        var result: [[String: Any]] = []
        for item in items {
            guard let label = item["label"] as? String, !seen.contains(label) else {
                continue
            }
            seen.insert(label)
            result.append(item)
        }
        return result.sorted { ($0["label"] as? String ?? "") < ($1["label"] as? String ?? "") }
    }

    private static func formatDocument(_ text: String) -> String {
        let lines = text.components(separatedBy: .newlines)
        var depth = 0
        var formatted: [String] = []
        formatted.reserveCapacity(lines.count)

        for rawLine in lines {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                formatted.append("")
                continue
            }

            if trimmed.hasPrefix("}") || trimmed.hasPrefix(")") || trimmed.hasPrefix("]") {
                depth = max(0, depth - 1)
            }

            formatted.append(String(repeating: "  ", count: depth) + trimmed)

            let delimiterBalance = formattingDelimiterBalance(in: trimmed)
            let opens = delimiterBalance.opens
            let closes = delimiterBalance.closes
            depth = max(0, depth + opens - closes)
        }

        return formatted.joined(separator: "\n")
    }

    private static func formattingDelimiterBalance(in line: String) -> (opens: Int, closes: Int) {
        var opens = 0
        var closes = 0
        var inString = false
        var escaped = false
        var index = line.startIndex

        while index < line.endIndex {
            let character = line[index]
            let next = line.index(after: index)

            if !inString,
                character == "/",
                next < line.endIndex,
                line[next] == "/"
            {
                break
            }

            if inString {
                if escaped {
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == "\"" {
                    inString = false
                }
                index = next
                continue
            }

            if character == "\"" {
                inString = true
            } else if "({[".contains(character) {
                opens += 1
            } else if ")}]".contains(character) {
                closes += 1
            }

            index = next
        }

        return (opens, closes)
    }

    private func isIdentifier(_ value: String) -> Bool {
        guard let first = value.first, first.isLetter || first == "_" else {
            return false
        }
        return value.dropFirst().allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
    }

    private func readMessage(from handle: FileHandle) throws -> Data? {
        var headers: [String: String] = [:]

        while true {
            guard let line = try readLine(from: handle) else {
                return nil
            }

            if line.isEmpty {
                break
            }

            let parts = line.split(separator: ":", maxSplits: 1).map(String.init)
            if parts.count == 2 {
                headers[parts[0].lowercased()] = parts[1].trimmingCharacters(in: .whitespaces)
            }
        }

        guard let contentLengthValue = headers["content-length"],
            let contentLength = Int(contentLengthValue)
        else {
            return nil
        }

        return try readBytes(count: contentLength, from: handle)
    }

    private func readLine(from handle: FileHandle) throws -> String? {
        var buffer = Data()

        while true {
            let chunk = handle.readData(ofLength: 1)
            if chunk.isEmpty {
                return buffer.isEmpty ? nil : String(data: buffer, encoding: .utf8)
            }

            buffer.append(chunk)

            if buffer.count >= 2, buffer.suffix(2) == Data([13, 10]) {
                buffer.removeLast(2)
                return String(data: buffer, encoding: .utf8) ?? ""
            }
        }
    }

    private func readBytes(count: Int, from handle: FileHandle) throws -> Data {
        var data = Data()

        while data.count < count {
            let chunk = handle.readData(ofLength: count - data.count)
            if chunk.isEmpty { break }
            data.append(chunk)
        }

        return data
    }

    private func sendResponse(id: Any?, result: Any) throws {
        var response: [String: Any] = [
            "jsonrpc": "2.0",
            "result": result,
        ]

        if let id {
            response["id"] = id
        }

        try send(message: response)
    }

    private func sendNotification(method: String, params: [String: Any]) throws {
        try send(message: [
            "jsonrpc": "2.0",
            "method": method,
            "params": params,
        ])
    }

    private func send(message: [String: Any]) throws {
        debugLog(outboundSummary(for: message))
        let payload = try JSONSerialization.data(withJSONObject: message)
        let header = "Content-Length: \(payload.count)\r\n\r\n"
        let output = FileHandle.standardOutput
        if let headerData = header.data(using: .utf8) {
            output.write(headerData)
        }
        output.write(payload)
    }

    private func debugLog(_ message: String) {
        let path = "/tmp/neat-lsp-debug.log"
        let line = "[\(ISO8601DateFormatter().string(from: Date()))] \(message)\n"
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: path) {
                if let handle = FileHandle(forWritingAtPath: path) {
                    _ = try? handle.seekToEnd()
                    _ = try? handle.write(contentsOf: data)
                    _ = try? handle.close()
                }
            } else {
                FileManager.default.createFile(atPath: path, contents: data)
            }
        }
    }

    private func outboundSummary(for message: [String: Any]) -> String {
        if let method = message["method"] as? String {
            let paramsDescription: String
            switch message["params"] {
            case nil:
                paramsDescription = "none"
            case is NSNull:
                paramsDescription = "null"
            case let dictionary as [String: Any]:
                paramsDescription = "object keys=\(dictionary.keys.sorted())"
            case let array as [Any]:
                paramsDescription = "array count=\(array.count)"
            default:
                paramsDescription = "scalar"
            }

            return "send notification method=\(method) params=\(paramsDescription)"
        }

        let idDescription = jsonScalarDescription(message["id"])
        let resultDescription: String
        switch message["result"] {
        case nil:
            resultDescription = "none"
        case is NSNull:
            resultDescription = "null"
        case let dictionary as [String: Any]:
            resultDescription = "object keys=\(dictionary.keys.sorted())"
        case let array as [Any]:
            resultDescription = "array count=\(array.count)"
        default:
            resultDescription = "scalar"
        }

        return "send response id=\(idDescription) result=\(resultDescription)"
    }

    private func jsonScalarDescription(_ value: Any?) -> String {
        switch value {
        case nil:
            return "nil"
        case is NSNull:
            return "null"
        case let string as String:
            return string
        case let int as Int:
            return "\(int)"
        case let double as Double:
            return "\(double)"
        case let bool as Bool:
            return bool ? "true" : "false"
        default:
            return "value"
        }
    }
}

private struct RequestContext {
    let state: DocumentState
    let position: Position
}

private enum DiagnosticMode {
    case none
    case validated
}

private struct DocumentState {
    let uri: String
    let text: String
    let index: DocumentIndex
    let diagnostics: [[String: Any]]

    var symbols: [Symbol] { index.symbols }
    var fullDocumentRange: RangePosition { index.fullDocumentRange }
    var semanticTokens: [Int] { index.semanticTokens }

    func symbol(at position: Position) -> Symbol? {
        index.symbol(at: position)
    }

    func word(at position: Position) -> String? {
        index.word(at: position)
    }

    func wordPrefix(at position: Position) -> String {
        index.wordPrefix(at: position)
    }

    func character(before position: Position) -> Character? {
        index.character(before: position)
    }

    func isArgumentLabel(at position: Position) -> Bool {
        index.isArgumentLabel(at: position)
    }

    func semanticTokenOccurrence(at position: Position) -> SemanticTokenOccurrence? {
        index.semanticTokenOccurrence(at: position)
    }

    func references(named name: String) -> [ReferenceOccurrence] {
        index.references(named: name)
    }
}

private struct ParameterDeclaration {
    let externalName: String?
    let externalRange: NSRange?
    let name: String
    let range: NSRange
}

private struct DocumentIndex {
    let text: String
    let uri: String
    let lines: [String]
    let symbols: [Symbol]
    let referencesByName: [String: [ReferenceOccurrence]]
    let semanticTokens: [Int]
    let semanticTokenOccurrences: [SemanticTokenOccurrence]
    let fullDocumentRange: RangePosition
    let firstNonWhitespaceRange: RangePosition?

    init(text: String, uri: String) {
        self.text = text
        self.uri = uri
        self.lines = text.components(separatedBy: .newlines)
        self.symbols = DocumentIndex.collectSymbols(in: lines, uri: uri)
        self.referencesByName = DocumentIndex.collectReferences(in: lines)
        self.semanticTokenOccurrences = DocumentIndex.collectSemanticTokenOccurrences(in: lines)
        self.semanticTokens = DocumentIndex.encodeSemanticTokens(semanticTokenOccurrences)
        let lastLine = max(0, lines.count - 1)
        let lastChar = lines.last?.count ?? 0
        self.fullDocumentRange = RangePosition(
            start: Position(line: 0, character: 0),
            end: Position(line: lastLine, character: lastChar)
        )
        self.firstNonWhitespaceRange = DocumentIndex.firstNonWhitespaceRange(in: lines)
    }

    func symbol(at position: Position) -> Symbol? {
        let word = word(at: position)
        return symbols.first(where: { $0.name == word })
    }

    func word(at position: Position) -> String? {
        wordRange(at: position).map { range in
            let nsLine = lines[position.line] as NSString
            return nsLine.substring(
                with: NSRange(
                    location: range.start.character,
                    length: range.end.character - range.start.character
                )
            )
        }
    }

    func wordPrefix(at position: Position) -> String {
        guard lines.indices.contains(position.line) else { return "" }
        let target = Array(lines[position.line])
        guard !target.isEmpty else { return "" }

        let anchor = max(0, min(position.character, target.count))
        var start = anchor
        while start > 0, isWordCharacter(target[start - 1]) {
            start -= 1
        }
        return String(target[start..<anchor])
    }

    func character(before position: Position) -> Character? {
        guard lines.indices.contains(position.line), position.character > 0 else {
            return nil
        }
        let target = Array(lines[position.line])
        guard target.indices.contains(position.character - 1) else { return nil }
        return target[position.character - 1]
    }

    func references(named name: String) -> [ReferenceOccurrence] {
        referencesByName[name] ?? []
    }

    func isArgumentLabel(at position: Position) -> Bool {
        guard let range = wordRange(at: position), lines.indices.contains(position.line) else {
            return false
        }
        let line = lines[position.line]
        let nsLine = line as NSString
        var cursor = range.end.character
        while cursor < nsLine.length {
            let character = nsLine.substring(with: NSRange(location: cursor, length: 1))
            guard character.rangeOfCharacter(from: .whitespacesAndNewlines) != nil else {
                break
            }
            cursor += 1
        }
        guard cursor < nsLine.length,
            nsLine.substring(with: NSRange(location: cursor, length: 1)) == ":"
        else {
            return false
        }
        return Self.argumentLabelTokenKind(
            in: lines,
            lineIndex: position.line,
            labelStart: range.start.character
        ) != nil
    }

    func semanticTokenOccurrence(at position: Position) -> SemanticTokenOccurrence? {
        semanticTokenOccurrences.first { occurrence in
            occurrence.line == position.line
                && position.character >= occurrence.startCharacter
                && position.character <= occurrence.startCharacter + occurrence.length
        }
    }

    private func wordRange(at position: Position) -> RangePosition? {
        guard lines.indices.contains(position.line) else { return nil }
        let target = Array(lines[position.line])
        guard !target.isEmpty else { return nil }

        let clamped = max(0, min(position.character, target.count - 1))
        if isWordCharacter(target[clamped]) {
            return sliceWordRange(in: target, line: position.line, around: clamped)
        }
        if clamped > 0, isWordCharacter(target[clamped - 1]) {
            return sliceWordRange(in: target, line: position.line, around: clamped - 1)
        }
        return nil
    }

    private func sliceWord(in target: [Character], around index: Int) -> String {
        let range = sliceWordBounds(in: target, around: index)
        return String(target[range.start..<range.end])
    }

    private func sliceWordRange(in target: [Character], line: Int, around index: Int)
        -> RangePosition
    {
        let range = sliceWordBounds(in: target, around: index)
        return RangePosition(
            start: Position(line: line, character: range.start),
            end: Position(line: line, character: range.end)
        )
    }

    private func sliceWordBounds(in target: [Character], around index: Int) -> (start: Int, end: Int) {
        var start = index
        var end = index

        while start > 0, isWordCharacter(target[start - 1]) {
            start -= 1
        }
        while end < target.count, isWordCharacter(target[end]) {
            end += 1
        }

        return (start, end)
    }

    private func isWordCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "_" || character == "@"
    }

    private static func collectSymbols(in lines: [String], uri: String) -> [Symbol] {
        var symbols: [Symbol] = []

        for (lineIndex, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            if let match = firstMatch(
                in: line,
                pattern: #"#([A-Za-z_][A-Za-z0-9_]*)(?:\s*:\s*([A-Za-z_][A-Za-z0-9_.]*))?\s*\{"#
            ) {
                let name = match[1]
                let declarationName = "#" + name
                let symbolRange = range(in: line, line: lineIndex, value: declarationName)
                symbols.append(
                    Symbol(
                        name: name, kind: .declaration, detail: "declaration", uri: uri,
                        range: symbolRange, selectionRange: symbolRange))
                continue
            }

            if let match = firstMatch(
                in: line,
                pattern: #"\bmacro\s+([a-z_][A-Za-z0-9_]*)\s*\("#
            ) {
                let name = match[1]
                let symbolRange = range(in: line, line: lineIndex, value: name)
                symbols.append(
                    Symbol(
                        name: name,
                        kind: .macro,
                        detail: "macro",
                        uri: uri,
                        range: symbolRange,
                        selectionRange: symbolRange
                    )
                )
                continue
            }

            if let match = firstMatch(in: line, pattern: #"\bnamespace\s+([A-Z][A-Za-z0-9_]*)\s*\{"#) {
                let name = match[1]
                let symbolRange = range(in: line, line: lineIndex, value: name)
                symbols.append(
                    Symbol(
                        name: name,
                        kind: .declaration,
                        detail: "namespace",
                        uri: uri,
                        range: symbolRange,
                        selectionRange: symbolRange
                    )
                )
                continue
            }

            if let match = firstMatch(
                in: line,
                pattern: #"\blet\s+([a-z_][A-Za-z0-9_]*)\s*:\s*([A-Z][A-Za-z0-9_.]*)\s*\{"#
            ) {
                let name = match[1]
                let symbolRange = range(in: line, line: lineIndex, value: name)
                symbols.append(
                    Symbol(
                        name: name, kind: .variable, detail: match[2], uri: uri,
                        range: symbolRange, selectionRange: symbolRange))
                continue
            }

            if let match = firstMatch(
                in: line,
                pattern: #"\bderived\s+([a-z_][A-Za-z0-9_]*)\s*:\s*([A-Z][A-Za-z0-9_.]*)"#
            ) {
                let name = match[1]
                let symbolRange = range(in: line, line: lineIndex, value: name)
                symbols.append(
                    Symbol(
                        name: name, kind: .variable, detail: "derived \(match[2])", uri: uri,
                        range: symbolRange, selectionRange: symbolRange))
                continue
            }

            if let match = firstMatch(in: line, pattern: #"\bextension\s+([A-Z][A-Za-z0-9_]*)"#) {
                let name = match[1]
                let symbolRange = range(in: line, line: lineIndex, value: name)
                symbols.append(
                    Symbol(
                        name: name, kind: .typeExtension, detail: "extension", uri: uri,
                        range: symbolRange, selectionRange: symbolRange))
                continue
            }

            if let match = firstMatch(in: line, pattern: #"@([a-z_][A-Za-z0-9_]*)\s*\("#) {
                let symbolName = "@" + match[1]
                let symbolRange = range(in: line, line: lineIndex, value: symbolName)
                symbols.append(
                    Symbol(
                        name: symbolName, kind: .callable, detail: "callable", uri: uri,
                        range: symbolRange, selectionRange: symbolRange))
                continue
            }

            if let match = firstMatch(
                in: line, pattern: #"\b(environment\s+state|state)\s+([a-z_][A-Za-z0-9_]*)"#)
            {
                let name = match[2]
                let symbolRange = range(in: line, line: lineIndex, value: name)
                symbols.append(
                    Symbol(
                        name: name, kind: .state, detail: match[1], uri: uri, range: symbolRange,
                        selectionRange: symbolRange))
                continue
            }

            if let match = firstMatch(
                in: line, pattern: #"\b(let|environment|derived)\s+([a-z_][A-Za-z0-9_]*)"#)
            {
                let name = match[2]
                let symbolRange = range(in: line, line: lineIndex, value: name)
                symbols.append(
                    Symbol(
                        name: name, kind: .variable, detail: match[1], uri: uri, range: symbolRange,
                        selectionRange: symbolRange))
                continue
            }

        }

        return symbols
    }

    private static func collectReferences(in lines: [String]) -> [String: [ReferenceOccurrence]] {
        var result: [String: [ReferenceOccurrence]] = [:]
        let pattern = #"@?[A-Za-z_][A-Za-z0-9_]*"#

        for (lineIndex, line) in lines.enumerated() {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let nsLine = line as NSString
            let matches = regex.matches(
                in: line, range: NSRange(location: 0, length: nsLine.length))
            for match in matches {
                let word = nsLine.substring(with: match.range)
                let range = RangePosition(
                    start: Position(line: lineIndex, character: match.range.location),
                    end: Position(
                        line: lineIndex, character: match.range.location + match.range.length)
                )
                result[word, default: []].append(ReferenceOccurrence(name: word, range: range))
            }
        }

        return result
    }

    fileprivate static func collectSemanticTokenOccurrences(in lines: [String]) -> [SemanticTokenOccurrence] {
        var seen: Set<SemanticTokenOccurrence> = []
        var tokens: [SemanticTokenOccurrence] = []
        var stringLiteralRangesByLine: [Int: [NSRange]] = [:]

        func overlapsStringLiteral(line: Int, start: Int, length: Int) -> Bool {
            let end = start + length
            return stringLiteralRangesByLine[line, default: []].contains { range in
                let rangeEnd = range.location + range.length
                return start < rangeEnd && range.location < end
            }
        }

        func record(_ token: SemanticTokenOccurrence) {
            guard seen.insert(token).inserted else { return }
            tokens.append(token)
        }

        func record(
            line: Int,
            range: NSRange,
            type: SemanticTokenType,
            modifiers: Set<SemanticTokenModifier> = []
        ) {
            guard range.location != NSNotFound, range.length > 0 else { return }
            if type != .string && type != .comment,
                overlapsStringLiteral(line: line, start: range.location, length: range.length)
            {
                return
            }
            record(
                SemanticTokenOccurrence(
                    line: line,
                    startCharacter: range.location,
                    length: range.length,
                    type: type,
                    modifiers: modifiers
                )
            )
        }

        func overlapsExisting(line: Int, start: Int, length: Int) -> Bool {
            let end = start + length
            return tokens.contains { token in
                guard token.line == line else { return false }
                let tokenEnd = token.startCharacter + token.length
                return start < tokenEnd && token.startCharacter < end
            }
        }

        let declarationPatterns: [String] = [
            #"\bconstruct\s+([A-Z][A-Za-z0-9_]*)"#,
            #"\bnamespace\s+([A-Z][A-Za-z0-9_]*)"#,
            #"\bprotocol\s+([A-Z][A-Za-z0-9_]*)"#,
            #"\benum\s+([A-Z][A-Za-z0-9_]*)"#,
            #"\*builder\s+([A-Z][A-Za-z0-9_]*)"#,
            #"\bprecedencegroup\s+([A-Z][A-Za-z0-9_]*)"#,
        ]

        let typePattern = #"\b[A-Z][A-Za-z0-9_]*\b"#
        let functionDeclarationPattern =
            #"\bfunction\s+([a-z_][A-Za-z0-9_]*|[!%&*+\-./<=>?^|~]+)(?:<[^>\n]+>)?\s*\("#
        let macroDeclarationPattern =
            #"\bmacro\s+([a-z_][A-Za-z0-9_]*)(?:<[^>\n]+>)?\s*\("#
        let markerDeclarationPattern =
            #"\bmarker\s+([a-z_][A-Za-z0-9_]*)(?:<[^>\n]+>)?\s*\("#
        let localCallPattern = #"\b([a-z_][A-Za-z0-9_]*)\s*\("#
        let memberPattern = #"(?:\b[A-Za-z_][A-Za-z0-9_]*|\])\.([a-z_][A-Za-z0-9_]*)\b"#
        let macroTokenPattern = #"([@#][a-z_][A-Za-z0-9_]*)\b"#
        let metadataTokenPattern = #"(#namespace|#main)\b"#
        let attributeKeywordPattern = #"@(background|defer|language|syntax|package|[A-Z][A-Za-z0-9_]*)\b"#
        let enumCaseDeclarationPattern = #"^\s*case\s+([a-z_][A-Za-z0-9_]*)\b"#
        let argumentValuePattern = #"(?:\(\s*|,\s*|:\s*)([a-z_][A-Za-z0-9_]*)\s*(?=[,)])"#
        let argumentLabelPattern = #"(?:\(\s*|,\s*|^\s*)([a-z_][A-Za-z0-9_]*)\s*:"#
        let localIdentifierPattern = #"\b([a-z_][A-Za-z0-9_]*)\b"#
        let stringPattern = #""(?:\\.|[^"\\])*""#
        let numberPattern = #"\b(?:\d+(?:\.\d+)?|true|false)\b"#
        let lineCommentPattern = #"//.*$"#
        let declarationKeywordPattern =
            #"\b(state|environment|binding|let|var|derived)\b(?=\s+[a-z][A-Za-z0-9_]*\b)"#
        let variableDeclarationPattern =
            #"\b(?:state|environment|binding|let|var|derived)\s+([a-z][A-Za-z0-9_]*)\b"#
        let localVariableNames = collectDeclaredVariableNames(in: lines)
        let parameterDeclarationsByLine = collectParameterDeclarationRanges(in: lines)
        let parameterNames = Set(
            parameterDeclarationsByLine.values.flatMap { declarations in
                declarations.map(\.name)
            }
        )
        let keywordNames: Set<String> = [
            "background", "binding", "break", "builder", "capture", "case", "construct",
            "continue", "core", "default", "derived", "else", "enum", "environment",
            "extension", "for", "function", "get", "if", "in", "infix", "init",
            "macro", "main", "marker", "namespace", "nil", "on", "operator", "postfix", "precedencegroup",
            "prefix", "protocol", "return", "self", "set", "state", "switch", "let", "var",
            "while",
        ]
        let keywordLikeIdentifierNames = Set(localVariableNames.union(parameterNames)).intersection(
            keywordNames
        )
        let identifierKeywordExclusions: Set<String> = [
            "if", "for", "while", "switch", "return", "macro", "marker", "function", "init",
            "construct", "namespace", "enum", "protocol", "extension", "background", "state",
            "environment", "binding", "derived", "let", "var", "case", "default", "break",
            "continue", "true", "false", "nil", "self",
        ]

        for (lineIndex, line) in lines.enumerated() {
            let nsLine = line as NSString

            if let commentRegex = try? NSRegularExpression(pattern: lineCommentPattern) {
                let matches = commentRegex.matches(
                    in: line,
                    range: NSRange(location: 0, length: nsLine.length)
                )
                for match in matches {
                    record(line: lineIndex, range: match.range, type: .comment)
                }
            }

            if let stringRegex = try? NSRegularExpression(pattern: stringPattern) {
                let matches = stringRegex.matches(
                    in: line,
                    range: NSRange(location: 0, length: nsLine.length)
                )
                for match in matches {
                    stringLiteralRangesByLine[lineIndex, default: []].append(match.range)
                    let literal = nsLine.substring(with: match.range)
                    if literal.contains(#"\("#) {
                        continue
                    }
                    record(line: lineIndex, range: match.range, type: .string)
                }
            }

            if let numberRegex = try? NSRegularExpression(pattern: numberPattern) {
                let matches = numberRegex.matches(
                    in: line,
                    range: NSRange(location: 0, length: nsLine.length)
                )
                for match in matches {
                    if overlapsExisting(
                        line: lineIndex,
                        start: match.range.location,
                        length: match.range.length
                    ) {
                        continue
                    }
                    record(line: lineIndex, range: match.range, type: .number)
                }
            }

            if let attributeKeywordRegex = try? NSRegularExpression(pattern: attributeKeywordPattern) {
                let matches = attributeKeywordRegex.matches(
                    in: line,
                    range: NSRange(location: 0, length: nsLine.length)
                )
                for match in matches {
                    if overlapsExisting(
                        line: lineIndex,
                        start: match.range.location,
                        length: match.range.length
                    ) {
                        continue
                    }
                    record(line: lineIndex, range: match.range, type: .keyword)
                }
            }

            for pattern in declarationPatterns {
                guard let match = firstMatch(in: line, pattern: pattern), match.count > 1 else {
                    continue
                }

                let name = match[1]
                let range = nsRange(in: line, value: name)
                let modifiers: Set<SemanticTokenModifier> = [.declaration]
                record(line: lineIndex, range: range, type: .type, modifiers: modifiers)
            }

            if let match = firstMatch(in: line, pattern: functionDeclarationPattern), match.count > 1 {
                let name = match[1]
                record(
                    line: lineIndex,
                    range: nsRange(in: line, value: name),
                    type: .function,
                    modifiers: [.declaration]
                )
            }

            if let match = firstMatch(in: line, pattern: macroDeclarationPattern), match.count > 1 {
                let name = match[1]
                record(
                    line: lineIndex,
                    range: nsRange(in: line, value: name),
                    type: .macro,
                    modifiers: [.declaration]
                )
            }

            if let match = firstMatch(in: line, pattern: markerDeclarationPattern), match.count > 1 {
                let name = match[1]
                record(
                    line: lineIndex,
                    range: nsRange(in: line, value: name),
                    type: .macro,
                    modifiers: [.declaration]
                )
            }

            if let match = firstMatch(in: line, pattern: enumCaseDeclarationPattern), match.count > 1 {
                let name = match[1]
                record(
                    line: lineIndex,
                    range: nsRange(in: line, value: name),
                    type: .enumMember,
                    modifiers: [.declaration]
                )
            }

            if let declarationKeywordRegex = try? NSRegularExpression(pattern: declarationKeywordPattern) {
                let matches = declarationKeywordRegex.matches(
                    in: line,
                    range: NSRange(location: 0, length: nsLine.length)
                )
                for match in matches {
                    if isPatternBindingStorageKeyword(in: line, keywordStart: match.range.location) {
                        continue
                    }
                    if overlapsExisting(
                        line: lineIndex,
                        start: match.range.location,
                        length: match.range.length
                    ) {
                        continue
                    }
                    record(
                        line: lineIndex,
                        range: match.range,
                        type: .keyword
                    )
                }
            }

            if let variableRegex = try? NSRegularExpression(pattern: variableDeclarationPattern) {
                let matches = variableRegex.matches(
                    in: line,
                    range: NSRange(location: 0, length: nsLine.length)
                )
                for match in matches {
                    guard match.numberOfRanges > 1 else { continue }
                    if isPatternBindingStorageKeyword(in: line, keywordStart: match.range.location) {
                        continue
                    }
                    let name = nsLine.substring(with: match.range(at: 1))
                    if keywordLikeIdentifierNames.contains(name) {
                        continue
                    }
                    record(
                        line: lineIndex,
                        range: match.range(at: 1),
                        type: .variable,
                        modifiers: [.declaration]
                    )
                }
            }

            if let keywordRegex = try? NSRegularExpression(pattern: #"\b[A-Za-z_][A-Za-z0-9_]*\b"#) {
                let matches = keywordRegex.matches(
                    in: line,
                    range: NSRange(location: 0, length: nsLine.length)
                )
                for match in matches {
                    let word = nsLine.substring(with: match.range)
                    guard keywordNames.contains(word) else { continue }
                    if keywordLikeIdentifierNames.contains(word) {
                        continue
                    }
                    if overlapsExisting(
                        line: lineIndex,
                        start: match.range.location,
                        length: match.range.length
                    ) {
                        continue
                    }
                    record(line: lineIndex, range: match.range, type: .keyword)
                }
            }

            guard let typeRegex = try? NSRegularExpression(pattern: typePattern) else {
                continue
            }
            let typeMatches = typeRegex.matches(
                in: line,
                range: NSRange(location: 0, length: nsLine.length)
            )
            for match in typeMatches {
                if overlapsExisting(
                    line: lineIndex,
                    start: match.range.location,
                    length: match.range.length
                ) {
                    continue
                }
                record(line: lineIndex, range: match.range, type: .type)
            }

            if let callRegex = try? NSRegularExpression(pattern: localCallPattern) {
                let callMatches = callRegex.matches(
                    in: line,
                    range: NSRange(location: 0, length: nsLine.length)
                )
                for match in callMatches {
                    guard match.numberOfRanges > 1 else { continue }
                    let nameRange = match.range(at: 1)
                    let name = nsLine.substring(with: nameRange)
                    guard !identifierKeywordExclusions.contains(name) else { continue }
                    if nameRange.location > 0 {
                        let previous = nsLine.substring(
                            with: NSRange(location: nameRange.location - 1, length: 1)
                        )
                        if previous == "#" || previous == "@" || previous == "." {
                            continue
                        }
                    }
                    if overlapsExisting(
                        line: lineIndex,
                        start: nameRange.location,
                        length: nameRange.length
                    ) {
                        continue
                    }
                    record(line: lineIndex, range: nameRange, type: .function, modifiers: [])
                }
            }

            if let memberRegex = try? NSRegularExpression(pattern: memberPattern) {
                let memberMatches = memberRegex.matches(
                    in: line,
                    range: NSRange(location: 0, length: nsLine.length)
                )
                for match in memberMatches {
                    guard match.numberOfRanges > 1 else { continue }
                    let nameRange = match.range(at: 1)
                    if overlapsExisting(
                        line: lineIndex,
                        start: nameRange.location,
                        length: nameRange.length
                    ) {
                        continue
                    }

                    let tokenType: SemanticTokenType
                    let afterLocation = nameRange.location + nameRange.length
                    var cursor = afterLocation
                    while cursor < nsLine.length {
                        let character = nsLine.substring(with: NSRange(location: cursor, length: 1))
                        guard character.rangeOfCharacter(from: .whitespacesAndNewlines) != nil else {
                            break
                        }
                        cursor += 1
                    }
                    if cursor < nsLine.length,
                        nsLine.substring(with: NSRange(location: cursor, length: 1)) == "("
                    {
                        tokenType = .method
                    } else {
                        tokenType = .property
                    }
                    record(line: lineIndex, range: nameRange, type: tokenType)
                }
            }

            if !isParameterDeclarationContext(line),
                let argumentLabelRegex = try? NSRegularExpression(pattern: argumentLabelPattern)
            {
                let labelMatches = argumentLabelRegex.matches(
                    in: line,
                    range: NSRange(location: 0, length: nsLine.length)
                )
                for match in labelMatches {
                    guard match.numberOfRanges > 1 else { continue }
                    let nameRange = match.range(at: 1)
                    if overlapsExisting(
                        line: lineIndex,
                        start: nameRange.location,
                        length: nameRange.length
                    ) {
                        continue
                    }
                    guard let (tokenType, modifiers) = argumentLabelTokenKind(
                        in: lines,
                        lineIndex: lineIndex,
                        labelStart: nameRange.location
                    ) else {
                        continue
                    }
                    record(line: lineIndex, range: nameRange, type: tokenType, modifiers: modifiers)
                }
            }

            if let argumentValueRegex = try? NSRegularExpression(
                pattern: argumentValuePattern
            ) {
                let argumentMatches = argumentValueRegex.matches(
                    in: line,
                    range: NSRange(location: 0, length: nsLine.length)
                )
                for match in argumentMatches {
                    guard match.numberOfRanges > 1 else { continue }
                    let nameRange = match.range(at: 1)
                    let name = nsLine.substring(with: nameRange)
                    let tokenType: SemanticTokenType
                    if parameterNames.contains(name) {
                        continue
                    } else if localVariableNames.contains(name) {
                        tokenType = .variable
                    } else {
                        continue
                    }
                    if overlapsExisting(
                        line: lineIndex,
                        start: nameRange.location,
                        length: nameRange.length
                    ) {
                        continue
                    }
                    record(
                        line: lineIndex,
                        range: nameRange,
                        type: tokenType,
                        modifiers: [.argument]
                    )
                }
            }

            for parameter in parameterDeclarationsByLine[lineIndex] ?? [] {
                if let externalRange = parameter.externalRange {
                    record(
                        line: lineIndex,
                        range: externalRange,
                        type: .label,
                        modifiers: [.declaration]
                    )
                    continue
                }

                if keywordLikeIdentifierNames.contains(parameter.name) {
                    continue
                }
                if overlapsExisting(
                    line: lineIndex,
                    start: parameter.range.location,
                    length: parameter.range.length
                ) {
                    continue
                }
                record(
                    line: lineIndex,
                    range: parameter.range,
                    type: .parameter,
                    modifiers: [.declaration]
                )
            }

            if let metadataTokenRegex = try? NSRegularExpression(pattern: metadataTokenPattern) {
                let metadataMatches = metadataTokenRegex.matches(
                    in: line,
                    range: NSRange(location: 0, length: nsLine.length)
                )
                for match in metadataMatches {
                    guard match.numberOfRanges > 1 else { continue }
                    let nameRange = match.range(at: 1)
                    record(line: lineIndex, range: nameRange, type: .keyword, modifiers: [])
                }
            }

            guard let macroTokenRegex = try? NSRegularExpression(pattern: macroTokenPattern) else {
                continue
            }
            let macroMatches = macroTokenRegex.matches(
                in: line,
                range: NSRange(location: 0, length: nsLine.length)
            )
            for match in macroMatches {
                guard match.numberOfRanges > 1 else { continue }
                let nameRange = match.range(at: 1)
                if overlapsExisting(
                    line: lineIndex,
                    start: nameRange.location,
                    length: nameRange.length
                ) {
                    continue
                }
                record(line: lineIndex, range: nameRange, type: .macro, modifiers: [])
            }

            if let localIdentifierRegex = try? NSRegularExpression(pattern: localIdentifierPattern) {
                let localMatches = localIdentifierRegex.matches(
                    in: line,
                    range: NSRange(location: 0, length: nsLine.length)
                )
                for match in localMatches {
                    guard match.numberOfRanges > 1 else { continue }
                    let nameRange = match.range(at: 1)
                    let name = nsLine.substring(with: nameRange)
                    guard !identifierKeywordExclusions.contains(name) else { continue }
                    guard localVariableNames.contains(name) else {
                        continue
                    }
                    if keywordLikeIdentifierNames.contains(name) {
                        continue
                    }
                    if overlapsExisting(
                        line: lineIndex,
                        start: nameRange.location,
                        length: nameRange.length
                    ) {
                        continue
                    }
                    if nameRange.location > 0 {
                        let previous = nsLine.substring(
                            with: NSRange(location: nameRange.location - 1, length: 1)
                        )
                        if previous == "." || previous == "#" || previous == "@" {
                            continue
                        }
                    }

                    var cursor = nameRange.location + nameRange.length
                    while cursor < nsLine.length {
                        let character = nsLine.substring(with: NSRange(location: cursor, length: 1))
                        guard character.rangeOfCharacter(from: .whitespacesAndNewlines) != nil else {
                            break
                        }
                        cursor += 1
                    }
                    if cursor < nsLine.length,
                        nsLine.substring(with: NSRange(location: cursor, length: 1)) == "."
                    {
                        continue
                    }
                    if cursor < nsLine.length,
                        nsLine.substring(with: NSRange(location: cursor, length: 1)) == ":"
                    {
                        continue
                    }

                    record(line: lineIndex, range: nameRange, type: .variable)
                }
            }
        }

        return tokens.sorted {
            if $0.line != $1.line { return $0.line < $1.line }
            if $0.startCharacter != $1.startCharacter { return $0.startCharacter < $1.startCharacter }
            if $0.length != $1.length { return $0.length < $1.length }
            if $0.type != $1.type { return $0.type.rawValue < $1.type.rawValue }
            return $0.modifierMask < $1.modifierMask
        }
    }

    fileprivate static func encodeSemanticTokens(_ tokens: [SemanticTokenOccurrence]) -> [Int] {
        var encoded: [Int] = []
        var previousLine = 0
        var previousStart = 0

        for token in tokens {
            let deltaLine = token.line - previousLine
            let deltaStart = deltaLine == 0 ? token.startCharacter - previousStart : token.startCharacter
            encoded.append(contentsOf: [
                deltaLine,
                deltaStart,
                token.length,
                token.typeIndex,
                token.modifierMask,
            ])
            previousLine = token.line
            previousStart = token.startCharacter
        }

        return encoded
    }

    private static func collectParameterDeclarationRanges(in lines: [String]) -> [Int: [ParameterDeclaration]] {
        var results: [Int: [ParameterDeclaration]] = [:]
        var insideParameterClause = false

        for (lineIndex, line) in lines.enumerated() {
            let nsLine = line as NSString

            if !insideParameterClause {
                guard isParameterDeclarationContext(line) else {
                    continue
                }

                if let openRange = line.range(of: "(") {
                    insideParameterClause = true
                    let start = openRange.upperBound.utf16Offset(in: line)
                    let end: Int
                    if let closeRange = line.range(of: ")", range: openRange.upperBound..<line.endIndex) {
                        end = closeRange.lowerBound.utf16Offset(in: line)
                        insideParameterClause = false
                    } else {
                        end = nsLine.length
                    }
                    appendParameterDeclarations(
                        in: NSRange(location: start, length: max(0, end - start)),
                        line: line,
                        lineIndex: lineIndex,
                        into: &results
                    )
                }
                continue
            }

            let end: Int
            if let closeRange = line.range(of: ")") {
                end = closeRange.lowerBound.utf16Offset(in: line)
                insideParameterClause = false
            } else {
                end = nsLine.length
            }

            appendParameterDeclarations(
                in: NSRange(location: 0, length: end),
                line: line,
                lineIndex: lineIndex,
                into: &results
            )
        }

        return results
    }

    private static func appendParameterDeclarations(
        in searchRange: NSRange,
        line: String,
        lineIndex: Int,
        into results: inout [Int: [ParameterDeclaration]]
    ) {
        guard searchRange.length > 0 else { return }

        let nsLine = line as NSString
        let segment = nsLine.substring(with: searchRange)
        guard !segment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        guard let regex = try? NSRegularExpression(
            pattern: #"(?:^|,)\s*(?:[@#][A-Za-z_][A-Za-z0-9_]*\s+)*(?:(_|[A-Za-z_][A-Za-z0-9_]*)\s+)?([a-z_][A-Za-z0-9_]*)\s*:"#
        ) else { return }

        let matches = regex.matches(
            in: segment,
            range: NSRange(location: 0, length: (segment as NSString).length)
        )
        let nsSegment = segment as NSString

        for match in matches {
            guard match.numberOfRanges > 2 else { continue }

            let nameRangeInSegment = match.range(at: 2)
            guard nameRangeInSegment.location != NSNotFound else { continue }

            let externalRangeInSegment = match.range(at: 1)
            let externalName: String?
            let externalRange: NSRange?
            if externalRangeInSegment.location != NSNotFound {
                externalName = nsSegment.substring(with: externalRangeInSegment)
                externalRange = NSRange(
                    location: searchRange.location + externalRangeInSegment.location,
                    length: externalRangeInSegment.length
                )
            } else {
                externalName = nil
                externalRange = nil
            }

            let name = nsSegment.substring(with: nameRangeInSegment)
            let nameRange = NSRange(
                location: searchRange.location + nameRangeInSegment.location,
                length: nameRangeInSegment.length
            )
            results[lineIndex, default: []].append(
                ParameterDeclaration(
                    externalName: externalName,
                    externalRange: externalRange,
                    name: name,
                    range: nameRange
                )
            )
        }
    }

    private static func isParameterDeclarationContext(_ line: String) -> Bool {
        guard let openRange = line.range(of: "(") else {
            return false
        }

        let prefix = String(line[..<openRange.lowerBound])
        let trimmedPrefix = prefix.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedPrefix.hasPrefix("init") {
            return true
        }

        let declarationPatterns = [
            #"\bfunction\s+(?:[a-z_][A-Za-z0-9_]*|[!%&*+\-./<=>?^|~]+)(?:<[^>\n]+>)?\s*$"#,
            #"\bmacro\s+[a-z_][A-Za-z0-9_]*(?:<[^>\n]+>)?\s*$"#,
            #"\bmarker\s+[a-z_][A-Za-z0-9_]*(?:<[^>\n]+>)?\s*$"#,
        ]

        return declarationPatterns.contains { pattern in
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
            let nsPrefix = trimmedPrefix as NSString
            let range = NSRange(location: 0, length: nsPrefix.length)
            return regex.firstMatch(in: trimmedPrefix, range: range) != nil
        }
    }

    private static func argumentLabelTokenKind(
        in lines: [String],
        lineIndex: Int,
        labelStart: Int
    ) -> (SemanticTokenType, Set<SemanticTokenModifier>)? {
        guard isArgumentLabelContext(in: lines, lineIndex: lineIndex, labelStart: labelStart) else {
            return nil
        }
        if isTypeReferenceArgumentLabelContext(in: lines, lineIndex: lineIndex, labelStart: labelStart) {
            return (.type, [.application])
        }
        return (.method, [])
    }

    private static func isArgumentLabelContext(
        in lines: [String],
        lineIndex: Int,
        labelStart: Int
    ) -> Bool {
        let line = lines[lineIndex]
        let prefix = String(line.prefix(labelStart))

        if prefix.range(
            of: #"(?:\(\s*|,\s*)$"#,
            options: .regularExpression
        ) != nil {
            return true
        }

        if !prefix.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return false
        }

        var prior = lineIndex - 1
        while prior >= 0 {
            let trimmed = lines[prior].trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                prior -= 1
                continue
            }
            if trimmed.contains(")") {
                return false
            }
            if trimmed.range(
                of: #"^(?:[A-Z][A-Za-z0-9_]*|[a-z_][A-Za-z0-9_]*|(?:\b[A-Za-z_][A-Za-z0-9_]*|\])\.[a-z_][A-Za-z0-9_]*)\s*\($"#,
                options: .regularExpression
            ) != nil {
                return true
            }
            if trimmed.contains("{") || trimmed.contains("}") {
                return false
            }
            prior -= 1
        }

        return false
    }

    private static func isTypeReferenceArgumentLabelContext(
        in lines: [String],
        lineIndex: Int,
        labelStart: Int
    ) -> Bool {
        let line = lines[lineIndex]
        let prefix = String(line.prefix(labelStart))

        if prefix.range(
            of: #"(?:^|[=(,\s])[A-Z][A-Za-z0-9_]*\s*\([^()]*$"#,
            options: .regularExpression
        ) != nil {
            return prefix.range(
                of: #"(?:^|[=(,\s])[A-Z][A-Za-z0-9_]*TypeReference\s*\([^()]*$"#,
                options: .regularExpression
            ) != nil
        }

        var prior = lineIndex - 1
        while prior >= 0 {
            let trimmed = lines[prior].trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                prior -= 1
                continue
            }
            if trimmed.contains(")") {
                return false
            }
            if trimmed.range(
                of: #"^[A-Z][A-Za-z0-9_]*TypeReference\s*\($"#,
                options: .regularExpression
            ) != nil {
                return true
            }
            if trimmed.range(
                of: #"^(?:[a-z_][A-Za-z0-9_]*|(?:\b[A-Za-z_][A-Za-z0-9_]*|\])\.[a-z_][A-Za-z0-9_]*)\s*\($"#,
                options: .regularExpression
            ) != nil {
                return false
            }
            prior -= 1
        }

        return false
    }

    private static func collectDeclaredVariableNames(in lines: [String]) -> Set<String> {
        let pattern = #"\b(state|environment|binding|let|var|derived)\s+([a-z][A-Za-z0-9_]*)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        var result: Set<String> = []
        for line in lines {
            let nsLine = line as NSString
            let matches = regex.matches(
                in: line,
                range: NSRange(location: 0, length: nsLine.length)
            )
            for match in matches where match.numberOfRanges > 2 {
                if isPatternBindingStorageKeyword(in: line, keywordStart: match.range(at: 1).location) {
                    continue
                }
                result.insert(nsLine.substring(with: match.range(at: 2)))
            }
        }
        return result
    }

    private static func isPatternBindingStorageKeyword(in line: String, keywordStart: Int) -> Bool {
        guard keywordStart > 0 else { return false }

        let nsLine = line as NSString
        var cursor = keywordStart - 1
        while cursor >= 0 {
            let character = nsLine.substring(with: NSRange(location: cursor, length: 1))
            if character.rangeOfCharacter(from: .whitespacesAndNewlines) == nil {
                return character == "(" || character == ","
            }
            cursor -= 1
        }
        return false
    }

    private static func collectDeclaredParameterNames(in lines: [String]) -> Set<String> {
        Set(collectParameterDeclarationRanges(in: lines).values.flatMap { declarations in
            declarations.map(\.name)
        })
    }

    private static func firstNonWhitespaceRange(in lines: [String]) -> RangePosition? {
        for (lineIndex, line) in lines.enumerated() {
            if let offset = line.firstIndex(where: { !$0.isWhitespace })?.utf16Offset(in: line) {
                return RangePosition(
                    start: Position(line: lineIndex, character: offset),
                    end: Position(line: lineIndex, character: offset + 1)
                )
            }
        }
        return nil
    }

    fileprivate static func firstMatch(in line: String, pattern: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsLine = line as NSString
        guard
            let match = regex.firstMatch(
                in: line, range: NSRange(location: 0, length: nsLine.length))
        else {
            return nil
        }

        return (0..<match.numberOfRanges).map { index in
            let range = match.range(at: index)
            guard range.location != NSNotFound else { return "" }
            return nsLine.substring(with: range)
        }
    }

    private static func range(in line: String, line lineIndex: Int, value: String) -> RangePosition
    {
        let range = nsRange(in: line, value: value)
        return RangePosition(
            start: Position(line: lineIndex, character: max(0, range.location)),
            end: Position(line: lineIndex, character: max(0, range.location + range.length))
        )
    }

    private static func nsRange(in line: String, value: String) -> NSRange {
        let nsLine = line as NSString
        return nsLine.range(of: value)
    }
}

// Semantic highlighting in Neat should stay semantic-first and editor-agnostic.
// Keep this taxonomy intentionally small and prefer standard LSP token types
// plus modifiers before adding custom distinctions. See:
// Zed/Neat/docs/SemanticHighlightingPlan.md
enum SemanticTokenType: String, CaseIterable {
    case type
    case function
    case method
    case macro
    case variable
    case property
    case parameter
    case enumMember
    case label
    case keyword
    case comment
    case string
    case number
}

enum SemanticTokenModifier: String, CaseIterable {
    case declaration
    case application
    case argument
}

struct SemanticTokenOccurrence: Hashable {
    let line: Int
    let startCharacter: Int
    let length: Int
    let type: SemanticTokenType
    let modifiers: Set<SemanticTokenModifier>

    var typeIndex: Int {
        SemanticTokenType.allCases.firstIndex(of: type) ?? 0
    }

    var modifierMask: Int {
        modifiers.reduce(0) { partial, modifier in
            guard let index = SemanticTokenModifier.allCases.firstIndex(of: modifier) else {
                return partial
            }
            return partial | (1 << index)
        }
    }
}

struct SemanticTokenSnapshot: Equatable {
    let text: String
    let line: Int
    let startCharacter: Int
    let length: Int
    let type: SemanticTokenType
    let modifiers: Set<SemanticTokenModifier>
}

struct DefinitionSnapshot: Equatable {
    let uri: String
    let line: Int
    let startCharacter: Int
    let endCharacter: Int
    let name: String
}

extension NeatLanguageServer {
    static func debugFormattedDocument(_ text: String) -> String {
        formatDocument(text)
    }

    static func debugSemanticTokenSnapshots(in text: String) -> [SemanticTokenSnapshot] {
        let lines = text.components(separatedBy: .newlines)
        return DocumentIndex.collectSemanticTokenOccurrences(in: lines).map { occurrence in
            let line = lines[occurrence.line]
            let nsLine = line as NSString
            let tokenText = nsLine.substring(
                with: NSRange(location: occurrence.startCharacter, length: occurrence.length)
            )
            return SemanticTokenSnapshot(
                text: tokenText,
                line: occurrence.line,
                startCharacter: occurrence.startCharacter,
                length: occurrence.length,
                type: occurrence.type,
                modifiers: occurrence.modifiers
            )
        }
    }

    static func debugDefinitionSnapshot(
        in text: String,
        line: Int,
        character: Int,
        supportDocuments: [(uri: String, text: String)] = []
    ) -> DefinitionSnapshot? {
        let primary = DocumentState(
            uri: "file:///Primary.neat",
            text: text,
            index: DocumentIndex(text: text, uri: "file:///Primary.neat"),
            diagnostics: []
        )
        let position = Position(line: line, character: character)
        let inputs = supportDocuments.map { document in
            SourceInput(path: URL(string: document.uri)?.path ?? document.uri, source: document.text, role: .core)
        } + [
            SourceInput(path: "/Primary.neat", source: text, role: .project)
        ]

        guard
            let word = primary.word(at: position),
            !primary.isArgumentLabel(at: position),
            let navigationIndex = try? ProjectNavigationIndex(inputs: inputs)
        else {
            return nil
        }

        let occurrence = primary.semanticTokenOccurrence(at: position)
        guard let definition = navigationIndex.definition(named: word, occurrence: occurrence) else {
            return nil
        }

        return DefinitionSnapshot(
            uri: definition.uri,
            line: definition.range.start.line,
            startCharacter: definition.range.start.character,
            endCharacter: definition.range.end.character,
            name: definition.name
        )
    }
}

private enum DefaultLibrarySymbols {
    static let typeNames: Set<String> = {
        collect(patterns: [
            #"\bconstruct\s+([A-Z][A-Za-z0-9_]*)"#,
            #"\bprotocol\s+([A-Z][A-Za-z0-9_]*)"#,
            #"\benum\s+([A-Z][A-Za-z0-9_]*)"#,
            #"\*builder\s+([A-Z][A-Za-z0-9_]*)"#,
            #"\bprecedencegroup\s+([A-Z][A-Za-z0-9_]*)"#,
        ])
    }()

    static let functionNames: Set<String> = {
        collect(patterns: [
            #"\bfunction\s+([a-z_][A-Za-z0-9_]*)\s*\("#,
            #"\bfunc\s+([a-z_][A-Za-z0-9_]*)\s*\("#,
        ])
    }()

    static let macroNames: Set<String> = {
        collect(patterns: [
            #"\bmacro\s+([a-z_][A-Za-z0-9_]*)\s*\("#,
        ])
    }()

    private static func collect(
        patterns: [String],
        transform: (([String]) -> String)? = nil
    ) -> Set<String> {
        guard let inputs = try? NeatCoreLoader.sourceInputs() else { return [] }

        var result: Set<String> = []
        for input in inputs where input.role == .core {
            let lines = input.source.components(separatedBy: .newlines)
            for line in lines {
                for pattern in patterns {
                    guard let match = DocumentIndex.firstMatch(in: line, pattern: pattern), match.count > 1 else {
                        continue
                    }
                    result.insert(transform?(match) ?? match[1])
                }
            }
        }
        return result
    }
}

private struct Symbol {
    let name: String
    let kind: SymbolKind
    let detail: String
    let uri: String
    let range: RangePosition
    let selectionRange: RangePosition
}

private enum SymbolKind {
    case attribute
    case declaration
    case callable
    case macro
    case variable
    case state
    case styleModifier
    case typeExtension
    case view
    case modifier
    case keyword

    var lspKind: Int {
        switch self {
        case .attribute:
            return 8
        case .declaration, .typeExtension, .view:
            return 5
        case .callable, .modifier, .macro:
            return 12
        case .variable, .state:
            return 13
        case .styleModifier:
            return 6
        case .keyword:
            return 14
        }
    }

    var completionKind: Int {
        switch self {
        case .callable, .modifier, .macro:
            return 3
        case .attribute, .keyword:
            return 14
        case .variable, .state:
            return 6
        default:
            return 7
        }
    }
}

private struct ReferenceOccurrence {
    let name: String
    let range: RangePosition
}

private struct DefinitionLocation {
    let name: String
    let uri: String
    let range: RangePosition
    let kind: DeclarationSourceKind
}

private struct NavigationIndexCacheEntry {
    let generation: Int
    let index: ProjectNavigationIndex
}

private struct ProjectNavigationIndex {
    let declarationGraph: DeclarationGraph

    init(inputs: [SourceInput]) throws {
        self.declarationGraph = try CompilerPipeline().build(inputs: inputs).declarationGraph
    }

    func definition(named word: String, occurrence: SemanticTokenOccurrence?) -> DefinitionLocation? {
        if word.first?.isUppercase == true || occurrence?.type == .type {
            if declarationGraph.registryView.hasConstruct(named: word)
                || declarationGraph.registryView.hasProtocol(named: word)
                || declarationGraph.registryView.hasEnumeration(named: word)
                || declarationGraph.hasNamespace(named: word)
            {
                return definitionLocation(named: word, kinds: [.type, .namespace])
            }
        }

        if occurrence?.type == .macro
            || declarationGraph.registryView.hasMacro(named: word)
            || declarationGraph.markersByName[word] != nil
        {
            return definitionLocation(named: word, kinds: [.macro, .marker])
        }

        if occurrence?.type == .function || occurrence?.type == .method {
            if !declarationGraph.registryView.callables(named: word).isEmpty {
                return definitionLocation(named: word, kinds: [.function])
            }
        }

        return nil
    }

    private func definitionLocation(
        named name: String,
        kinds: Set<DeclarationSourceKind>
    ) -> DefinitionLocation? {
        guard let location = declarationGraph.sourceLocation(named: name, kinds: kinds) else {
            return nil
        }
        return DefinitionLocation(
            name: location.name,
            uri: URL(fileURLWithPath: location.path).absoluteString,
            range: RangePosition(
                start: Position(
                    line: location.range.start.line,
                    character: location.range.start.character
                ),
                end: Position(
                    line: location.range.end.line,
                    character: location.range.end.character
                )
            ),
            kind: location.kind
        )
    }
}

private struct RangePosition {
    let start: Position
    let end: Position

    var json: [String: Any] {
        [
            "start": start.json,
            "end": end.json,
        ]
    }
}

private struct Position {
    let line: Int
    let character: Int

    var json: [String: Int] {
        [
            "line": line,
            "character": character,
        ]
    }
}
