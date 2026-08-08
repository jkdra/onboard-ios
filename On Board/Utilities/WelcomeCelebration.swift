//
//  WelcomeCelebration.swift
//  On Board
//

import Foundation

/// Per-user welcome-celebration bookkeeping.
///
/// The welcome must fire the first time a user reaches `complete`, but NOT for a
/// returning, already-complete user signing in on a fresh device. The signal
/// that distinguishes them is "did THIS install ever see this user mid-onboarding
/// (incomplete / waitlisted)". `markSeenIncomplete` records that persistently, so
/// the celebration still fires on a cold launch after an admission that happened
/// while the app was closed — the common admin-admit → "You're On Board!" push
/// path — which an in-session-only flag would miss. `hasShown` then guards
/// against ever repeating it.
enum WelcomeCelebration {
    private static func key(for userID: UUID) -> String {
        "welcomeShown.\(userID.uuidString)"
    }
    private static func incompleteKey(for userID: UUID) -> String {
        "sawIncompleteOnboarding.\(userID.uuidString)"
    }

    static func hasShown(for userID: UUID) -> Bool {
        UserDefaults.standard.bool(forKey: key(for: userID))
    }

    static func markShown(for userID: UUID) {
        UserDefaults.standard.set(true, forKey: key(for: userID))
    }

    /// Whether this install has ever observed this user needing onboarding.
    static func wasSeenIncomplete(for userID: UUID) -> Bool {
        UserDefaults.standard.bool(forKey: incompleteKey(for: userID))
    }

    static func markSeenIncomplete(for userID: UUID) {
        UserDefaults.standard.set(true, forKey: incompleteKey(for: userID))
    }
}
