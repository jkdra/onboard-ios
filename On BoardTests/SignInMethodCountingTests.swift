//
//  SignInMethodCountingTests.swift
//  On BoardTests
//

import Foundation
import Testing
@testable import On_Board

@MainActor
struct SignInMethodCountingTests {
    private func session(
        email: String? = nil,
        phone: String? = nil,
        hasEmailIdentity: Bool = false,
        hasPhoneIdentity: Bool = false,
        identities: [LinkedIdentity] = []
    ) -> AuthSession {
        AuthSession(
            userId: UUID(),
            primaryProvider: .google,
            email: email,
            phone: phone,
            hasEmailIdentity: hasEmailIdentity,
            hasPhoneIdentity: hasPhoneIdentity,
            linkedIdentities: identities
        )
    }

    // A Google-only user has user.email copied from the OAuth provider.
    // That copied email must NOT count as a sign-in method.
    @Test func oauthCopiedEmailDoesNotAllowUnlinkingSoleIdentity() {
        let google = LinkedIdentity(id: "g1", provider: .google, email: "me@gmail.com")
        let s = session(email: "me@gmail.com", identities: [google])
        #expect(!s.canUnlinkIdentity(google))
        #expect(s.remainingSignInMethodCount(excludingIdentityId: "g1") == 0)
    }

    @Test func realEmailIdentityAllowsUnlinkingOAuth() {
        let google = LinkedIdentity(id: "g1", provider: .google, email: "me@gmail.com")
        let s = session(email: "me@gmail.com", hasEmailIdentity: true, identities: [google])
        #expect(s.canUnlinkIdentity(google))
    }

    @Test func hasLinkedUsesIdentityFlagsNotCopiedFields() {
        let s = session(email: "me@gmail.com", phone: "+15555550100")
        #expect(!s.hasLinked(.email))
        #expect(!s.hasLinked(.phone))
        let s2 = session(hasEmailIdentity: true, hasPhoneIdentity: true)
        #expect(s2.hasLinked(.email))
        #expect(s2.hasLinked(.phone))
    }

    @Test func decodingOldSessionWithoutFlagsDefaultsToFalse() throws {
        let json = """
        {"userId":"\(UUID().uuidString)","primaryProvider":"google","email":"a@b.co","linkedIdentities":[]}
        """
        let decoded = try JSONDecoder().decode(AuthSession.self, from: Data(json.utf8))
        #expect(!decoded.hasEmailIdentity)
        #expect(!decoded.hasPhoneIdentity)
    }
}
