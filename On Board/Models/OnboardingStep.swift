//
//  OnboardingStep.swift
//  On Board
//

import Foundation

enum OnboardingStep: String, Codable, Sendable, CaseIterable, Hashable {
    case birthday
    case username
    case profile
    /// Client-only step — never persisted server-side (no backing DB column/enum
    /// value). Completion is tracked locally via `@AppStorage`, since the content
    /// preference it sets (`profanityEnabled`) is itself a local, per-device
    /// setting, not account data. See `OnboardingCoordinator.effectiveStep`.
    case contentPreferences = "content_preferences"
    case schoolVerify = "school_verify"
    /// Client-only step — never persisted server-side (no backing DB enum value).
    /// Inserted after school verification when `expected_graduation` is still
    /// null; the persisted field itself is the completion signal (unlike
    /// contentPreferences, which uses a local flag). See
    /// `OnboardingCoordinator.effectiveStep`.
    case graduation
    case waitlist
    case complete
}
