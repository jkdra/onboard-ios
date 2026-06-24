//
//  SignInMethodKind.swift
//  On Board
//

import Foundation

enum SignInMethodKind: Equatable, Sendable {
    case phone
    case email
    case apple
    case google
}

extension AuthSession {
    var signInMethodKinds: [SignInMethodKind] {
        var methods: [SignInMethodKind] = []
        if let phone, !phone.isEmpty {
            methods.append(.phone)
        }
        if let email, !email.isEmpty {
            methods.append(.email)
        }
        for identity in linkedIdentities {
            switch identity.provider {
            case .apple where !methods.contains(.apple):
                methods.append(.apple)
            case .google where !methods.contains(.google):
                methods.append(.google)
            default:
                break
            }
        }
        return methods
    }

    func remainingSignInMethodCount(excludingIdentityId: String? = nil) -> Int {
        var count = 0
        if let phone, !phone.isEmpty { count += 1 }
        if let email, !email.isEmpty { count += 1 }
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
            phone?.isEmpty == false
        case .email:
            email?.isEmpty == false
        case .apple, .google:
            linkedIdentities.contains { $0.provider == provider }
        }
    }
}
