//
//  OnboardingSchoolEmailStepView.swift
//  On Board
//
//  The school gate, as ONE screen with three stages (2026-08-07):
//
//    email → code → graduation
//
//  Stage `email` collects the .edu address; stage `code` REPLACES the field
//  with OTP entry (a disabled email field under a code box was dead weight —
//  the address becomes a caption, and "Use a different email" is the way
//  back); stage `graduation` collects the expected graduation date. The user
//  verifies and dates without ever leaving the screen — the coordinator holds
//  `.graduation` at the SAME navigation path as `.schoolVerify`, so stage
//  changes are in-place slides, not pushes. The profanity preference follows
//  as its OWN pushed step (one decision per screen — Jawad, 2026-08-08).
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

    // Graduation-stage state (the old standalone step, folded in).
    @State private var gradMonth = 5   // May
    @State private var gradYear = Calendar.current.component(.year, from: Date()) + 1
    private let monthNames: [String] = Calendar.current.monthSymbols

    private enum LookupState: Equatable {
        case idle
        case checking
        case unsupported
        case inUse
        case networkError
    }

    private enum Stage: Equatable {
        case email, code, graduation
    }

    /// Derived, not stored: server status is the source of truth, so a killed
    /// app reopens exactly where the user left off (pending email → code
    /// entry; verified but no graduation → graduation stage).
    private var stage: Stage {
        if onboarding.status?.verifiedSchoolEmail != nil { return .graduation }
        if codeSent { return .code }
        return .email
    }

    private var normalizedEmail: String {
        EmailNormalizer.normalized(email)
    }

    private var canSendCode: Bool {
        SchoolEmailRules.isValid(normalizedEmail) && matchedSchool != nil && !onboarding.isSubmitting
    }

    private var years: [Int] {
        let current = Calendar.current.component(.year, from: Date())
        return Array(current...(current + 8))
    }

    private var selectedGraduation: Date? {
        var comps = DateComponents()
        comps.year = gradYear
        comps.month = gradMonth
        comps.day = 1
        return Calendar.current.date(from: comps)
    }

    var body: some View {
        ScrollView {
            OnboardingProgressBar(step: 4, totalSteps: 6)
                .safeAreaPadding(.horizontal)
            Group {
                switch stage {
                case .email:   emailStage
                case .code:    codeStage
                case .graduation: graduationStage
                }
            }
            .safeAreaPadding(.horizontal)
            // In-place stage slides — reads as progress without a push.
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            ))
        }
        .animation(.smooth(duration: 0.35), value: stage)
        .scrollDismissesKeyboard(.interactively)
        .disabled(onboarding.isSubmitting)
        .keyboardDoneToolbar()
        .navigationTitle(stage == .graduation ? "Graduation" : "Verify your school")
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

    // MARK: - Stage 1: email

    private var emailStage: some View {
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
                .onChange(of: email) { _, _ in scheduleSchoolLookup() }

            schoolMatchLabel

            Button {
                Task { await sendCode() }
            } label: {
                LoadingButtonLabel("Send verification code", systemImage: "envelope.fill", isLoading: onboarding.isSubmitting, isActive: canSendCode)
            }
            .buttonStyle(.boardPrimary)
            .disabled(!canSendCode)
        }
    }

    // MARK: - Stage 2: code

    private var codeStage: some View {
        VStack(alignment: .leading, spacing: 20) {
            // The address the field used to show, now as context — the field
            // itself is gone (it was disabled dead weight at this stage).
            (Text("We sent a code to ").foregroundStyle(.secondary)
             + Text(normalizedEmail).fontWeight(.semibold).foregroundStyle(.primary))
                .fontStyle(.subheadline)

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
        }
    }

    // MARK: - Stage 3: details (the old graduation step, folded in)

    private var graduationStage: some View {
        VStack(alignment: .leading, spacing: 24) {
            if let verified = onboarding.status?.verifiedSchoolEmail {
                Label("\(verified) verified", systemImage: "checkmark.seal.fill")
                    .fontStyle(.footnote)
                    .foregroundStyle(.green)
            }

            Text("When do you expect to graduate? This lets your board follow you when you become an alum. You can change it anytime in Settings.")
                .fontStyle(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 0) {
                Picker("Month", selection: $gradMonth) {
                    ForEach(1...12, id: \.self) { m in
                        Text(monthNames[m - 1]).tag(m)
                    }
                }
                .pickerStyle(.wheel)
                .frame(maxWidth: .infinity)

                Picker("Year", selection: $gradYear) {
                    ForEach(years, id: \.self) { y in
                        Text(String(y)).tag(y)
                    }
                }
                .pickerStyle(.wheel)
                .frame(maxWidth: .infinity)
            }
            .disabled(onboarding.isSubmitting)

            Button {
                guard let date = selectedGraduation else { return }
                Task { await onboarding.submitGraduation(date) }
            } label: {
                LoadingButtonLabel("Continue", systemImage: "arrow.forward", isLoading: onboarding.isSubmitting, isActive: true)
            }
            .buttonStyle(.boardPrimary)
            .disabled(onboarding.isSubmitting)
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
