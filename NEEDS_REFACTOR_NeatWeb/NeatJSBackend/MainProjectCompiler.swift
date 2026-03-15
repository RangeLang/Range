import ArgumentParser
import Foundation
import NeatSyntax

public struct MainProjectCompiler {
    private let path: String
    private let showSummary: Bool

    public init(path: String, showSummary: Bool = true) {
        self.path = path
        self.showSummary = showSummary
    }

    public func run() throws -> URL {
        let startedAt = Date()
        let root = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
        let packageFile = root.appendingPathComponent("Package.neat", isDirectory: false)

        guard FileManager.default.fileExists(atPath: packageFile.path) else {
            throw ValidationError("Missing Package.neat in \(root.path)")
        }

        let packageSource = try String(contentsOf: packageFile, encoding: .utf8)
        let packageName = parsePackageName(from: packageSource) ?? root.lastPathComponent
        let entryFile = try discoverEntryFile(in: root)
        let source = try String(contentsOf: entryFile, encoding: .utf8)
        let annotated = annotateDebugPrints(in: source, fileName: entryFile.lastPathComponent)
        var parser = try Parser(source: annotated)

        let compiled: String
        switch try parser.parseSourceFile() {
        case .mainBlock(let mainBlock):
            compiled = MainJavaScriptGenerator().generate(mainBlock: mainBlock)
        case .extensions:
            throw ValidationError(
                "Main entry file '\(entryFile.lastPathComponent)' must use @main { ... }."
            )
        case .declaration:
            throw ValidationError(
                "Main entry file '\(entryFile.lastPathComponent)' must use @main { ... }."
            )
        case .module:
            throw ValidationError(
                "Main entry file '\(entryFile.lastPathComponent)' must use @main { ... }."
            )
        }

        let buildDirectory =
            root
            .appendingPathComponent(".neat", isDirectory: true)
            .appendingPathComponent("Build", isDirectory: true)
        try FileManager.default.createDirectory(
            at: buildDirectory,
            withIntermediateDirectories: true
        )

        let outputURL = buildDirectory.appendingPathComponent("program.js", isDirectory: false)
        try compiled.write(to: outputURL, atomically: true, encoding: .utf8)

        if showSummary {
            let elapsedMS = Int((Date().timeIntervalSince(startedAt) * 1000.0).rounded())
            let durationText =
                elapsedMS >= 1000
                ? String(format: "%.2fs", Double(elapsedMS) / 1000.0)
                : "\(elapsedMS)ms"
            Swift.print("Compiled \(packageName) \(durationText)")
        }

        return outputURL
    }

    private func parsePackageName(from source: String) -> String? {
        match(in: source, pattern: #"Package\("([^"]+)"\)"#)
    }

    private func annotateDebugPrints(in source: String, fileName: String) -> String {
        let lines = source.components(separatedBy: .newlines)
        var result: [String] = []
        result.reserveCapacity(lines.count)

        for (index, rawLine) in lines.enumerated() {
            let lineNumber = index + 1
            let prefix = "[\(fileName):\(lineNumber)] "

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

    private func match(in source: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }
        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        guard let match = regex.firstMatch(in: source, range: range), match.numberOfRanges > 1,
            let resultRange = Range(match.range(at: 1), in: source)
        else {
            return nil
        }
        return String(source[resultRange])
    }

    private func discoverEntryFile(in root: URL) throws -> URL {
        let fileManager = FileManager.default
        guard
            let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: []
            )
        else {
            throw ValidationError("Could not inspect project files in \(root.path)")
        }

        var matches: [URL] = []

        while let fileURL = enumerator.nextObject() as? URL {
            let path = fileURL.path
            let isDirectory =
                (try? fileURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory)
                ?? false

            if path.contains("/.git/") || path.contains("/.build/")
                || path.contains("/.neat/Build/") || path.contains("/.neat/Packages/")
            {
                if isDirectory {
                    enumerator.skipDescendants()
                }
                continue
            }

            if isDirectory || fileURL.pathExtension.lowercased() != "neat" {
                continue
            }

            let fileName = fileURL.lastPathComponent
            if fileName == "Package.neat" || fileName == "Fonts.neat" {
                continue
            }

            let source = try String(contentsOf: fileURL, encoding: .utf8)
            if hasMainBlock(in: source) {
                matches.append(fileURL)
            }
        }

        if matches.isEmpty {
            throw ValidationError("Missing @main block in \(root.path)")
        }
        if matches.count > 1 {
            let names = matches.map(\.lastPathComponent).sorted().joined(separator: ", ")
            throw ValidationError("Found multiple @main modules: \(names)")
        }
        return matches[0]
    }

    private func hasMainBlock(in source: String) -> Bool {
        source.range(of: #"@main\s*\{"#, options: .regularExpression) != nil
    }
}
