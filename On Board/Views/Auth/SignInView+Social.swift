//
//  SignInView+Social.swift
//  On Board
//
//  Apple/Google sign-in — pulled out of SignInView.swift because this is the one
//  genuinely separable concern in that file: unlike the phone/email/OTP/password
//  flow, it never touches credentialMode, phoneNumber, emailAddress, password,
//  otpCode, otpSent, submittedDestination, or resendCooldown. It only needs
//  auth/network, resolvingProvider/appleFlowInFlight/alertError/appeared, and
//  presentAlert — all widened from `private` in SignInView.swift for this file.
//

import SwiftUI

extension SignInView {
    // MARK: - Social sign-in

    var socialSection: some View {
        VStack(spacing: 12) {
            Text("Or continue with")
                .fontStyle(.footnote)
                .foregroundStyle(.secondary)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    appleSignInButton
                    googleSignInButton
                }
                
                VStack(spacing: 12) {
                    appleSignInButton
                    googleSignInButton
                }
            }
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 18)
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    /// Shared label so the Apple and Google buttons stay visually identical:
    /// the provider logo (or an inline spinner while busy) next to the one-word name.
    func socialButtonLabel(systemImage: String? = nil, assetImage: String? = nil, title: String, isLoading: Bool) -> some View {
        HStack(spacing: 8) {
            if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .tint(.primary)
            } else if let assetImage {
                Image(assetImage).renderingMode(.original)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 16, height: 16)
            } else if let systemImage {
                Image(systemName: systemImage)
            }
            Text(title)
        }
    }

    // MARK: - Apple sign-in
    //
    // Custom button (not SignInWithAppleButton) so it matches the Google button exactly.
    // The one-word "Apple" label is an intentional product choice; the Apple logo and a
    // neutral (non-brand-colored) treatment are kept. Auth runs through the same
    // programmatic ASAuthorizationController path via AppleSignInCoordinator.

    var appleSignInButton: some View {
        let isSigningIn = if case .signingIn(.apple) = auth.state { true } else { false }
        let busy = appleFlowInFlight || isSigningIn || isResolving(.apple)

        return Button {
            Task { await runAppleSignIn() }
        } label: {
            socialButtonLabel(systemImage: "applelogo", title: "Apple", isLoading: busy)
        }
        .buttonStyle(.boardSecondary)
        .disabled(busy)
        .accessibilityLabel("Continue with Apple")
    }

    func runAppleSignIn() async {
        if usesLiveBackend, !network.isConnected {
            presentAlert(PresentableAlertError.from(AuthError.networkUnavailable))
            return
        }

        appleFlowInFlight = true
        resolvingProvider = .apple
        defer { appleFlowInFlight = false }

        do {
            let authorization = try await AppleSignInCoordinator.requestAuthorization()
            let idToken = try AppleSignInCoordinator.idToken(from: authorization.credential)
            let fullName = AppleSignInCoordinator.fullName(from: authorization.credential)
            await auth.signInWithApple(idToken: idToken, nonce: authorization.rawNonce, fullName: fullName)
        } catch {
            // Cancellation maps to a nil alert (silent); real failures surface.
            if let alert = PresentableAlertError.from(error) {
                presentAlert(alert)
            }
            resolvingProvider = nil
            auth.cancelSignIn()
        }
    }

    // MARK: - Google sign-in

    @ViewBuilder
    var googleSignInButton: some View {
        if googleSignInAvailable {
            let isSigningIn = if case .signingIn(.google) = auth.state { true } else { false }
            let busy = isSigningIn || isResolving(.google)

            Button {
                resolvingProvider = .google
                Task { await auth.signInWithGoogle() }
            } label: {
                socialButtonLabel(assetImage: "Google_Favicon_2025", title: "Google", isLoading: busy)
            }
            .buttonStyle(.boardSecondary)
            .disabled(busy)
            .accessibilityLabel("Continue with Google")
        } else {
            // Same shape as `.boardSecondary`, dimmed, for the not-yet-available state.
            socialButtonLabel(assetImage: "Google_Favicon_2025", title: "Google", isLoading: false)
                .fontStyle(.headline)
                .foregroundStyle(.primary)
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity)
                .background(Capsule(style: .continuous).fill(.thinMaterial))
                .overlay(Capsule(style: .continuous).stroke(Color.secondary.opacity(0.20), lineWidth: 1))
                .opacity(0.50)
                .accessibilityLabel("Google, coming soon")
                .accessibilityAddTraits(.isStaticText)
        }
    }
}
