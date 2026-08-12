//
//  OnboardingStalenessTests.swift
//  On BoardTests
//

import Foundation
import Testing
@testable import On_Board

@MainActor
struct OnboardingStalenessTests {
    /// Wraps `MockOnboardingService` to count `fetchStatus()` calls, so the test
    /// can assert `refreshIfOnline()` only refetches once the cached status is stale.
    private final class CountingOnboardingService: OnboardingService, @unchecked Sendable {
        let inner: MockOnboardingService
        nonisolated(unsafe) var fetchCount = 0

        init(defaults: UserDefaults) {
            inner = MockOnboardingService(defaults: defaults)
        }

        func fetchStatus() async throws -> OnboardingStatus {
            fetchCount += 1
            return try await inner.fetchStatus()
        }

        func completeBirthday(birthday: Date, showBirthday: Bool) async throws -> OnboardingStep {
            try await inner.completeBirthday(birthday: birthday, showBirthday: showBirthday)
        }

        func checkHandleAvailable(_ handle: String) async throws -> Bool {
            try await inner.checkHandleAvailable(handle)
        }

        func completeUsername(_ handle: String) async throws -> OnboardingStep {
            try await inner.completeUsername(handle)
        }

        func completeProfile(displayName: String, bio: String?, avatarUrl: String?) async throws -> OnboardingStep {
            try await inner.completeProfile(displayName: displayName, bio: bio, avatarUrl: avatarUrl)
        }

        func lookupSchool(for email: String) async throws -> SchoolMatch? {
            try await inner.lookupSchool(for: email)
        }

        func checkSchoolEmailAvailable(_ email: String) async throws -> Bool {
            try await inner.checkSchoolEmailAvailable(email)
        }

        func beginSchoolEmailVerification(_ email: String) async throws -> SchoolMatch {
            try await inner.beginSchoolEmailVerification(email)
        }

        func completeSchoolEmailVerification(_ email: String, token: String) async throws -> OnboardingStep {
            try await inner.completeSchoolEmailVerification(email, token: token)
        }

        func completeSchoolEmailVerificationByLink(_ token: String) async throws -> OnboardingStep {
            try await inner.completeSchoolEmailVerificationByLink(token)
        }

        func joinWaitlist() async throws -> OnboardingStep {
            try await inner.joinWaitlist()
        }

        func submitReferralCode(_ code: String) async throws {
            try await inner.submitReferralCode(code)
        }

        func setExpectedGraduation(_ month: Date) async throws {
            try await inner.setExpectedGraduation(month)
        }

        func acceptPledge() async throws {
            try await inner.acceptPledge()
        }
    }

    @Test func refreshIfOnlineRefetchesOnceStatusIsStale() async throws {
        let authDefaults = UserDefaults(suiteName: "OnboardingStalenessAuth")!
        authDefaults.removePersistentDomain(forName: "OnboardingStalenessAuth")

        let auth = AuthStore(service: MockAuthService(defaults: authDefaults))
        await auth.signIn(with: .apple)

        let service = CountingOnboardingService(defaults: authDefaults)
        let store = OnboardingStore(service: service, auth: auth, network: NetworkMonitor())

        await store.refreshIfOnline()
        #expect(service.fetchCount == 1)

        // Fresh: no refetch.
        await store.refreshIfOnline()
        #expect(service.fetchCount == 1)

        // Stale: refetch.
        store.statusStaleInterval = 0
        await store.refreshIfOnline()
        #expect(service.fetchCount == 2)
    }

    // Guards the pledge-persistence fix: signing the pledge (WelcomeOnBoardView)
    // must reach the `accept_pledge` RPC through OnboardingStore, not silently
    // no-op, so the acceptance survives an app kill between admission and signing.
    @Test func acceptPledgeSucceedsWhenSignedIn() async {
        let authDefaults = UserDefaults(suiteName: "OnboardingPledgeAuth")!
        authDefaults.removePersistentDomain(forName: "OnboardingPledgeAuth")

        let auth = AuthStore(service: MockAuthService(defaults: authDefaults))
        await auth.signIn(with: .apple)

        let store = OnboardingStore(
            service: MockOnboardingService(defaults: authDefaults),
            auth: auth,
            network: NetworkMonitor()
        )

        let succeeded = await store.acceptPledge()
        #expect(succeeded)
        #expect(store.lastError == nil)
    }

    @Test func acceptPledgeFailsWhenSignedOut() async {
        let authDefaults = UserDefaults(suiteName: "OnboardingPledgeAuthSignedOut")!
        authDefaults.removePersistentDomain(forName: "OnboardingPledgeAuthSignedOut")

        let auth = AuthStore(service: MockAuthService(defaults: authDefaults))
        let store = OnboardingStore(
            service: MockOnboardingService(defaults: authDefaults),
            auth: auth,
            network: NetworkMonitor()
        )

        let succeeded = await store.acceptPledge()
        #expect(!succeeded)
    }
}
