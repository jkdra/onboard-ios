//
//  OnboardingCoordinator.swift
//  On Board
//
//  Owns the entire pre-board navigation stack: sign-in at root, then each
//  onboarding step pushed on top. Placing SignInView as the NavigationStack
//  root means the auth→username transition is a native push slide, not a
//  conditional view swap.
//

import SwiftUI

struct OnboardingCoordinator: View {
    @Environment(OnboardingStore.self) private var onboarding
    @Environment(AuthStore.self) private var auth

    @State private var path: [OnboardingStep] = []
    @State private var alertError: PresentableAlertError?
    /// Set when the user just completed sign-in so the first push is animated.
    @State private var pendingSignIn = false

    private var effectiveStep: OnboardingStep {
        onboarding.status?.effectiveOnboardingStep ?? .username
    }

    var body: some View {
        NavigationStack(path: $path) {
            SignInView()
                .navigationDestination(for: OnboardingStep.self) { step in
                    switch step {
                    case .username:
                        OnboardingUsernameStepView()
                            .navigationBarBackButtonHidden()
                    case .profile:
                        OnboardingProfileStepView()
                    case .schoolVerify:
                        OnboardingSchoolEmailStepView()
                    case .waitlist:
                        OnboardingWaitlistStepView()
                    default:
                        EmptyView()
                    }
                }
        }
        .overlay {
            // Cover SignInView while status loads after a fresh sign-in.
            if auth.isSignedIn && !onboarding.hasResolvedStatus {
                ZStack {
                    Color(.systemBackground).ignoresSafeArea()
                    ProgressView("Setting up your account…")
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
        }
        .onAppear {
            guard auth.isSignedIn, onboarding.hasResolvedStatus else { return }
            // Session restore: already have all data, skip animation.
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) { path = targetPath(for: effectiveStep) }
        }
        .onChange(of: auth.isSignedIn) { old, isSignedIn in
            if isSignedIn, !old {
                // Fresh sign-in — animate the upcoming push.
                pendingSignIn = true
            } else if !isSignedIn {
                pendingSignIn = false
                var t = Transaction()
                t.disablesAnimations = true
                withTransaction(t) { path = [] }
            }
        }
        .onChange(of: onboarding.hasResolvedStatus) { _, resolved in
            guard resolved, auth.isSignedIn else { return }
            if pendingSignIn {
                pendingSignIn = false
                path = targetPath(for: effectiveStep)  // animated
            } else if path.isEmpty {
                var t = Transaction()
                t.disablesAnimations = true
                withTransaction(t) { path = targetPath(for: effectiveStep) }
            }
        }
        .onChange(of: effectiveStep) { _, step in
            advancePathIfNeeded(for: step)
        }
        .onChange(of: onboarding.isSubmitting) { _, isSubmitting in
            guard !isSubmitting else { return }
            advancePathIfNeeded(for: effectiveStep)
        }
        .onChange(of: onboarding.lastError) { _, message in
            guard let message, !message.isEmpty else { return }
            alertError = PresentableAlertError(
                message: message,
                recoverySuggestion: onboarding.lastErrorRecovery
            )
        }
        .presentableErrorAlert(error: $alertError) {
            onboarding.clearLastError()
        }
    }

    private func advancePathIfNeeded(for step: OnboardingStep) {
        let target = targetPath(for: step)
        if target.count > path.count { path = target }
    }

    private func targetPath(for step: OnboardingStep) -> [OnboardingStep] {
        guard auth.isSignedIn else { return [] }
        switch step {
        case .username, .complete: return [.username]
        case .profile:             return [.username, .profile]
        case .schoolVerify:        return [.username, .profile, .schoolVerify]
        case .waitlist:            return [.username, .profile, .schoolVerify, .waitlist]
        }
    }
}

#Preview {
    OnboardingCoordinator()
        .environment(OnboardingStore(
            service: MockOnboardingService(),
            auth: AuthStore(service: MockAuthService()),
            network: NetworkMonitor()
        ))
        .environment(AuthStore(service: MockAuthService()))
}
