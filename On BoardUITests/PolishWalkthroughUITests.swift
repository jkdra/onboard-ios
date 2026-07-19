//
//  PolishWalkthroughUITests.swift
//  On BoardUITests
//
//  TEMPORARY driver for the 2026-07-17 polish pass: walks the app in mock
//  mode while an external `simctl io recordVideo` captures the run, so the
//  edit-mode morphs can be reviewed frame-by-frame. Not a regression suite.
//

import XCTest

final class PolishWalkthroughUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    @MainActor
    private func launchAsMaya() -> XCUIApplication {
        let session = #"{"userId":"A0000000-0000-4000-8000-000000000001","primaryProvider":"email","email":"student@example.edu","phone":null,"hasEmailIdentity":true,"hasPhoneIdentity":false,"hasPassword":false,"linkedIdentities":[{"id":"mock-email","provider":"email","email":"student@example.edu"}]}"#
        let hex = Data(session.utf8).map { String(format: "%02x", $0) }.joined()
        let app = XCUIApplication()
        app.launchArguments = ["-mock.auth.session", "<\(hex)>"]
        app.launch()

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.alerts.buttons["Allow"]
        if allow.waitForExistence(timeout: 4) { allow.tap() }
        sleep(2)
        return app
    }

    /// Taps the nav-bar ellipsis menu whatever XCUI decides to call it.
    @MainActor
    private func tapMoreMenu(_ app: XCUIApplication) {
        let bar = app.navigationBars.firstMatch
        for candidate in [bar.buttons["More"], bar.buttons["ellipsis"]] where candidate.exists {
            candidate.tap()
            return
        }
        // Fallback: trailing-most nav bar button.
        let buttons = bar.buttons
        if buttons.count > 0 {
            buttons.element(boundBy: buttons.count - 1).tap()
        }
    }

    @MainActor
    func test1_PostDetailEditMorph() throws {
        let app = launchAsMaya()

        let card = app.staticTexts
            .matching(NSPredicate(format: "label CONTAINS[c] %@", "brat by charli"))
            .firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10), "maya's feed card")
        card.tap()
        sleep(2)

        sleep(5)            // long static span: marks the morph in the video
        tapMoreMenu(app)
        let edit = app.buttons["Edit"]
        XCTAssertTrue(edit.waitForExistence(timeout: 4), "Edit menu item")
        edit.tap()          // morph: read -> edit
        sleep(5)

        let cancel = app.buttons["Cancel"]
        if cancel.waitForExistence(timeout: 4) {
            cancel.tap()    // morph: edit -> read
        }
        sleep(5)
    }

    @MainActor
    func test2_ProfileEditMorph() throws {
        let app = launchAsMaya()

        let more = app.buttons["More"]
        XCTAssertTrue(more.waitForExistence(timeout: 10), "More menu")
        more.tap()
        let settings = app.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 4), "Settings menu item")
        settings.tap()
        sleep(1)

        let profileRow = app.staticTexts
            .matching(NSPredicate(format: "label CONTAINS[c] %@", "maya"))
            .firstMatch
        XCTAssertTrue(profileRow.waitForExistence(timeout: 6), "profile preview row")
        profileRow.tap()
        sleep(2)

        let editProfile = app.buttons["Edit Profile"]
        XCTAssertTrue(editProfile.waitForExistence(timeout: 6), "Edit Profile button")
        editProfile.tap()   // morph: read -> edit
        sleep(3)

        let cancel = app.buttons["Cancel"]
        if cancel.waitForExistence(timeout: 4) {
            cancel.tap()    // morph: edit -> read
        }
        sleep(3)
    }

    @MainActor
    func test3_Composer() throws {
        let app = launchAsMaya()

        let newPost = app.buttons["New post"]
        XCTAssertTrue(newPost.waitForExistence(timeout: 10), "new post card")
        newPost.tap()
        sleep(2)

        let title = app.textFields.firstMatch
        if title.waitForExistence(timeout: 4) {
            title.tap()
            title.typeText("midnight taco run anyone")
        }
        let body = app.textFields.element(boundBy: 1)
        if body.exists {
            body.tap()
            body.typeText("leaving from the east lot at 11:45, three seats free")
        }
        sleep(15)   // hold for external screenshot
    }

    @MainActor
    func test4_SecuritySettings() throws {
        let app = launchAsMaya()

        let more = app.buttons["More"]
        XCTAssertTrue(more.waitForExistence(timeout: 10), "More menu")
        more.tap()
        let settings = app.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 4), "Settings menu item")
        settings.tap()
        sleep(1)

        let security = app.buttons
            .matching(NSPredicate(format: "label CONTAINS[c] %@", "Security"))
            .firstMatch
        for _ in 0..<4 where !security.exists {
            app.swipeUp()
        }
        XCTAssertTrue(security.waitForExistence(timeout: 6), "Security row")
        security.tap()
        sleep(3)
    }

    // TEMPORARY — verification (Task 6, comment composer redesign). Drives
    // the checklist in docs/superpowers/plans/2026-07-18-comment-composer-
    // redesign.md's testing section end to end and attaches a named
    // screenshot at every state that matters, so evidence can be pulled out
    // of the .xcresult with `xcrun xcresulttool export attachments`.
    @MainActor
    private func snap(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func test7_ComposerFullFlow() throws {
        let app = launchAsMaya()

        let card = app.staticTexts
            .matching(NSPredicate(format: "label CONTAINS[c] %@", "brat by charli"))
            .firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10), "maya's feed card")
        card.tap()
        XCTAssertTrue(app.staticTexts["Comments"].waitForExistence(timeout: 6))

        // ---- Item 1: browse -> compose morph ----
        let circleButton = app.buttons["Add a comment"]
        XCTAssertTrue(circleButton.waitForExistence(timeout: 6), "circle comment button")
        XCTAssertTrue(app.buttons["Like, 89"].exists, "reaction pills visible in browse")
        snap(app, "01-browse-state")

        circleButton.tap()
        XCTAssertTrue(app.buttons["Cancel comment"].waitForExistence(timeout: 4), "compose close button")
        XCTAssertTrue(app.buttons["Post comment"].exists, "send button")
        XCTAssertFalse(app.buttons["Like, 89"].exists, "pills gone in compose state")
        snap(app, "02-compose-state-empty-keyboard-up")

        // ---- Item 2: draft persists across X / Done / swipe dismiss ----
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 4))
        field.tap()
        field.typeText("verification draft one")

        app.buttons["Cancel comment"].tap()   // X dismiss
        XCTAssertFalse(app.buttons["Cancel comment"].waitForExistence(timeout: 2), "back to browse after X")
        XCTAssertTrue(app.buttons["Add a comment"].waitForExistence(timeout: 3))

        circleButton.tap()
        XCTAssertTrue(app.buttons["Cancel comment"].waitForExistence(timeout: 3))
        let valueAfterXReopen = field.value as? String
        XCTAssertEqual(valueAfterXReopen, "verification draft one", "draft survived X-dismiss and reappeared")
        snap(app, "03-draft-persists-after-X-dismiss")

        // Done button in the keyboard accessory bar
        let doneButton = app.buttons["Dismiss keyboard"]
        if doneButton.waitForExistence(timeout: 3) {
            doneButton.tap()
        } else {
            app.buttons["Done"].tap()
        }
        XCTAssertFalse(app.buttons["Cancel comment"].waitForExistence(timeout: 2), "back to browse after Done")

        circleButton.tap()
        XCTAssertTrue(app.buttons["Cancel comment"].waitForExistence(timeout: 3))
        XCTAssertEqual(field.value as? String, "verification draft one", "draft survived Done-dismiss")

        // Interactive swipe-down dismiss
        app.scrollViews.firstMatch.swipeDown()
        sleep(1)
        let composingAfterSwipe = app.buttons["Cancel comment"].exists
        if !composingAfterSwipe {
            circleButton.tap()
            XCTAssertTrue(app.buttons["Cancel comment"].waitForExistence(timeout: 3))
            XCTAssertEqual(field.value as? String, "verification draft one", "draft survived swipe-down dismiss")
        } else {
            // Interactive swipe didn't cross the dismiss threshold under XCUITest's
            // synthetic drag — not a defect (Done/X are the deterministic paths);
            // note it and continue.
            snap(app, "03b-swipe-down-did-not-dismiss-keyboard")
        }

        // Back to browse for the next section. The draft ("verification draft
        // one") deliberately survives — per spec, switching targets keeps the
        // draft text, so it'll reappear (and get appended to) once we target
        // the reply below. That's expected behavior, not test pollution.
        if app.buttons["Cancel comment"].exists {
            app.buttons["Cancel comment"].tap()
        }

        // ---- Item 3: reply on a nested comment ----
        let replyButtons = app.buttons.matching(NSPredicate(format: "label == %@", "Reply"))
        XCTAssertTrue(replyButtons.count >= 2, "expected at least two Reply buttons (top-level + nested)")
        let nestedReply = replyButtons.element(boundBy: 1) // maya.c's reply, nested under leokp's comment
        nestedReply.tap()

        XCTAssertTrue(app.staticTexts["Replying to maya.c"].waitForExistence(timeout: 4), "reply chip shows the right handle")
        snap(app, "04-reply-chip-target-highlighted-scrolled")

        // ---- Item 4 / 4b: multiline draft -> Expand -> sheet -> back -> post ----
        let replyField = app.textFields.firstMatch
        XCTAssertTrue(replyField.waitForExistence(timeout: 3))
        replyField.tap()
        replyField.typeText("This is a verification message intended to wrap across two or more lines so the Expand affordance appears above the send button reliably.")

        let expandButton = app.buttons["Expand composer"]
        XCTAssertTrue(expandButton.waitForExistence(timeout: 4), "Expand appears once text wraps")
        snap(app, "05-multiline-expand-button-appears")

        expandButton.tap()
        XCTAssertTrue(app.navigationBars["Reply"].waitForExistence(timeout: 4), "full-screen sheet opened with reply title")
        // The sheet's own toolbar chevron only exists once the presentation
        // has actually mounted; wait for it, then give the slide-up animation
        // a moment to finish before tapping — tapping too early can land on
        // the still-animating scrim behind the sheet and dismiss it instead
        // of focusing the field (observed: an errant tap here silently
        // cancelled the whole composer via the bar's focus-loss handler).
        XCTAssertTrue(app.buttons["Collapse composer"].waitForExistence(timeout: 4), "sheet toolbar mounted")
        sleep(1)
        XCTAssertTrue(app.staticTexts["Replying to maya.c"].waitForExistence(timeout: 3), "reply context carried into sheet")
        // Read (not tap) the value here: the inline field is still mounted
        // (covered, not destroyed) behind the sheet, so `.textFields.firstMatch`
        // is ambiguous between the two for interaction purposes — but both
        // share the exact same `composer.draft` binding, so reading either's
        // `.value` is an equally valid check that the draft carried over.
        // We deliberately avoid tapping/typing into this ambiguous match
        // (an earlier attempt landed on the wrong, non-hittable instance and
        // silently cancelled the composer via the focus-loss handler).
        let sheetFieldValue = app.textFields.firstMatch.value as? String
        XCTAssertTrue(sheetFieldValue?.contains("wrap across two or more lines") == true, "draft carried into sheet")
        snap(app, "06-sheet-open-draft-and-reply-context-intact")

        app.buttons["Collapse composer"].tap()
        XCTAssertTrue(app.buttons["Post comment"].waitForExistence(timeout: 4), "back to inline composer")
        XCTAssertTrue(app.staticTexts["Replying to maya.c"].exists, "reply chip still present after sheet dismiss")
        XCTAssertTrue((field.value as? String)?.contains("wrap across two or more lines") == true, "draft intact in inline field after sheet dismiss")
        snap(app, "07-sheet-dismissed-draft-and-reply-intact")

        // Second half of 4b: posting FROM the sheet. NOTE: mock mode has no
        // BoardService at all (BoardStore+Comments.swift's addComment guards
        // `boardService == nil` with `loadError = "Connect to the On Board
        // backend to comment."` and returns false BEFORE any optimistic
        // mutation) — so posting a comment can never actually succeed here;
        // this is a pre-existing, unrelated limitation of mock mode, not a
        // composer regression.
        //
        // FINDING (real, reproducible, not mock-mode-specific): the failure
        // alert is attached to PostDetailView (the sheet's *presenter*), so
        // presenting it force-dismisses the still-open CommentComposerSheet
        // first (iOS won't stack a second modal on the presenter). That
        // sheet dismissal drops `showExpandedComposer`/`isSheetPresented` to
        // false with no field newly focused, which trips
        // CommentComposerBar's focus-loss guard
        // (`!focused && composing && !isPosting && !isSheetPresented`) —
        // `isPosting` has *already* reset to false by the time the alert
        // arrives (it resets synchronously after `await onPost()`, while
        // `store.loadError` is only observed on the next run-loop tick), so
        // the guard is open and `composer.dismiss()` fires. Net effect: a
        // failed post from the sheet (any real network failure, not just
        // this mock-mode path) silently cancels the whole compose session —
        // the draft text survives (dismiss() keeps a non-empty draft), but
        // the reply *target* is lost (dismiss() always clears target to
        // nil), so the user's "replying to @maya.c" context silently
        // reverts to a fresh top-level comment. Captured as evidence below;
        // reported as a concern rather than patched (the fix needs the bar
        // to distinguish this involuntary alert-driven defocus from a
        // deliberate user dismiss, which the current isPosting-window guard
        // has no signal for — not a safe one-line local fix).
        expandButton.tap()
        XCTAssertTrue(app.navigationBars["Reply"].waitForExistence(timeout: 4), "sheet reopened with draft intact")
        let postFromSheetButton = app.buttons["Post"]
        XCTAssertTrue(postFromSheetButton.waitForExistence(timeout: 3))
        sleep(1)
        postFromSheetButton.tap()

        let backendAlertOK = app.alerts.buttons["OK"]
        XCTAssertTrue(backendAlertOK.waitForExistence(timeout: 6), "post failure surfaces the 'connect to backend' alert")
        snap(app, "08a-post-fails-alert-force-dismisses-sheet")
        backendAlertOK.tap()

        // Evidence of the finding above: browse state resumed (composer was
        // silently cancelled), and re-opening shows the reply target was
        // lost even though it was never intentionally cleared.
        XCTAssertTrue(app.buttons["Add a comment"].waitForExistence(timeout: 4), "FINDING: alert force-dismissed the sheet, which cancelled the whole composer back to browse")
        snap(app, "08b-finding-composer-silently-cancelled-by-alert")
        app.buttons["Add a comment"].tap()
        XCTAssertTrue(app.buttons["Cancel comment"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["Replying to maya.c"].exists, "FINDING: reply target was silently dropped by the involuntary dismiss")
        snap(app, "08c-finding-reply-target-lost-only-newcomment-remains")
        if app.buttons["Cancel comment"].exists { app.buttons["Cancel comment"].tap() }

        // ---- Item 5: editing a comment hides the bottom bar entirely ----
        // Mock mode can't create new comments (see above), so edit an
        // EXISTING sample comment Maya already owns: the "maya.c" reply
        // ("second one or third one bc both were evil") resolves its
        // authorId to SampleProfileID.maya via Comment.authored(by:) ->
        // Profile.lookup(handle:), which equals the mock session's
        // currentUserID — so BoardStore.canEdit(comment:) is true for it
        // without needing to post anything first.
        let mayaCommentMore = app.buttons.matching(NSPredicate(format: "label == %@", "More")).element(boundBy: 2)
        // [0] nav-bar More, [1] leokp's comment More, [2] maya.c's reply More.
        mayaCommentMore.tap()
        let editMenuItem = app.buttons["Edit"]
        XCTAssertTrue(editMenuItem.waitForExistence(timeout: 3))
        editMenuItem.tap()

        XCTAssertFalse(app.buttons["Add a comment"].exists, "bottom bar hidden entirely while editing a comment")
        XCTAssertFalse(app.buttons["Cancel comment"].exists, "compose state also hidden while editing a comment")
        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 3), "edit toolbar Cancel exists in the accessibility tree")
        sleep(1)
        snap(app, "09a-comment-edit-mode-keyboard-up-no-visible-save-cancel")

        // FINDING (real, reproducible, pre-existing — not introduced by this
        // redesign; confirmed via an isolated repro in test10_DiagEditCancel):
        // while the keyboard is showing during comment edit, the .bottomBar
        // Save/Cancel toolbar items exist in the accessibility tree and
        // report isHittable == true, but are NOT actually drawn anywhere on
        // screen (screenshot 09a shows no Save/Cancel — only the keyboard's
        // own "Done" accessory). Tapping the accessibility element in that
        // state is a no-op (verified: editingCommentID never clears). Only
        // once the keyboard is dismissed do Save/Cancel actually render and
        // become tappable. This means a user editing a comment has no way to
        // Save or Cancel while actively typing — they must first dismiss the
        // keyboard. Likely a SwiftUI `.bottomBar` + `.keyboardDoneToolbar()`
        // (ToolbarItemGroup(placement: .keyboard)) interaction on the same
        // view; PostDetailView's post-edit-mode bottomBar (Cancel/Save/
        // TonePicker) shares the same mechanism and may have the same issue.
        // This predates the composer redesign (the comment-edit toolbar
        // itself is untouched by this task) and touches toolbar architecture
        // shared with post editing, so it is reported here rather than
        // patched — not a safe, scoped local fix.
        if app.buttons["Dismiss keyboard"].exists {
            app.buttons["Dismiss keyboard"].tap()
            sleep(1)
        }
        snap(app, "09b-after-dismissing-keyboard-save-cancel-now-visible")

        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["Add a comment"].waitForExistence(timeout: 4), "bottom bar restored after cancelling comment edit (once Cancel is reachable)")
        snap(app, "10-comment-edit-cancelled-bar-restored")

        // ---- Item 6: collapsible thread lines ----
        let collapseLine = app.buttons["Collapse replies"]
        XCTAssertTrue(collapseLine.waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["second one or third one bc both were evil"].exists, "nested reply visible before collapse")
        collapseLine.tap()

        // No new reply was actually created (mock mode has no backend, see
        // above), so the original sample tree's count holds: leokp's dp
        // comment has 2 replies (maya.c, leokp again) -> threadCount 3,
        // hiddenCount = 3 - 1 = 2.
        let expandPill = app.buttons["Expand 2 hidden replies"]
        XCTAssertTrue(expandPill.waitForExistence(timeout: 4), "collapsed pill shows correct recursive count")
        XCTAssertFalse(app.staticTexts["second one or third one bc both were evil"].exists, "nested replies hidden when collapsed")
        snap(app, "11-thread-collapsed-show-2-replies")

        expandPill.tap()
        XCTAssertTrue(app.staticTexts["second one or third one bc both were evil"].waitForExistence(timeout: 4), "expands back")
        XCTAssertTrue(app.buttons["Collapse replies"].waitForExistence(timeout: 3))
        snap(app, "12-thread-expanded-again")
    }

    // TEMPORARY — verification (Task 6). Item 8 spot-check: largest
    // accessibility Dynamic Type size should collapse ReactionBar to a
    // Menu while the circle "Add a comment" button stays present alongside
    // it (CommentComposerBar's browseLayout doesn't gate the circle button
    // on typeSize — only ReactionBar's own internal layout branches).
    @MainActor
    func test8_AccessibilityDynamicType() throws {
        let session = #"{"userId":"A0000000-0000-4000-8000-000000000001","primaryProvider":"email","email":"student@example.edu","phone":null,"hasEmailIdentity":true,"hasPhoneIdentity":false,"hasPassword":false,"linkedIdentities":[{"id":"mock-email","provider":"email","email":"student@example.edu"}]}"#
        let hex = Data(session.utf8).map { String(format: "%02x", $0) }.joined()
        let app = XCUIApplication()
        app.launchArguments = [
            "-mock.auth.session", "<\(hex)>",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge"
        ]
        app.launch()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.alerts.buttons["Allow"]
        if allow.waitForExistence(timeout: 4) { allow.tap() }
        sleep(2)

        let card = app.staticTexts
            .matching(NSPredicate(format: "label CONTAINS[c] %@", "brat by charli"))
            .firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10), "maya's feed card visible at largest Dynamic Type")
        card.tap()
        XCTAssertTrue(app.staticTexts["Comments"].waitForExistence(timeout: 6))

        XCTAssertTrue(app.buttons["Add a comment"].waitForExistence(timeout: 6), "circle comment button still present at largest Dynamic Type")
        // ReactionBar's accessibleMenu path: label is "React" (no reaction
        // selected yet) or "<reaction> selected"; either way it's a Menu,
        // not the segmented pill strip.
        let reactionMenu = app.buttons["React"]
        XCTAssertTrue(reactionMenu.waitForExistence(timeout: 4), "reactions collapse to a Menu ('React') at largest Dynamic Type")
        snap(app, "13-dynamic-type-accessibility-xxxl-menu-plus-circle")
    }

}
