import Foundation
import os

struct ShellResult: Sendable {
    let status: Int32
    let output: String
    let error: String

    var succeeded: Bool { status == 0 }
}

enum ShellError: LocalizedError {
    case launchFailed(String)
    case failed(String)
    case cancelledByUser

    var errorDescription: String? {
        switch self {
        case .launchFailed(let message): "Could not start the command: \(message)"
        case .failed(let message): message.isEmpty ? "The command failed." : message
        case .cancelledByUser: "Cancelled."
        }
    }
}

/// Runs command-line tools. Executables are launched directly (no shell) unless
/// a method says otherwise.
enum Shell {
    static func run(_ executable: String, _ arguments: [String] = []) async throws -> ShellResult {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    continuation.resume(returning: try runSync(executable, arguments))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Blocking variant for code that already runs on a background thread.
    static func runSync(_ executable: String, _ arguments: [String] = []) throws -> ShellResult {
        let process = Process()
        process.executableURL = URL(filePath: executable)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
        } catch {
            throw ShellError.launchFailed(error.localizedDescription)
        }

        // Drain both pipes concurrently; a full pipe would otherwise block the child forever.
        let errData = OSAllocatedUnfairLock(initialState: Data())
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            let data = errPipe.fileHandleForReading.readDataToEndOfFile()
            errData.withLock { $0 = data }
            group.leave()
        }
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        group.wait()
        process.waitUntilExit()

        return ShellResult(
            status: process.terminationStatus,
            output: String(decoding: outData, as: UTF8.self),
            error: errData.withLock { String(decoding: $0, as: UTF8.self) }
        )
    }

    /// Runs `command` through /bin/sh as root. macOS shows its standard
    /// administrator password dialog first.
    @discardableResult
    static func runAsAdmin(_ command: String, prompt: String? = nil) async throws -> ShellResult {
        var script = "do shell script \"\(appleScriptEscaped(command))\" with administrator privileges"
        if let prompt {
            script += " with prompt \"\(appleScriptEscaped(prompt))\""
        }
        let result = try await run("/usr/bin/osascript", ["-e", script])
        guard result.succeeded else {
            if result.error.contains("(-128)") || result.error.localizedCaseInsensitiveContains("user canceled") {
                throw ShellError.cancelledByUser
            }
            throw ShellError.failed(result.error.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return result
    }

    /// Wraps a string in single quotes for /bin/sh.
    static func quoted(_ string: String) -> String {
        "'" + string.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func appleScriptEscaped(_ string: String) -> String {
        string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
