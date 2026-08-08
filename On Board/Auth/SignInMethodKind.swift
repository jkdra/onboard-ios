//
//  SignInMethodKind.swift
//  On Board
//

import Foundation

extension AuthSession {
    func remainingSignInMethodCount(excludingIdentityId: String? = nil) -> Int {
        var count = 0
        if hasPhoneIdentity { count += 1 }
        if hasEmailIdentity { count += 1 }
        for identity in linkedIdentities where identity.id != excludingIdentityId {
            count += 1
        }
        return count
    }

    func canUnlinkIdentity(_ identity: LinkedIdentity) -> Bool {
        remainingSignInMethodCount(excludingIdentityId: identity.id) > 0
    }

    func hasLinked(_ provider: AuthProvider) -> Bool {
        switch provider {
        case .phone:
            hasPhoneIdentity
        case .email:
            hasEmailIdentity
        case .apple, .google:
            linkedIdentities.contains { $0.provider == provider }
        }
    }
}
