//
//  OnboardingSchoolEmailStepView.swift
//  On Board
//

import SwiftUI

struct OnboardingSchoolEmailStepView: View {
    @Environment(OnboardingStore.self) private var onboarding
    @Environment(\.colorScheme) private var scheme

    @State private var email = ""
    @State private var otpCode = ""
    @State private var matchedSchool: SchoolMatch?
    @State private var codeSent = false
    @State private var lookupState: LookupState = .idle

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
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Verify your school")
                            .fontStyle(.largeTitle)
                            .fontWeight(.heavy)
                        Text("Use your .edu email to join your campus board.")
                            .fontStyle(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    TextField("you@school.edu", text: $email)
                        .textFieldStyle(.board)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .disabled(codeSent || onboarding.isSubmitting)
                        .onChange(of: email) { _, _ in
                            scheduleSchoolLookup()
                        }

                    schoolMatchLabel

                    if codeSent {
                        TextField("Verification code", text: $otpCode)
                            .textFieldStyle(.board)
                            .keyboardType(.numberPad)
                            .textContentType(.oneTimeCode)
                    }

                    if codeSent {
                        Button {
                            Task { await verifyCode() }
                        } label: {
                            Label("Verify email", systemImage: "checkmark.seal.fill")
                        }
                        .buttonStyle(.boardPrimary)
                        .disabled(onboarding.isSubmitting || otpCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        Button("Use a different email") {
                            codeSent = false
                            otpCode = ""
                            lookupState = .idle
                        }
                        .fontStyle(.footnote)
                        .foregroundStyle(.secondary)
                    } else {
                        Button {
                            Task { await sendCode() }
                        } label: {
                            Label("Send verification code", systemImage: "envelope.fill")
                        }
                        .buttonStyle(.boardPrimary)
                        .disabled(!canSendCode)
                    }

                    if AppConfiguration.current.isSupabaseConfigured == false {
                        Text("Dev tip: use name@example.edu to test school verification.")
                            .fontStyle(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(20)
            }
            .background(onboardingBackground)
            .navigationTitle("School email")
            .navigationBarTitleDisplayMode(.inline)
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
    }

    @ViewBuilder
    private var schoolMatchLabel: some View {
        if let matchedSchool {
            Label("\(matchedSchool.schoolName) · \(matchedSchool.boardName)", systemImage: "building.columns.fill")
                .fontStyle(.footnote)
                .foregroundStyle(.green)
        } else if SchoolEmailRules.isValid(normalizedEmail) {
            switch lookupState {
            case .checking:
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
            case .idle:
                Label("Checking school…", systemImage: "ellipsis")
                    .fontStyle(.footnote)
                    .foregroundStyle(.secondary)
            }
        } else {
            Text("We'll match your email domain to your campus board.")
                .fontStyle(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var onboardingBackground: some View {
        LinearGradient(
            colors: [
                Color.teal.opacity(scheme == .light ? 0.12 : 0.16),
                Color(.systemBackground)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    private func scheduleSchoolLookup() {
        guard SchoolEmailRules.isValid(normalizedEmail) else {
            matchedSchool = nil
            lookupState = .idle
            return
        }

        lookupState = .checking
        matchedSchool = nil

        Task {
            let result = await onboarding.lookupSchool(for: normalizedEmail)
            guard normalizedEmail == email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else { return }
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
        }
    }

    private func verifyCode() async {
        let token = otpCode.trimmingCharacters(in: .whitespacesAndNewlines)
        _ = await onboarding.verifySchoolEmail(normalizedEmail, code: token)
    }
}

#Preview {
    OnboardingSchoolEmailStepView()
        .environment(OnboardingStore(
            service: MockOnboardingService(),
            auth: AuthStore(service: MockAuthService()),
            network: NetworkMonitor()
        ))
}
