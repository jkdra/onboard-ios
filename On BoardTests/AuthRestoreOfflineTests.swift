//
//  AuthRestoreOfflineTests.swift
//  On BoardTests
//

import Foundation
import Testing
@testable import On_Board

@MainActor
struct AuthRestoreOfflineTests {
    @Test func connectivityFailureDuringRestoreBecomesRestoreFailedOffline() async {
        let service = ScriptedAuthService()
        service.restoreResult = .failure(AuthError.networkUnavailable)
        let store = AuthStore(service: service)
        await store.restoreSession()
        #expect(store.state == .restoreFailedOffline)
        #expect(!store.isSignedIn)
    }

    @Test func signOutErrorStillSignsOutLocally() async {
        let service = ScriptedAuthService()
        service.signOutError = AuthError.networkUnavailable
        let store = AuthStore(service: service)
        await store.signOut()
        #expect(store.state == .signedOut)
    }
}
