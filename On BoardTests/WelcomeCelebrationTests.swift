//
//  WelcomeCelebrationTests.swift
//  On BoardTests
//
//  Pins the per-user "has seen the welcome" flag. The celebration must fire
//  at most once per user id per device, and one user's flag must never leak
//  into another's — otherwise a second account on the same device would skip
//  the mandatory admission + pledge flow.
//

import Foundation
import Testing
@testable import On_Board

@MainActor
struct WelcomeCelebrationTests {

    /// `WelcomeCelebration` writes to `UserDefaults.standard`; every test uses a
    /// fresh random user id (so keys never collide) and clears it afterwards.
    private func withFreshUser(_ body: (UUID) -> Void) {
        let userID = UUID()
        defer {
            UserDefaults.standard.removeObject(forKey: "welcomeShown.\(userID.uuidString)")
            UserDefaults.standard.removeObject(forKey: "sawIncompleteOnboarding.\(userID.uuidString)")
        }
        body(userID)
    }

    /// Mirrors RootView's trigger: the welcome fires when the user reaches
    /// complete AND this install saw them mid-onboarding (in-session OR
    /// persisted) AND it hasn't already shown.
    private func shouldShowWelcome(sawIncompleteThisSession: Bool, userID: UUID) -> Bool {
        (sawIncompleteThisSession || WelcomeCelebration.wasSeenIncomplete(for: userID))
            && !WelcomeCelebration.hasShown(for: userID)
    }

    @Test func unseenUserHasNotShown() {
        withFreshUser { userID in
            #expect(WelcomeCelebration.hasShown(for: userID) == false)
        }
    }

    @Test func markShownFlipsTheFlag() {
        withFreshUser { userID in
            WelcomeCelebration.markShown(for: userID)
            #expect(WelcomeCelebration.hasShown(for: userID) == true)
        }
    }

    @Test func flagIsScopedToTheUser() {
        withFreshUser { seenUser in
            withFreshUser { otherUser in
                WelcomeCelebration.markShown(for: seenUser)
                #expect(WelcomeCelebration.hasShown(for: seenUser) == true)
                // A different user id on the same device is unaffected.
                #expect(WelcomeCelebration.hasShown(for: otherUser) == false)
            }
        }
    }

    // MARK: - Cold-launch-after-admission gap

    /// The bug: a user admitted while the app was closed cold-launches straight
    /// to `complete` without the in-session incomplete flag ever flipping. The
    /// persisted `seenIncomplete` marker from their onboarding session is what
    /// lets the welcome still fire.
    @Test func persistedIncompleteFiresWelcomeOnColdLaunch() {
        withFreshUser { userID in
            // Onboarding session marked them incomplete (persisted).
            WelcomeCelebration.markSeenIncomplete(for: userID)
            // Fresh cold-launch session: no in-session signal at all.
            #expect(shouldShowWelcome(sawIncompleteThisSession: false, userID: userID) == true)
        }
    }

    /// A returning, already-complete user signing in on a NEW device (no
    /// persisted marker, never seen incomplete here) must NOT see the welcome.
    @Test func returningUserOnNewDeviceStaysSilent() {
        withFreshUser { userID in
            #expect(shouldShowWelcome(sawIncompleteThisSession: false, userID: userID) == false)
        }
    }

    /// Once shown, a later cold launch never repeats it, even with the marker set.
    @Test func neverRepeatsAfterShown() {
        withFreshUser { userID in
            WelcomeCelebration.markSeenIncomplete(for: userID)
            WelcomeCelebration.markShown(for: userID)
            #expect(shouldShowWelcome(sawIncompleteThisSession: true, userID: userID) == false)
        }
    }

    @Test func seenIncompleteIsScopedToTheUser() {
        withFreshUser { seenUser in
            withFreshUser { otherUser in
                WelcomeCelebration.markSeenIncomplete(for: seenUser)
                #expect(WelcomeCelebration.wasSeenIncomplete(for: seenUser) == true)
                #expect(WelcomeCelebration.wasSeenIncomplete(for: otherUser) == false)
            }
        }
    }
}
