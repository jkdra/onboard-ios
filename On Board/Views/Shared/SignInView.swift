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
    @Environment(OnboardingStore.self) private var onboarding
    @Environment(NetworkMonitor.self) private var network
    @Environment(\.colorScheme) private var scheme

    @State private var credentialMode: CredentialMode = .phone
    @State private var phoneNumber = ""
    @State private var emailAddress = ""
    @State private var password = ""
    @State private var usePassword = false
    @State private var otpCode = ""
    @State private var otpSent = false
    @State private var isSendingOTP = false
    @State private var alertError: PresentableAlertError?
    @State private var submittedDestination = ""
    @State private var resendCooldown = OTPCooldown()
    @State private var isVerifyingOTP = false
    @State private var appleFlowInFlight = false
    @State private var appeared = false
    /// The provider whose sign-in succeeded and is now waiting on onboarding status
    /// to resolve. Keeps that button's spinner running through the post-sign-in
    /// window so we never swap in a separate loading screen here.
    @State private var resolvingProvider: AuthProvider?

    private let otpCooldownSeconds = 60

    /// True from the moment sign-in succeeds until onboarding status is known —
    /// the page is disabled and the tapped button keeps spinning during it.
    private var isResolvingPostSignIn: Bool {
        auth.isSignedIn && !onboarding.hasResolvedStatus
    }

    private func isResolving(_ provider: AuthProvider) -> Bool {
        resolvingProvider == provider && isResolvingPostSignIn
    }

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
                SignInHeaderView(appeared: appeared)
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
                    SignInFooterView(appeared: appeared)
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
        // Fresh sign-in: keep the form interactive-locked (not swapped for a loading
        // screen) until onboarding status resolves and the coordinator pushes the next step.
        .disabled(isResolvingPostSignIn)
        .keyboardDoneToolbar()
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
        // Once status resolves (or auth drops out), stop holding the button spinner.
        .onChange(of: onboarding.hasResolvedStatus) { _, resolved in
            if resolved { resolvingProvider = nil }
        }
        .onChange(of: auth.state) { _, state in
            switch state {
            case .signedOut, .failed:
                resolvingProvider = nil
            default:
                break
            }
        }
        .onAppear {
            withAnimation(.spring(duration: 0.75, bounce: 0.22).delay(0.08)) {
                appeared = true
            }
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
                    VStack(spacing: 10) {
                        TextField("Email address", text: $emailAddress)
                            .textFieldStyle(.board)
                            .keyboardType(.emailAddress)
                            .textContentType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .disabled(isSendingOTP)
                            .accessibilityLabel("Email address")

                        if usePassword {
                            SecureField("Password", text: $password)
                                .textFieldStyle(.board)
                                .textContentType(.password)
                                .submitLabel(.go)
                                .onSubmit {
                                    Task { await signInWithPassword() }
                                }
                                .disabled(isSigningInCredential)
                                .accessibilityLabel("Password")
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
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
                    if isSigningInCredential || isVerifyingOTP || isResolving(credentialProvider) {
                        ProgressView().tint(Color(.systemBackground))
                    }
                }
            }
            .buttonStyle(.boardPrimary)
            .disabled(isSigningInCredential || isVerifyingOTP || isResolving(credentialProvider) || !OTPCodeInput.isComplete(otpCode))
            .accessibilityLabel("Verify code")
            .transition(.move(edge: .bottom).combined(with: .opacity))
        } else if credentialMode == .email, usePassword {
            VStack(spacing: 10) {
                Button {
                    Task { await signInWithPassword() }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "key.fill")
                        Text("Sign In")
                            .fontStyle(.headline)
                        Spacer()
                        if isSigningInCredential || isResolving(.email) {
                            ProgressView().tint(Color(.systemBackground))
                        }
                    }
                }
                .buttonStyle(.boardPrimary)
                .disabled(isSigningInCredential || isResolving(.email) || normalizedCredentialValue.isEmpty || password.isEmpty)
                .accessibilityLabel("Sign in with password")

                Button("Use a one-time code instead") {
                    withAnimation(.snappy(duration: 0.3)) {
                        usePassword = false
                        password = ""
                    }
                }
                .fontStyle(.footnote)
                .foregroundStyle(.secondary)
                .disabled(isSigningInCredential)
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        } else {
            VStack(spacing: 10) {
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

                if credentialMode == .email {
                    Button("Have a password? Sign in with it") {
                        withAnimation(.snappy(duration: 0.3)) { usePassword = true }
                    }
                    .fontStyle(.footnote)
                    .foregroundStyle(.secondary)
                    .disabled(isSendingOTP)
                }
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    // MARK: - Social sign-in

    private var socialSection: some View {
        VStack(spacing: 12) {
            Text("Or continue with")
                .fontStyle(.footnote)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                appleSignInButton
                googleSignInButton
            }
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 18)
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    /// Shared label so the Apple and Google buttons stay visually identical:
    /// the provider logo (or an inline spinner while busy) next to the one-word name.
    private func socialButtonLabel(systemImage: String? = nil, assetImage: String? = nil, title: String, isLoading: Bool) -> some View {
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

    private var appleSignInButton: some View {
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

    private func runAppleSignIn() async {
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
    private var googleSignInButton: some View {
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



    // MARK: - Helpers (logic unchanged)

    private func resetOTPSession() {
        otpSent = false
        otpCode = ""
        password = ""
        usePassword = false
        submittedDestination = ""
        isVerifyingOTP = false
        resendCooldown.reset()
    }

    private func signInWithPassword() async {
        if usesLiveBackend, !network.isConnected {
            presentAlert(PresentableAlertError.from(AuthError.networkUnavailable))
            return
        }
        guard !normalizedCredentialValue.isEmpty, !password.isEmpty else { return }

        do {
            let email = try resolvedDestination()
            resolvingProvider = .email
            await auth.signInWithPassword(email: email, password: password)
        } catch {
            presentAlert(PresentableAlertError.from(error))
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

    private var isSigningInCredential: Bool {
        switch credentialMode {
        case .phone:
            if case .signingIn(.phone) = auth.state { true } else { false }
        case .email:
            if case .signingIn(.email) = auth.state { true } else { false }
        }
    }

    private var credentialProvider: AuthProvider {
        credentialMode == .phone ? .phone : .email
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
        resolvingProvider = credentialProvider
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
    let auth = AuthStore(service: MockAuthService())
    return SignInView()
        .environment(auth)
        .environment(OnboardingStore(
            service: MockOnboardingService(),
            auth: auth,
            network: NetworkMonitor()
        ))
        .environment(BoardStore.sampleBoard())
        .environment(NetworkMonitor())
}
