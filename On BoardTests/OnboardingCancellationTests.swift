//
//  OnboardingCancellationTests.swift
//  On BoardTests
//

import Foundation
import Testing
@testable import On_Board

/// Pins the store path behind onboarding's "Delete my info & cancel" action
/// (OnboardingCancelModifier): deleting the account must sign the user out
/// *and* destroy the persisted session, so a relaunch can't silently restore
/// a half-created account that no longer exists server-side.
struct OnboardingCancellationTests {
    @Test @MainActor func deleteAccountSignsOutAndClearsPersistedSession() async throws {
        let defaults = UserDefaults(suiteName: "OnboardingCancellationTests")!
        defaults.removePersistentDomain(forName: "OnboardingCancellationTests")
        let service = MockAuthService(defaults: defaults)
        let auth = AuthStore(service: service)

        await auth.signIn(with: .apple)
        #expect(auth.isSignedIn)

        try await auth.deleteAccount()

        #expect(!auth.isSignedIn)
        let restored = try await service.restoreSession()
        #expect(restored == nil)
    }

    @Test @MainActor func signInAfterCancellationStartsCleanly() async throws {
        let defaults = UserDefaults(suiteName: "OnboardingCancellationRejoinTests")!
        defaults.removePersistentDomain(forName: "OnboardingCancellationRejoinTests")
        let auth = AuthStore(service: MockAuthService(defaults: defaults))

        await auth.signIn(with: .apple)
        try await auth.deleteAccount()
        await auth.signIn(with: .apple)

        #expect(auth.isSignedIn)
        #expect(auth.session?.userId == SampleProfileID.maya)
    }
}
