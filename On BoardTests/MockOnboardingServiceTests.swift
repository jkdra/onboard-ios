//
//  MockOnboardingServiceTests.swift
//  On BoardTests
//

import Foundation
import Testing
@testable import On_Board

@MainActor
struct MockOnboardingServiceTests {
    @Test func phoneUserStartsAtBirthday() async throws {
        let defaults = UserDefaults(suiteName: "MockOnboardingPhone")!
        defaults.removePersistentDomain(forName: "MockOnboardingPhone")

        let auth = MockAuthService(defaults: defaults)
        _ = try await auth.verifyPhoneOTP(phone: "+15555550100", token: "123456")

        let onboarding = MockOnboardingService(defaults: defaults)
        let status = try await onboarding.fetchStatus()
        #expect(status.onboardingStep == .birthday)
        #expect(status.isComplete == false)
    }

    @Test func completesOnboardingFlow() async throws {
        let defaults = UserDefaults(suiteName: "MockOnboardingFlow")!
        defaults.removePersistentDomain(forName: "MockOnboardingFlow")

        let auth = MockAuthService(defaults: defaults)
        _ = try await auth.verifyPhoneOTP(phone: "+15555550101", token: "123456")

        let onboarding = MockOnboardingService(defaults: defaults)
        _ = try await onboarding.completeUsername("new.tester")
        var status = try await onboarding.fetchStatus()
        #expect(status.onboardingStep == .profile)

        _ = try await onboarding.completeProfile(displayName: "New Tester", bio: "Hello", avatarUrl: nil)
        status = try await onboarding.fetchStatus()
        #expect(status.onboardingStep == .schoolVerify)

        _ = try await onboarding.beginSchoolEmailVerification("student@example.edu")
        _ = try await onboarding.completeSchoolEmailVerification("student@example.edu", token: "123456")
        status = try await onboarding.fetchStatus()
        // Verifying the .edu is what places the user on the waitlist — there is no
        // separate "join" tap. They stay parked (on the waitlist, not complete)
        // until an admin admits them and assigns a board.
        #expect(status.onboardingStep == .waitlist)
        #expect(status.isComplete == false)
        #expect(status.waitlistJoinedAt != nil)
    }

    @Test @MainActor func vipEmailInstantAdmissionThroughStore() async throws {
        let defaults = UserDefaults(suiteName: "MockOnboardingVIPStore")!
        defaults.removePersistentDomain(forName: "MockOnboardingVIPStore")

        let authService = MockAuthService(defaults: defaults)
        let auth = AuthStore(service: authService)
        await auth.verifyPhoneOTP(phone: "+15555550104", token: "123456")

        let store = OnboardingStore(
            service: MockOnboardingService(defaults: defaults),
            auth: auth,
            network: NetworkMonitor()
        )
        await store.refresh()

        // Full device sequence, through the store like the UI drives it.
        #expect(await store.submitBirthday(birthday: Calendar.current.date(byAdding: .year, value: -20, to: .now)!, showBirthday: false))
        #expect(await store.submitUsername("vip.store.tester"))
        #expect(await store.submitProfile(displayName: "VIP", bio: nil))
        #expect(await store.sendSchoolVerificationCode(to: "vip@example.edu"))
        let verified = await store.verifySchoolEmail("vip@example.edu", code: "123456")
        #expect(verified, "verify failed: \(store.lastError ?? "no error")")
        #expect(store.isComplete)
    }

    @Test func vipEmailSimulatesInstantAdmission() async throws {
        let defaults = UserDefaults(suiteName: "MockOnboardingVIP")!
        defaults.removePersistentDomain(forName: "MockOnboardingVIP")

        let auth = MockAuthService(defaults: defaults)
        _ = try await auth.verifyPhoneOTP(phone: "+15555550103", token: "123456")

        let onboarding = MockOnboardingService(defaults: defaults)
        _ = try await onboarding.completeBirthday(
            birthday: Calendar.current.date(byAdding: .year, value: -20, to: .now)!,
            showBirthday: false
        )
        _ = try await onboarding.completeUsername("vip.tester")
        _ = try await onboarding.completeProfile(displayName: "VIP", bio: nil, avatarUrl: nil)
        _ = try await onboarding.beginSchoolEmailVerification("vip@example.edu")
        let step = try await onboarding.completeSchoolEmailVerification("vip@example.edu", token: "123456")
        #expect(step == .complete)

        let status = try await onboarding.fetchStatus()
        #expect(status.effectiveOnboardingStep == .complete)
        #expect(!status.needsOnboarding)
    }

    @Test func rejectsSchoolEmailAlreadyLinkedToAnotherAccount() async throws {
        let defaults = UserDefaults(suiteName: "MockOnboardingEmailInUse")!
        defaults.removePersistentDomain(forName: "MockOnboardingEmailInUse")

        let auth = MockAuthService(defaults: defaults)
        _ = try await auth.verifyPhoneOTP(phone: "+15555550102", token: "123456")

        let onboarding = MockOnboardingService(defaults: defaults)
        await #expect(throws: OnboardingError.schoolEmailInUse) {
            _ = try await onboarding.beginSchoolEmailVerification("taken@example.edu")
        }

        // The inline pre-check the school email step uses reports the same email
        // as taken, and a fresh one as available.
        #expect(try await onboarding.checkSchoolEmailAvailable("taken@example.edu") == false)
        #expect(try await onboarding.checkSchoolEmailAvailable("fresh@example.edu") == true)
    }

    @Test func referralRewardLadderBoundaries() {
        #expect(ReferralRewards.earnedFirstClassMonths(for: 0) == 0)
        #expect(ReferralRewards.earnedFirstClassMonths(for: 3) == 0)
        #expect(ReferralRewards.earnedFirstClassMonths(for: 4) == 1)
        #expect(ReferralRewards.earnedFirstClassMonths(for: 5) == 3)
        #expect(ReferralRewards.earnedFirstClassMonths(for: 12) == 3)
        // Clawback consistency: rewards derive from the live count, so a
        // deleted referred account dropping the count from 5 to 4 also drops
        // the earned months from 3 to 1 — by design, not by accident.
        #expect(ReferralRewards.earnedFirstClassMonths(for: 5 - 1) == 1)
    }

    @Test func firstClassIsProgressivelyDisclosed() {
        // No First Class mention until the user is one invite from earning it.
        #expect(ReferralRewards.milestoneText(for: 0) == nil)
        #expect(ReferralRewards.milestoneText(for: 2) == nil)
        #expect(ReferralRewards.milestoneText(for: 3)?.contains("1 more invite") == true)
        #expect(ReferralRewards.milestoneText(for: 4)?.contains("Free month") == true)
        #expect(ReferralRewards.milestoneText(for: 5)?.contains("3 free months") == true)
    }
}
