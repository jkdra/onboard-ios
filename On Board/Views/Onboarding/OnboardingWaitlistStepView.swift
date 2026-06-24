//
//  OnboardingWaitlistStepView.swift
//  On Board
//

import SwiftUI

struct OnboardingWaitlistStepView: View {
    @Environment(OnboardingStore.self) private var onboarding

    private var hasJoined: Bool {
        onboarding.status?.waitlistJoinedAt != nil
    }

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            VStack(spacing: 12) {
                Text(hasJoined ? "You're on the list!" : "You're almost On Board!")
                    .fontStyle(.largeTitle)
                    .multilineTextAlignment(.center)

                Text(
                    hasJoined
                        ? "We'll send you a notification when your spot opens up. Keep an eye out."
                        : "On Board is rolling out periodically. Join the waitlist and we'll let you know when you're in."
                )
                .fontStyle(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
            }

            if let schoolName = onboarding.status?.schoolName {
                Text(schoolName)
                    .fontStyle(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let handle = onboarding.status?.handle {
                Text("@\(handle)")
                    .fontStyle(.headline)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Capsule(style: .continuous).fill(.thinMaterial))
            }

            if !hasJoined {
                Button {
                    Task { await onboarding.joinWaitlist() }
                } label: {
                    if onboarding.isSubmitting {
                        ProgressView().tint(.white)
                    } else {
                        Label("Join the waitlist", systemImage: "bell.badge.fill")
                    }
                }
                .buttonStyle(.boardPrimary)
                .disabled(onboarding.isSubmitting)
            } else {
                Label("You're on the waitlist", systemImage: "checkmark.circle.fill")
                    .fontStyle(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .safeAreaPadding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationBarBackButtonHidden(true)
    }
}

#Preview {
    NavigationStack {
        OnboardingWaitlistStepView()
    }
    .environment(OnboardingStore(
        service: MockOnboardingService(),
        auth: AuthStore(service: MockAuthService()),
        network: NetworkMonitor()
    ))
}
