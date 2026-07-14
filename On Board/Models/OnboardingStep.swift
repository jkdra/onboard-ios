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
    case waitlist
    case complete
}
