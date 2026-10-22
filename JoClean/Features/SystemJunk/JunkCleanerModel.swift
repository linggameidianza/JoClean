//
//  JunkCleanerModel.swift
//  JoClean
//

import Foundation

/// Categories of regenerable or unnecessary files that are safe to clean.
nonisolated enum JunkCategory: String, CaseIterable, Identifiable, Sendable {
    case userCaches
    case userLogs
    case xcodeDerivedData
    case xcodeDeviceSupport
    case simulatorCaches
    case installers

    var id: String { rawValue }

    var title: String {
        switch self {
        case .userCaches: "User Caches"
        case .userLogs: "User Logs"
        case .xcodeDerivedData: "Xcode Derived Data"
        case .xcodeDeviceSupport: "Xcode Device Support"
        case .simulatorCaches: "Simulator Caches"
        case .installers: "Installer Files"
        }
    }

    var subtitle: String {
        switch self {
        case .userCaches: "Temporary files that apps recreate automatically"
        case .userLogs: "App activity logs you no longer need"
        case .xcodeDerivedData: "Xcode build products that can be regenerated"
        case .xcodeDeviceSupport: "Debug symbols for old iOS devices"
        case .simulatorCaches: "Caches from the iOS Simulator"
        case .installers: ".dmg, .pkg, and .xip files in your Downloads folder"
        }
    }

    var systemImage: String {
        switch self {
        case .userCaches: "internaldrive"
        case .userLogs: "doc.text"
        case .xcodeDerivedData: "hammer"
        case .xcodeDeviceSupport: "iphone"
        case .simulatorCaches: "ipad.and.iphone"
        case .installers: "shippingbox"
        }
    }

    /// Finds removable items for this category. Runs synchronously; call from a background task.
    func scan() -> [CleanupItem] {
        let library = FileUtilities.library
        switch self {
        case .userCaches:
            let ownCache = Bundle.main.bundleIdentifier
            return FileUtilities.childrenWithSizes(of: library.appending(path: "Caches")) {
                $0.lastPathComponent != ownCache
            }
        case .userLogs:
            return FileUtilities.childrenWithSizes(of: library.appending(path: "Logs"))
        case .xcodeDerivedData:
            return FileUtilities.childrenWithSizes(of: library.appending(path: "Developer/Xcode/DerivedData"))
        case .xcodeDeviceSupport:
            return FileUtilities.childrenWithSizes(of: library.appending(path: "Developer/Xcode/iOS DeviceSupport"))
        case .simulatorCaches:
            return FileUtilities.childrenWithSizes(of: library.appending(path: "Developer/CoreSimulator/Caches"))
        case .installers:
            let extensions: Set<String> = ["dmg", "pkg", "mpkg", "xip"]
            return FileUtilities.childrenWithSizes(of: FileUtilities.home.appending(path: "Downloads")) {
                extensions.contains($0.pathExtension.lowercased())
            }
        }
    }
}

/// Scans and cleans system junk.
@Observable
final class JunkCleanerModel {
    private(set) var results: [JunkCategory: [CleanupItem]] = [:]
    var selection: Set<URL> = []
    private(set) var isScanning = false
    private(set) var isCleaning = false
    private(set) var hasScanned = false
    var lastResult: RemovalResult?

    var totalSize: Int64 {
        results.values.joined().reduce(0) { $0 + $1.size }
    }

    var selectedItems: [CleanupItem] {
        results.values.joined().filter { selection.contains($0.url) }
    }

    var selectedSize: Int64 {
        selectedItems.reduce(0) { $0 + $1.size }
    }

    func items(in category: JunkCategory) -> [CleanupItem] {
        results[category] ?? []
    }

    func size(of category: JunkCategory) -> Int64 {
        items(in: category).reduce(0) { $0 + $1.size }
    }

    // MARK: Selection

    func isSelected(_ category: JunkCategory) -> Bool {
        let items = items(in: category)
        return !items.isEmpty && items.allSatisfy { selection.contains($0.url) }
    }

    func setSelected(_ category: JunkCategory, _ selected: Bool) {
        let urls = items(in: category).map(\.url)
        if selected {
            selection.formUnion(urls)
        } else {
            selection.subtract(urls)
        }
    }

    func setSelected(_ item: CleanupItem, _ selected: Bool) {
        if selected {
            selection.insert(item.url)
        } else {
            selection.remove(item.url)
        }
    }

    // MARK: Actions

    func scan() async {
        guard !isScanning else { return }
        isScanning = true
        lastResult = nil
        let found = await Self.scanAllCategories()
        results = found
        // Installers are personal files, so they are not pre-selected.
        selection = Set(found.filter { $0.key != .installers }.values.joined().map(\.url))
        isScanning = false
        hasScanned = true
    }

    /// Moves the selected items to the Trash.
    func cleanSelected() async {
        let items = selectedItems
        guard !items.isEmpty, !isCleaning else { return }
        isCleaning = true
        let result = await FileUtilities.removeInBackground(items, permanently: false)
        lastResult = result

        // Drop successfully cleaned items from the results without rescanning.
        let removed = Set(items.map(\.url)).subtracting(result.failures)
        for category in results.keys {
            results[category]?.removeAll { removed.contains($0.url) }
        }
        selection.subtract(removed)
        isCleaning = false
    }

    @concurrent
    nonisolated private static func scanAllCategories() async -> [JunkCategory: [CleanupItem]] {
        await withTaskGroup(of: (JunkCategory, [CleanupItem]).self) { group in
            for category in JunkCategory.allCases {
                group.addTask { (category, category.scan()) }
            }
            var found: [JunkCategory: [CleanupItem]] = [:]
            for await (category, items) in group {
                found[category] = items
            }
            return found
        }
    }
}
