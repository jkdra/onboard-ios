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
    /// DEBUG-only: drive the path manually with on-screen Next/Back controls,
    /// bypassing auth/status so the real screens (and the glow bloom) can be
    /// walked without entering any input.
    var devDriven = false

    @Environment(OnboardingStore.self) private var onboarding
    @Environment(AuthStore.self) private var auth

    /// Client-only completion flag for `.contentPreferences` — see that case's
    /// doc comment on `OnboardingStep` for why this can't live on `OnboardingStatus`.
    @AppStorage("hasCompletedProfanityStep") private var hasCompletedProfanityStep = false

    @State private var path: [OnboardingStep] = []
    @State private var alertError: PresentableAlertError?
    /// Set when the user just completed sign-in so the first push is animated.
    @State private var pendingSignIn = false
    /// True once auth has passed through `.signingIn` this session — i.e. the user
    /// signed in interactively from SignInView (as opposed to a silent cold-launch
    /// `restoreSession`, which jumps straight to `.signedIn`). Used to decide whether
    /// the post-sign-in window should show the covering loader (restore) or let
    /// SignInView handle it inline with its tapped button (interactive).
    @State private var interactiveSignIn = false

    private var effectiveStep: OnboardingStep {
        guard let backendStep = onboarding.status?.effectiveOnboardingStep else { return .birthday }
        // .contentPreferences has no backing DB state, so it can't come back from
        // effectiveOnboardingStep — insert it locally once profile is behind the
        // user and it hasn't been shown yet.
        if !hasCompletedProfanityStep, Self.rank(backendStep) > Self.rank(.profile) {
            return .contentPreferences
        }
        return backendStep
    }

    private static func rank(_ step: OnboardingStep) -> Int {
        OnboardingStep.allCases.firstIndex(of: step) ?? 0
    }

    var body: some View {
        NavigationStack(path: $path) {
            SignInView()
                .navigationDestination(for: OnboardingStep.self) { step in
                    switch step {
                    case .birthday:
                        OnboardingBirthdayStepView()
                            .navigationBarBackButtonHidden()
                    case .username:
                        OnboardingUsernameStepView()
                            .navigationBarBackButtonHidden()
                    case .profile:
                        OnboardingProfileStepView()
                    case .contentPreferences:
                        OnboardingContentPreferencesStepView()
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
            // Cover SignInView only on a cold-launch session restore, where showing the
            // sign-in form (even briefly) would be wrong. A *fresh* interactive sign-in
            // instead keeps SignInView in place with its tapped button spinning and the
            // form disabled (see SignInView.isResolvingPostSignIn), so we skip the cover.
            if auth.isSignedIn && !onboarding.hasResolvedStatus && !interactiveSignIn {
                ZStack {
                    Color(.systemBackground).ignoresSafeArea()
                    VStack(spacing: 24) {
                        BrandLogo(size: 72, renderingMode: .original)
                        ProgressView()
                            .scaleEffect(1.1)
                        Text("Setting up your account…")
                            .fontStyle(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .transition(.opacity)
            }
        }
        .onAppear {
            guard !devDriven else { return }
            guard auth.isSignedIn, onboarding.hasResolvedStatus else { return }
            // Session restore: already have all data, skip animation.
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) { path = targetPath(for: effectiveStep) }
        }
        .onChange(of: auth.state) { _, state in
            guard !devDriven else { return }
            // Latch interactive sign-in: only the interactive flows pass through
            // `.signingIn`; a silent restore goes straight to `.signedIn`.
            if case .signingIn = state { interactiveSignIn = true }
        }
        .onChange(of: auth.isSignedIn) { old, isSignedIn in
            guard !devDriven else { return }
            if isSignedIn, !old {
                // Fresh sign-in — animate the upcoming push.
                pendingSignIn = true
            } else if !isSignedIn {
                pendingSignIn = false
                interactiveSignIn = false
                var t = Transaction()
                t.disablesAnimations = true
                withTransaction(t) { path = [] }
            }
        }
        .onChange(of: onboarding.hasResolvedStatus) { _, resolved in
            guard !devDriven else { return }
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
            guard !devDriven else { return }
            advancePathIfNeeded(for: step)
        }
        .onChange(of: onboarding.isSubmitting) { _, isSubmitting in
            guard !devDriven, !isSubmitting else { return }
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
        Self.targetPath(for: step, isSignedIn: auth.isSignedIn)
    }

    static func targetPath(for step: OnboardingStep, isSignedIn: Bool) -> [OnboardingStep] {
        guard isSignedIn else { return [] }
        switch step {
        // .complete means onboarding is already done — RootView swaps this whole
        // coordinator out for BoardListView, so there's no step to push to.
        case .complete:            return []
        case .birthday:            return [.birthday]
        case .username:            return [.birthday, .username]
        case .profile:             return [.birthday, .username, .profile]
        case .contentPreferences:  return [.birthday, .username, .profile, .contentPreferences]
        case .schoolVerify:        return [.birthday, .username, .profile, .contentPreferences, .schoolVerify]
        case .waitlist:            return [.birthday, .username, .profile, .contentPreferences, .schoolVerify, .waitlist]
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
