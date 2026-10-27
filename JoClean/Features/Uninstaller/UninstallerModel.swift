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

/// Lists installed apps and removes them together with their leftover files —
/// including root-owned apps and system-wide components, using the macOS administrator prompt.
@Observable
final class UninstallerModel {
    private(set) var apps: [InstalledApp] = []
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    var selectedAppID: URL? {
        didSet { Task { await loadLeftovers() } }
    }
    private(set) var analysis = UninstallAnalysis()
    var leftoverSelection: Set<URL> = []
    private(set) var isLoadingLeftovers = false
    private(set) var isUninstalling = false
    private(set) var isRunningOfficialUninstaller = false
    var lastResult: RemovalResult?
    /// Whether `lastResult` came from a permanent deletion (vs. moving to the Trash).
    private(set) var lastRemovalWasPermanent = false
    var errorMessage: String?
    var infoMessage: String?

    var selectedApp: InstalledApp? { apps.first { $0.id == selectedAppID } }
    var leftovers: [LeftoverItem] { analysis.leftovers }
    var selectedLeftovers: [LeftoverItem] { leftovers.filter { leftoverSelection.contains($0.url) } }

    var totalUninstallSize: Int64 {
        (selectedApp?.size ?? 0) + selectedLeftovers.reduce(0) { $0 + $1.size }
    }

    /// Whether uninstalling will show the administrator password prompt.
    var requiresAdmin: Bool {
        analysis.appRequiresAdmin || selectedLeftovers.contains(where: \.requiresAdmin)
    }

    var isSelectedAppRunning: Bool {
        guard let bundleID = selectedApp?.bundleIdentifier else { return false }
        return !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    func loadApps() async {
        guard !isLoading else { return }
        isLoading = true
        apps = await Self.findInstalledApps()
        isLoading = false
        hasLoaded = true
    }

    func loadLeftovers() async {
        analysis = UninstallAnalysis()
        leftoverSelection = []
        infoMessage = nil
        guard let app = selectedApp else { return }
        isLoadingLeftovers = true
        let result = await Self.analyze(app)
        // Ignore stale results if the user picked another app meanwhile.
        guard app.id == selectedAppID else { return }
        analysis = result
        leftoverSelection = Set(result.leftovers.map(\.url))
        isLoadingLeftovers = false
    }

    func quitSelectedApp() {
        guard let bundleID = selectedApp?.bundleIdentifier else { return }
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).forEach { $0.terminate() }
    }

    /// Uninstalls the selected app and its selected leftovers — moved to the Trash (default,
    /// recoverable) or deleted permanently.
    func uninstallSelectedApp(permanently: Bool = false) async {
        guard let app = selectedApp, !isUninstalling else { return }
        if isSelectedAppRunning {
            errorMessage = "\(app.name) is running. Quit the app first."
            return
        }

        isUninstalling = true
        defer { isUninstalling = false }

        let leftovers = selectedLeftovers
        let launchJobs = leftovers.filter(\.isLaunchJob)
        let result: RemovalResult

        if requiresAdmin || !launchJobs.isEmpty || !analysis.packageIDs.isEmpty {
            // One script (one password prompt) stops launchd jobs and moves everything to the Trash.
            let script = UninstallPlanner.removalScript(
                items: [app.url] + leftovers.map(\.url),
                launchJobs: launchJobs,
                packageIDs: requiresAdmin ? analysis.packageIDs : [],
                trashDirectory: FileUtilities.home.appending(path: ".Trash", directoryHint: .isDirectory),
                userID: getuid(),
                permanently: permanently
            )
            do {
                let output = try await PrivilegedShell.run(
                    script: script,
                    asAdministrator: requiresAdmin,
                    prompt: permanently
                        ? "JoClean wants to permanently delete \(app.name) and its system components."
                        : "JoClean wants to uninstall \(app.name) and its system components."
                )
                let parsed = UninstallPlanner.parseRemovalOutput(output)
                let sizes = Dictionary(uniqueKeysWithValues: ([CleanupItem(url: app.url, size: app.size)]
                    + leftovers.map { CleanupItem(url: $0.url, size: $0.size) }).map { ($0.url.path(percentEncoded: false), $0.size) })
                var removal = RemovalResult()
                removal.removedCount = parsed.removed.count
                removal.removedBytes = parsed.removed.reduce(0) { $0 + (sizes[$1.path(percentEncoded: false)] ?? 0) }
                removal.failures = parsed.failed
                result = removal
            } catch PrivilegedShell.ShellError.cancelled {
                return
            } catch {
                errorMessage = "Uninstall failed: \(error.localizedDescription)"
                return
            }
        } else {
            let targets = [CleanupItem(url: app.url, size: app.size)] + leftovers.map { CleanupItem(url: $0.url, size: $0.size) }
            result = await FileUtilities.removeInBackground(targets, permanently: permanently)
        }

        lastResult = result
        lastRemovalWasPermanent = permanently
        if FileManager.default.fileExists(atPath: app.url.path(percentEncoded: false)) {
            errorMessage = "\(app.name) couldn’t be removed. If macOS blocked it, allow JoClean in System Settings → Privacy & Security → App Management, or use the app’s official uninstaller."
        } else {
            if analysis.hasSystemExtension {
                infoMessage = "\(app.name) installed a system extension. Restart your Mac to finish removing it."
            }
            apps.removeAll { $0.id == app.id }
            selectedAppID = nil
        }
    }

    /// Runs the vendor's uninstaller (as administrator for scripts; apps are simply opened).
    func runOfficialUninstaller() async {
        guard let app = selectedApp, let uninstaller = analysis.officialUninstaller, !isRunningOfficialUninstaller else { return }

        switch uninstaller.kind {
        case .app:
            NSWorkspace.shared.open(uninstaller.url)
            infoMessage = "The official uninstaller for \(app.name) has been opened. Follow its steps, then click Reload."
        case .script:
            isRunningOfficialUninstaller = true
            defer { isRunningOfficialUninstaller = false }
            let path = uninstaller.url.path(percentEncoded: false)
            let runner = FileManager.default.isExecutableFile(atPath: path) ? PrivilegedShell.quote(path) : "/bin/sh " + PrivilegedShell.quote(path)
            do {
                _ = try await PrivilegedShell.run(
                    script: "#!/bin/sh\n\(runner) >/dev/null 2>&1\nexit 0\n",
                    asAdministrator: true,
                    prompt: "JoClean wants to run the official uninstaller for \(app.name)."
                )
            } catch PrivilegedShell.ShellError.cancelled {
                return
            } catch {
                errorMessage = "The official uninstaller failed: \(error.localizedDescription)"
                return
            }

            if FileManager.default.fileExists(atPath: app.url.path(percentEncoded: false)) {
                errorMessage = "The official uninstaller finished, but \(app.name) is still installed. Try Uninstall instead."
                await loadLeftovers()
            } else {
                infoMessage = "\(app.name) was removed by its official uninstaller."
                apps.removeAll { $0.id == app.id }
                selectedAppID = nil
            }
        }
    }

    @concurrent
    nonisolated private static func analyze(_ app: InstalledApp) async -> UninstallAnalysis {
        UninstallPlanner.analyze(appURL: app.url, appName: app.name, bundleIdentifier: app.bundleIdentifier)
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
}
