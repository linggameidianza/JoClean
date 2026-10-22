//
//  UninstallerModel.swift
//  JoClean
//

import Foundation
import AppKit

nonisolated struct InstalledApp: Identifiable, Hashable, Sendable {
    let url: URL
    let name: String
    let bundleIdentifier: String?
    let version: String?
    let size: Int64

    var id: URL { url }
}

/// Lists installed apps and removes them together with their leftover files.
@Observable
final class UninstallerModel {
    private(set) var apps: [InstalledApp] = []
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    var selectedAppID: URL? {
        didSet { Task { await loadLeftovers() } }
    }
    private(set) var leftovers: [CleanupItem] = []
    var leftoverSelection: Set<URL> = []
    private(set) var isLoadingLeftovers = false
    private(set) var isUninstalling = false
    var lastResult: RemovalResult?
    var errorMessage: String?

    var selectedApp: InstalledApp? { apps.first { $0.id == selectedAppID } }

    var totalUninstallSize: Int64 {
        let leftoverSize = leftovers.filter { leftoverSelection.contains($0.url) }.reduce(0) { $0 + $1.size }
        return (selectedApp?.size ?? 0) + leftoverSize
    }

    func loadApps() async {
        guard !isLoading else { return }
        isLoading = true
        apps = await Self.findInstalledApps()
        isLoading = false
        hasLoaded = true
    }

    func loadLeftovers() async {
        leftovers = []
        leftoverSelection = []
        guard let app = selectedApp else { return }
        isLoadingLeftovers = true
        let found = await Self.findLeftovers(for: app)
        // Ignore stale results if the user picked another app meanwhile.
        guard app.id == selectedAppID else { return }
        leftovers = found
        leftoverSelection = Set(found.map(\.url))
        isLoadingLeftovers = false
    }

    func uninstallSelectedApp() async {
        guard let app = selectedApp, !isUninstalling else { return }

        if let bundleID = app.bundleIdentifier,
           !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty {
            errorMessage = "\(app.name) is running. Quit the app first."
            return
        }

        isUninstalling = true
        var targets = [CleanupItem(url: app.url, size: app.size)]
        targets += leftovers.filter { leftoverSelection.contains($0.url) }
        let result = await FileUtilities.removeInBackground(targets, permanently: false)
        lastResult = result

        if result.failures.contains(app.url) {
            errorMessage = "\(app.name) couldn’t be removed. App Store or system apps may require administrator permission — try deleting it in the Finder."
        } else {
            apps.removeAll { $0.id == app.id }
            selectedAppID = nil
        }
        isUninstalling = false
    }

    // MARK: Scanning

    @concurrent
    nonisolated private static func findInstalledApps() async -> [InstalledApp] {
        let fileManager = FileManager.default
        let roots = [
            URL(filePath: "/Applications", directoryHint: .isDirectory),
            FileUtilities.home.appending(path: "Applications", directoryHint: .isDirectory)
        ]

        // Collect .app bundles at the top level and one folder deep (e.g. "/Applications/Utilities").
        var bundleURLs: [URL] = []
        for root in roots {
            let children = (try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? []
            for child in children {
                if child.pathExtension == "app" {
                    bundleURLs.append(child)
                } else if (try? child.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                    let nested = (try? fileManager.contentsOfDirectory(at: child, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? []
                    bundleURLs += nested.filter { $0.pathExtension == "app" }
                }
            }
        }

        let ownBundleID = Bundle.main.bundleIdentifier
        let apps = await withTaskGroup(of: InstalledApp?.self) { group in
            for url in bundleURLs {
                group.addTask {
                    let bundle = Bundle(url: url)
                    let bundleID = bundle?.bundleIdentifier
                    if bundleID != nil && bundleID == ownBundleID { return nil }
                    return InstalledApp(
                        url: url,
                        name: url.deletingPathExtension().lastPathComponent,
                        bundleIdentifier: bundleID,
                        version: bundle?.infoDictionary?["CFBundleShortVersionString"] as? String,
                        size: FileUtilities.allocatedSize(of: url)
                    )
                }
            }
            var result: [InstalledApp] = []
            for await app in group {
                if let app { result.append(app) }
            }
            return result
        }
        return apps.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Searches ~/Library for files that belong to the app, matched by bundle identifier or exact app name.
    @concurrent
    nonisolated private static func findLeftovers(for app: InstalledApp) async -> [CleanupItem] {
        let folders: [String] = [
            "Application Support", "Application Scripts", "Caches", "Containers", "Group Containers",
            "Preferences", "Logs", "Saved Application State", "HTTPStorages", "WebKit", "Cookies", "LaunchAgents"
        ]
        let bundleID = app.bundleIdentifier?.lowercased()
        let appName = app.name.lowercased()

        func belongsToApp(_ url: URL) -> Bool {
            let name = url.lastPathComponent.lowercased()
            if name == appName { return true }
            guard let bundleID, !bundleID.isEmpty else { return false }
            // Matches "com.foo.app", "com.foo.app.plist", "com.foo.app.savedState",
            // and group containers like "TEAMID.com.foo.app".
            return name == bundleID
                || name.hasPrefix(bundleID + ".")
                || name.hasSuffix("." + bundleID)
        }

        var found: [CleanupItem] = []
        for folder in folders {
            let directory = FileUtilities.library.appending(path: folder, directoryHint: .isDirectory)
            found += FileUtilities.childrenWithSizes(of: directory, filter: belongsToApp)
        }
        return found.sorted { $0.size > $1.size }
    }
}
