//
//  OnboardingStatus.swift
//  On Board
//

import Foundation

struct OnboardingStatus: Equatable, Codable, Sendable {
    let id: UUID
    let handle: String
    let displayName: String
    let bio: String?
    let avatarUrl: String?
    let onboardingStep: OnboardingStep
    let onboardingCompletedAt: Date?
    let waitlistJoinedAt: Date?
    let verifiedSchoolEmail: String?
    let pendingSchoolEmail: String?
    let schoolName: String?
    let boardId: UUID?
    let boardName: String?

    /// Raw DB step — may read `complete` for users grandfathered by migration before picking a handle.
    var isComplete: Bool { onboardingStep == .complete }

    /// Step the app should route to. Defends against the server reporting `complete`
    /// for users that never actually finished onboarding (e.g. a fresh OIDC sign-in
    /// where the profile trigger short-circuits to `complete`).
    var effectiveOnboardingStep: OnboardingStep {
        guard onboardingStep == .complete else { return onboardingStep }

        if HandleRules.isProvisional(handle) {
            return .username
        }

        if displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .profile
        }

        // boardId is set only after admin approval. verifiedSchoolEmail alone is not
        // enough to bypass school verify — waitlistJoinedAt must not short-circuit
        // this gate (web pre-registrants have it stamped before verifying school).
        if verifiedSchoolEmail == nil, boardId == nil {
            return .schoolVerify
        }

        // Verified school and joined the waitlist, but admin hasn't admitted yet.
        // Return .waitlist so the coordinator keeps showing the confirmed button state
        // instead of routing to BoardListView with no board.
        if waitlistJoinedAt != nil, boardId == nil {
            return .waitlist
        }

        return .complete
    }

    var needsOnboarding: Bool { effectiveOnboardingStep != .complete }
}

enum HandleRules {
    private static let pattern = "^[a-zA-Z0-9._]{2,32}$"

    static func isValid(_ handle: String) -> Bool {
        let trimmed = handle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2, trimmed.count <= 32 else { return false }
        return trimmed.range(of: pattern, options: .regularExpression) != nil
    }

    /// Server-assigned placeholder handles before the user picks a username.
    static func isProvisional(_ handle: String) -> Bool {
        let trimmed = handle.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("u_") && trimmed.count <= 14
    }
}
