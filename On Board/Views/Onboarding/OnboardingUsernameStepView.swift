//
//  OnboardingUsernameStepView.swift
//  On Board
//

import SwiftUI

struct OnboardingUsernameStepView: View {
    @Environment(OnboardingStore.self) private var onboarding

    @State private var handle = ""
    @State private var availability: Availability = .idle
    @State private var debouncer = Debouncer()

    private enum Availability: Equatable {
        case idle
        case checking
        case available
        case unavailable
        case invalid
        case offline
    }

    private let handleLimit = 32

    private var trimmedHandle: String {
        handle.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var canContinue: Bool {
        HandleRules.isValid(trimmedHandle) && availability == .available && !onboarding.isSubmitting
    }

    var body: some View {
        ScrollView {
            OnboardingProgressBar(step: 2, totalSteps: 5)
                .safeAreaPadding(.horizontal)
            VStack(alignment: .leading, spacing: 20) {

                Text("This is how people will find you on the board.")
                    .fontStyle(.subheadline)
                    .foregroundStyle(.secondary)

                VStack(alignment: .trailing, spacing: 2) {
                    TextField("username", text: $handle)
                        .fontStyle(.title2)
                        .textInputAutocapitalization(.never)
                        .textFieldStyle(.boardStandard)
                        .autocorrectionDisabled()
                        .textContentType(.username)
                        .keyboardType(.asciiCapable)
                        .onChange(of: handle) { _, _ in
                            scheduleAvailabilityCheck()
                        }
                    
                    if trimmedHandle.count >= Int(Double(handleLimit) * 0.75) {
                        Text("\(trimmedHandle.count)/\(handleLimit)")
                            .fontStyle(.caption2)
                            .foregroundStyle(trimmedHandle.count >= handleLimit ? Color.red : Color.orange)
                            .monospacedDigit()
                    }
                }

                availabilityLabel

                Button {
                    Task { await onboarding.submitUsername(trimmedHandle) }
                } label: {
                    LoadingButtonLabel("Continue", systemImage: "arrow.forward", isLoading: onboarding.isSubmitting, isActive: canContinue)
                }
                .buttonStyle(.boardPrimary)
                .disabled(!canContinue)
            }
            .safeAreaPadding(.horizontal)
        }
        .scrollDismissesKeyboard(.interactively)
        .disabled(onboarding.isSubmitting)
        .keyboardDoneToolbar()
        .navigationTitle("Pick a username")
        .navigationBarTitleDisplayMode(.large)
        .onAppear { hydrateFromStatus() }
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

    private func scheduleAvailabilityCheck() {
        let candidate = trimmedHandle

        guard !candidate.isEmpty else {
            debouncer.cancel()
            availability = .idle
            return
        }

        guard HandleRules.isValid(candidate) else {
            debouncer.cancel()
            availability = .invalid
            return
        }

        availability = .checking
        debouncer.schedule(isStillCurrent: { trimmedHandle == candidate }) {
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
    NavigationStack {
        OnboardingUsernameStepView()
    }
    .environment(OnboardingStore(
        service: MockOnboardingService(),
        auth: AuthStore(service: MockAuthService()),
        network: NetworkMonitor()
    ))
}
