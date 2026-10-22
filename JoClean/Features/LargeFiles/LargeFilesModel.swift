//
//  LargeFilesModel.swift
//  JoClean
//

import Foundation

nonisolated struct LargeFile: Identifiable, Hashable, Sendable {
    let url: URL
    let size: Int64
    let modified: Date?
    let lastOpened: Date?

    var id: URL { url }
    var name: String { url.lastPathComponent }
    var kind: String { url.pathExtension.isEmpty ? "—" : url.pathExtension.uppercased() }
    var folder: String { url.deletingLastPathComponent().path(percentEncoded: false) }

    // Non-optional values so `Table` columns can sort by them.
    var modifiedSortKey: Date { modified ?? .distantPast }
    var lastOpenedSortKey: Date { lastOpened ?? .distantPast }
}

/// Age filter for "old" files, based on modification date.
enum FileAgeFilter: String, CaseIterable, Identifiable {
    case any, sixMonths, oneYear, twoYears

    var id: String { rawValue }

    var title: String {
        switch self {
        case .any: "Any age"
        case .sixMonths: "Older than 6 months"
        case .oneYear: "Older than 1 year"
        case .twoYears: "Older than 2 years"
        }
    }

    var cutoffDate: Date? {
        let calendar = Calendar.current
        switch self {
        case .any: return nil
        case .sixMonths: return calendar.date(byAdding: .month, value: -6, to: .now)
        case .oneYear: return calendar.date(byAdding: .year, value: -1, to: .now)
        case .twoYears: return calendar.date(byAdding: .year, value: -2, to: .now)
        }
    }
}

/// Finds large and old files inside a folder (the home folder by default).
@Observable
final class LargeFilesModel {
    var rootURL: URL = FileUtilities.home
    var minimumSizeMB = 100
    var ageFilter: FileAgeFilter = .any
    var sortOrder = [KeyPathComparator(\LargeFile.size, order: .reverse)]
    var selection: Set<URL> = []
    private(set) var files: [LargeFile] = []
    private(set) var isScanning = false
    private(set) var isRemoving = false
    private(set) var hasScanned = false
    var lastResult: RemovalResult?

    private var scanTask: Task<Void, Never>?

    var sortedFiles: [LargeFile] { files.sorted(using: sortOrder) }
    var totalSize: Int64 { files.reduce(0) { $0 + $1.size } }
    var selectedFiles: [LargeFile] { files.filter { selection.contains($0.url) } }
    var selectedSize: Int64 { selectedFiles.reduce(0) { $0 + $1.size } }

    func scan() {
        scanTask?.cancel()
        isScanning = true
        lastResult = nil
        selection = []
        let root = rootURL
        let minimumSize = Int64(minimumSizeMB) * 1_000_000
        let cutoff = ageFilter.cutoffDate

        scanTask = Task {
            let found = await Self.findLargeFiles(in: root, minimumSize: minimumSize, modifiedBefore: cutoff)
            guard !Task.isCancelled else { return }
            files = found
            isScanning = false
            hasScanned = true
        }
    }

    func cancelScan() {
        scanTask?.cancel()
        scanTask = nil
        isScanning = false
    }

    func removeSelected() async {
        let targets = selectedFiles.map { CleanupItem(url: $0.url, size: $0.size) }
        guard !targets.isEmpty, !isRemoving else { return }
        isRemoving = true
        let result = await FileUtilities.removeInBackground(targets, permanently: false)
        lastResult = result
        let removed = Set(targets.map(\.url)).subtracting(result.failures)
        files.removeAll { removed.contains($0.url) }
        selection.subtract(removed)
        isRemoving = false
    }

    @concurrent
    nonisolated private static func findLargeFiles(in root: URL, minimumSize: Int64, modifiedBefore cutoff: Date?) async -> [LargeFile] {
        let keys: Set<URLResourceKey> = [
            .isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey,
            .contentModificationDateKey, .contentAccessDateKey
        ]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else { return [] }

        // ~/Library holds app data that should be cleaned by other modules, not by hand.
        func normalizedPath(_ url: URL) -> String {
            var path = url.standardizedFileURL.path(percentEncoded: false)
            while path.count > 1 && path.hasSuffix("/") { path.removeLast() }
            return path
        }
        let libraryPath = normalizedPath(FileUtilities.library)
        var found: [LargeFile] = []

        while let url = enumerator.nextObject() as? URL {
            if Task.isCancelled { return [] }
            if normalizedPath(url) == libraryPath {
                enumerator.skipDescendants()
                continue
            }
            guard let values = try? url.resourceValues(forKeys: keys), values.isRegularFile == true else { continue }
            let size = Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
            guard size >= minimumSize else { continue }
            if let cutoff, let modified = values.contentModificationDate, modified > cutoff { continue }
            found.append(LargeFile(
                url: url,
                size: size,
                modified: values.contentModificationDate,
                lastOpened: values.contentAccessDate
            ))
        }
        return found
    }
}
