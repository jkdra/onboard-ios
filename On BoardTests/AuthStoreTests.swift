//
//  AuthStoreTests.swift
//  On BoardTests
//

import Foundation
import Testing
@testable import On_Board

struct AuthStoreTests {
    @Test @MainActor func signInUpdatesState() async {
        let defaults = UserDefaults(suiteName: "AuthStoreTests")!
        defaults.removePersistentDomain(forName: "AuthStoreTests")
        let auth = AuthStore(service: MockAuthService(defaults: defaults))

        await auth.signIn(with: .apple)
        #expect(auth.isSignedIn)
        #expect(auth.session?.userId == SampleProfileID.maya)
    }

    @Test @MainActor func signOutClearsState() async {
        let defaults = UserDefaults(suiteName: "AuthStoreSignOutTests")!
        defaults.removePersistentDomain(forName: "AuthStoreSignOutTests")
        let auth = AuthStore(service: MockAuthService(defaults: defaults))

        await auth.signIn(with: .apple)
        await auth.signOut()
        #expect(!auth.isSignedIn)
    }
}
