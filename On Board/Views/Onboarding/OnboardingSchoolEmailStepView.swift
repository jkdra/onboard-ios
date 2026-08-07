//
//  OnboardingSchoolEmailStepView.swift
//  On Board
//

import SwiftUI

struct OnboardingSchoolEmailStepView: View {
    @Environment(OnboardingStore.self) private var onboarding
    @Environment(RemoteConfigStore.self) private var remoteConfig

    @State private var email = ""
    @State private var otpCode = ""
    @State private var matchedSchool: SchoolMatch?
    @State private var codeSent = false
    @State private var lookupState: LookupState = .idle
    @State private var debouncer = Debouncer()
    @State private var resendCooldown = OTPCooldown()
    @State private var showNiceTryAlert = false

    private enum LookupState: Equatable {
        case idle
        case checking
        case unsupported
        case inUse
        case networkError
    }

    private var normalizedEmail: String {
        EmailNormalizer.normalized(email)
    }

    private var canSendCode: Bool {
        SchoolEmailRules.isValid(normalizedEmail) && matchedSchool != nil && !onboarding.isSubmitting
    }

    var body: some View {
        ScrollView {
            OnboardingProgressBar(step: 4, totalSteps: 6)
                .safeAreaPadding(.horizontal)
            VStack(alignment: .leading, spacing: 20) {

                Text("Use your .edu email to join your campus board.")
                    .fontStyle(.subheadline)
                    .foregroundStyle(.secondary)

                TextField("you@school.edu", text: $email)
                    .textFieldStyle(.boardStandard)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .disabled(codeSent || onboarding.isSubmitting)
                    .onChange(of: email) { _, _ in scheduleSchoolLookup() }

                schoolMatchLabel

                if codeSent {
                    OTPCodeField(code: $otpCode, isEnabled: !onboarding.isSubmitting) {
                        Task { await verifyCode() }
                    }

                    Button {
                        Task { await verifyCode() }
                    } label: {
                        LoadingButtonLabel("Verify email", systemImage: "checkmark.seal.fill", isLoading: onboarding.isSubmitting, isActive: !otpCode.isEmpty)
                    }
                    .buttonStyle(.boardPrimary)
                    .disabled(onboarding.isSubmitting || otpCode.isEmpty)

                    HStack(spacing: 4) {
                        Text("Didn't get it?")
                            .fontStyle(.footnote)
                            .foregroundStyle(.secondary)
                        if !resendCooldown.canResend {
                            Text("Resend in \(resendCooldown.secondsRemaining)s")
                                .fontStyle(.footnote)
                                .foregroundStyle(.secondary)
                        } else {
                            Button("Resend") {
                                Task { await resendCode() }
                            }
                            .fontStyle(.footnote)
                            .disabled(onboarding.isSubmitting)
                        }
                    }

                    Text("Check your spam folder if you don't see it.")
                        .fontStyle(.footnote)
                        .foregroundStyle(.secondary)

                    Button("Use a different email") {
                        codeSent = false
                        otpCode = ""
                        // Cooldown deliberately kept: re-sending to the SAME
                        // email inside the window just reopens code entry (see
                        // sendCode) instead of invalidating the code in flight.
                        lookupState = .idle
                    }
                    .fontStyle(.footnote)
                    .foregroundStyle(.secondary)
                } else {
                    Button {
                        Task { await sendCode() }
                    } label: {
                        LoadingButtonLabel("Send verification code", systemImage: "envelope.fill", isLoading: onboarding.isSubmitting, isActive: canSendCode)
                    }
                    .buttonStyle(.boardPrimary)
                    .disabled(!canSendCode)
                }
            }
            .safeAreaPadding(.horizontal)
        }
        .scrollDismissesKeyboard(.interactively)
        .disabled(onboarding.isSubmitting)
        .keyboardDoneToolbar()
        .navigationTitle("Verify your school")
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            if email.isEmpty {
                email = onboarding.status?.pendingSchoolEmail
                    ?? onboarding.status?.verifiedSchoolEmail
                    ?? ""
            }
            if onboarding.status?.pendingSchoolEmail != nil {
                codeSent = true
            }
            if let schoolName = onboarding.status?.schoolName,
               let boardName = onboarding.status?.boardName,
               let boardId = onboarding.status?.boardId {
                matchedSchool = SchoolMatch(
                    domain: SchoolEmailRules.isValid(email) ? normalizedEmail.split(separator: "@").last.map(String.init) ?? "" : "",
                    schoolName: schoolName,
                    boardId: boardId,
                    boardName: boardName
                )
                lookupState = .idle
            }
        }
        .alert("Nice Try.", isPresented: $showNiceTryAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Impressive. You should be on our dev team, but rules are rules. Please put your actual school email.")
        }
    }

    @ViewBuilder
    private var schoolMatchLabel: some View {
        if let matchedSchool {
            let display = matchedSchool.schoolName == matchedSchool.boardName
                ? matchedSchool.schoolName
                : "\(matchedSchool.schoolName) · \(matchedSchool.boardName)"
            Label(display, systemImage: "building.columns.fill")
                .fontStyle(.footnote)
                .foregroundStyle(.green)
        } else if SchoolEmailRules.isValid(normalizedEmail) {
            switch lookupState {
            case .checking, .idle:
                Label("Checking school…", systemImage: "ellipsis")
                    .fontStyle(.footnote)
                    .foregroundStyle(.secondary)
            case .unsupported:
                Label(OnboardingError.schoolUnsupported.localizedDescription, systemImage: "xmark.circle.fill")
                    .fontStyle(.footnote)
                    .foregroundStyle(.red)
            case .inUse:
                Label("Email already registered & verified.", systemImage: "xmark.circle.fill")
                    .fontStyle(.footnote)
                    .foregroundStyle(.red)
            case .networkError:
                Label("Offline — connect to check school", systemImage: "wifi.slash")
                    .fontStyle(.footnote)
                    .foregroundStyle(.orange)
            }
        } else {
            Text("We'll match your email domain to your campus board.")
                .fontStyle(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func scheduleSchoolLookup() {
        guard SchoolEmailRules.isValid(normalizedEmail) else {
            debouncer.cancel()
            matchedSchool = nil
            lookupState = .idle
            return
        }

        lookupState = .checking
        matchedSchool = nil

        let candidate = normalizedEmail
        debouncer.schedule(isStillCurrent: { normalizedEmail == candidate }) {
            let result = await onboarding.lookupSchool(for: candidate)
            guard !Task.isCancelled, normalizedEmail == candidate else { return }
            switch result {
            case .matched(let match):
                // School is supported — now make sure no other account has
                // already verified this exact email (same live-check pattern
                // as the username step).
                let availability = await onboarding.checkSchoolEmailAvailable(candidate)
                guard !Task.isCancelled, normalizedEmail == candidate else { return }
                switch availability {
                case .taken:
                    matchedSchool = nil
                    lookupState = .inUse
                case .available, .networkError:
                    // networkError here means the school lookup succeeded but
                    // the availability check flaked — don't strand the user;
                    // begin_school_email_verification re-checks server-side.
                    matchedSchool = match
                    lookupState = .idle
                }
            case .unsupported:
                matchedSchool = nil
                lookupState = .unsupported
            case .networkError:
                matchedSchool = nil
                lookupState = .networkError
            }
        }
    }

    private func sendCode() async {
        if normalizedEmail.contains("+") {
            showNiceTryAlert = true
            return
        }

        // Same email, window still open: the code already sent is still valid —
        // reopen the entry UI without burning it. A different email sends fresh.
        guard resendCooldown.canSend(to: normalizedEmail) else {
            codeSent = true
            return
        }
        // matchedSchool is already set by the debounced lookup (sending is
        // gated on it) — no fallback reconstruction here. The old fallback
        // rebuilt it from onboarding.status, whose school/board names only
        // resolve AFTER verification, so it always rendered the placeholders
        // ("Your school · On Board").
        let success = await onboarding.sendSchoolVerificationCode(to: normalizedEmail)
        if success {
            codeSent = true
            resendCooldown.start(
                duration: remoteConfig.config.otpCooldownSeconds,
                destination: normalizedEmail
            )
        }
    }

    private func resendCode() async {
        guard resendCooldown.canResend else { return }
        otpCode = ""
        let success = await onboarding.sendSchoolVerificationCode(to: normalizedEmail)
        if success {
            resendCooldown.start(
                duration: remoteConfig.config.otpCooldownSeconds,
                destination: normalizedEmail
            )
        }
    }

    private func verifyCode() async {
        _ = await onboarding.verifySchoolEmail(normalizedEmail, code: otpCode)
    }
}

#Preview {
    NavigationStack {
        OnboardingSchoolEmailStepView()
    }
    .environment(OnboardingStore(
        service: MockOnboardingService(),
        auth: AuthStore(service: MockAuthService()),
        network: NetworkMonitor()
    ))
        .environment(RemoteConfigStore())
}
