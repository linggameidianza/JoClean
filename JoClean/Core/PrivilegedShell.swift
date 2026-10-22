//
//  PrivilegedShell.swift
//  JoClean
//

import Foundation

/// Runs shell scripts, optionally as root through the standard macOS administrator password prompt.
///
/// The password is entered in the system's own authentication dialog (via `osascript`'s
/// `do shell script … with administrator privileges`); JoClean never sees it.
nonisolated enum PrivilegedShell {
    enum ShellError: LocalizedError, Equatable {
        case cancelled
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .cancelled: "Administrator authorization was canceled."
            case .failed(let message): message.isEmpty ? "The command failed." : message
            }
        }
    }

    /// Single-quotes a value for `/bin/sh`, e.g. `it's` → `'it'\''s'`.
    static func quote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Escapes a value for use inside an AppleScript string literal.
    static func escapeAppleScript(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// Writes `script` to a private temporary file and runs it. Returns standard output.
    @concurrent
    static func run(script: String, asAdministrator: Bool, prompt: String) async throws -> String {
        // Per-user temporary directory (already mode 0700), plus a private 0700 subfolder.
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "JoClean-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }

        let scriptURL = directory.appending(path: "run.sh")
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptURL.path(percentEncoded: false))

        let process = Process()
        let command = "/bin/sh " + quote(scriptURL.path(percentEncoded: false))
        if asAdministrator {
            process.executableURL = URL(filePath: "/usr/bin/osascript")
            process.arguments = [
                "-e",
                "do shell script \"\(escapeAppleScript(command))\" with prompt \"\(escapeAppleScript(prompt))\" with administrator privileges without altering line endings"
            ]
        } else {
            process.executableURL = URL(filePath: "/bin/sh")
            process.arguments = [scriptURL.path(percentEncoded: false)]
        }

        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        let outputData = output.fileHandleForReading.readDataToEndOfFile()
        let errorData = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let errorText = String(decoding: errorData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard process.terminationStatus == 0 else {
            // osascript reports a canceled password prompt as AppleScript error -128.
            if errorText.contains("-128") || errorText.localizedCaseInsensitiveContains("canceled") {
                throw ShellError.cancelled
            }
            throw ShellError.failed(errorText)
        }
        return String(decoding: outputData, as: UTF8.self)
    }
}
