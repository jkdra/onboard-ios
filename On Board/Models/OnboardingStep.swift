//
//  OnboardingStep.swift
//  On Board
//

import Foundation

enum OnboardingStep: String, Codable, Sendable, CaseIterable, Hashable {
    case birthday
    case username
    case profile
    case schoolVerify = "school_verify"
    /// Client-only HOLD state — never persisted server-side (no backing DB
    /// enum value), and never pushed: its target path equals `.schoolVerify`'s,
    /// keeping the user on the school screen's graduation stage while
    /// `expected_graduation` is still null. The persisted field is the
    /// completion signal.
    case graduation
    /// Client-only step — never persisted server-side. The profanity
    /// preference, as its own pushed screen after graduation (Jawad's call,
    /// 2026-08-08: one decision per screen). Completion is the local
    /// `hasCompletedProfanityStep` flag; the preference itself stays plain,
    /// un-scoped `@AppStorage("profanityEnabled")` — per-device, not
    /// per-account, the documented design.
    case contentPreferences = "content_preferences"
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
        [.birthday, .username, .profile,
         .schoolVerify, .graduation, .contentPreferences, .waitlist, .complete]
    }

    nonisolated init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = OnboardingStep(rawValue: raw) ?? .unrecognized
    }
}
