//
//  OnboardingSchoolEmailStepView.swift
//  On Board
//

import SwiftUI

struct OnboardingSchoolEmailStepView: View {
    @Environment(OnboardingStore.self) private var onboarding

    @State private var email = ""
    @State private var otpCode = ""
    @State private var matchedSchool: SchoolMatch?
    @State private var codeSent = false
    @State private var lookupState: LookupState = .idle
    @State private var lookupTask: Task<Void, Never>?
    @State private var resendCooldown = 0

    private enum LookupState: Equatable {
        case idle
        case checking
        case unsupported
        case networkError
    }

    private var normalizedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var canSendCode: Bool {
        SchoolEmailRules.isValid(normalizedEmail) && matchedSchool != nil && !onboarding.isSubmitting
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Use your .edu email to join your campus board.")
                    .fontStyle(.subheadline)
                    .foregroundStyle(.secondary)

                TextField("you@school.edu", text: $email)
                    .textFieldStyle(.board)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .disabled(codeSent || onboarding.isSubmitting)
                    .onChange(of: email) { _, _ in scheduleSchoolLookup() }

                schoolMatchLabel

                if codeSent {
                    TextField("Verification code", text: $otpCode)
                        .textFieldStyle(.board)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)

                    Button {
                        Task { await verifyCode() }
                    } label: {
                        if onboarding.isSubmitting {
                            ProgressView().tint(.white)
                        } else {
                            Label("Verify email", systemImage: "checkmark.seal.fill")
                        }
                    }
                    .buttonStyle(.boardPrimary)
                    .disabled(onboarding.isSubmitting || otpCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    HStack(spacing: 4) {
                        Text("Didn't get it?")
                            .fontStyle(.footnote)
                            .foregroundStyle(.secondary)
                        if resendCooldown > 0 {
                            Text("Resend in \(resendCooldown)s")
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
                        resendCooldown = 0
                        lookupState = .idle
                    }
                    .fontStyle(.footnote)
                    .foregroundStyle(.secondary)
                } else {
                    Button {
                        Task { await sendCode() }
                    } label: {
                        if onboarding.isSubmitting {
                            ProgressView().tint(.white)
                        } else {
                            Label("Send verification code", systemImage: "envelope.fill")
                        }
                    }
                    .buttonStyle(.boardPrimary)
                    .disabled(!canSendCode)
                }
            }
            .safeAreaPadding(.horizontal)
        }
        .navigationTitle("Verify your school")
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
        lookupTask?.cancel()

        guard SchoolEmailRules.isValid(normalizedEmail) else {
            matchedSchool = nil
            lookupState = .idle
            return
        }

        lookupState = .checking
        matchedSchool = nil

        let candidate = normalizedEmail
        lookupTask = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }

            let result = await onboarding.lookupSchool(for: candidate)
            guard !Task.isCancelled, normalizedEmail == candidate else { return }
            switch result {
            case .matched(let match):
                matchedSchool = match
                lookupState = .idle
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
        let success = await onboarding.sendSchoolVerificationCode(to: normalizedEmail)
        if success {
            codeSent = true
            matchedSchool = onboarding.status.map {
                SchoolMatch(
                    domain: normalizedEmail.split(separator: "@").last.map(String.init) ?? "",
                    schoolName: $0.schoolName ?? "Your school",
                    boardId: $0.boardId ?? SampleBoardID.main,
                    boardName: $0.boardName ?? "On Board"
                )
            } ?? matchedSchool
            startResendCooldown()
        }
    }

    private func resendCode() async {
        otpCode = ""
        let success = await onboarding.sendSchoolVerificationCode(to: normalizedEmail)
        if success {
            startResendCooldown()
        }
    }

    private func verifyCode() async {
        let token = otpCode.trimmingCharacters(in: .whitespacesAndNewlines)
        _ = await onboarding.verifySchoolEmail(normalizedEmail, code: token)
    }

    private func startResendCooldown() {
        resendCooldown = 30
        Task {
            while resendCooldown > 0 {
                try? await Task.sleep(for: .seconds(1))
                resendCooldown = max(0, resendCooldown - 1)
            }
        }
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
}
