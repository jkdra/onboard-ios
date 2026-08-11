//
//  RemoteConfigInspectorUITests.swift
//  On BoardUITests
//
//  Smoke test for the DEBUG-only Remote Config inspector: feed → ••• menu →
//  Settings → Remote Config [DEV], then assert the screen's load-bearing rows
//  exist. Navigation goes through nav-bar/menu/list buttons only — none of the
//  feed-grid card taps that are currently undeliverable (see
//  ReactionBarInsetUITests' header) are involved.
//

import XCTest

final class RemoteConfigInspectorUITests: XCTestCase {

    @MainActor
    func testInspectorShowsFlagsAndMockStatus() throws {
        // Re-enable by setting ONBOARD_UITEST_TAPS_FIXED=1 once a newer Xcode
        // delivers taps to SwiftUI elements again.
        if ProcessInfo.processInfo.environment["ONBOARD_UITEST_TAPS_FIXED"] == nil {
            throw XCTSkip("Xcode XCUITest 'Automation type mismatch' on SwiftUI elements — see ReactionBarInsetUITests.swift header.")
        }
        let session = #"{"userId":"A0000000-0000-4000-8000-000000000001","primaryProvider":"email","email":"student@example.edu","phone":null,"hasEmailIdentity":true,"hasPhoneIdentity":false,"hasPassword":false,"linkedIdentities":[{"id":"mock-email","provider":"email","email":"student@example.edu"}]}"#
        let hex = Data(session.utf8).map { String(format: "%02x", $0) }.joined()
        let app = XCUIApplication()
        app.launchArguments = ["-mock.auth.session", "<\(hex)>", "-dev.hideDevBlock"]
        app.launch()

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for title in ["Allow", "Don't Allow"] {
            let button = springboard.alerts.buttons[title]
            if button.waitForExistence(timeout: 3) { button.tap(); break }
        }

        // ••• menu → Settings
        let bar = app.navigationBars.firstMatch
        XCTAssertTrue(bar.waitForExistence(timeout: 15), "nav bar")
        let more = bar.buttons["More"].exists ? bar.buttons["More"] : bar.buttons.element(boundBy: bar.buttons.count - 1)
        more.tap()
        let settings = app.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 8), "Settings menu item")
        settings.tap()

        // Scroll to and open the inspector row.
        let row = app.buttons["Remote Config [DEV]"]
        var attempts = 0
        while !row.exists && attempts < 8 {
            app.swipeUp()
            attempts += 1
        }
        XCTAssertTrue(row.waitForExistence(timeout: 5), "inspector row")
        row.tap()

        // Load-bearing content: mock-mode status, all four flags, empty raw config.
        XCTAssertTrue(app.staticTexts["unavailable (mock/unconfigured build)"]
            .waitForExistence(timeout: 8), "mock fetch status")
        for flag in ["zoomTransition", "glassEffects", "postPhotoAttachments", "hostVoice"] {
            XCTAssertTrue(app.staticTexts[flag].exists, "flag row: \(flag)")
        }
        let defaultNote = app.staticTexts
            .matching(NSPredicate(format: "label CONTAINS %@", "compiled default"))
            .firstMatch
        XCTAssertTrue(defaultNote.exists, "source line explains the compiled-default fallback")
    }
}
