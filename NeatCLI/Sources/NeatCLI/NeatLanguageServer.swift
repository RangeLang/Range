import Foundation
import NeatSyntax

struct NeatLanguageServer {
    private var documents: [String: DocumentState] = [:]
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

        switch method {
        case "initialize":
            try sendResponse(
                id: id,
                result: [
                    "capabilities": [
                        "textDocumentSync": 1,
                        "hoverProvider": true,
                        "definitionProvider": true,
                        "referencesProvider": true,
                        "renameProvider": true,
                        "documentSymbolProvider": true,
                        "documentFormattingProvider": true,
                        "completionProvider": [
                            "resolveProvider": false,
                            "triggerCharacters": [".", "@", "#"],
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

        try updateDocument(uri: uri, text: text)
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

        try updateDocument(uri: uri, text: latest)
    }

    private mutating func refreshSavedDocument(from message: [String: Any]) throws {
        guard
            let params = message["params"] as? [String: Any],
            let textDocument = params["textDocument"] as? [String: Any],
            let uri = textDocument["uri"] as? String,
            let state = documents[uri]
        else {
            return
        }

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
    }

    private mutating func updateDocument(uri: String, text: String) throws {
        let state = buildDocumentState(uri: uri, text: text)
        documents[uri] = state
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

    private func definitionResult(for message: [String: Any]) -> [String: Any]? {
        guard
            let request = requestContext(from: message),
            let word = request.state.word(at: request.position),
            let definition = documents.values
                .flatMap(\.symbols)
                .first(where: { $0.name == word })
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
        } else {
            items =
                keywordCompletions()
                + builtinViewCompletions()
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

        let formatted = formatDocument(request.state.text)
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

    private func hoverDescription(for symbol: Symbol) -> String {
        switch symbol.kind {
        case .attribute:
            return "Neat callable sigil"
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

    private func buildDocumentState(uri: String, text: String) -> DocumentState {
        let index = DocumentIndex(text: text, uri: uri)
        let diagnostics = diagnosticPayload(for: text, index: index)
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

    private func diagnosticPayload(for text: String, index: DocumentIndex) -> [[String: Any]] {
        do {
            let annotated = annotateDebugPrints(in: text)
            var parser = try Parser(source: annotated)
            _ = try parser.parseDeclaration()
            return []
        } catch {
            let fallbackRange = index.firstNonWhitespaceRange ?? index.fullDocumentRange
            return [
                [
                    "range": fallbackRange.json,
                    "severity": 1,
                    "source": "neat-lsp",
                    "message": String(describing: error),
                ]
            ]
        }
    }

    private func annotateDebugPrints(in source: String) -> String {
        let lines = source.components(separatedBy: .newlines)
        var result: [String] = []
        result.reserveCapacity(lines.count)

        for (index, rawLine) in lines.enumerated() {
            let lineNumber = index + 1
            let prefix = "[L\(lineNumber)] "

            if let range = rawLine.range(of: "print(\"") {
                var line = rawLine
                line.replaceSubrange(range, with: "print(\"\(prefix)")
                result.append(line)
                continue
            }

            result.append(rawLine)
        }

        return result.joined(separator: "\n")
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

    private func location(uri: String, range: RangePosition) -> [String: Any] {
        [
            "uri": uri,
            "range": range.json,
        ]
    }

    private func keywordCompletions() -> [[String: Any]] {
        [
            "case", "extension", "let", "state", "switch",
            "var",
        ].map { completionItem(label: $0, kind: 14, detail: "keyword") }
    }

    private func attributeCompletions() -> [[String: Any]] {
        [
            "@init", "@run", "@background",
        ].map { completionItem(label: $0, kind: 14, detail: "attribute") }
    }

    private func builtinViewCompletions() -> [[String: Any]] {
        [
            "Body", "Button", "Div", "ForEach", "HStack", "Image", "List", "Portal",
            "ScrollArea", "Spacer", "Text", "TextField", "Toggle", "VStack", "ZStack",
        ].map { completionItem(label: $0, kind: 7, detail: "built-in view") }
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

    private func formatDocument(_ text: String) -> String {
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

            let opens = trimmed.filter { "({[".contains($0) }.count
            let closes = trimmed.filter { ")}]".contains($0) }.count
            depth = max(0, depth + opens - closes)
        }

        return formatted.joined(separator: "\n")
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
        let payload = try JSONSerialization.data(withJSONObject: message)
        let header = "Content-Length: \(payload.count)\r\n\r\n"
        let output = FileHandle.standardOutput
        if let headerData = header.data(using: .utf8) {
            output.write(headerData)
        }
        output.write(payload)
        output.synchronizeFile()
    }
}

private struct RequestContext {
    let state: DocumentState
    let position: Position
}

private struct DocumentState {
    let uri: String
    let text: String
    let index: DocumentIndex
    let diagnostics: [[String: Any]]

    var symbols: [Symbol] { index.symbols }
    var fullDocumentRange: RangePosition { index.fullDocumentRange }

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

    func references(named name: String) -> [ReferenceOccurrence] {
        index.references(named: name)
    }
}

private struct DocumentIndex {
    let text: String
    let uri: String
    let lines: [String]
    let symbols: [Symbol]
    let referencesByName: [String: [ReferenceOccurrence]]
    let fullDocumentRange: RangePosition
    let firstNonWhitespaceRange: RangePosition?

    init(text: String, uri: String) {
        self.text = text
        self.uri = uri
        self.lines = text.components(separatedBy: .newlines)
        self.symbols = DocumentIndex.collectSymbols(in: lines, uri: uri)
        self.referencesByName = DocumentIndex.collectReferences(in: lines)
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
        guard lines.indices.contains(position.line) else { return nil }
        let target = Array(lines[position.line])
        guard !target.isEmpty else { return nil }

        let clamped = max(0, min(position.character, target.count - 1))
        if isWordCharacter(target[clamped]) {
            return sliceWord(in: target, around: clamped)
        }
        if clamped > 0, isWordCharacter(target[clamped - 1]) {
            return sliceWord(in: target, around: clamped - 1)
        }
        return nil
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

    private func sliceWord(in target: [Character], around index: Int) -> String {
        var start = index
        var end = index

        while start > 0, isWordCharacter(target[start - 1]) {
            start -= 1
        }
        while end < target.count, isWordCharacter(target[end]) {
            end += 1
        }

        return String(target[start..<end])
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
                pattern: #"\bvar\s+([a-z_][A-Za-z0-9_]*)\s*:\s*([A-Z][A-Za-z0-9_.]*)\s*\{"#
            ) {
                let name = match[1]
                let symbolRange = range(in: line, line: lineIndex, value: name)
                symbols.append(
                    Symbol(
                        name: name, kind: .variable, detail: match[2], uri: uri,
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
                in: line, pattern: #"\bstate\s+([a-z_][A-Za-z0-9_]*)"#)
            {
                let name = match[1]
                let symbolRange = range(in: line, line: lineIndex, value: name)
                symbols.append(
                    Symbol(
                        name: name, kind: .state, detail: "state", uri: uri, range: symbolRange,
                        selectionRange: symbolRange))
                continue
            }

            if let match = firstMatch(in: line, pattern: #"\b(let|var)\s+([a-z_][A-Za-z0-9_]*)"#) {
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

    private static func firstMatch(in line: String, pattern: String) -> [String]? {
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
        let nsLine = line as NSString
        let range = nsLine.range(of: value)
        return RangePosition(
            start: Position(line: lineIndex, character: max(0, range.location)),
            end: Position(line: lineIndex, character: max(0, range.location + range.length))
        )
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
        case .callable, .modifier:
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
        case .callable, .modifier:
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
