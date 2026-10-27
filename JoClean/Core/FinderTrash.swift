//
//  FinderTrash.swift
//  JoClean
//

import Foundation

/// Reads and empties the Trash through Finder (Apple Events).
///
/// macOS hides the contents of `~/.Trash` from apps without Full Disk Access, but Finder can always
/// see and empty it. The first use shows the system prompt "JoClean wants to control Finder".
nonisolated enum FinderTrash {
    struct Listing: Sendable, Equatable {
        struct Entry: Sendable, Equatable {
            let name: String
            /// `nil` when Finder hasn't calculated the size (common for folders).
            let size: Int64?
        }
        let totalCount: Int
        let entries: [Entry]
    }

    enum FinderError: LocalizedError, Equatable {
        case notAuthorized
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .notAuthorized: "JoClean isn’t allowed to control Finder."
            case .failed(let message): message.isEmpty ? "Finder couldn’t complete the request." : message
            }
        }
    }

    /// Lists up to `limit` Trash items as "name<TAB>size" lines, preceded by the total count.
    static let listScript = """
    tell application "Finder"
        set trashItems to items of trash
        set total to count of trashItems
        set output to (total as text) & linefeed
        repeat with i from 1 to total
            if i > 500 then exit repeat
            set anItem to item i of trashItems
            set itemSize to -1
            try
                set s to size of anItem
                if s is not missing value then set itemSize to s
            end try
            set output to output & (name of anItem) & tab & (itemSize as text) & linefeed
        end repeat
        return output
    end tell
    """

    static let emptyScript = """
    with timeout of 3600 seconds
        tell application "Finder" to empty trash
    end timeout
    """

    @concurrent
    static func list() async throws -> Listing {
        try parseListing(try run(listScript))
    }

    @concurrent
    static func empty() async throws {
        _ = try run(emptyScript)
    }

    /// Parses `listScript` output. AppleScript prints big sizes as reals ("1.2345E+9"), and some
    /// locales use a decimal comma, so both are accepted.
    static func parseListing(_ output: String) throws -> Listing {
        var lines = output.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let first = lines.first, let total = Int(first.trimmingCharacters(in: .whitespaces)) else {
            throw FinderError.failed("Unexpected response from Finder.")
        }
        lines.removeFirst()
        let entries = lines.compactMap { line -> Listing.Entry? in
            guard let tab = line.lastIndex(of: "\t") else { return nil }
            let name = String(line[..<tab])
            let rawSize = line[line.index(after: tab)...].replacingOccurrences(of: ",", with: ".")
            let size = Double(rawSize).flatMap { $0 >= 0 ? Int64($0) : nil }
            return name.isEmpty ? nil : Listing.Entry(name: name, size: size)
        }
        return Listing(totalCount: total, entries: entries)
    }

    private static func run(_ source: String) throws -> String {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/osascript")
        process.arguments = ["-e", source]
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
            // -1743: the user (or policy) denied Automation access to Finder.
            if errorText.contains("-1743") || errorText.localizedCaseInsensitiveContains("not authorized") {
                throw FinderError.notAuthorized
            }
            throw FinderError.failed(errorText)
        }
        return String(decoding: outputData, as: UTF8.self)
    }
}
