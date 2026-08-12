//
//  PendingSchoolVerificationToken.swift
//  On Board
//

import Foundation

/// A one-tap verification token captured from `onboardapp.org/verify/<token>`.
///
/// The tap can land at an awkward moment — the app cold-launching, sitting on
/// a different onboarding step, or not yet signed in — so the token parks here
/// (UserDefaults, like `PendingReferralCode`) until the school step is on
/// screen and able to spend it. Cleared on success, on failure, and on
/// sign-out, so a token can never leak into a different account's onboarding
/// on the same device.
enum PendingSchoolVerificationToken {
    static let key = "pendingSchoolVerificationToken"

    /// Tokens are 32 random bytes as unpadded base64url (43 chars). Anything
    /// wildly off that shape is a malformed link, not a token — reject it
    /// before it reaches the server.
    private static let maxLength = 128

    static func store(_ token: String) {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= maxLength else { return }
        UserDefaults.standard.set(trimmed, forKey: key)
    }

    static var current: String? {
        UserDefaults.standard.string(forKey: key)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
