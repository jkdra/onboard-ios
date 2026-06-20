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
    let avatarEmoji: String
    let onboardingStep: OnboardingStep
    let onboardingCompletedAt: Date?
    let waitlistJoinedAt: Date?
    let verifiedSchoolEmail: String?
    let pendingSchoolEmail: String?
    let schoolName: String?
    let boardId: UUID?
    let boardName: String?

    var isComplete: Bool { onboardingStep == .complete }
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
