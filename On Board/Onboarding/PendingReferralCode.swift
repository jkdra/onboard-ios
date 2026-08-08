//
//  PendingReferralCode.swift
//  On Board
//

import Foundation

/// A referral code captured from an invite deep link before the user reaches
/// the profile step. Lives in UserDefaults (not the store) so it survives the
/// sign-in flow; cleared on successful submission and on sign-out so it can't
/// leak into a different account's onboarding on the same device.
enum PendingReferralCode {
    static let key = "pendingReferralCode"

    static func store(_ code: String) {
        UserDefaults.standard.set(code, forKey: key)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
