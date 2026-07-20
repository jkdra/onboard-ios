//
//  OnboardingProfileCompletionTests.swift
//  On BoardTests
//
//  Display name is optional — OnboardingProfileStepView.canContinue already
//  allows an empty name through, so the service layer must accept one too.
//  Pins the fix for the case where the RPC/mock still guarded against it.
//

import Foundation
import Testing
@testable import On_Board

@MainActor
struct OnboardingProfileCompletionTests {

    private func freshUser() -> (UUID, UserDefaults) {
        let userID = UUID()
        let suiteName = "OnboardingProfileCompletionTests.\(userID.uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let session = AuthSession(userId: userID, primaryProvider: .apple)
        defaults.set(try! JSONEncoder().encode(session), forKey: "mock.auth.session")
        return (userID, defaults)
    }

    @Test func completeProfileAcceptsEmptyDisplayName() async throws {
        let (_, defaults) = freshUser()
        let service = MockOnboardingService(defaults: defaults)
        let step = try await service.completeProfile(displayName: "", bio: nil, avatarUrl: nil)
        #expect(step == .schoolVerify)
    }

    @Test func completeProfileAcceptsWhitespaceOnlyDisplayName() async throws {
        let (_, defaults) = freshUser()
        let service = MockOnboardingService(defaults: defaults)
        let step = try await service.completeProfile(displayName: "   ", bio: nil, avatarUrl: nil)
        #expect(step == .schoolVerify)
    }
}
