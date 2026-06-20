//
//  SignInView.swift
//  On Board
//

import AuthenticationServices
import SwiftUI

struct SignInView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(NetworkMonitor.self) private var network
    @Environment(\.colorScheme) private var scheme

    @State private var phoneNumber = ""
    @State private var otpCode = ""
    @State private var otpSent = false
    @State private var isSendingOTP = false
    @State private var alertError: PresentableAlertError?

    private var usesLiveBackend: Bool {
        AppConfiguration.current.isSupabaseConfigured
    }

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            VStack(spacing: 10) {
                Text("On Board")
                    .fontStyle(.largeTitle)
                    .fontWeight(.heavy)
                Text("your weekly bulletin board")
                    .fontStyle(.subheadline)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 12) {
                phoneSignInSection

                if usesLiveBackend {
                    appleSignInButton
                } else {
                    signInButton(for: .apple)
                }

                googleSignInButton
            }
            .padding(.horizontal, 24)

            if usesLiveBackend {
                Text("Connected to the official On Board backend.")
                    .fontStyle(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            } else {
                Text("Development mode: mock sign-in and sample board data. Use phone to walk through onboarding.")
                    .fontStyle(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            LinearGradient(
                colors: [
                    Color.gray.opacity(scheme == .light ? 0.25 : 0.20),
                    Color(.systemBackground)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
        .presentableErrorAlert(error: $alertError) {
            clearAuthFailureIfNeeded()
        }
        .onChange(of: authFailureMessage) { _, message in
            guard let message else { return }
            alertError = PresentableAlertError(message: message)
        }
    }

    private var authFailureMessage: String? {
        if case .failed(let message) = auth.state { message }
        else { nil }
    }

    private func presentAlert(_ error: PresentableAlertError?) {
        guard let error else { return }
        alertError = error
    }

    private func clearAuthFailureIfNeeded() {
        if case .failed = auth.state {
            auth.cancelSignIn()
        }
    }

    private var phoneSignInSection: some View {
        VStack(spacing: 10) {
            TextField("Phone number", text: $phoneNumber)
                .textFieldStyle(.board)
                .keyboardType(.phonePad)
                .textContentType(.telephoneNumber)
                .disabled(otpSent || isSendingOTP)

            if otpSent {
                TextField("Verification code", text: $otpCode)
                    .textFieldStyle(.board)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
            }

            if otpSent {
                Button {
                    Task { await verifyPhoneOTP() }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: AuthProvider.phone.systemImage)
                        Text("Verify code")
                            .fontStyle(.headline)
                        Spacer()
                        if isSigningInPhone {
                            ProgressView()
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
                .buttonStyle(.boardPrimary)
                .disabled(isSigningInPhone || otpCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button("Use a different number") {
                    otpSent = false
                    otpCode = ""
                }
                .fontStyle(.footnote)
                .foregroundStyle(.secondary)
            } else {
                Button {
                    Task { await sendPhoneOTP() }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: AuthProvider.phone.systemImage)
                        Text("Continue with Phone")
                            .fontStyle(.headline)
                        Spacer()
                        if isSendingOTP || isSigningInPhone {
                            ProgressView()
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
                .buttonStyle(.boardSecondary)
                .disabled(isSendingOTP || isSigningInPhone || normalizedPhone.isEmpty)
            }
        }
    }

    private var isSigningInPhone: Bool {
        if case .signingIn(.phone) = auth.state { true } else { false }
    }

    private var normalizedPhone: String {
        phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func sendPhoneOTP() async {
        if usesLiveBackend, !network.isConnected {
            presentAlert(PresentableAlertError.from(AuthError.networkUnavailable))
            return
        }
        isSendingOTP = true
        defer { isSendingOTP = false }

        do {
            try await auth.sendPhoneOTP(phone: normalizedPhone)
            otpSent = true
        } catch {
            presentAlert(PresentableAlertError.from(error))
        }
    }

    private func verifyPhoneOTP() async {
        if usesLiveBackend, !network.isConnected {
            presentAlert(PresentableAlertError.from(AuthError.networkUnavailable))
            return
        }
        await auth.verifyPhoneOTP(phone: normalizedPhone, token: otpCode.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private var appleSignInButton: some View {
        let isSigningIn = if case .signingIn(.apple) = auth.state { true } else { false }

        return SignInWithAppleButton(.continue) { request in
            request.requestedScopes = [.email, .fullName]
        } onCompletion: { result in
            switch result {
            case .failure(let error):
                Task { @MainActor in
                    if let alert = PresentableAlertError.from(error) {
                        presentAlert(alert)
                    }
                    auth.cancelSignIn()
                }
            case .success(let authorization):
                guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                      let tokenData = credential.identityToken,
                      let idToken = String(data: tokenData, encoding: .utf8) else {
                    Task { @MainActor in
                        presentAlert(PresentableAlertError(message: String(localized: "Could not read your Apple ID token.")))
                        auth.cancelSignIn()
                    }
                    return
                }

                let fullName = credential.fullName?.formatted()
                Task {
                    await auth.signInWithApple(idToken: idToken, fullName: fullName)
                }
            }
        }
        .signInWithAppleButtonStyle(scheme == .dark ? .white : .black)
        .frame(height: 50)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            if isSigningIn {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.black.opacity(0.15))
                ProgressView()
            }
        }
        .disabled(isSigningIn)
    }

    private var googleSignInButton: some View {
        HStack(spacing: 10) {
            Image(systemName: AuthProvider.google.systemImage)
            Text("Continue with Google")
                .fontStyle(.headline)
            Spacer()
            Text("Soon")
                .fontStyle(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.thinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.secondary.opacity(0.20), lineWidth: 1)
        )
        .opacity(0.55)
        .accessibilityLabel("Continue with Google, coming soon")
    }

    @ViewBuilder
    private func signInButton(for provider: AuthProvider) -> some View {
        let isSigningIn = if case .signingIn(let active) = auth.state {
            active == provider
        } else {
            false
        }

        Button {
            Task { await auth.signIn(with: provider) }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: provider.systemImage)
                Text("Continue with \(provider.label)")
                    .fontStyle(.headline)
                Spacer()
                if isSigningIn {
                    ProgressView()
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .buttonStyle(.boardSecondary)
        .disabled(isSigningIn)
    }
}

#Preview {
    SignInView()
        .environment(AuthStore(service: MockAuthService()))
        .environment(BoardStore.sampleBoard())
        .environment(NetworkMonitor())
}
