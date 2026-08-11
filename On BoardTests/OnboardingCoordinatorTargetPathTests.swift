//
//  OnboardingCoordinatorTargetPathTests.swift
//  On BoardTests
//

import Foundation
import Testing
@testable import On_Board

@MainActor
struct OnboardingCoordinatorTargetPathTests {
    // A returning, already-onboarded user must not be routed into any onboarding
    // step screen — the coordinator gets swapped out for BoardListView instead.
    @Test func completeStepProducesEmptyPath() {
        #expect(OnboardingCoordinator.targetPath(for: .complete, isSignedIn: true) == [])
    }

    @Test func usernameStepProducesUsernamePath() {
        #expect(OnboardingCoordinator.targetPath(for: .username, isSignedIn: true) == [.birthday, .username])
    }

    @Test func waitlistStepProducesFullPath() {
        #expect(
            OnboardingCoordinator.targetPath(for: .waitlist, isSignedIn: true)
                == [.birthday, .username, .profile, .schoolVerify, .contentPreferences, .waitlist]
        )
    }

    /// The graduation hold must keep the user ON the school screen: identical
    /// target path, so verification advances the screen's stage in place
    /// instead of pushing. If these ever diverge, verifying an email pushes a
    /// destination the coordinator no longer renders.
    @Test func graduationHoldsOnTheSchoolScreen() {
        #expect(
            OnboardingCoordinator.targetPath(for: .graduation, isSignedIn: true)
                == OnboardingCoordinator.targetPath(for: .schoolVerify, isSignedIn: true)
        )
    }

    @Test func signedOutProducesEmptyPathRegardlessOfStep() {
        #expect(OnboardingCoordinator.targetPath(for: .waitlist, isSignedIn: false) == [])
    }
}
