//
//  OptimizationModel.swift
//  JoClean
//

import Foundation
import AppKit

/// A running GUI app with its memory footprint.
struct RunningAppInfo: Identifiable {
    let app: NSRunningApplication
    let memory: UInt64

    var id: pid_t { app.processIdentifier }
    var name: String { app.localizedName ?? "PID \(app.processIdentifier)" }
}

/// A user launch agent (a background helper that starts at login).
nonisolated struct LaunchAgent: Identifiable, Hashable, Sendable {
    let url: URL
    let label: String
    let program: String?
    let size: Int64

    var id: URL { url }
}

/// Shows heavy running apps and login launch agents.
@Observable
final class OptimizationModel {
    private(set) var runningApps: [RunningAppInfo] = []
    private(set) var launchAgents: [LaunchAgent] = []
    var lastResult: RemovalResult?
    private(set) var isScanning = false
    private(set) var hasScanned = false

    /// Runs only when the user presses "Pindai" (never automatically).
    func refresh() async {
        guard !isScanning else { return }
        isScanning = true
        refreshRunningApps()
        launchAgents = await Self.findLaunchAgents()
        isScanning = false
        hasScanned = true
    }

    func refreshRunningApps() {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        runningApps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.processIdentifier != ownPID }
            .map { RunningAppInfo(app: $0, memory: SystemStats.memoryFootprint(of: $0.processIdentifier)) }
            .sorted { $0.memory > $1.memory }
    }

    func quit(_ info: RunningAppInfo, force: Bool = false) {
        if force {
            info.app.forceTerminate()
        } else {
            info.app.terminate()
        }
        // Give the app a moment to exit before refreshing the list.
        Task {
            try? await Task.sleep(for: .seconds(1))
            refreshRunningApps()
        }
    }

    /// Moves a launch agent to the Trash. It stops loading at the next login.
    func remove(_ agent: LaunchAgent) async {
        let item = CleanupItem(url: agent.url, size: agent.size)
        lastResult = await FileUtilities.removeInBackground([item], permanently: false)
        launchAgents = await Self.findLaunchAgents()
    }

    @concurrent
    nonisolated private static func findLaunchAgents() async -> [LaunchAgent] {
        let directory = FileUtilities.library.appending(path: "LaunchAgents", directoryHint: .isDirectory)
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { $0.pathExtension == "plist" }
            .map { url in
                let plist = NSDictionary(contentsOf: url)
                let arguments = plist?["ProgramArguments"] as? [String]
                return LaunchAgent(
                    url: url,
                    label: plist?["Label"] as? String ?? url.deletingPathExtension().lastPathComponent,
                    program: plist?["Program"] as? String ?? arguments?.first,
                    size: FileUtilities.allocatedSize(of: url)
                )
            }
            .sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
    }
}
