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
