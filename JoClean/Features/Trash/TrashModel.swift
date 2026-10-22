//
//  TrashModel.swift
//  JoClean
//

import Foundation

/// Reads and empties the user's Trash.
@Observable
final class TrashModel {
    private(set) var items: [CleanupItem] = []
    private(set) var isScanning = false
    private(set) var isEmptying = false
    private(set) var hasScanned = false
    /// True when macOS refused to list the Trash (Full Disk Access is required).
    private(set) var needsFullDiskAccess = false
    var lastResult: RemovalResult?

    var totalSize: Int64 { items.reduce(0) { $0 + $1.size } }

    func scan() async {
        guard !isScanning else { return }
        isScanning = true
        let scan = await Self.scanTrash()
        items = scan.items
        needsFullDiskAccess = !scan.readable
        isScanning = false
        hasScanned = true
    }

    /// Permanently deletes everything in the Trash.
    func empty() async {
        guard !items.isEmpty, !isEmptying else { return }
        isEmptying = true
        lastResult = await FileUtilities.removeInBackground(items, permanently: true)
        isEmptying = false
        await scan()
    }

    @concurrent
    nonisolated private static func scanTrash() async -> (items: [CleanupItem], readable: Bool) {
        let trash = FileUtilities.home.appending(path: ".Trash", directoryHint: .isDirectory)
        guard (try? FileManager.default.contentsOfDirectory(atPath: trash.path)) != nil else {
            return ([], false)
        }
        return (FileUtilities.childrenWithSizes(of: trash), true)
    }
}
