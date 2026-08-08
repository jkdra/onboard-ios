//
//  AuthSessionTests.swift
//  On BoardTests
//

import Foundation
import Testing
@testable import On_Board

@MainActor
struct AuthSessionTests {
    @Test func countsSignInMethodsForUnlinkGuardrails() {
        let appleOnly = AuthSession(
            userId: UUID(),
            primaryProvider: .apple,
            linkedIdentities: [LinkedIdentity(id: "apple-1", provider: .apple, email: "you@icloud.com")]
        )
        #expect(!appleOnly.canUnlinkIdentity(appleOnly.linkedIdentities[0]))

        let phoneAndApple = AuthSession(
            userId: UUID(),
            primaryProvider: .phone,
            phone: "+15555550100",
            hasPhoneIdentity: true,
            linkedIdentities: [LinkedIdentity(id: "apple-1", provider: .apple, email: nil)]
        )
        #expect(phoneAndApple.canUnlinkIdentity(phoneAndApple.linkedIdentities[0]))
    }
}
