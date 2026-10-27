//
//  JoCleanUITests.swift
//  JoCleanUITests
//
//  Created by ichio on 22/10/26.
//

import XCTest

/// Verifies that every module opens, shows a reachable scan button, and only scans after it is clicked.
final class JoCleanUITests: XCTestCase {

    private var app: XCUIApplication!
    private var window: XCUIElement!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        // Tests can't answer the "control Finder" Automation prompt, so keep the Finder fallback off.
        app.launchArguments += ["-JoCleanDisableFinderTrash"]
        app.launch()
        app.activate()
        window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 10), "Main window did not appear")
    }

    override func tearDownWithError() throws {
        app.terminate()
    }

    // MARK: Helpers

    /// Selects a module in the sidebar.
    private func openModule(_ title: String) {
        let row = window.outlines.staticTexts[title].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "Sidebar item '\(title)' not found")
        row.click()
    }

    /// Asserts the round scan button is on screen and clickable, then clicks it.
    private func clickScanButton(_ title: String = "Scan") {
        let button = window.buttons[title].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 5), "Button '\(title)' not found.\n\(window.debugDescription)")
        XCTAssertTrue(button.isHittable, "Button '\(title)' is off-screen: window=\(window.frame) button=\(button.frame)")
        button.click()
    }

    /// Waits for any of the given texts to appear (results differ between machines).
    private func waitForAnyText(_ texts: [String], timeout: TimeInterval) -> Bool {
        let deadline = Date.now.addingTimeInterval(timeout)
        while Date.now < deadline {
            for text in texts where window.staticTexts.containing(NSPredicate(format: "value CONTAINS %@", text)).firstMatch.exists {
                return true
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        return false
    }

    // MARK: Tests

    @MainActor
    func testSmartScan() throws {
        clickScanButton()
        XCTAssertTrue(waitForAnyText(["Ready to clean"], timeout: 30), "Smart Scan never finished.\n\(window.debugDescription)")
    }

    @MainActor
    func testSystemJunk() throws {
        openModule("System Junk")
        clickScanButton()
        XCTAssertTrue(waitForAnyText(["of files you can clean"], timeout: 30), "System Junk scan never finished.\n\(window.debugDescription)")
    }

    @MainActor
    func testTrash() throws {
        openModule("Trash")
        clickScanButton()
        XCTAssertTrue(
            waitForAnyText(["Trash Is Empty", "items using", "See Your Trash"], timeout: 20),
            "Trash scan never finished.\n\(window.debugDescription)"
        )
    }

    @MainActor
    func testUninstaller() throws {
        openModule("Uninstaller")
        clickScanButton("View Apps")
        XCTAssertTrue(waitForAnyText(["apps installed"], timeout: 60), "App list never loaded.\n\(window.debugDescription)")
    }

    @MainActor
    func testOptimization() throws {
        openModule("Optimization")
        // Must not scan by itself: the welcome screen with its button has to be shown first.
        clickScanButton()
        XCTAssertTrue(waitForAnyText(["Running Apps"], timeout: 20), "Optimization scan never finished.\n\(window.debugDescription)")
    }

    /// Without access to ~/.Trash the module must explain how to fix it — never claim the Trash is empty.
    @MainActor
    func testTrashExplainsMissingPermission() throws {
        openModule("Trash")
        clickScanButton()
        XCTAssertTrue(waitForAnyText(["See Your Trash", "items using", "Trash Is Empty"], timeout: 20))
        if window.staticTexts.containing(NSPredicate(format: "value CONTAINS %@", "See Your Trash")).firstMatch.exists {
            XCTAssertTrue(window.buttons["Open Automation"].isHittable)
            XCTAssertTrue(window.buttons["Open Full Disk Access"].isHittable)
            XCTAssertTrue(window.buttons["Try Again"].firstMatch.isHittable)
            XCTAssertFalse(window.staticTexts["Trash Is Empty"].exists, "Must not claim the Trash is empty when it can't be read")
        }
    }

    /// Selecting a root-owned, system-wide app shows the admin requirement and its official uninstaller.
    /// Read-only: nothing is uninstalled.
    @MainActor
    func testUninstallerShowsAdminAndOfficialUninstaller() throws {
        try XCTSkipUnless(FileManager.default.fileExists(atPath: "/Applications/GlobalProtect.app"), "GlobalProtect not installed")
        openModule("Uninstaller")
        clickScanButton("View Apps")
        XCTAssertTrue(waitForAnyText(["apps installed"], timeout: 60))

        let search = window.textFields["Search apps"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.click()
        search.typeText("GlobalProtect")
        let row = window.staticTexts["GlobalProtect"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.click()

        XCTAssertTrue(waitForAnyText(["Official uninstaller available"], timeout: 20), "Official uninstaller card missing.\n\(window.debugDescription)")
        // Must be on screen, not just in the accessibility tree — an overflowing layout once pushed
        // these off-screen while they still "existed".
        XCTAssertTrue(window.buttons["Run Official Uninstaller"].isHittable, "Official uninstaller button is off-screen")
        XCTAssertTrue(window.buttons["Uninstall"].firstMatch.isHittable, "Uninstall button is off-screen")
        XCTAssertTrue(window.outlines.staticTexts["Smart Scan"].firstMatch.isHittable, "Sidebar was pushed off-screen")
        XCTAssertTrue(waitForAnyText(["requires administrator password"], timeout: 5))
        // The root-owned app row carries the "Admin" badge (leftover kinds are covered by unit tests).
        XCTAssertTrue(window.staticTexts["Admin"].firstMatch.waitForExistence(timeout: 5), "Admin badge missing")
    }

    /// The malware check works without any account: open it, press Scan, and get results
    /// from XProtect, Gatekeeper and CIRCL.
    @MainActor
    func testMalwareCheckScansWithoutAPIKey() throws {
        openModule("Malware Check")
        XCTAssertTrue(window.staticTexts["XProtect"].waitForExistence(timeout: 5), "Engine list missing")
        clickScanButton()
        XCTAssertTrue(
            waitForAnyText(["Done:"], timeout: 240),
            "Malware scan never finished.\n\(window.debugDescription)"
        )
    }

    /// Scanning the home folder can trigger privacy prompts, so only check the button is reachable.
    @MainActor
    func testLargeFilesButtonReachable() throws {
        openModule("Large & Old Files")
        let button = window.buttons["Scan"].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        XCTAssertTrue(button.isHittable, "Scan button off-screen: window=\(window.frame) button=\(button.frame)")
    }
}
