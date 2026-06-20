//
//  OnboardingCoordinator.swift
//  On Board
//

import SwiftUI

struct OnboardingCoordinator: View {
    @Environment(OnboardingStore.self) private var onboarding

    @State private var alertError: PresentableAlertError?

    var body: some View {
        Group {
            switch onboarding.status?.onboardingStep {
            case .username, .none:
                OnboardingUsernameStepView()
            case .profile:
                OnboardingProfileStepView()
            case .schoolVerify:
                OnboardingSchoolEmailStepView()
            case .waitlist:
                OnboardingWaitlistStepView()
            case .complete:
                ProgressView("Finishing up…")
            }
        }
        .animation(.smooth(duration: 0.25), value: onboarding.status?.onboardingStep)
        .safeAreaInset(edge: .top, spacing: 0) {
            if let syncFailure = onboarding.syncFailure {
                syncFailureBanner(syncFailure)
            }
        }
        .onChange(of: onboarding.lastError) { _, message in
            guard let message, !message.isEmpty else { return }
            alertError = PresentableAlertError(
                message: message,
                recoverySuggestion: onboarding.lastErrorRecovery
            )
        }
        .presentableErrorAlert(error: $alertError) {
            onboarding.clearLastError()
        }
    }

    private func syncFailureBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "icloud.slash")
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 4) {
                Text("Couldn't sync your progress")
                    .fontStyle(.footnote)
                    .fontWeight(.semibold)
                Text("You're seeing your last saved step. \(message)")
                    .fontStyle(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Button("Retry") {
                Task { await onboarding.refresh() }
            }
            .fontStyle(.footnote)
            .fontWeight(.semibold)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }
}

#Preview {
    OnboardingCoordinator()
        .environment(OnboardingStore(
            service: MockOnboardingService(),
            auth: AuthStore(service: MockAuthService()),
            network: NetworkMonitor()
        ))
}
