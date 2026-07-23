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
        defer { UserDefaults.standard.removeObject(forKey: "welcomeShown.\(userID.uuidString)") }
        body(userID)
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
}
