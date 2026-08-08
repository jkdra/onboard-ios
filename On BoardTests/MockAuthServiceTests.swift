//
//  MockAuthServiceTests.swift
//  On BoardTests
//

import Foundation
import Testing
@testable import On_Board

@MainActor
struct MockAuthServiceTests {
    @Test func signInPersistsAndRestoresSession() async throws {
        let defaults = UserDefaults(suiteName: "MockAuthServiceTests")!
        defaults.removePersistentDomain(forName: "MockAuthServiceTests")
        let service = MockAuthService(defaults: defaults)

        let session = try await service.signIn(with: .apple)
        #expect(session.userId == SampleProfileID.maya)
        #expect(session.provider == .apple)
        #expect(session.hasLinked(.apple))

        let restored = try await service.restoreSession()
        #expect(restored == session)

        try await service.signOut()
        let cleared = try await service.restoreSession()
        #expect(cleared == nil)
    }

    @Test func googleSignInUsesDifferentSampleUser() async throws {
        let defaults = UserDefaults(suiteName: "MockAuthServiceGoogleTests")!
        defaults.removePersistentDomain(forName: "MockAuthServiceGoogleTests")
        let service = MockAuthService(defaults: defaults)

        let session = try await service.signIn(with: .google)
        #expect(session.userId == SampleProfileID.leo)
        #expect(session.hasLinked(.google))
    }

    @Test func cannotUnlinkLastSignInMethod() async throws {
        let defaults = UserDefaults(suiteName: "MockAuthUnlinkTests")!
        defaults.removePersistentDomain(forName: "MockAuthUnlinkTests")
        let service = MockAuthService(defaults: defaults)

        let session = try await service.signIn(with: .apple)
        let identity = try #require(session.linkedIdentities.first)

        do {
            _ = try await service.unlinkIdentity(id: identity.id)
            Issue.record("Expected cannotUnlinkLastSignInMethod")
        } catch let error as AuthError {
            #expect(error == .cannotUnlinkLastSignInMethod)
        }
    }

    @Test func canUnlinkWhenBackupMethodExists() async throws {
        let defaults = UserDefaults(suiteName: "MockAuthUnlinkBackupTests")!
        defaults.removePersistentDomain(forName: "MockAuthUnlinkBackupTests")
        let service = MockAuthService(defaults: defaults)

        _ = try await service.signIn(with: .apple)
        _ = try await service.verifyLinkPhoneOTP(phone: "+15555550123", token: "123456")
        let session = try await service.restoreSession()
        let identity = try #require(session?.linkedIdentities.first)

        let updated = try await service.unlinkIdentity(id: identity.id)
        #expect(updated.linkedIdentities.isEmpty)
        #expect(updated.hasLinked(.phone))
    }
}
