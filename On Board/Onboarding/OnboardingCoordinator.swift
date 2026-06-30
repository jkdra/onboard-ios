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
        // One persistent glow pinned above the whole stack, emitting from the bottom
        // edge. `path.count` is the step depth (0 = sign-in … 4 = waitlist), so it grows
        // forward as each screen is pushed. It's an overlay, not a background, because
        // NavigationStack paints an opaque background that would occlude anything behind
        // it — and the glow is a transparent band, so overlaying doesn't obscure content.
        .overlay {
            OnboardingProgressBackground(step: path.count, edge: .bottom)
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
                        ZStack {
                            Circle()
                                .fill(.thinMaterial)
                                .frame(width: 72, height: 72)
                                .shadow(color: .black.opacity(0.12), radius: 14, x: 0, y: 7)
                            Image("OBLogo")
                                .renderingMode(.original)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 40, height: 40)
                                .foregroundStyle(.primary)
                        }
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
        #if DEBUG
        .overlay(alignment: .bottom) {
            if devDriven { devControls }
        }
        #endif
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
        guard auth.isSignedIn else { return [] }
        switch step {
        case .username, .complete: return [.username]
        case .profile:             return [.username, .profile]
        case .schoolVerify:        return [.username, .profile, .schoolVerify]
        case .waitlist:            return [.username, .profile, .schoolVerify, .waitlist]
        }
    }

    #if DEBUG
    /// Ordered destinations the dev Next button walks through (sign-in is the root).
    private static let devSteps: [OnboardingStep] = [.username, .profile, .schoolVerify, .waitlist]

    private var devControls: some View {
        HStack(spacing: 14) {
            Button {
                if !path.isEmpty { path.removeLast() }
            } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(path.isEmpty)

            Text("Step \(path.count) / \(Self.devSteps.count)")
                .font(.caption.monospacedDigit().weight(.semibold))
                .frame(minWidth: 64)

            Button {
                if path.count < Self.devSteps.count { path.append(Self.devSteps[path.count]) }
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(path.count >= Self.devSteps.count)
        }
        .font(.title3)
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().stroke(.secondary.opacity(0.25), lineWidth: 1))
        .padding(.bottom, 8)
        .tint(.primary)
    }
    #endif
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
