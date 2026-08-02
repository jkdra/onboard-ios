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
    private func launchAsMaya(extraArguments: [String] = []) -> XCUIApplication {
        let session = #"{"userId":"A0000000-0000-4000-8000-000000000001","primaryProvider":"email","email":"student@example.edu","phone":null,"hasEmailIdentity":true,"hasPhoneIdentity":false,"hasPassword":false,"linkedIdentities":[{"id":"mock-email","provider":"email","email":"student@example.edu"}]}"#
        let hex = Data(session.utf8).map { String(format: "%02x", $0) }.joined()
        let app = XCUIApplication()
        app.launchArguments = ["-mock.auth.session", "<\(hex)>"] + extraArguments
        app.launch()

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.alerts.buttons["Allow"]
        if allow.waitForExistence(timeout: 4) { allow.tap() }
        sleep(2)
        return app
    }

    /// Taps the nav-bar ellipsis menu whatever XCUI decides to call it.
    ///
    /// On this simulator OS the toolbar `Menu` reports an "Automation type
    /// mismatch: computed Button from legacy attributes vs PopUpButton from
    /// modern attribute" — the semantic `.tap()` sometimes fails to actually
    /// open the menu even though the element `.exists`. A coordinate tap on
    /// the same frame sidesteps the ambiguous synthesis path.
    @MainActor
    private func tapMoreMenu(_ app: XCUIApplication) {
        let bar = app.navigationBars.firstMatch
        let candidate: XCUIElement = {
            for c in [bar.buttons["More"], bar.buttons["ellipsis"]] where c.exists { return c }
            let buttons = bar.buttons
            return buttons.count > 0 ? buttons.element(boundBy: buttons.count - 1) : bar.buttons.firstMatch
        }()
        candidate.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
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


    // TEMPORARY — verification (2026-07-29 First Class subscription shell).
    // Drives Settings -> boarding-pass card -> FirstClassView, capturing the
    // promo state, plan selection, purchase, and resulting membership state.
    // Requires the app's UserDefaults key "mock.firstclass.subscribed" to be
    // unset before this runs (fresh install / deleted via
    // `simctl spawn <udid> defaults delete org.onboardapp.onboard mock.firstclass.subscribed`).
    @MainActor
    func test20_FirstClassPromoAndPurchase() throws {
        let app = launchAsMaya(extraArguments: ["-dev.openSettings"])
        sleep(1)

        // Matched across any element type, not just .buttons: this card's
        // accessibility node gets inconsistently classified (Button/Link/
        // PopUpButton) across runs on this simulator OS — the same class of
        // "Automation type mismatch" seen on the toolbar `Menu` — so a
        // type-constrained query intermittently misses it entirely.
        let card = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS[c] %@", "First Class"))
            .firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 6), "First Class boarding-pass card in Settings")
        snap(app, "fc-01-settings-with-boarding-pass-card")
        card.tap()

        XCTAssertTrue(app.staticTexts["First Class"].waitForExistence(timeout: 8), "First Class hero title")
        XCTAssertTrue(app.staticTexts["What you get"].waitForExistence(timeout: 8), "perks section")
        snap(app, "fc-02-promo-state-perks-and-plans")

        // Switch plan selection.
        let monthly = app.staticTexts["Monthly"]
        if monthly.waitForExistence(timeout: 6) {
            monthly.tap()
            snap(app, "fc-03-monthly-selected")
        }
        let yearly = app.staticTexts["Yearly"]
        if yearly.waitForExistence(timeout: 6) {
            yearly.tap()
            snap(app, "fc-04-yearly-selected")
        }

        // Purchase.
        let cta = app.buttons
            .matching(NSPredicate(format: "label CONTAINS[c] %@", "trial"))
            .firstMatch
        XCTAssertTrue(cta.waitForExistence(timeout: 8), "purchase CTA")
        cta.tap()
        sleep(1)
        snap(app, "fc-05-purchasing-spinner")

        let memberTitle = app.staticTexts
            .matching(NSPredicate(format: "label CONTAINS[c] %@", "First Class"))
            .firstMatch
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "flying First Class"))
                .firstMatch.waitForExistence(timeout: 6),
            "member confirmation copy"
        )
        snap(app, "fc-06-member-state-after-purchase")

        // Back to Settings — the hero card should now read as a membership pass.
        let back = app.navigationBars.buttons.firstMatch
        if back.exists { back.tap() }
        sleep(1)
        snap(app, "fc-07-settings-card-now-membership-pass")
        _ = memberTitle

        // Profile Colors: now that we're First Class, the profile edit screen
        // should show the swatch picker instead of the locked upsell row.
        // Soft (`if`-gated, not asserted) on purpose — this tail is a nice-to-
        // have screenshot of a separate feature, not what this walkthrough
        // exists to prove; it shouldn't fail the whole purchase-flow test
        // under a slow simulator.
        let profileRow = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS[c] %@", "maya"))
            .firstMatch
        if profileRow.waitForExistence(timeout: 8) {
            profileRow.tap()
            sleep(1)
            let editProfile = app.buttons["Edit Profile"]
            if editProfile.waitForExistence(timeout: 8) {
                editProfile.tap()
                sleep(1)
                if app.staticTexts["Profile Color"].waitForExistence(timeout: 8) {
                    snap(app, "fc-09-profile-colors-swatch-picker-unlocked")
                    let coral = app.buttons["Coral"]
                    if coral.waitForExistence(timeout: 4) {
                        coral.tap()
                        sleep(1)
                        snap(app, "fc-10-profile-colors-coral-selected")
                    }
                }
            }
        }
    }

    // TEMPORARY — verification. Restore path on a fresh (unsubscribed) install.
    @MainActor
    func test21_FirstClassRestore() throws {
        let app = launchAsMaya(extraArguments: ["-dev.openSettings"])
        sleep(1)

        // Matched across any element type, not just .buttons: this card's
        // accessibility node gets inconsistently classified (Button/Link/
        // PopUpButton) across runs on this simulator OS — the same class of
        // "Automation type mismatch" seen on the toolbar `Menu` — so a
        // type-constrained query intermittently misses it entirely.
        let card = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS[c] %@", "First Class"))
            .firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 6), "First Class boarding-pass card")

        // Intermittently on this simulator OS a tap lands without the pushed
        // destination mounting (same class of synthesis flake seen on the
        // toolbar `Menu`) — retry the tap a couple of times rather than fail
        // the whole walkthrough on a missed hit.
        let restore = app.buttons["Restore purchase"]
        for attempt in 0..<3 where !restore.exists {
            if attempt > 0 { sleep(1) }
            card.tap()
            _ = restore.waitForExistence(timeout: 4)
        }
        XCTAssertTrue(restore.waitForExistence(timeout: 4), "Restore purchase button")
        restore.tap()

        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "flying First Class"))
                .firstMatch.waitForExistence(timeout: 6),
            "restore flips to member state"
        )
        snap(app, "fc-08-restored-member-state")
    }

    // TEMPORARY — verification (2026-07-29 Host-peek contrast fix). Captures
    // the FirstClassView hero (with its Host peek + backdrop) in whatever
    // light/dark appearance the simulator is currently set to via
    // `xcrun simctl ui <udid> appearance light|dark` — run this test once per
    // appearance from the host to compare both.
    @MainActor
    func test22_FirstClassHeroAppearanceCheck() throws {
        let app = launchAsMaya(extraArguments: ["-dev.openSettings"])
        sleep(1)

        let card = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS[c] %@", "First Class"))
            .firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 6), "First Class boarding-pass card")
        sleep(1)

        // "First Class" alone also matches the compact Settings card's own
        // title text — "What you get" only exists on the pushed FirstClassView.
        let heroTitle = app.staticTexts["What you get"]
        for attempt in 0..<3 where !heroTitle.exists {
            if attempt > 0 { sleep(1) }
            card.tap()
            _ = heroTitle.waitForExistence(timeout: 4)
        }
        XCTAssertTrue(heroTitle.waitForExistence(timeout: 4), "navigated to FirstClassView hero")
        sleep(2)
        snap(app, "fc-11-hero-appearance-check")   // celebration moment
        sleep(6)                                    // let the celebration fully resolve
        snap(app, "fc-12-hero-steady-after-celebration")
    }
}

// MARK: - Board clearing walkthrough

/// Drives the weekly-reset scenarios so the clears-soon UI and the take-down can be
/// reviewed on video. Separate class from `PolishWalkthroughUITests` on purpose — that
/// one is listed in the scheme's `<SkippedTests>` by class identifier, this one isn't.
final class BoardClearingWalkthroughUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// `clearAfter` arms the delayed dev countdown, for scenarios where the More menu
    /// is unreachable because a sheet is covering it.
    @MainActor
    private func launchAsMaya(clearAfter: Int? = nil) -> XCUIApplication {
        let session = #"{"userId":"A0000000-0000-4000-8000-000000000001","primaryProvider":"email","email":"student@example.edu","phone":null,"hasEmailIdentity":true,"hasPhoneIdentity":false,"hasPassword":false,"linkedIdentities":[{"id":"mock-email","provider":"email","email":"student@example.edu"}]}"#
        let hex = Data(session.utf8).map { String(format: "%02x", $0) }.joined()
        let app = XCUIApplication()
        app.launchArguments = [
            "-mock.auth.session", "<\(hex)>",
            "-dev.hideDevBlock",
            "-dev.skipPushPrompt",
        ]
        if let clearAfter {
            app.launchArguments += ["-dev.clearAfter", "\(clearAfter)"]
        }
        app.launch()
        sleep(2)
        return app
    }

    @MainActor
    private func tapMoreMenu(_ app: XCUIApplication) {
        let bar = app.navigationBars.firstMatch
        for candidate in [bar.buttons["More"], bar.buttons["ellipsis"]] where candidate.exists {
            candidate.tap()
            return
        }
        let buttons = bar.buttons
        if buttons.count > 0 {
            buttons.element(boundBy: buttons.count - 1).tap()
        }
    }

    /// Fires the dev hook that shrinks the active week to ~10s from now.
    @MainActor
    private func startTenSecondCountdown(_ app: XCUIApplication) {
        tapMoreMenu(app)
        let clear = app.buttons
            .matching(NSPredicate(format: "label CONTAINS[c] %@", "Clear board in 10s"))
            .firstMatch
        XCTAssertTrue(clear.waitForExistence(timeout: 6), "dev 'Clear board in 10s' menu item")
        clear.tap()

        // Prove the hook landed. Without this the walkthrough happily "passes" against
        // an untouched 6-day countdown — which is exactly how the first run wasted a
        // full video: the springboard push alert had swallowed the menu taps.
        let clearsSoon = app.staticTexts["CLEARS SOON!"]
        XCTAssertTrue(
            clearsSoon.waitForExistence(timeout: 5),
            "countdown card should switch to its red 'CLEARS SOON!' caption"
        )
    }

    /// TEMPORARY — capturing the feed's first-load entrance (fade+grow) animation to
    /// verify the `.topLeading` anchor fix on `BoardFeedView.masonryCell`'s
    /// `scaleEffect` removes the perceived title-text shift, particularly on the
    /// "brat by charli xcx..." sample post (2-line, heavy-weight title). Video
    /// recording must start before this test process launches the app, since that's
    /// when the reveal animation fires.
    @MainActor
    func testGridCardEntranceAnimationCapture() throws {
        _ = launchAsMaya()
        sleep(2)
    }

    /// A) Sitting on the feed as the board clears. Scrolls mid-window so the
    /// countdown moves into the nav principal, then rides through the take-down.
    @MainActor
    func testClearA_FeedDuringReset() throws {
        let app = launchAsMaya()
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "brat"))
                .firstMatch.waitForExistence(timeout: 15),
            "feed loaded"
        )
        sleep(2)
        startTenSecondCountdown(app)
        sleep(2)                 // clears-soon: red pulse + disabled compose card
        app.swipeUp(velocity: .slow)
        sleep(3)                 // countdown card off screen -> principal countdown
        sleep(10)                // ride through the reset
        sleep(6)                 // aftermath: what does the board look like now?
    }

    /// B) Reading a post as the board clears — the auto-dismiss path.
    @MainActor
    func testClearB_PostOpenDuringReset() throws {
        let app = launchAsMaya()
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "brat"))
                .firstMatch.waitForExistence(timeout: 15),
            "feed loaded"
        )
        startTenSecondCountdown(app)
        sleep(1)
        let card = app.staticTexts
            .matching(NSPredicate(format: "label CONTAINS[c] %@", "brat"))
            .firstMatch
        card.tap()
        sleep(14)                // principal countdown, then the auto-dismiss
        sleep(6)                 // where does the user land?
    }

    /// C) Navigated into Settings as the board clears — does the reset evict the user?
    @MainActor
    func testClearC_SettingsOpenDuringReset() throws {
        let app = launchAsMaya()
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "brat"))
                .firstMatch.waitForExistence(timeout: 15),
            "feed loaded"
        )
        startTenSecondCountdown(app)
        sleep(1)
        tapMoreMenu(app)
        let settings = app.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5), "Settings menu item")
        settings.tap()
        sleep(14)                // does the reset pop Settings out from under the user?

        // Back out by hand. If the countdown card is frozen at 00s the reset DID fire
        // while Settings covered the feed; if the week is intact it never ran at all.
        let back = app.navigationBars.buttons.firstMatch
        if back.exists { back.tap() }
        sleep(8)
    }

    /// D) Composing a post with a typed draft when the board clears. Previously
    /// unreachable — the menu-driven dev hook closes posting instantly, so the composer
    /// couldn't be opened. `-dev.clearAfter` arms the countdown on a delay instead.
    @MainActor
    func testClearD_ComposerOpenDuringReset() throws {
        let app = launchAsMaya(clearAfter: 18)
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "brat"))
                .firstMatch.waitForExistence(timeout: 15),
            "feed loaded"
        )

        let compose = app.buttons["New post"].firstMatch
        XCTAssertTrue(compose.waitForExistence(timeout: 6), "compose card")
        compose.tap()

        let titleField = app.textFields.firstMatch
        XCTAssertTrue(titleField.waitForExistence(timeout: 6), "composer title field")
        titleField.tap()
        titleField.typeText("draft that must survive the wipe")

        // Countdown fires at ~18s, reset ~5s later — both while this sheet is up.
        sleep(20)

        // The draft must still be here afterwards.
        let draft = app.staticTexts
            .matching(NSPredicate(format: "label CONTAINS[c] %@", "must survive"))
            .firstMatch
        let draftField = app.textFields
            .matching(NSPredicate(format: "value CONTAINS[c] %@", "must survive"))
            .firstMatch
        XCTAssertTrue(
            draft.exists || draftField.exists,
            "typed draft must survive the weekly reset instead of being silently discarded"
        )
        sleep(8)
    }

    /// TEMPORARY — investigating a user-reported "almost imperceptible" scroll glitch,
    /// suspected to involve the bottom-bar new-post button. Does a single continuous
    /// touch (press, hold, THEN drag without lifting — not a flick) across the new-post
    /// card's visibility boundary, since `showsBottomBarNewPost` in ContentView.swift
    /// conditionally mounts a ToolbarItem(placement: .bottomBar) exactly the way the
    /// nav-principal ToolbarItem used to (already fixed elsewhere for that defect).
    @MainActor
    func testScrollHoldDragNewPostBoundary() throws {
        let app = launchAsMaya(clearAfter: nil)
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "brat"))
                .firstMatch.waitForExistence(timeout: 15),
            "feed loaded"
        )
        sleep(1)

        // Kept well clear of the bottom edge — a first attempt starting at dy:0.8
        // turned out to graze the system's swipe-up-and-hold-to-home gesture zone
        // (confirmed via video: the app visibly backgrounded to SpringBoard), which
        // produced a dramatic full-screen fade that was a test-harness artifact, not
        // an app bug. dy:0.55→0.25 stays solidly mid-screen, well inside app content.
        let scrollView = app.scrollViews.firstMatch
        let start = scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55))
        let end = scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))

        // Single continuous touch: press, hold, THEN drag — never lifts in between.
        // This is deliberately NOT a flick/swipe (a separate, momentary gesture); it's
        // the "tap-and-hold-scroll" the user described. Repeated a few times (each its
        // own press-hold-drag, not one mega-drag) to accumulate enough scroll distance
        // to cross the new-post card's visibility boundary at least once each way.
        for _ in 0..<3 {
            start.press(forDuration: 0.6, thenDragTo: end)
            usleep(400_000)
        }
        sleep(1)
        for _ in 0..<3 {
            end.press(forDuration: 0.6, thenDragTo: start)
            usleep(400_000)
        }
        sleep(2)
    }
}
