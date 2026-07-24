//
//  DevAdmitWelcomeUITests.swift
//  On BoardUITests
//
//  End-to-end regression for the mock-mode admission flow: walks real
//  onboarding (deliberately SKIPPING the optional display name — the exact
//  account shape that used to trap admitted users behind the
//  effectiveOnboardingStep display-name gate), reaches the waitlist, taps
//  "Join Board [DEV]", and asserts the welcome celebration plays.
//
//  Requires a mock-mode app build (no Secrets.xcconfig). Only the auth
//  session is seeded via NSArgumentDomain — onboarding status is NOT seeded,
//  because argument-domain defaults are a read-only overlay that would mask
//  every state write the flow performs.
//

import XCTest

final class DevAdmitWelcomeUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func hexLiteral(_ json: String) -> String {
        "<" + Data(json.utf8).map { String(format: "%02x", $0) }.joined() + ">"
    }

    @MainActor
    func testDevAdmitShowsWelcomeCelebration() throws {
        // Fresh user id EVERY run → MockOnboardingService starts at .birthday.
        // App-container state persists across test runs, so a fixed id would
        // resume mid-flow on the second run.
        let userID = UUID().uuidString
        let session = #"{"userId":"\#(userID)","primaryProvider":"phone","email":null,"phone":"+15555550111","hasEmailIdentity":false,"hasPhoneIdentity":true,"hasPassword":false,"linkedIdentities":[]}"#

        let app = XCUIApplication()
        app.launchArguments = [
            "-mock.auth.session", hexLiteral(session),
            // The content-preferences (profanity) step is gated by this local
            // flag, not server status.
            "-hasCompletedProfanityStep", "YES",
            // The welcome fireworks are a continuous animation; leaving them off
            // keeps the app idle so XCUITest's taps/assertions don't stall.
            "-disableCelebrationFX", "YES"
        ]
        app.launch()

        // ── Birthday ──────────────────────────────────────────────────────
        let yearWheel = app.pickerWheels.element(boundBy: 2)
        XCTAssertTrue(yearWheel.waitForExistence(timeout: 12), "birthday step did not appear")
        yearWheel.adjust(toPickerWheelValue: "2000")
        tapContinue(app)

        // ── Username ──────────────────────────────────────────────────────
        let usernameField = app.textFields.firstMatch
        XCTAssertTrue(usernameField.waitForExistence(timeout: 8), "username step did not appear")
        usernameField.tap()
        usernameField.typeText("dev.walkthrough")
        // Debounced availability check gates the button.
        tapContinue(app, timeout: 8)

        // ── Profile — deliberately skip the optional display name ────────
        XCTAssertTrue(app.navigationBars["Set up your profile"].waitForExistence(timeout: 8), "profile step did not appear")
        tapContinue(app)

        // ── School email ──────────────────────────────────────────────────
        let emailField = app.textFields["you@school.edu"]
        XCTAssertTrue(emailField.waitForExistence(timeout: 8), "school step did not appear")
        emailField.tap()
        emailField.typeText("student@example.edu")

        let sendButton = app.buttons["Send verification code"]
        XCTAssertTrue(sendButton.waitForExistence(timeout: 8))
        // Wait for the debounced school match + availability check to enable it.
        let enabled = NSPredicate(format: "isEnabled == true")
        _ = XCTNSPredicateExpectation(predicate: enabled, object: sendButton)
        XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: enabled, object: sendButton)], timeout: 8)
        sendButton.tap()

        // OTP: mock accepts any 6-digit code; entry auto-submits when full.
        // The backing TextField is near-invisible (opacity 0.015) but stays
        // in the accessibility tree, so it can be focused directly.
        let otpField = app.textFields["Verification code"]
        XCTAssertTrue(otpField.waitForExistence(timeout: 8), "OTP entry did not appear")
        otpField.tap()
        otpField.typeText("123456")

        // ── Graduation ───────────────────────────────────────────────────
        // Client-inserted step after school verification; the default month/year
        // is fine, so just Continue.
        XCTAssertTrue(app.navigationBars["Graduation"].waitForExistence(timeout: 10), "graduation step did not appear")
        let gradContinue = app.buttons["Continue"]
        XCTAssertTrue(gradContinue.waitForExistence(timeout: 4))
        gradContinue.tap()

        // ── Waitlist → dev admission ─────────────────────────────────────
        let devButton = app.buttons["Join Board [DEV]"]
        XCTAssertTrue(devButton.waitForExistence(timeout: 12), "waitlist screen with dev button did not appear")
        devButton.tap()

        // ── Welcome celebration ──────────────────────────────────────────
        // Typewriter text — match on the full typed line's container.
        let reveal = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "You're in!")).firstMatch
        XCTAssertTrue(reveal.waitForExistence(timeout: 10), "welcome celebration did not appear after dev admission")

        let continueButton = app.buttons["Continue"]
        XCTAssertTrue(continueButton.waitForExistence(timeout: 6))
        let enabledCTA = NSPredicate(format: "isEnabled == true")
        XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: enabledCTA, object: continueButton)], timeout: 6)
        continueButton.tap()

        // ── Pledge ────────────────────────────────────────────────────────
        XCTAssertTrue(app.staticTexts["One more thing."].waitForExistence(timeout: 6), "pledge screen did not appear")

        let signButton = app.buttons["Sign & step on board"]
        XCTAssertTrue(signButton.waitForExistence(timeout: 4))
        XCTAssertFalse(signButton.isEnabled, "sign button should be disabled before a signature is drawn")

        let canvas = app.descendants(matching: .any).matching(identifier: "SignatureCanvas").firstMatch
        XCTAssertTrue(canvas.waitForExistence(timeout: 4), "signature canvas missing")
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.55)))

        XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: enabledCTA, object: signButton)], timeout: 4)
        XCTAssertTrue(signButton.isEnabled, "sign button did not enable after drawing")
        signButton.tap()

        // Signing dismisses the whole cover back to the feed.
        XCTAssertTrue(app.staticTexts["One more thing."].waitForNonExistence(timeout: 6))
    }

    @MainActor
    private func tapContinue(_ app: XCUIApplication, timeout: TimeInterval = 5) {
        let button = app.buttons["Continue"]
        XCTAssertTrue(button.waitForExistence(timeout: timeout), "Continue button missing")
        let enabled = NSPredicate(format: "isEnabled == true")
        XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: enabled, object: button)], timeout: timeout)
        button.tap()
    }
}
