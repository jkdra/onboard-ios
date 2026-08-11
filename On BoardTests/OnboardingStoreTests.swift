//
//  OnboardingStoreTests.swift
//  On BoardTests
//

import Foundation
import Testing
@testable import On_Board

struct OnboardingStoreTests {
    @Test @MainActor func refreshMarksCompleteForSampleAppleUser() async {
        let authDefaults = UserDefaults(suiteName: "OnboardingStoreAppleAuth")!
        authDefaults.removePersistentDomain(forName: "OnboardingStoreAppleAuth")
        let auth = AuthStore(service: MockAuthService(defaults: authDefaults))
        await auth.signIn(with: .apple)

        let store = OnboardingStore(
            service: MockOnboardingService(defaults: authDefaults),
            auth: auth,
            network: NetworkMonitor()
        )
        await store.refresh()
        #expect(store.isComplete)
        #expect(!store.needsOnboarding)
    }

    @Test @MainActor func provisionalCompleteProfileStillNeedsOnboarding() {
        let status = OnboardingStatus(
            id: UUID(),
            handle: "u_abc123def456",
            displayName: "",
            bio: nil,
            avatarUrl: nil,
            birthday: "2000-01-01",
            showBirthday: false,
            onboardingStep: .complete,
            onboardingCompletedAt: .now,
            waitlistJoinedAt: nil,
            verifiedSchoolEmail: nil,
            pendingSchoolEmail: nil,
            schoolName: nil,
            boardId: nil,
            boardName: nil,
            referralCode: nil,
            verifiedReferralCount: nil,
            instantInvitesRemaining: nil,
            expectedGraduation: nil
        )

        #expect(status.isComplete)
        #expect(status.needsOnboarding)
        #expect(status.effectiveOnboardingStep == .username)
    }

    /// Display name is optional by design — an admitted user who skipped it
    /// must read as complete. The old empty-displayName gate trapped these
    /// users in an inescapable profile-step loop (found via a real device's
    /// stuck mock state, 2026-07-22).
    @Test @MainActor func emptyDisplayNameDoesNotBlockAdmittedUser() {
        let status = OnboardingStatus(
            id: UUID(),
            handle: "real.handle",
            displayName: "",
            bio: nil,
            avatarUrl: nil,
            birthday: "2000-01-01",
            showBirthday: false,
            onboardingStep: .complete,
            onboardingCompletedAt: .now,
            waitlistJoinedAt: .now,
            verifiedSchoolEmail: "student@example.edu",
            pendingSchoolEmail: nil,
            schoolName: "Example University",
            boardId: SampleBoardID.main,
            boardName: "On Board",
            referralCode: "abc123",
            verifiedReferralCount: 0,
            instantInvitesRemaining: 3,
            expectedGraduation: nil
        )

        #expect(status.effectiveOnboardingStep == .complete)
        #expect(!status.needsOnboarding)
    }
}
