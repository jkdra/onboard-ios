//
//  SignInView.swift
//  On Board
//

import AuthenticationServices
import SwiftUI

struct SignInView: View {
    // Not private: SignInView+Logic.swift's credential/OTP helpers switch on it.
    enum CredentialMode: String, CaseIterable, Identifiable {
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

    // Not private: SignInView+Social.swift's Apple/Google flow reads auth/network
    // state and shares resolvingProvider/appleFlowInFlight/alertError/appeared with
    // the rest of this form.
    @Environment(AuthStore.self) var auth
    @Environment(OnboardingStore.self) private var onboarding
    @Environment(NetworkMonitor.self) var network
    @Environment(RemoteConfigStore.self) private var remoteConfig
    @Environment(\.colorScheme) private var scheme

    // Form state is not private: SignInView+Logic.swift's helpers (resetOTPSession,
    // sendOTP, verifyOTP, the password paths) read and mutate it.
    @State var credentialMode: CredentialMode = .phone
    @State var phoneNumber = ""
    @State var emailAddress = ""
    @State var password = ""
    @State var confirmPassword = ""
    @State var usePassword = false
    @State var otpCode = ""
    @State var otpSent = false
    @State var isSendingOTP = false
    @State var emailStatus: EmailStatus? = nil
    @State var phoneExists: Bool? = nil
    @State var showAccountDetectedToast = false
    @State var requiresEmailVerification = false
    @State var alertError: PresentableAlertError?
    @State var submittedDestination = ""
    @State var resendCooldown = OTPCooldown()
    @State var isVerifyingOTP = false
    @State var appleFlowInFlight = false
    @State var appeared = false
    /// The provider whose sign-in succeeded and is now waiting on onboarding status
    /// to resolve. Keeps that button's spinner running through the post-sign-in
    /// window so we never swap in a separate loading screen here.
    @State var resolvingProvider: AuthProvider?

    /// Server-tunable (`otp_cooldown_seconds`, default 30) — an anti-abuse dial
    /// on an endpoint that costs real money per send.
    /// (Not private: read by SignInView+Logic.swift's `sendOTP`.)
    var otpCooldownSeconds: Int { remoteConfig.config.otpCooldownSeconds }

    /// True from the moment sign-in succeeds until onboarding status is known —
    /// the page is disabled and the tapped button keeps spinning during it.
    private var isResolvingPostSignIn: Bool {
        auth.isSignedIn && !onboarding.hasResolvedStatus
    }

    func isResolving(_ provider: AuthProvider) -> Bool {
        resolvingProvider == provider && isResolvingPostSignIn
    }

    var usesLiveBackend: Bool {
        AppConfiguration.current.isSupabaseConfigured
    }

    var googleSignInAvailable: Bool {
        AppConfiguration.current.isGoogleOAuthAvailable
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Spacer()
            
            Text("Let's get you On Board")
                .fontStyle(.largeTitle)
                .fontWeight(.heavy)
                .accessibilityAddTraits(.isHeader)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 10)
            
            formCard
            
            Spacer(minLength: 40)
            
            if !otpSent && !usePassword {
                VStack(spacing: 16) {
                    Button(credentialMode == .phone ? "Use Email" : "Use Phone") {
                        withAnimation(.snappy(duration: 0.3)) {
                            credentialMode = credentialMode == .phone ? .email : .phone
                        }
                    }
                    .buttonStyle(.boardSecondary)
                    .disabled(isSendingOTP)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 18)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))

                    // Mock (no-Supabase) builds hide social sign-in entirely —
                    // the buttons would only exercise mock stubs and clutter
                    // demo/UI-test runs.
                    if usesLiveBackend {
                        socialSection
                    }
                }
            }
        }
        .safeAreaPadding()
        .scrollDismissesKeyboard(.interactively)
        .scrollBounceBehavior(.basedOnSize)
        // Fresh sign-in: keep the form interactive-locked (not swapped for a loading
        // screen) until onboarding status resolves and the coordinator pushes the next step.
        .disabled(isResolvingPostSignIn)
        .keyboardDoneToolbar()
        .toolbar {
            if otpSent || usePassword {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        withAnimation(.snappy(duration: 0.35)) {
                            resetOTPSession()
                        }
                    } label: {
                        Label("Back", systemImage: "chevron.left").fontWeight(.semibold)
                    }
                    .accessibilityLabel("Back to sign in")
                }
            }
        }
        .authFailureAlert(auth, error: $alertError)
        .onChange(of: credentialMode) { _, _ in resetOTPSession() }
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
        .background {
            AnimatedLogoBackgroundView(opacity: 0.07)
        }
        .toast(isPresented: $showAccountDetectedToast, message: "Account Found!", icon: "person.crop.circle.fill.badge.checkmark")
    }



    // MARK: - Form card

    private var formCard: some View {
        VStack(spacing: 12) {
            credentialBlock

            primaryButton
        }
        .animation(.snappy(duration: 0.35), value: otpSent)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 22)
    }

    @ViewBuilder
    private var credentialBlock: some View {
        if usePassword {
            if requiresEmailVerification {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "envelope.fill")
                            .foregroundStyle(.secondary)
                            .fontStyle(.subheadline)
                        Text(emailAddress)
                            .fontStyle(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Text("Check your email for a verification link to continue.")
                        .fontStyle(.body)
                        .foregroundStyle(.secondary)
                }
                .transition(.opacity)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "envelope.fill")
                            .foregroundStyle(.secondary)
                            .fontStyle(.subheadline)
                        Text(emailAddress)
                            .fontStyle(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    SecureField("Password", text: $password)
                        .textFieldStyle(.boardStandard)
                        .textContentType(emailStatus?.exists == false ? .newPassword : .password)
                        .submitLabel(emailStatus?.exists == false ? .next : .go)
                        .onSubmit {
                            if emailStatus?.exists != false {
                                Task { await signInWithPassword() }
                            }
                        }
                        .disabled(isSigningInCredential)
                        .accessibilityLabel("Password")
                    
                    if emailStatus?.exists == false {
                        SecureField("Confirm Password", text: $confirmPassword)
                            .textFieldStyle(.boardStandard)
                            .textContentType(.newPassword)
                            .submitLabel(.go)
                            .onSubmit {
                                Task { await signUpWithPassword() }
                            }
                            .disabled(isSigningInCredential)
                            .accessibilityLabel("Confirm Password")
                    }
                }
                .transition(.opacity)
            }
        } else if otpSent {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .fontStyle(.subheadline)
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
                    Spacer()
                    OTPResendControl(
                        channel: credentialMode == .phone ? "text" : "email",
                        secondsRemaining: resendCooldown.secondsRemaining,
                        isSending: isSendingOTP,
                        onResend: { Task { await sendOTP(isResend: true) } }
                    )
                    Spacer()
                }
            }
            .transition(.opacity)
        } else {
            Group {
                if credentialMode == .phone {
                    VStack(alignment: .leading, spacing: 6) {
                        TextField("+1 (555) 555-0100", text: $phoneNumber)
                            .textFieldStyle(.boardStandard)
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
                            .textFieldStyle(.boardStandard)
                            .keyboardType(.emailAddress)
                            .textContentType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .disabled(isSendingOTP)
                            .accessibilityLabel("Email address")
                    }
                }
            }
            .transition(.opacity)
        }
    }

    @ViewBuilder
    private var primaryButton: some View {
        if usePassword {
            if requiresEmailVerification {
                VStack(spacing: 10) {
                    Button("Back to Sign In") {
                        withAnimation(.snappy(duration: 0.3)) { resetOTPSession() }
                    }
                    .buttonStyle(.boardSecondary)
                }
                .transition(.opacity)
            } else {
                VStack(spacing: 10) {
                    if emailStatus?.exists == false {
                        Button {
                            Task { await signUpWithPassword() }
                        } label: {
                            LoadingButtonLabel(
                                "Sign Up",
                                systemImage: "person.badge.plus",
                                isLoading: isSigningInCredential || isResolving(.email)
                            )
                        }
                        .buttonStyle(.boardPrimary)
                        .disabled(isSigningInCredential || isResolving(.email) || password.isEmpty || password != confirmPassword)
                        .accessibilityLabel("Sign up with password")
                    } else {
                        Button {
                            Task { await signInWithPassword() }
                        } label: {
                            LoadingButtonLabel(
                                "Sign In",
                                systemImage: "key.fill",
                                isLoading: isSigningInCredential || isResolving(.email)
                            )
                        }
                        .buttonStyle(.boardPrimary)
                        .disabled(isSigningInCredential || isResolving(.email) || password.isEmpty)
                        .accessibilityLabel("Sign in with password")
                    }

                    Button("Use a one-time code instead") {
                        withAnimation(.snappy(duration: 0.3)) {
                            usePassword = false
                            password = ""
                            confirmPassword = ""
                        }
                    }
                    .fontStyle(.footnote)
                    .foregroundStyle(.secondary)
                    .disabled(isSigningInCredential)
                }
                .transition(.opacity)
            }
        } else if otpSent {
            VStack(spacing: 10) {
                Button {
                    Task { await verifyOTP() }
                } label: {
                    LoadingButtonLabel(
                        "Verify Code",
                        systemImage: credentialMode == .phone
                            ? AuthProvider.phone.systemImage
                            : AuthProvider.email.systemImage,
                        isLoading: isSigningInCredential || isVerifyingOTP || isResolving(credentialProvider)
                    )
                }
                .buttonStyle(.boardPrimary)
                .disabled(isSigningInCredential || isVerifyingOTP || isResolving(credentialProvider) || !OTPCodeInput.isComplete(otpCode))
                .accessibilityLabel("Verify code")
                
                if credentialMode == .email {
                    let exists = emailStatus?.exists == true
                    let hasPassword = emailStatus?.hasPassword == true
                    if !exists || hasPassword {
                        Button(exists ? "Have a password? Sign in with it" : "Want to use a password? Sign up with it") {
                            withAnimation(.snappy(duration: 0.3)) { usePassword = true }
                        }
                        .fontStyle(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                        .disabled(isVerifyingOTP)
                    }
                }
            }
            .transition(.opacity)
        } else {
            VStack(spacing: 10) {
                Button {
                    Task { await sendOTP(isResend: false) }
                } label: {
                    LoadingButtonLabel(
                        "Continue",
                        systemImage: "arrow.forward",
                        isLoading: isSendingOTP || isSigningInCredential,
                        isActive: !normalizedCredentialValue.isEmpty
                    )
                }
                .buttonStyle(.boardPrimary)
                .disabled(isSendingOTP || isSigningInCredential || normalizedCredentialValue.isEmpty)
            }
            .transition(.opacity)
        }
    }

    // The credential/OTP/password helpers live in SignInView+Logic.swift.
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
        .environment(RemoteConfigStore())
}
