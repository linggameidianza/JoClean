//
//  TrashModel.swift
//  JoClean
//

import Foundation

/// Reads and empties the user's Trash.
///
/// With Full Disk Access the Trash is read directly. Without it, macOS hides `~/.Trash`, so JoClean
/// asks Finder instead (Apple Events) — the same thing Finder's own "Empty Trash" does.
@Observable
final class TrashModel {
    enum AccessMode: Equatable {
        /// Read directly from disk (Full Disk Access granted).
        case direct
        /// Read and emptied through Finder.
        case finder
        /// Neither works yet: needs Full Disk Access or permission to control Finder.
        case unavailable
    }

    private(set) var items: [CleanupItem] = []
    private(set) var isScanning = false
    private(set) var isEmptying = false
    private(set) var hasScanned = false
    private(set) var accessMode: AccessMode = .direct
    /// Items in the Trash (Finder lists at most 500 by name, but always reports the full count).
    private(set) var itemCount = 0
    /// Some sizes are unknown (Finder doesn't always calculate folder sizes).
    private(set) var sizeIsIncomplete = false
    var lastResult: RemovalResult?
    var errorMessage: String?

    var totalSize: Int64 { items.reduce(0) { $0 + $1.size } }
    var needsPermission: Bool { accessMode == .unavailable }
    /// Kept for Smart Scan's hint banner.
    var needsFullDiskAccess: Bool { accessMode == .unavailable }

    /// UI tests can't answer the Automation prompt, so they may turn the Finder fallback off.
    private let finderFallbackEnabled = !ProcessInfo.processInfo.arguments.contains("-JoCleanDisableFinderTrash")

    nonisolated static var trashURL: URL { FileUtilities.home.appending(path: ".Trash", directoryHint: .isDirectory) }

    func scan() async {
        guard !isScanning else { return }
        isScanning = true
        defer {
            isScanning = false
            hasScanned = true
        }
        errorMessage = nil

        if let direct = await Self.scanDirectly() {
            accessMode = .direct
            items = direct
            itemCount = direct.count
            sizeIsIncomplete = false
            return
        }

        guard finderFallbackEnabled else {
            accessMode = .unavailable
            items = []
            itemCount = 0
            return
        }
        do {
            let listing = try await FinderTrash.list()
            accessMode = .finder
            itemCount = listing.totalCount
            items = listing.entries.map {
                CleanupItem(url: Self.trashURL.appending(path: $0.name), size: $0.size ?? 0)
            }
            sizeIsIncomplete = listing.entries.contains { $0.size == nil } || listing.totalCount > listing.entries.count
        } catch {
            accessMode = .unavailable
            items = []
            itemCount = 0
            if case FinderTrash.FinderError.failed(let message) = error, !message.isEmpty {
                errorMessage = message
            }
        }
    }

    /// Permanently deletes everything in the Trash.
    func empty() async {
        guard itemCount > 0, !isEmptying else { return }
        isEmptying = true
        defer { isEmptying = false }
        errorMessage = nil

        let countBefore = itemCount
        let sizeBefore = totalSize

        switch accessMode {
        case .direct:
            var result = await FileUtilities.removeInBackground(items, permanently: true)
            // Locked or root-owned items can't be deleted directly — let Finder handle the rest
            // (it asks for an administrator password when needed).
            if !result.failures.isEmpty, finderFallbackEnabled {
                do {
                    try await FinderTrash.empty()
                    result.removedCount += result.failures.count
                    result.removedBytes = sizeBefore
                    result.failures = []
                } catch {
                    errorMessage = "Some items couldn’t be deleted: \(error.localizedDescription)"
                }
            }
            lastResult = result
        case .finder:
            do {
                try await FinderTrash.empty()
                var result = RemovalResult()
                result.removedCount = countBefore
                result.removedBytes = sizeBefore
                lastResult = result
            } catch {
                errorMessage = "Finder couldn’t empty the Trash: \(error.localizedDescription)"
            }
        case .unavailable:
            return
        }
        await scan()
    }

    /// `nil` when macOS doesn't let JoClean read the Trash (no Full Disk Access).
    @concurrent
    nonisolated private static func scanDirectly() async -> [CleanupItem]? {
        guard (try? FileManager.default.contentsOfDirectory(atPath: trashURL.path(percentEncoded: false))) != nil else {
            return nil
        }
        return FileUtilities.childrenWithSizes(of: trashURL)
    }
}
