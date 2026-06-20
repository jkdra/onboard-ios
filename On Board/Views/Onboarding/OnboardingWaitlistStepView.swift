//
//  OnboardingWaitlistStepView.swift
//  On Board
//

import SwiftUI

struct OnboardingWaitlistStepView: View {
    @Environment(OnboardingStore.self) private var onboarding
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                Spacer()

                VStack(spacing: 12) {
                    Text("You're almost On Board")
                        .fontStyle(.largeTitle)
                        .fontWeight(.heavy)
                        .multilineTextAlignment(.center)

                    Text("On Board is rolling out periodically. Join the waitlist and we'll let you know when you're on board.")
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

                Button {
                    Task { await onboarding.joinWaitlist() }
                } label: {
                    Label("Join the waitlist", systemImage: "bell.badge.fill")
                }
                .buttonStyle(.boardPrimary)
                .disabled(onboarding.isSubmitting)

                Spacer()
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                LinearGradient(
                    colors: [
                        Color.accentColor.opacity(scheme == .light ? 0.12 : 0.18),
                        Color(.systemBackground)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            }
            .navigationTitle("Waitlist")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview {
    OnboardingWaitlistStepView()
        .environment(OnboardingStore(
            service: MockOnboardingService(),
            auth: AuthStore(service: MockAuthService()),
            network: NetworkMonitor()
        ))
}
