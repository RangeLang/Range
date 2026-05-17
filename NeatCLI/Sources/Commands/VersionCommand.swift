import ArgumentParser
import Foundation

extension NeatCLI {
    struct Version: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Print the installed Neat version and available updates."
        )

        @Flag(help: "Skip checking the remote repository for updates.")
        var noCheck: Bool = false

        mutating func run() throws {
            print("Neat \(NeatVersion.current)")
            print("Installed: \(installedExecutablePath())")

            guard !noCheck else {
                print("Updates: not checked")
                print("Checked: not checked")
                return
            }

            let canAnimate = Platform.isTerminal(Platform.standardOutputFileDescriptor)
            if canAnimate {
                print("Updates: checking...")
                print("Checked: checking...")
            }

            let result = runCheckWithSpinner(canAnimate: canAnimate)
            do {
                let status = try result.get()
                replaceCheckLines(
                    updates: updateText(for: status),
                    checked: status.checkedRepository
                )
            } catch {
                replaceCheckLines(
                    updates: "unavailable",
                    checked: String(describing: error)
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

        private func replaceCheckLines(updates: String, checked: String) {
            if Platform.isTerminal(Platform.standardOutputFileDescriptor) {
                fputs("\u{001B}[2A", stdout)
                fputs("\u{001B}[2K", stdout)
                print("Updates: \(updates)")
                fputs("\u{001B}[2K", stdout)
                print("Checked: \(checked)")
            } else {
                print("Updates: \(updates)")
                print("Checked: \(checked)")
            }
            fflush(stdout)
        }

        private func installedExecutablePath() -> String {
            let executable = CommandLine.arguments.first ?? "neat"
            if executable.contains("/") {
                return URL(fileURLWithPath: executable).standardizedFileURL.path
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
                        return path
                    }
                }
            } catch {
                return executable
            }

            return executable
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
