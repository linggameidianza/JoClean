//
//  UninstallPlanner.swift
//  JoClean
//

import Foundation

/// A file or folder that belongs to an app outside its bundle.
nonisolated struct LeftoverItem: Identifiable, Hashable, Sendable {
    enum Kind: String, Sendable {
        case userData, systemData, launchAgent, launchDaemon, helperTool

        var title: String {
            switch self {
            case .userData: "User data"
            case .systemData: "System-wide data"
            case .launchAgent: "Launch Agent"
            case .launchDaemon: "Launch Daemon"
            case .helperTool: "Privileged Helper"
            }
        }
    }

    let url: URL
    let size: Int64
    let kind: Kind
    /// The current user can't move it to the Trash (root-owned, or in a root-owned folder).
    let requiresAdmin: Bool

    var id: URL { url }
    var name: String { url.lastPathComponent }
    var isLaunchJob: Bool { kind == .launchAgent || kind == .launchDaemon }
}

/// A vendor-provided uninstaller (script or app) that removes system components cleanly.
nonisolated struct OfficialUninstaller: Hashable, Sendable {
    enum Kind: Sendable { case script, app }
    let url: URL
    let kind: Kind
}

/// Everything needed to remove an app completely.
nonisolated struct UninstallAnalysis: Sendable {
    var leftovers: [LeftoverItem] = []
    var officialUninstaller: OfficialUninstaller?
    var appRequiresAdmin = false
    /// The app ships a system extension (VPN, network filter, endpoint security…).
    var hasSystemExtension = false
    /// Installer receipts (`pkgutil`) to forget after removal.
    var packageIDs: [String] = []
}

/// Finds an app's leftovers (in ~/Library and /Library) and builds the removal script.
nonisolated enum UninstallPlanner {
    static let userFolders = [
        "Application Support", "Application Scripts", "Caches", "Containers", "Group Containers",
        "Preferences", "Logs", "Saved Application State", "HTTPStorages", "WebKit", "Cookies", "LaunchAgents"
    ]
    static let systemFolders = [
        "Application Support", "Caches", "Preferences", "Logs", "LaunchAgents", "LaunchDaemons", "PrivilegedHelperTools"
    ]

    // MARK: Matching

    /// Reverse-DNS prefixes that identify the app's files: the bundle ID, plus its parent when the
    /// parent ends with the app's name (`com.vendor.GlobalProtect.client` → `com.vendor.globalprotect`).
    static func matchPrefixes(bundleIdentifier: String?, appName: String) -> [String] {
        guard let bundleID = bundleIdentifier?.lowercased(), !bundleID.isEmpty else { return [] }
        var prefixes = [bundleID]
        let parts = bundleID.split(separator: ".")
        if parts.count >= 3, parts[parts.count - 2] == Substring(compactName(appName)) {
            prefixes.append(parts.dropLast().joined(separator: "."))
        }
        return prefixes
    }

    /// Lowercased letters and digits only: "Acme Tool's" → "acmetools".
    static func compactName(_ name: String) -> String {
        String(name.lowercased().unicodeScalars.filter(CharacterSet.alphanumerics.contains).map(Character.init))
    }

    /// Second reverse-DNS component, e.g. "paloaltonetworks" for `com.paloaltonetworks.…`.
    static func vendorToken(bundleIdentifier: String?) -> String? {
        let parts = bundleIdentifier?.lowercased().split(separator: ".") ?? []
        return parts.count >= 3 ? String(parts[1]) : nil
    }

    static func nameMatches(_ name: String, appName: String, prefixes: [String]) -> Bool {
        let name = name.lowercased()
        if name == appName.lowercased() { return true }
        return prefixes.contains { prefix in
            // "com.foo.app", "com.foo.app.plist", "com.foo.app.savedState", "TEAMID.com.foo.app"
            name == prefix || name.hasPrefix(prefix + ".") || name.hasSuffix("." + prefix)
        }
    }

    /// A launchd job belongs to the app if its program lives inside the app bundle.
    static func launchJobRunsInside(_ plist: URL, appURL: URL) -> Bool {
        guard let dictionary = NSDictionary(contentsOf: plist) else { return false }
        let arguments = dictionary["ProgramArguments"] as? [String]
        guard let program = dictionary["Program"] as? String ?? arguments?.first else { return false }
        return program.hasPrefix(appURL.path(percentEncoded: false).trimmingSuffix("/") + "/")
    }

    // MARK: Analysis

    static func analyze(
        appURL: URL,
        appName: String,
        bundleIdentifier: String?,
        userLibrary: URL = FileUtilities.library,
        systemLibrary: URL = URL(filePath: "/Library")
    ) -> UninstallAnalysis {
        let prefixes = matchPrefixes(bundleIdentifier: bundleIdentifier, appName: appName)
        let vendor = vendorToken(bundleIdentifier: bundleIdentifier)
        var found: [URL: LeftoverItem] = [:]

        func add(_ url: URL, kind: LeftoverItem.Kind) {
            guard found[url] == nil, isSafeToRemove(url, userLibrary: userLibrary, systemLibrary: systemLibrary) else { return }
            found[url] = LeftoverItem(
                url: url,
                size: max(FileUtilities.allocatedSize(of: url), 0),
                kind: kind,
                requiresAdmin: requiresAdmin(url)
            )
        }

        for (library, folders, isSystem) in [(userLibrary, userFolders, false), (systemLibrary, systemFolders, true)] {
            for folder in folders {
                let directory = library.appending(path: folder, directoryHint: .isDirectory)
                let children = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
                let kind = kind(forFolder: folder, isSystem: isSystem)

                for child in children {
                    let isLaunchFolder = folder == "LaunchAgents" || folder == "LaunchDaemons"
                    if nameMatches(child.lastPathComponent, appName: appName, prefixes: prefixes)
                        || (isLaunchFolder && launchJobRunsInside(child, appURL: appURL)) {
                        add(child, kind: kind)
                    }
                    // Vendor folders, e.g. "/Library/Application Support/PaloAltoNetworks/GlobalProtect".
                    if folder == "Application Support" || folder == "Logs",
                       let vendor, child.lastPathComponent.lowercased() == vendor {
                        let nested = (try? FileManager.default.contentsOfDirectory(at: child, includingPropertiesForKeys: nil)) ?? []
                        for item in nested where nameMatches(item.lastPathComponent, appName: appName, prefixes: prefixes) {
                            add(item, kind: kind)
                        }
                    }
                }
            }
        }

        let systemExtensions = appURL.appending(path: "Contents/Library/SystemExtensions")
        return UninstallAnalysis(
            leftovers: found.values.sorted { ($0.requiresAdmin ? 0 : 1, -$0.size) < ($1.requiresAdmin ? 0 : 1, -$1.size) },
            officialUninstaller: findOfficialUninstaller(appURL: appURL, appName: appName, vendor: vendor),
            appRequiresAdmin: requiresAdmin(appURL),
            hasSystemExtension: !((try? FileManager.default.contentsOfDirectory(atPath: systemExtensions.path(percentEncoded: false))) ?? []).isEmpty,
            packageIDs: packageReceipts(for: appURL, appName: appName, vendor: vendor)
        )
    }

    private static func kind(forFolder folder: String, isSystem: Bool) -> LeftoverItem.Kind {
        switch folder {
        case "LaunchAgents": .launchAgent
        case "LaunchDaemons": .launchDaemon
        case "PrivilegedHelperTools": .helperTool
        default: isSystem ? .systemData : .userData
        }
    }

    /// Moving an item needs write access to its parent folder — and, for a folder or bundle, to the
    /// folder itself (macOS updates its ".." entry). Root-owned items therefore need admin rights,
    /// even inside /Applications, which admins can otherwise write to.
    static func requiresAdmin(_ url: URL) -> Bool {
        let path = url.path(percentEncoded: false)
        let fileManager = FileManager.default
        guard fileManager.isDeletableFile(atPath: path) else { return true }
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue {
            return !fileManager.isWritableFile(atPath: path)
        }
        return false
    }

    /// Looks for an uninstaller inside the bundle, or an "Uninstall …" app next to it.
    static func findOfficialUninstaller(appURL: URL, appName: String, vendor: String?) -> OfficialUninstaller? {
        let fileManager = FileManager.default
        for folder in ["Contents/Resources", "Contents/MacOS", "Contents/SharedSupport", "Contents/Helpers"] {
            let directory = appURL.appending(path: folder)
            let children = (try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
            for child in children.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
            where child.lastPathComponent.lowercased().contains("uninstall") {
                switch child.pathExtension.lowercased() {
                case "app":
                    return OfficialUninstaller(url: child, kind: .app)
                case "sh", "command", "tool":
                    return OfficialUninstaller(url: child, kind: .script)
                case "" where fileManager.isExecutableFile(atPath: child.path(percentEncoded: false)):
                    return OfficialUninstaller(url: child, kind: .script)
                default:
                    continue
                }
            }
        }

        let compactAppName = compactName(appName)
        let siblings = (try? fileManager.contentsOfDirectory(at: appURL.deletingLastPathComponent(), includingPropertiesForKeys: nil)) ?? []
        for sibling in siblings where sibling.pathExtension == "app" && sibling != appURL {
            let name = compactName(sibling.deletingPathExtension().lastPathComponent)
            if name.contains("uninstall"), name.contains(compactAppName) || (vendor.map(name.contains) ?? false) {
                return OfficialUninstaller(url: sibling, kind: .app)
            }
        }
        return nil
    }

    /// Installer receipts whose install location is this app (so `pkgutil` forgets them afterwards).
    static func packageReceipts(for appURL: URL, appName: String, vendor: String?) -> [String] {
        let tokens = [vendor, compactName(appName)].compactMap { $0 }.filter { !$0.isEmpty }
        let relativePath = appURL.path(percentEncoded: false).trimmingPrefix("/").trimmingSuffix("/")
        let candidates = run("/usr/sbin/pkgutil", ["--pkgs"])
            .split(separator: "\n").map(String.init)
            .filter { id in tokens.contains { id.lowercased().contains($0) } }
        return candidates.filter { id in
            run("/usr/sbin/pkgutil", ["--pkg-info", id])
                .split(separator: "\n")
                .contains { $0 == "location: \(relativePath)" || $0 == "location: /\(relativePath)" }
        }
    }

    private static func run(_ tool: String, _ arguments: [String]) -> String {
        let process = Process()
        process.executableURL = URL(filePath: tool)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: Safety

    /// Never touch system roots or the folders we search in — only items *inside* them.
    static func isSafeToRemove(_ url: URL, userLibrary: URL = FileUtilities.library, systemLibrary: URL = URL(filePath: "/Library")) -> Bool {
        let path = url.standardizedFileURL.path(percentEncoded: false).trimmingSuffix("/")
        guard path.hasPrefix("/"), !path.hasPrefix("/System/"), url.standardizedFileURL.pathComponents.count >= 3 else {
            return false
        }
        let home = FileUtilities.home.path(percentEncoded: false).trimmingSuffix("/")
        var protected: Set<String> = [
            "/", "/Applications", "/Library", "/System", "/Users", "/usr", "/bin", "/sbin", "/private",
            "/var", "/etc", "/opt", "/Volumes", home, home + "/Applications", home + "/Library",
            userLibrary.path(percentEncoded: false).trimmingSuffix("/"),
            systemLibrary.path(percentEncoded: false).trimmingSuffix("/")
        ]
        for folder in userFolders { protected.insert(userLibrary.appending(path: folder).path(percentEncoded: false).trimmingSuffix("/")) }
        for folder in systemFolders { protected.insert(systemLibrary.appending(path: folder).path(percentEncoded: false).trimmingSuffix("/")) }
        return !protected.contains(path)
    }

    // MARK: Removal script

    /// Shell script that stops the app's launchd jobs, moves everything to the user's Trash
    /// (re-owned by the user so it can be restored or emptied normally) and forgets receipts.
    /// Prints `REMOVED:<path>` / `FAILED:<path>` per item.
    static func removalScript(
        items: [URL],
        launchJobs: [LeftoverItem],
        packageIDs: [String],
        trashDirectory: URL,
        userID: UInt32
    ) -> String {
        let q = PrivilegedShell.quote
        var lines = [
            "#!/bin/sh",
            "TRASH=\(q(trashDirectory.path(percentEncoded: false)))",
            "OWNER=\(userID)",
            "mkdir -p \"$TRASH\"",
            "move_to_trash() {",
            "  src=\"$1\"",
            "  if [ ! -e \"$src\" ] && [ ! -L \"$src\" ]; then echo \"REMOVED:$src\"; return 0; fi",
            "  base=$(basename \"$src\")",
            "  dest=\"$TRASH/$base\"",
            "  n=2",
            "  while [ -e \"$dest\" ] || [ -L \"$dest\" ]; do dest=\"$TRASH/$base $n\"; n=$((n+1)); done",
            "  if mv \"$src\" \"$dest\"; then chown -R \"$OWNER\" \"$dest\" 2>/dev/null; echo \"REMOVED:$src\"; else echo \"FAILED:$src\"; fi",
            "}"
        ]
        // Stop background jobs first so their files aren't in use.
        for job in launchJobs {
            let domain = job.kind == .launchDaemon ? "system" : "gui/\(userID)"
            lines.append("launchctl bootout \(domain) \(q(job.url.path(percentEncoded: false))) >/dev/null 2>&1")
        }
        if !launchJobs.isEmpty { lines.append("sleep 1") }

        for item in items where isSafeToRemove(item) {
            lines.append("move_to_trash \(q(item.path(percentEncoded: false)))")
        }
        for id in packageIDs {
            lines.append("pkgutil --forget \(q(id)) >/dev/null 2>&1")
        }
        lines.append("exit 0")
        return lines.joined(separator: "\n") + "\n"
    }

    /// Parses the script's `REMOVED:` / `FAILED:` lines.
    static func parseRemovalOutput(_ output: String) -> (removed: [URL], failed: [URL]) {
        var removed: [URL] = []
        var failed: [URL] = []
        for line in output.split(whereSeparator: \.isNewline) {
            if line.hasPrefix("REMOVED:") { removed.append(URL(filePath: String(line.dropFirst(8)))) }
            if line.hasPrefix("FAILED:") { failed.append(URL(filePath: String(line.dropFirst(7)))) }
        }
        return (removed, failed)
    }
}

nonisolated private extension String {
    func trimmingSuffix(_ suffix: String) -> String {
        var value = self
        while value.count > 1 && value.hasSuffix(suffix) { value.removeLast(suffix.count) }
        return value
    }

    func trimmingPrefix(_ prefix: String) -> String {
        var value = Substring(self)
        while value.hasPrefix(prefix) { value = value.dropFirst(prefix.count) }
        return String(value)
    }
}
