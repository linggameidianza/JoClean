//
//  JoCleanTests.swift
//  JoCleanTests
//
//  Created by ichio on 22/10/26.
//

import Testing
import Foundation
@testable import JoClean

@Suite("VirusTotal malware check")
struct MalwareCheckTests {

    /// Trimmed copy of a real `GET /api/v3/files/{id}` response.
    private let sampleJSON = """
    {
      "data": {
        "id": "275a021bbfb6489e54d471899f7db9d1663fc695ec2fe2a2c4538aabf651fd0f",
        "type": "file",
        "attributes": {
          "last_analysis_date": 1729500000,
          "last_analysis_stats": {
            "malicious": 62, "suspicious": 1, "undetected": 7, "harmless": 0,
            "timeout": 1, "confirmed-timeout": 0, "failure": 0, "type-unsupported": 4
          },
          "popular_threat_classification": { "suggested_threat_label": "virus.eicar/test" },
          "meaningful_name": "eicar.com"
        }
      }
    }
    """

    @Test func decodesFileReport() throws {
        let report = try VirusTotalClient.decodeReport(from: Data(sampleJSON.utf8))
        #expect(report.malicious == 62)
        #expect(report.suspicious == 1)
        #expect(report.engineCount == 70)          // timeouts / unsupported are excluded
        #expect(report.threatLabel == "virus.eicar/test")
        #expect(report.analysisDate == Date(timeIntervalSince1970: 1_729_500_000))
        #expect(report.severity == .malicious)
    }

    @Test func rejectsMalformedResponse() {
        #expect(throws: VirusTotalClient.ClientError.invalidResponse) {
            try VirusTotalClient.decodeReport(from: Data(#"{"error":{"code":"NotFoundError"}}"#.utf8))
        }
    }

    @Test(arguments: [
        (0, 0, VTReport.Severity.clean),
        (0, 1, .suspicious),
        (1, 0, .suspicious),   // a single engine is often a false positive
        (2, 3, .suspicious),
        (3, 0, .malicious),
        (40, 2, .malicious)
    ])
    func classifiesSeverity(malicious: Int, suspicious: Int, expected: VTReport.Severity) {
        let report = VTReport(stats: ["malicious": malicious, "suspicious": suspicious, "undetected": 60],
                              threatLabel: nil, analysisDate: nil)
        #expect(report.severity == expected)
    }

    @Test func cacheExpiresByResultType() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let report = VTReport(stats: ["undetected": 70], threatLabel: nil, analysisDate: nil)
        var cache = VTCache()
        cache.store(report, for: "known", now: start)
        cache.store(nil, for: "unknown", now: start)

        // Within 1 day both are cached.
        #expect(cache.lookup("known", now: start.addingTimeInterval(3600)) == .found(report))
        #expect(cache.lookup("unknown", now: start.addingTimeInterval(3600)) == .notFound)

        // After 2 days "unknown" must be re-checked, the known report is still valid.
        let twoDays = start.addingTimeInterval(2 * 24 * 3600)
        #expect(cache.lookup("unknown", now: twoDays) == nil)
        #expect(cache.lookup("known", now: twoDays) == .found(report))

        // After 8 days everything is stale.
        #expect(cache.lookup("known", now: start.addingTimeInterval(8 * 24 * 3600)) == nil)
        #expect(cache.lookup("missing", now: start) == nil)
    }

    @Test func hashesFilesWithSHA256() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "joclean-hash-\(UUID().uuidString).txt")
        try Data("abc".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        // Well-known SHA-256 test vector for "abc".
        #expect(try FileHasher.sha256(of: url) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    @Test func detectsCodeSignatures() throws {
        #expect(MalwareCheckModel.codeSignature(of: URL(filePath: "/bin/ls")) == .apple)

        // A plain text file has no code signature.
        let url = FileManager.default.temporaryDirectory.appending(path: "joclean-sig-\(UUID().uuidString).txt")
        try Data("hello".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let signature = MalwareCheckModel.codeSignature(of: url)
        #expect(signature == .notApplicable || signature == .unsigned)
        #expect(!signature.isTrusted)
    }

    @Test func buildsVirusTotalReportLink() {
        let url = VirusTotalClient.guiURL(forSHA256: VirusTotalClient.eicarSHA256)
        #expect(url?.absoluteString == "https://www.virustotal.com/gui/file/\(VirusTotalClient.eicarSHA256)")
    }
}

@Suite("Local & no-signup malware engines")
struct NoSignupEngineTests {

    // MARK: XProtect / YARA

    @Test func loadsApplesXProtectRules() throws {
        let engine = try XProtectEngine.load()
        #expect(engine.ruleCount > 400)
        #expect(engine.version != "?")
        // A clean system binary must not match any malware signature.
        #expect(try engine.scan(fileURL: URL(filePath: "/bin/ls")).isEmpty)
    }

    @Test func matchesCustomTextAndHexRules() throws {
        let rules = """
        rule TextProbe { meta: description = "TEST.TEXT" strings: $a = "joclean_marker" nocase condition: $a }
        rule HexProbe { strings: $h = { 4A 4F ?? 43 [1-3] 4E } condition: $h and filesize < 1KB }
        rule NeverMatches { strings: $x = "definitely-not-present" condition: $x }
        """
        let engine = try XProtectEngine.compile(sources: [(rules, "Test")], version: "test")
        let url = FileManager.default.temporaryDirectory.appending(path: "yara-\(UUID().uuidString).bin")
        try Data("xx JOCLEAN_MARKER JO_C--N yy".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let matches = try engine.scan(fileURL: url)
        #expect(Set(matches.map(\.rule)) == ["TextProbe", "HexProbe"])
        #expect(matches.first { $0.rule == "TextProbe" }?.displayName == "TEST.TEXT")
        #expect(matches.allSatisfy { $0.namespace == "Test" })
    }

    @Test func reportsInvalidRules() {
        #expect(throws: XProtectEngine.EngineError.self) {
            try XProtectEngine.compile(sources: [("rule Broken { condition: $missing }", "Test")], version: "test")
        }
    }

    // MARK: Gatekeeper

    @Test func parsesSpctlOutput() {
        let accepted = GatekeeperChecker.parse(
            "/A.app: accepted\nsource=Notarized Developer ID\norigin=Developer ID Application: Example (ABC123)\n",
            exitCode: 0
        )
        #expect(accepted.accepted && accepted.source == "Notarized Developer ID")
        #expect(accepted.origin == "Developer ID Application: Example (ABC123)")

        let tool = GatekeeperChecker.parse("/bin/ls: rejected (the code is valid but does not seem to be an app)\n", exitCode: 3)
        #expect(!tool.accepted && tool.isNonAppCode)

        let unsigned = GatekeeperChecker.parse("/x: rejected\nsource=no usable signature\n", exitCode: 3)
        #expect(!unsigned.accepted && !unsigned.isNonAppCode)
        #expect(GatekeeperChecker.label(for: unsigned) == "No valid signature")
    }

    @Test func assessesRealApps() throws {
        let calculator = try #require(GatekeeperChecker.assess(URL(filePath: "/System/Applications/Calculator.app")))
        #expect(calculator.accepted)
        #expect(calculator.source == "Apple System")

        let ls = try #require(GatekeeperChecker.assess(URL(filePath: "/bin/ls")))
        #expect(ls.isNonAppCode)

        // Plain documents are outside Gatekeeper's scope.
        let url = FileManager.default.temporaryDirectory.appending(path: "gk-\(UUID().uuidString).txt")
        try Data("hi".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(GatekeeperChecker.assess(url) == nil)
    }

    // MARK: CIRCL

    @Test func decodesCIRCLRecords() throws {
        let trusted = try CIRCLHashlookupClient.decodeRecord(from: Data("""
        {"FileName": "./usr/bin/tool", "ProductCode": {"ProductName": "Ubuntu"}, "hashlookup:trust": 100, "source": "snap:x"}
        """.utf8))
        #expect(trusted.isTrusted)
        #expect(trusted.fileName == "tool")
        #expect(MalwareCheckModel.circlFinding(trusted).level == .trusted)

        let lowTrust = CIRCLRecord(trust: 10, fileName: nil, productName: nil, source: "x", knownMalicious: nil)
        #expect(MalwareCheckModel.circlFinding(lowTrust).level == .info)

        let malicious = try CIRCLHashlookupClient.decodeRecord(from: Data(#"{"hashlookup:trust": 0, "KnownMalicious": "malshare"}"#.utf8))
        #expect(MalwareCheckModel.circlFinding(malicious).level == .malicious)

        #expect(MalwareCheckModel.circlFinding(nil).level == .info)
        #expect(MalwareCheckModel.circlFinding(nil, failed: true).summary.contains("Couldn’t connect"))
    }

    @Test(.timeLimit(.minutes(1)))
    func looksUpRealHashOnCIRCL() async throws {
        // SHA-256 of an empty file — present in NIST NSRL.
        let known = try await CIRCLHashlookupClient().lookup(sha256: "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        #expect(known != nil)
        let unknown = try await CIRCLHashlookupClient().lookup(sha256: String(repeating: "0", count: 63) + "1")
        #expect(unknown == nil)
    }

    // MARK: Verdict aggregation

    private func entry(_ findings: [EngineFinding]) -> MalwareEntry {
        let target = MalwareTarget(fileURL: URL(filePath: "/tmp/x"), itemURL: URL(filePath: "/tmp/x"),
                                   displayName: "x", category: .custom, signature: .notApplicable)
        var entry = MalwareEntry(target: target)
        entry.findings = findings
        entry.state = .done
        return entry
    }

    @Test func combinesEngineVerdicts() {
        let xpClean = EngineFinding(engine: .xprotect, level: .clean, summary: "")
        let xpHit = EngineFinding(engine: .xprotect, level: .malicious, summary: "Terdeteksi: MACOS.TEST")
        let gkRejected = EngineFinding(engine: .gatekeeper, level: .notice, summary: "")
        let circlTrusted = EngineFinding(engine: .circl, level: .trusted, summary: "")
        let circlUnknown = EngineFinding(engine: .circl, level: .info, summary: "")

        #expect(entry([xpClean, circlTrusted]).verdict == .clean)
        #expect(entry([xpClean, gkRejected, circlUnknown]).verdict == .notice)
        // An XProtect hit wins even if another engine trusts the file.
        #expect(entry([xpHit, circlTrusted]).verdict == .malicious)
        #expect(entry([xpHit, circlTrusted]).headline?.engine == .xprotect)
        #expect(entry([circlUnknown]).verdict == .unknown)
    }
}

@Suite("Uninstaller with administrator support")
struct UninstallerTests {

    /// Builds a throwaway "Library" layout plus a fake app in a temporary folder.
    private struct Sandbox {
        let root: URL
        let userLibrary: URL
        let systemLibrary: URL
        let trash: URL
        let app: URL

        init() throws {
            root = FileManager.default.temporaryDirectory.appending(path: "joclean-uninstall-\(UUID().uuidString)")
            userLibrary = root.appending(path: "home/Library")
            systemLibrary = root.appending(path: "Library")
            trash = root.appending(path: "home/.Trash")
            // A space and an apostrophe in the path exercise the shell quoting.
            app = root.appending(path: "Applications/Acme Tool's.app")
            let fm = FileManager.default
            for folder in UninstallPlanner.userFolders { try fm.createDirectory(at: userLibrary.appending(path: folder), withIntermediateDirectories: true) }
            for folder in UninstallPlanner.systemFolders { try fm.createDirectory(at: systemLibrary.appending(path: folder), withIntermediateDirectories: true) }
            try fm.createDirectory(at: app.appending(path: "Contents/MacOS"), withIntermediateDirectories: true)
            try fm.createDirectory(at: app.appending(path: "Contents/Resources"), withIntermediateDirectories: true)
            try Data("binary".utf8).write(to: app.appending(path: "Contents/MacOS/AcmeHelper"))
        }

        func write(_ text: String, to relative: String, in base: URL) throws {
            let url = base.appending(path: relative)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url)
        }

        func launchPlist(program: String) -> String {
            """
            <?xml version="1.0" encoding="UTF-8"?>
            <plist version="1.0"><dict>
            <key>Label</key><string>com.acmecorp.agent</string>
            <key>ProgramArguments</key><array><string>\(program)</string></array>
            </dict></plist>
            """
        }
    }

    @Test func derivesMatchPrefixesFromBundleID() {
        #expect(UninstallPlanner.matchPrefixes(bundleIdentifier: "com.paloaltonetworks.GlobalProtect.client", appName: "GlobalProtect")
                == ["com.paloaltonetworks.globalprotect.client", "com.paloaltonetworks.globalprotect"])
        // The parent prefix is only used when it ends with the app's name.
        #expect(UninstallPlanner.matchPrefixes(bundleIdentifier: "com.microsoft.Word", appName: "Microsoft Word") == ["com.microsoft.word"])
        #expect(UninstallPlanner.vendorToken(bundleIdentifier: "com.paloaltonetworks.GlobalProtect.client") == "paloaltonetworks")

        let prefixes = UninstallPlanner.matchPrefixes(bundleIdentifier: "com.paloaltonetworks.GlobalProtect.client", appName: "GlobalProtect")
        #expect(UninstallPlanner.nameMatches("com.paloaltonetworks.GlobalProtect.settings.plist", appName: "GlobalProtect", prefixes: prefixes))
        #expect(!UninstallPlanner.nameMatches("com.paloaltonetworks.cortex.plist", appName: "GlobalProtect", prefixes: prefixes))
    }

    @Test func neverRemovesProtectedFolders() {
        for path in ["/", "/Applications", "/Library", "/Library/LaunchDaemons", "/Library/Application Support",
                     "/System/Library/CoreServices/Finder.app", "/Users"] {
            #expect(!UninstallPlanner.isSafeToRemove(URL(filePath: path)), "\(path) must be protected")
        }
        #expect(!UninstallPlanner.isSafeToRemove(FileUtilities.library))
        #expect(!UninstallPlanner.isSafeToRemove(FileUtilities.library.appending(path: "Preferences")))
        #expect(UninstallPlanner.isSafeToRemove(URL(filePath: "/Applications/GlobalProtect.app")))
        #expect(UninstallPlanner.isSafeToRemove(URL(filePath: "/Library/LaunchDaemons/com.paloaltonetworks.gp.pangpsd.plist")))
    }

    @Test func buildsSafelyQuotedRemovalScript() {
        let daemon = LeftoverItem(url: URL(filePath: "/Library/LaunchDaemons/com.acme.d.plist"), size: 1, kind: .launchDaemon, requiresAdmin: true)
        let agent = LeftoverItem(url: URL(filePath: "/Library/LaunchAgents/com.acme.a.plist"), size: 1, kind: .launchAgent, requiresAdmin: true)
        let script = UninstallPlanner.removalScript(
            items: [URL(filePath: "/Applications/Acme's Tool.app"), URL(filePath: "/Library"), daemon.url],
            launchJobs: [daemon, agent],
            packageIDs: ["com.acme.pkg"],
            trashDirectory: URL(filePath: "/Users/test/.Trash"),
            userID: 501
        )
        #expect(script.contains("launchctl bootout system '/Library/LaunchDaemons/com.acme.d.plist'"))
        #expect(script.contains("launchctl bootout gui/501 '/Library/LaunchAgents/com.acme.a.plist'"))
        #expect(script.contains("move_to_trash '/Applications/Acme'\\''s Tool.app'"))
        #expect(!script.contains("move_to_trash '/Library'\n"), "protected folders must be skipped")
        #expect(script.contains("pkgutil --forget 'com.acme.pkg'"))
        #expect(PrivilegedShell.escapeAppleScript(#"say "hi" \ bye"#) == #"say \"hi\" \\ bye"#)
    }

    @Test func findsLeftoversAndOfficialUninstaller() throws {
        let box = try Sandbox()
        defer { try? FileManager.default.removeItem(at: box.root) }

        try box.write("x", to: "Preferences/com.acmecorp.AcmeTools.settings.plist", in: box.systemLibrary)          // parent prefix ("Acme Tool's" → acmetools)
        try box.write("x", to: "Application Support/AcmeCorp/Acme Tool's/data.db", in: box.systemLibrary)         // vendor folder
        try box.write(box.launchPlist(program: box.app.appending(path: "Contents/MacOS/AcmeHelper").path(percentEncoded: false)),
                      to: "LaunchDaemons/com.acmecorp.helperd.plist", in: box.systemLibrary)                       // runs inside the app
        try box.write("x", to: "Caches/com.acmecorp.AcmeTools.client/cache.bin", in: box.userLibrary)              // bundle ID
        try box.write("x", to: "Preferences/com.other.unrelated.plist", in: box.userLibrary)                      // must be ignored
        try box.write("#!/bin/sh\nexit 0\n", to: "Contents/Resources/uninstall_acme.sh", in: box.app)

        let analysis = UninstallPlanner.analyze(
            appURL: box.app,
            appName: "Acme Tool's",
            bundleIdentifier: "com.acmecorp.AcmeTools.client",
            userLibrary: box.userLibrary,
            systemLibrary: box.systemLibrary
        )
        let names = Set(analysis.leftovers.map(\.name))
        #expect(names.isSuperset(of: ["com.acmecorp.AcmeTools.settings.plist", "Acme Tool's", "com.acmecorp.helperd.plist", "com.acmecorp.AcmeTools.client"]))
        #expect(!names.contains("com.other.unrelated.plist"))
        #expect(analysis.leftovers.first { $0.name == "com.acmecorp.helperd.plist" }?.kind == .launchDaemon)
        #expect(analysis.officialUninstaller?.url.lastPathComponent == "uninstall_acme.sh")
        #expect(analysis.officialUninstaller?.kind == .script)
    }

    @Test(.timeLimit(.minutes(1)))
    func removalScriptMovesEverythingToTrash() async throws {
        let box = try Sandbox()
        defer { try? FileManager.default.removeItem(at: box.root) }
        try box.write("x", to: "Preferences/com.acmecorp.AcmeTool.client.plist", in: box.userLibrary)
        try box.write(box.launchPlist(program: "/usr/bin/true"), to: "LaunchAgents/com.acmecorp.agent.plist", in: box.userLibrary)
        try FileManager.default.createDirectory(at: box.trash, withIntermediateDirectories: true)
        // A same-named item already in the Trash must not be overwritten.
        try box.write("old", to: "com.acmecorp.AcmeTool.client.plist", in: box.trash)

        let preference = box.userLibrary.appending(path: "Preferences/com.acmecorp.AcmeTool.client.plist")
        let agent = LeftoverItem(url: box.userLibrary.appending(path: "LaunchAgents/com.acmecorp.agent.plist"), size: 0, kind: .launchAgent, requiresAdmin: false)
        let script = UninstallPlanner.removalScript(
            items: [box.app, preference, agent.url],
            launchJobs: [agent],
            packageIDs: [],
            trashDirectory: box.trash,
            userID: getuid()
        )
        // Same script the app runs as administrator — here without elevation, on user-owned files.
        let output = try await PrivilegedShell.run(script: script, asAdministrator: false, prompt: "")
        let parsed = UninstallPlanner.parseRemovalOutput(output)

        #expect(parsed.failed.isEmpty, "failures: \(parsed.failed)")
        #expect(parsed.removed.count == 3)
        let fm = FileManager.default
        #expect(!fm.fileExists(atPath: box.app.path(percentEncoded: false)))
        #expect(!fm.fileExists(atPath: preference.path(percentEncoded: false)))
        #expect(fm.fileExists(atPath: box.trash.appending(path: "Acme Tool's.app/Contents/MacOS/AcmeHelper").path(percentEncoded: false)))
        #expect(fm.fileExists(atPath: box.trash.appending(path: "com.acmecorp.AcmeTool.client.plist 2").path(percentEncoded: false)))
        #expect(try String(contentsOf: box.trash.appending(path: "com.acmecorp.AcmeTool.client.plist"), encoding: .utf8) == "old")
    }

    /// Read-only: checks what JoClean would remove for the real GlobalProtect install (nothing is deleted).
    @Test(.enabled(if: FileManager.default.fileExists(atPath: "/Applications/GlobalProtect.app")))
    func analyzesInstalledGlobalProtect() {
        let analysis = UninstallPlanner.analyze(
            appURL: URL(filePath: "/Applications/GlobalProtect.app"),
            appName: "GlobalProtect",
            bundleIdentifier: "com.paloaltonetworks.GlobalProtect.client"
        )
        let paths = Set(analysis.leftovers.map { $0.url.path(percentEncoded: false) })
        #expect(paths.contains("/Library/LaunchDaemons/com.paloaltonetworks.gp.pangpsd.plist"))
        #expect(paths.contains("/Library/LaunchAgents/com.paloaltonetworks.gp.pangps.plist"))
        #expect(paths.contains("/Library/LaunchAgents/com.paloaltonetworks.gp.pangpa.plist"))
        #expect(paths.contains("/Library/Preferences/com.paloaltonetworks.GlobalProtect.settings.plist"))
        #expect(analysis.appRequiresAdmin)
        let launchJobs = analysis.leftovers.filter { $0.url.path(percentEncoded: false).hasPrefix("/Library/Launch") }
        let allNeedAdmin = launchJobs.allSatisfy { $0.requiresAdmin }
        #expect(allNeedAdmin)
        #expect(analysis.hasSystemExtension)
        #expect(analysis.officialUninstaller?.url.lastPathComponent == "uninstall_gp.sh")
        #expect(analysis.packageIDs == ["com.paloaltonetworks.globalprotect.pkg"])
    }
}

@Suite("Trash via Finder")
struct FinderTrashTests {
    @Test func parsesFinderListing() throws {
        let output = "4\nReport.pdf\t20480\nOld Project\t-1\nmovie.mov\t1.234567891E+9\nwith\ttab.txt\t512\n"
        let listing = try FinderTrash.parseListing(output)
        #expect(listing.totalCount == 4)
        #expect(listing.entries.count == 4)
        #expect(listing.entries[0] == .init(name: "Report.pdf", size: 20_480))
        #expect(listing.entries[1] == .init(name: "Old Project", size: nil))       // folder size not calculated
        #expect(listing.entries[2].size == 1_234_567_891)                          // AppleScript real notation
        #expect(listing.entries[3] == .init(name: "with\ttab.txt", size: 512))     // name containing a tab
    }

    @Test func acceptsDecimalCommaLocales() throws {
        let listing = try FinderTrash.parseListing("1\nbackup.zip\t2,5E+9\n")
        #expect(listing.entries.first?.size == 2_500_000_000)
    }

    @Test func handlesEmptyTrashAndBadOutput() throws {
        #expect(try FinderTrash.parseListing("0\n") == .init(totalCount: 0, entries: []))
        #expect(throws: FinderTrash.FinderError.self) { try FinderTrash.parseListing("execution error") }
    }
}
