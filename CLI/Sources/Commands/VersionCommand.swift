import ArgumentParser
import Foundation

extension CLI {
    struct Version: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Print the installed Range version and available updates."
        )

        @Flag(help: "Skip checking the remote repository for updates.")
        var noCheck: Bool = false

        mutating func run() throws {
            print(
                TerminalLog.style("Range", level: .change, bold: true)
                    + " "
                    + TerminalLog.subtleStdout("\(RangeVersion.current)")
            )
            print(statusLine(label: "Installed", value: installedExecutablePath()))

            guard !noCheck else {
                print(statusLine(label: "Updates", value: "not checked", level: .waiting))
                print(statusLine(label: "Checked", value: "not checked"))
                return
            }

            let canAnimate = Platform.isTerminal(Platform.standardOutputFileDescriptor)
            if canAnimate {
                print(statusLine(label: "Updates", value: "checking...", level: .waiting))
                print(statusLine(label: "Checked", value: "checking...", level: .waiting))
            }

            let result = runCheckWithSpinner(canAnimate: canAnimate)
            do {
                let status = try result.get()
                replaceCheckLines(
                    updates: updateText(for: status),
                    checked: status.checkedRepository,
                    updatesLevel: updateLevel(for: status)
                )
            } catch {
                replaceCheckLines(
                    updates: "unavailable",
                    checked: ErrorDescription.message(for: error),
                    updatesLevel: .error,
                    checkedLevel: .error
                )
            }
        }

        private func runCheckWithSpinner(canAnimate: Bool) -> Result<VersionUpdateStatus, Error> {
            let box = VersionCheckResultBox()
            let thread = Thread {
                do {
                    box.store(.success(try VersionChecker().check()))
                } catch {
                    box.store(.failure(error))
                }
            }
            thread.start()

            guard canAnimate else {
                while box.load() == nil {
                    Thread.sleep(forTimeInterval: 0.05)
                }
                return box.load()!
            }

            let frames = ["|", "/", "-", "\\"]
            var index = 0
            while box.load() == nil {
                replaceCheckLines(
                    updates: "checking \(frames[index % frames.count])",
                    checked: "checking \(frames[index % frames.count])"
                )
                index += 1
                Thread.sleep(forTimeInterval: 0.1)
            }

            return box.load()!
        }

        private func updateText(for status: VersionUpdateStatus) -> String {
            guard let latest = status.latest else {
                return "no release tags found"
            }
            if status.updateAvailable {
                return "\(latest) available"
            }
            return "up to date"
        }

        private func updateLevel(for status: VersionUpdateStatus) -> CLIStatusLevel {
            guard status.latest != nil else {
                return .warning
            }
            return .success
        }

        private func statusLine(
            label: String,
            value: String,
            level: CLIStatusLevel? = nil
        ) -> String {
            let renderedLabel = TerminalLog.accentStdout("\(label):", color: .change, bold: true)
            let renderedValue: String
            if let level {
                renderedValue = TerminalLog.style(value, level: level)
            } else {
                renderedValue = TerminalLog.subtleStdout(value)
            }
            return "\(renderedLabel) \(renderedValue)"
        }

        private func replaceCheckLines(
            updates: String,
            checked: String,
            updatesLevel: CLIStatusLevel? = nil,
            checkedLevel: CLIStatusLevel? = nil
        ) {
            if Platform.isTerminal(Platform.standardOutputFileDescriptor) {
                fputs("\u{001B}[2A", stdout)
                fputs("\u{001B}[2K", stdout)
                print(statusLine(label: "Updates", value: updates, level: updatesLevel))
                fputs("\u{001B}[2K", stdout)
                print(statusLine(label: "Checked", value: checked, level: checkedLevel))
            } else {
                print(statusLine(label: "Updates", value: updates, level: updatesLevel))
                print(statusLine(label: "Checked", value: checked, level: checkedLevel))
            }
            fflush(stdout)
        }

        private func installedExecutablePath() -> String {
            let executable = CommandLine.arguments.first ?? "range"
            if executable.contains("/") {
                return displayPath(URL(fileURLWithPath: executable).standardizedFileURL.path)
            }

            guard let lookupTool = Platform.defaultExecutableLookupTool else {
                return executable
            }

            let process = Process()
            process.executableURL = lookupTool
            process.arguments = ["which", executable]
            let output = Pipe()
            process.standardOutput = output

            do {
                try process.run()
                process.waitUntilExit()
                if process.terminationStatus == 0 {
                    let data = output.fileHandleForReading.readDataToEndOfFile()
                    let path = String(data: data, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if let path, !path.isEmpty {
                        return displayPath(path)
                    }
                }
            } catch {
                return executable
            }

            return executable
        }

        private func displayPath(_ path: String) -> String {
            let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
            if path == home {
                return "~"
            }
            let prefix = home.hasSuffix("/") ? home : home + "/"
            if path.hasPrefix(prefix) {
                return "~/" + path.dropFirst(prefix.count)
            }
            return path
        }
    }
}

private final class VersionCheckResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<VersionUpdateStatus, Error>?

    func store(_ result: Result<VersionUpdateStatus, Error>) {
        lock.lock()
        self.result = result
        lock.unlock()
    }

    func load() -> Result<VersionUpdateStatus, Error>? {
        lock.lock()
        defer { lock.unlock() }
        return result
    }
}
