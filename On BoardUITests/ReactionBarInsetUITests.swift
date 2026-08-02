//
//  ReactionBarInsetUITests.swift
//  On BoardUITests
//
//  Diagnostic for the reported bug: opening the composer, cancelling it, then
//  opening a post leaves PostDetailView's bottom-pinned reaction bar pushed up,
//  as if a keyboard-sized safe-area inset were still applied.
//
//  Measures the bar's actual frame rather than eyeballing a screenshot, and
//  compares the clean path against the composer-first path on the same build.
//
//  ⚠️ CURRENTLY BLOCKED — DOES NOT REPRODUCE. Read this before spending time on it.
//
//  What was ruled out across four iterations (2026-08-02):
//   • Element lookup. SwiftUI collapses each grid card into ONE Button whose
//     accessibility label is the card's whole aggregated content; the inner
//     staticTexts are not tappable targets. Query `app.buttons`, not staticTexts.
//   • Two elements answer to "New post" — the 55x44 toolbar plus and the dashed
//     compose card. `.firstMatch` picks the toolbar one, which is offscreen until
//     the card scrolls away. Pick by largest frame.
//   • Offscreen content. The Debug-only in-feed dev scratch block fills ~1.5
//     screens above the masonry, putting both targets below the fold. Fixed by
//     passing `-dev.hideDevBlock` (see ContentView.hidesDevBlock).
//
//  What remains: with all of the above corrected and the accessibility tree
//  confirming the card Button on screen at {{16, 374}, {179, 206}} with nothing
//  overlaying it, BOTH `.tap()` and a normalized-coordinate tap fail to
//  navigate — `stillOnFeedAfterTap` stays true. This matches the project's known
//  issue where perpetual SwiftUI animations (the countdown ticks every second,
//  plus the animated stripes) keep the app from ever reaching idle, which makes
//  XCUITest gesture delivery unreliable on this screen.
//
//  Reviving this likely needs the non-idle animations suppressed under a launch
//  argument, the way `-dev.hideDevBlock` suppresses the scratch block.
//

import XCTest

final class ReactionBarInsetUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    @MainActor
    private func launchAsMaya() -> XCUIApplication {
        let session = #"{"userId":"A0000000-0000-4000-8000-000000000001","primaryProvider":"email","email":"student@example.edu","phone":null,"hasEmailIdentity":true,"hasPhoneIdentity":false,"hasPassword":false,"linkedIdentities":[{"id":"mock-email","provider":"email","email":"student@example.edu"}]}"#
        let hex = Data(session.utf8).map { String(format: "%02x", $0) }.joined()
        let app = XCUIApplication()
        // -dev.hideDevBlock is essential here, not cosmetic: the in-feed dev
        // scratch block fills ~1.5 screens above the masonry, which puts both the
        // compose card and the first post card below the fold and made every
        // tap a no-op.
        app.launchArguments = ["-mock.auth.session", "<\(hex)>", "-dev.hideDevBlock"]
        app.launch()

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for title in ["Allow", "Don't Allow"] {
            let button = springboard.alerts.buttons[title]
            if button.waitForExistence(timeout: 3) { button.tap(); break }
        }
        sleep(2)
        return app
    }

    /// SwiftUI collapses each grid card into ONE Button whose accessibility
    /// label is the card's whole aggregated content — tapping the inner
    /// staticText does not navigate.
    @MainActor
    private func openFirstPost(_ app: XCUIApplication) {
        let card = app.buttons
            .matching(NSPredicate(format: "label CONTAINS[c] %@", "brat by charli"))
            .firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 15), "feed card should appear")
        // Coordinate tap, not element tap: the grid card carries composed
        // gestures and a rotationEffect, and a plain .tap() was not navigating.
        card.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        sleep(4)
        // Prove we actually left the feed before measuring anything.
        let stillOnFeed = app.buttons
            .matching(NSPredicate(format: "label CONTAINS[c] %@", "selling math239"))
            .firstMatch.exists
        print("REACTIONBAR[nav] stillOnFeedAfterTap=\(stillOnFeed)")
    }

    /// The leftmost reaction pill. Labels are "\(reaction.label), \(count)".
    @MainActor
    private func reactionPill(_ app: XCUIApplication) -> XCUIElement {
        app.buttons
            .matching(NSPredicate(format: "label BEGINSWITH[c] %@", "Like,"))
            .firstMatch
    }

    @MainActor
    private func report(_ label: String, _ app: XCUIApplication) -> CGFloat {
        let screenHeight = app.windows.firstMatch.frame.height
        let pill = reactionPill(app)

        guard pill.waitForExistence(timeout: 10) else {
            // Evidence, not a guess: dump every button so the real reaction-bar
            // labels (and whether PostDetailView even opened) are visible.
            print("REACTIONBAR[\(label)] PILL NOT FOUND. screenH=\(screenHeight)")
            let buttons = app.buttons.allElementsBoundByIndex
            print("REACTIONBAR[\(label)] button count=\(buttons.count)")
            for button in buttons {
                print("REACTIONBAR[\(label)] button label=\(button.label.debugDescription) id=\(button.identifier.debugDescription) frame=\(button.frame)")
            }
            print("REACTIONBAR[\(label)] TREE >>>\n\(app.debugDescription)\n<<< TREE")
            XCTFail("\(label): reaction bar should exist")
            return -1
        }

        let gap = screenHeight - pill.frame.maxY
        print("REACTIONBAR[\(label)] pill.maxY=\(pill.frame.maxY) screenH=\(screenHeight) gapFromBottom=\(gap)")
        return gap
    }

    /// Control: straight to a post, no composer involved.
    @MainActor
    func testA_CleanOpenGap() throws {
        let app = launchAsMaya()
        openFirstPost(app)
        _ = report("clean", app)
    }

    /// Repro: composer (auto-focuses a field, raising the keyboard), cancel,
    /// then straight into a post.
    @MainActor
    func testB_AfterComposerCancelGap() throws {
        let app = launchAsMaya()

        // Two elements answer to "New post": the toolbar plus (55x44) and the
        // dashed compose card. Take the largest — the toolbar one sits offscreen
        // until the card scrolls away.
        let composeCandidates = app.buttons
            .matching(NSPredicate(format: "label CONTAINS[c] %@", "New post"))
        XCTAssertTrue(composeCandidates.firstMatch.waitForExistence(timeout: 15), "compose control should appear")
        let compose = composeCandidates.allElementsBoundByIndex
            .max { $0.frame.height < $1.frame.height }
        XCTAssertNotNil(compose, "a compose control should exist")
        print("REACTIONBAR[compose] chosen frame=\(compose!.frame)")
        compose!.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        sleep(4)   // let the sheet settle and the keyboard come up

        let cancel = app.buttons["Cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 8), "composer Cancel should exist")
        cancel.tap()
        sleep(1)   // deliberately short: the bug is a race with the dismiss transition

        openFirstPost(app)
        _ = report("afterComposerCancel", app)
    }
}
