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

    /// A step this build doesn't know about — a value added to the
    /// `onboarding_step` Postgres enum after this version shipped.
    ///
    /// Every other wire enum in the app degrades to a usable local value. This
    /// one deliberately does not: mapping an unknown step to `.complete` would
    /// admit a user who never finished onboarding, and mapping it to any
    /// concrete step could trap them in a loop with no exit. Stopping and asking
    /// them to update is the only correct behavior, so this routes to
    /// `OnboardingUpdateRequiredView`.
    case unrecognized = "__unrecognized__"

    /// Deliberately excludes `.unrecognized`. `OnboardingCoordinator.rank(_:)`
    /// uses `allCases.firstIndex(of:)` for step ordering and
    /// `OnboardingProgressBar` takes a step index — a sentinel in this list
    /// would shift both.
    static var allCases: [OnboardingStep] {
        [.birthday, .username, .profile, .contentPreferences,
         .schoolVerify, .graduation, .waitlist, .complete]
    }

    nonisolated init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = OnboardingStep(rawValue: raw) ?? .unrecognized
    }
}
