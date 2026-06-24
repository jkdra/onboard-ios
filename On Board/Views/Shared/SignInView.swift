//
//  SignInView.swift
//  On Board
//

import AuthenticationServices
import SwiftUI

struct SignInView: View {
    private enum CredentialMode: String, CaseIterable, Identifiable {
        case phone
        case email

        var id: String { rawValue }

        var label: String {
            switch self {
            case .phone: "Phone"
            case .email: "Email"
            }
        }
    }

    @Environment(AuthStore.self) private var auth
    @Environment(NetworkMonitor.self) private var network
    @Environment(\.colorScheme) private var scheme

    @State private var credentialMode: CredentialMode = .phone
    @State private var phoneNumber = ""
    @State private var emailAddress = ""
    @State private var otpCode = ""
    @State private var otpSent = false
    @State private var isSendingOTP = false
    @State private var alertError: PresentableAlertError?
    @State private var submittedDestination = ""
    @State private var resendCooldown = OTPCooldown()
    @State private var isVerifyingOTP = false
    @State private var appleRawNonce: String?
    @State private var appeared = false

    private let otpCooldownSeconds = 60

    private var usesLiveBackend: Bool {
        AppConfiguration.current.isSupabaseConfigured
    }

    private var googleSignInAvailable: Bool {
        AppConfiguration.current.isGoogleOAuthAvailable
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                headerSection
                    .padding(.top, 80)
                    .padding(.bottom, 36)
                    .padding(.horizontal, 24)

                formCard
                    .padding(.horizontal, 20)

                if !otpSent {
                    socialSection
                        .padding(.horizontal, 20)
                        .padding(.top, 14)
                }

                if !usesLiveBackend {
                    devModeFooter
                        .padding(.horizontal, 32)
                        .padding(.top, 20)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 48)
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollBounceBehavior(.basedOnSize)
        .ignoresSafeArea(edges: .top)
        .presentableErrorAlert(error: $alertError) {
            clearAuthFailureIfNeeded()
        }
        .onChange(of: authFailureMessage) { _, message in
            guard let message else { return }
            alertError = PresentableAlertError(message: message)
        }
        .onChange(of: credentialMode) { _, _ in
            resetOTPSession()
        }
        .onAppear {
            withAnimation(.spring(duration: 0.75, bounce: 0.22).delay(0.08)) {
                appeared = true
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(.thinMaterial)
                    .frame(width: 76, height: 76)
                    .shadow(
                        color: .black.opacity(scheme == .dark ? 0.45 : 0.14),
                        radius: 14, x: 0, y: 7
                    )
                Image(systemName: "pin.fill")
                    .font(.title.weight(.bold))
                    .foregroundStyle(.tint)
                    .rotationEffect(.degrees(-30))
            }
            .scaleEffect(appeared ? 1 : 0.55)
            .opacity(appeared ? 1 : 0)

            VStack(spacing: 5) {
                Text("On Board")
                    .fontStyle(.largeTitle)
                    .fontWeight(.heavy)
                    .accessibilityAddTraits(.isHeader)

                Text("your weekly bulletin board")
                    .fontStyle(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 10)
        }
    }

    // MARK: - Form card

    private var formCard: some View {
        VStack(spacing: 14) {
            if !otpSent {
                Picker("Sign-in method", selection: $credentialMode) {
                    ForEach(CredentialMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(isSendingOTP)
                .transition(.opacity.combined(with: .move(edge: .top)))
                .accessibilityLabel("Sign-in method")
            }

            credentialBlock

            primaryButton
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.thinMaterial)
                .shadow(
                    color: .black.opacity(scheme == .dark ? 0.38 : 0.10),
                    radius: 18, x: 0, y: 8
                )
        )
        .animation(.snappy(duration: 0.35), value: otpSent)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 22)
    }

    @ViewBuilder
    private var credentialBlock: some View {
        if otpSent {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.subheadline)
                    Text(otpSentMessage)
                        .fontStyle(.footnote)
                        .foregroundStyle(.secondary)
                }

                OTPCodeField(code: $otpCode, isEnabled: !isVerifyingOTP) {
                    Task { await verifyOTP() }
                }
                .accessibilityLabel("Verification code")
                .accessibilityHint("Enter the 6-digit code we sent you")

                HStack(alignment: .center) {
                    OTPResendControl(
                        channel: credentialMode == .phone ? "text" : "email",
                        secondsRemaining: resendCooldown.secondsRemaining,
                        isSending: isSendingOTP,
                        onResend: { Task { await sendOTP(isResend: true) } }
                    )

                    Spacer()

                    Button(credentialMode == .phone ? "Change number" : "Change email") {
                        withAnimation(.snappy(duration: 0.35)) { resetOTPSession() }
                    }
                    .fontStyle(.footnote)
                    .foregroundStyle(.secondary)
                }
            }
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            ))
        } else {
            Group {
                if credentialMode == .phone {
                    VStack(alignment: .leading, spacing: 6) {
                        TextField("+1 555 555 0100", text: $phoneNumber)
                            .textFieldStyle(.board)
                            .keyboardType(.phonePad)
                            .textContentType(.telephoneNumber)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .disabled(isSendingOTP)
                            .accessibilityLabel("Phone number")

                    }
                } else {
                    TextField("Email address", text: $emailAddress)
                        .textFieldStyle(.board)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .disabled(isSendingOTP)
                        .accessibilityLabel("Email address")
                }
            }
            .transition(.asymmetric(
                insertion: .move(edge: .leading).combined(with: .opacity),
                removal: .move(edge: .trailing).combined(with: .opacity)
            ))
        }
    }

    @ViewBuilder
    private var primaryButton: some View {
        if otpSent {
            Button {
                Task { await verifyOTP() }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: credentialMode == .phone
                          ? AuthProvider.phone.systemImage
                          : AuthProvider.email.systemImage)
                    Text("Verify Code")
                        .fontStyle(.headline)
                    Spacer()
                    if isSigningInCredential || isVerifyingOTP {
                        ProgressView().tint(.white)
                    }
                }
            }
            .buttonStyle(.boardPrimary)
            .disabled(isSigningInCredential || isVerifyingOTP || !OTPCodeInput.isComplete(otpCode))
            .accessibilityLabel("Verify code")
            .transition(.move(edge: .bottom).combined(with: .opacity))
        } else {
            Button {
                Task { await sendOTP(isResend: false) }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: credentialMode == .phone
                          ? AuthProvider.phone.systemImage
                          : AuthProvider.email.systemImage)
                    Text(credentialMode == .phone ? "Continue with Phone" : "Continue with Email")
                        .fontStyle(.headline)
                    Spacer()
                    if isSendingOTP || isSigningInCredential {
                        ProgressView()
                    }
                }
            }
            .buttonStyle(.boardSecondary)
            .disabled(isSendingOTP || isSigningInCredential || normalizedCredentialValue.isEmpty)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    // MARK: - Social sign-in

    private var socialSection: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Rectangle()
                    .fill(Color.secondary.opacity(0.22))
                    .frame(height: 0.5)
                Text("or")
                    .fontStyle(.footnote)
                    .foregroundStyle(.secondary)
                Rectangle()
                    .fill(Color.secondary.opacity(0.22))
                    .frame(height: 0.5)
            }
            .padding(.horizontal, 4)

            appleSignInButton

            googleSignInButton
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 18)
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    // MARK: - Apple sign-in

    private var appleSignInButton: some View {
        let isSigningIn = if case .signingIn(.apple) = auth.state { true } else { false }

        return SignInWithAppleButton(.continue) { request in
            let rawNonce = AppleNonce.randomNonce()
            appleRawNonce = rawNonce
            request.requestedScopes = [.email, .fullName]
            request.nonce = AppleNonce.sha256Hex(rawNonce)
        } onCompletion: { result in
            switch result {
            case .failure(let error):
                Task { @MainActor in
                    if let alert = PresentableAlertError.from(error) {
                        presentAlert(alert)
                    }
                    appleRawNonce = nil
                    auth.cancelSignIn()
                }
            case .success(let authorization):
                guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                      let tokenData = credential.identityToken,
                      let idToken = String(data: tokenData, encoding: .utf8) else {
                    Task { @MainActor in
                        presentAlert(PresentableAlertError(
                            message: String(localized: "Could not read your Apple ID token.")
                        ))
                        appleRawNonce = nil
                        auth.cancelSignIn()
                    }
                    return
                }
                let fullName = credential.fullName?.formatted()
                let nonce = appleRawNonce
                Task {
                    await auth.signInWithApple(idToken: idToken, nonce: nonce, fullName: fullName)
                    await MainActor.run { appleRawNonce = nil }
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
        .accessibilityLabel("Sign in with Apple")
    }

    // MARK: - Google sign-in

    @ViewBuilder
    private var googleSignInButton: some View {
        if googleSignInAvailable {
            let isSigningIn = if case .signingIn(.google) = auth.state { true } else { false }

            Button {
                Task { await auth.signInWithGoogle() }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: AuthProvider.google.systemImage)
                    Text("Continue with Google")
                        .fontStyle(.headline)
                    Spacer()
                    if isSigningIn { ProgressView() }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .buttonStyle(.boardSecondary)
            .disabled(isSigningIn)
            .accessibilityLabel("Continue with Google")
        } else {
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
            .opacity(0.50)
            .accessibilityLabel("Continue with Google, coming soon")
            .accessibilityAddTraits(.isStaticText)
        }
    }

    // MARK: - Dev footer

    private var devModeFooter: some View {
        Label("Development mode — mock sign-in", systemImage: "hammer.fill")
            .fontStyle(.caption)
            .foregroundStyle(.secondary)
            .opacity(appeared ? 1 : 0)
    }

    // MARK: - Helpers (logic unchanged)

    private func resetOTPSession() {
        otpSent = false
        otpCode = ""
        submittedDestination = ""
        isVerifyingOTP = false
        resendCooldown.reset()
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

    private var isSigningInCredential: Bool {
        switch credentialMode {
        case .phone:
            if case .signingIn(.phone) = auth.state { true } else { false }
        case .email:
            if case .signingIn(.email) = auth.state { true } else { false }
        }
    }

    private var otpSentMessage: String {
        switch credentialMode {
        case .phone:
            let label = PhoneNumberNormalizer.displayLabel(for: submittedDestination)
            return "Code sent to \(label)"
        case .email:
            return "Code sent to \(submittedDestination)"
        }
    }

    private var normalizedCredentialValue: String {
        switch credentialMode {
        case .phone:
            phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        case .email:
            emailAddress.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
    }

    private func resolvedDestination() throws -> String {
        switch credentialMode {
        case .phone:
            guard let e164 = PhoneNumberNormalizer.e164(from: normalizedCredentialValue) else {
                throw AuthError.invalidPhoneNumber
            }
            return e164
        case .email:
            let email = normalizedCredentialValue
            guard email.contains("@"), email.contains(".") else {
                throw AuthError.unknown("Enter a valid email address.")
            }
            return email
        }
    }

    private func sendOTP(isResend: Bool) async {
        if usesLiveBackend, !network.isConnected {
            presentAlert(PresentableAlertError.from(AuthError.networkUnavailable))
            return
        }

        if isResend, !resendCooldown.canResend { return }

        isSendingOTP = true
        defer { isSendingOTP = false }

        do {
            let destination = try resolvedDestination()
            switch credentialMode {
            case .phone:
                try await auth.sendPhoneOTP(phone: destination)
            case .email:
                try await auth.sendEmailOTP(email: destination)
            }
            submittedDestination = destination
            withAnimation(.snappy(duration: 0.35)) {
                otpSent = true
            }
            if !isResend { otpCode = "" }
            resendCooldown.start(duration: otpCooldownSeconds)
        } catch {
            presentAlert(PresentableAlertError.from(error))
        }
    }

    private func verifyOTP() async {
        guard !isVerifyingOTP else { return }
        if usesLiveBackend, !network.isConnected {
            presentAlert(PresentableAlertError.from(AuthError.networkUnavailable))
            return
        }

        isVerifyingOTP = true
        defer { isVerifyingOTP = false }

        let token = OTPCodeInput.sanitized(otpCode)
        let destination = submittedDestination.isEmpty
            ? (try? resolvedDestination()) ?? normalizedCredentialValue
            : submittedDestination

        switch credentialMode {
        case .phone:
            await auth.verifyPhoneOTP(phone: destination, token: token)
        case .email:
            await auth.verifyEmailOTP(email: destination, token: token)
        }
    }
}

#Preview {
    SignInView()
        .environment(AuthStore(service: MockAuthService()))
        .environment(BoardStore.sampleBoard())
        .environment(NetworkMonitor())
}
