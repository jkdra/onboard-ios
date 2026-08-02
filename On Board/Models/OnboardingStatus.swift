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
    let birthday: String?
    let showBirthday: Bool?
    let onboardingStep: OnboardingStep
    let onboardingCompletedAt: Date?
    let waitlistJoinedAt: Date?
    let verifiedSchoolEmail: String?
    let pendingSchoolEmail: String?
    let schoolName: String?
    let boardId: UUID?
    let boardName: String?
    
    // Referral fields
    let referralCode: String?
    let verifiedReferralCount: Int?
    /// Golden-ticket quota: while admitted, each signup through this user's
    /// code consumes one and skips the waitlist. nil until the migration ships.
    let instantInvitesRemaining: Int?

    /// Expected graduation month as an ISO date string ("2027-05-01"), or nil
    /// if the user hasn't provided it yet. Drives the client-inserted
    /// `.graduation` onboarding step and the Institution Settings editor.
    let expectedGraduation: String?

    /// Raw DB step — may read `complete` for users grandfathered by migration before picking a handle.
    var isComplete: Bool { onboardingStep == .complete }

    /// Step the app should route to. Defends against the server reporting `complete`
    /// for users that never actually finished onboarding (e.g. a fresh OIDC sign-in
    /// where the profile trigger short-circuits to `complete`).
    var effectiveOnboardingStep: OnboardingStep {
        if birthday == nil {
            return .birthday
        }

        guard onboardingStep == .complete else { return onboardingStep }

        if HandleRules.isProvisional(handle) {
            return .username
        }

        // Deliberately NO display-name gate here: display name is optional by
        // design (the profile step says so), so an empty one is not evidence
        // of unfinished onboarding. The old `displayName.isEmpty → .profile`
        // check trapped legitimately-admitted users who skipped it in an
        // inescapable loop — server said complete, client bounced them to the
        // profile step, and resubmitting an (allowed) empty name re-tripped
        // the gate. The provisional-handle check above already catches
        // accounts that truly never finished.

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

/// Referral reward ladder: 1–3 verified invites buy queue priority; the 4th
/// earns a free month of On Board First Class (when it launches); the 5th
/// upgrades that to 3 months.
///
/// Rewards are DERIVED from the live count on purpose, never latched:
/// deleting a referred account already claws back the referrer's count, and
/// deriving keeps the reward consistent with that clawback — a latched
/// milestone could be farmed with disposable accounts. Redemption tracking
/// becomes real work only when First Class ships.
/// Single source of truth for invite links and share copy — used by both the
/// waitlist step and the Settings invite section.
enum InviteLink {
    static func url(for code: String) -> URL? {
        URL(string: "https://onboardapp.org/invite/\(code.lowercased())")
    }

    /// Instant-invite copy while the sharer has golden tickets left; waitlist
    /// priority copy otherwise.
    static func shareMessage(code: String, hasInstantInvites: Bool) -> String {
        if hasInstantInvites {
            return "I've got an instant invite to On Board — use my code \(code.uppercased()) to skip the waitlist!"
        }
        return "I'm on the waitlist for On Board. Use my code \(code.uppercased()) to skip the line!"
    }
}

enum ReferralRewards {
    static let oneMonthThreshold = 4
    static let threeMonthThreshold = 5

    /// First Class is progressively disclosed: invites 1–3 are pitched purely
    /// as queue priority, and the subscription reward is only revealed once
    /// the user is one invite away from earning it. Keeps the unlaunched
    /// subscription out of everyone's face and lands the reveal on proven
    /// sharers.
    static let disclosureThreshold = 3

    /// Thresholds are parameters (defaulting to the compiled constants) so the
    /// waitlist screen can pass `RemoteConfig` values once First Class ships and
    /// its call site is uncommented — retuning the viral loop is exactly the
    /// kind of change you want without waiting on App Review.
    static func earnedFirstClassMonths(
        for count: Int,
        oneMonth: Int = oneMonthThreshold,
        threeMonth: Int = threeMonthThreshold
    ) -> Int {
        if count >= threeMonth { return 3 }
        if count >= oneMonth { return 1 }
        return 0
    }

    /// Milestone line for the waitlist card; nil below the disclosure
    /// threshold (no First Class mention at all).
    static func milestoneText(
        for count: Int,
        oneMonth: Int = oneMonthThreshold,
        threeMonth: Int = threeMonthThreshold,
        disclosure: Int = disclosureThreshold
    ) -> String? {
        switch earnedFirstClassMonths(for: count, oneMonth: oneMonth, threeMonth: threeMonth) {
        case 3:
            return "🏆 3 free months of First Class earned!"
        case 1:
            return "🎟️ Free month of First Class earned — 1 more invite makes it 3!"
        default:
            guard count >= disclosure else { return nil }
            return "✨ 1 more invite to earn a free month of On Board First Class"
        }
    }
}

enum HandleRules {
    private static let pattern = "^[a-zA-Z0-9._]{2,32}$"

    /// Impersonation-prone handles blocked for everyone. Mirrors the server list
    /// in `check_handle_available` so the client can reject them instantly.
    static let reserved: Set<String> = [
        "admin", "administrator", "mod", "moderator", "support", "staff",
        "official", "onboard", "onboardapp", "help", "team", "root", "system",
        "everyone", "here", "anonymous", "deleted", "moderation", "security"
    ]

    static func isReserved(_ handle: String) -> Bool {
        reserved.contains(handle.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }

    static func isValid(_ handle: String) -> Bool {
        let trimmed = handle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2, trimmed.count <= 32 else { return false }
        guard !isReserved(trimmed) else { return false }
        return trimmed.range(of: pattern, options: .regularExpression) != nil
    }

    /// Server-assigned placeholder handles before the user picks a username.
    static func isProvisional(_ handle: String) -> Bool {
        let trimmed = handle.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("u_") && trimmed.count <= 14
    }
}
