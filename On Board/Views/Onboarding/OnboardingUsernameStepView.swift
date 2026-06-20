//
//  OnboardingUsernameStepView.swift
//  On Board
//

import SwiftUI

struct OnboardingUsernameStepView: View {
    @Environment(OnboardingStore.self) private var onboarding
    @Environment(\.colorScheme) private var scheme

    @State private var handle = ""
    @State private var availability: Availability = .idle
    @State private var checkTask: Task<Void, Never>?

    private enum Availability: Equatable {
        case idle
        case checking
        case available
        case unavailable
        case invalid
        case offline
    }

    private var trimmedHandle: String {
        handle.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canContinue: Bool {
        HandleRules.isValid(trimmedHandle) && availability == .available && !onboarding.isSubmitting
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Pick a username")
                            .fontStyle(.largeTitle)
                            .fontWeight(.heavy)
                        Text("This is how people will find you on the board.")
                            .fontStyle(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 8) {
                        Text("@")
                            .fontStyle(.title2)
                            .foregroundStyle(.secondary)
                        TextField("username", text: $handle)
                            .fontStyle(.title2)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .textContentType(.username)
                            .onChange(of: handle) { _, _ in
                                scheduleAvailabilityCheck()
                            }
                    }
                    .textFieldStyle(.board)

                    availabilityLabel

                    Button {
                        Task {
                            await onboarding.submitUsername(trimmedHandle)
                        }
                    } label: {
                        Label("Continue", systemImage: "arrow.right")
                    }
                    .buttonStyle(.boardPrimary)
                    .disabled(!canContinue)
                }
                .padding(20)
            }
            .background(onboardingBackground)
            .navigationTitle("Welcome")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                hydrateFromStatus()
            }
        }
    }

    private func hydrateFromStatus() {
        guard handle.isEmpty, let status = onboarding.status else { return }
        let saved = status.handle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard HandleRules.isValid(saved), !HandleRules.isProvisional(saved) else { return }
        handle = saved
        availability = .available
    }

    @ViewBuilder
    private var availabilityLabel: some View {
        switch availability {
        case .idle:
            Text("Letters, numbers, periods, and underscores only.")
                .fontStyle(.footnote)
                .foregroundStyle(.secondary)
        case .checking:
            Label("Checking availability…", systemImage: "ellipsis")
                .fontStyle(.footnote)
                .foregroundStyle(.secondary)
        case .available:
            Label("Available", systemImage: "checkmark.circle.fill")
                .fontStyle(.footnote)
                .foregroundStyle(.green)
        case .unavailable:
            Label("Already taken", systemImage: "xmark.circle.fill")
                .fontStyle(.footnote)
                .foregroundStyle(.red)
        case .invalid:
            Label("Use 2–32 characters: letters, numbers, . or _", systemImage: "exclamationmark.circle.fill")
                .fontStyle(.footnote)
                .foregroundStyle(.orange)
        case .offline:
            Label("Offline — connect to check availability", systemImage: "wifi.slash")
                .fontStyle(.footnote)
                .foregroundStyle(.orange)
        }
    }

    private var onboardingBackground: some View {
        LinearGradient(
            colors: [
                Color.gray.opacity(scheme == .light ? 0.20 : 0.16),
                Color(.systemBackground)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    private func scheduleAvailabilityCheck() {
        checkTask?.cancel()
        let candidate = trimmedHandle

        guard !candidate.isEmpty else {
            availability = .idle
            return
        }

        guard HandleRules.isValid(candidate) else {
            availability = .invalid
            return
        }

        availability = .checking
        checkTask = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }

            let result = await onboarding.checkHandleAvailable(candidate)
            guard !Task.isCancelled, trimmedHandle == candidate else { return }
            switch result {
            case .available: availability = .available
            case .taken: availability = .unavailable
            case .networkError: availability = .offline
            }
        }
    }
}

#Preview {
    OnboardingUsernameStepView()
        .environment(OnboardingStore(
            service: MockOnboardingService(),
            auth: AuthStore(service: MockAuthService()),
            network: NetworkMonitor()
        ))
}
