//
//  FileUtilities.swift
//  JoClean
//

import Foundation

/// A file or folder that can be removed to reclaim disk space.
nonisolated struct CleanupItem: Identifiable, Hashable, Sendable {
    let url: URL
    let size: Int64

    var id: URL { url }
    var name: String { url.lastPathComponent }
}

/// The outcome of removing a batch of items.
nonisolated struct RemovalResult: Sendable {
    var removedBytes: Int64 = 0
    var removedCount = 0
    var failures: [URL] = []
}

nonisolated extension Int64 {
    /// Human readable byte count, e.g. "1,2 GB".
    var formattedBytes: String { formatted(.byteCount(style: .file)) }
}

nonisolated extension UInt64 {
    var formattedBytes: String { Int64(clamping: self).formattedBytes }
}

/// File system helpers shared by every cleaning module.
/// All functions are synchronous and meant to be called from background tasks.
nonisolated enum FileUtilities {
    static var home: URL { FileManager.default.homeDirectoryForCurrentUser }
    static var library: URL { home.appending(path: "Library", directoryHint: .isDirectory) }

    private static let sizeKeys: Set<URLResourceKey> = [
        .isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey,
        .totalFileAllocatedSizeKey, .fileAllocatedSizeKey
    ]

    /// Returns the on-disk size of a file, or the recursive size of a directory (including bundles).
    static func allocatedSize(of url: URL) -> Int64 {
        guard let values = try? url.resourceValues(forKeys: sizeKeys) else { return 0 }
        if values.isSymbolicLink == true { return 0 }
        if values.isDirectory != true {
            return Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }

        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: Array(sizeKeys),
            options: [],
            errorHandler: { _, _ in true }
        ) else { return 0 }

        var total: Int64 = 0
        while let fileURL = enumerator.nextObject() as? URL {
            if Task.isCancelled { break }
            guard let v = try? fileURL.resourceValues(forKeys: sizeKeys), v.isRegularFile == true else { continue }
            total += Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
        }
        return total
    }

    /// Lists the immediate children of a directory with their sizes, largest first. Empty entries are skipped.
    static func childrenWithSizes(of directory: URL, filter: (URL) -> Bool = { _ in true }) -> [CleanupItem] {
        guard let children = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil, options: []
        ) else { return [] }

        return children
            .filter { $0.lastPathComponent != ".DS_Store" && filter($0) }
            .compactMap { child -> CleanupItem? in
                if Task.isCancelled { return nil }
                let size = allocatedSize(of: child)
                return size > 0 ? CleanupItem(url: child, size: size) : nil
            }
            .sorted { $0.size > $1.size }
    }

    /// Moves items to the Trash, or deletes them permanently.
    static func remove(_ items: [CleanupItem], permanently: Bool) -> RemovalResult {
        var result = RemovalResult()
        for item in items {
            do {
                if permanently {
                    try FileManager.default.removeItem(at: item.url)
                } else {
                    try FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
                }
                result.removedBytes += item.size
                result.removedCount += 1
            } catch {
                result.failures.append(item.url)
            }
        }
        return result
    }

    /// Background-thread variant of `remove(_:permanently:)`.
    @concurrent
    static func removeInBackground(_ items: [CleanupItem], permanently: Bool) async -> RemovalResult {
        remove(items, permanently: permanently)
    }
}
