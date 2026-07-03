//
//  OnboardingWaitlistStepView.swift
//  On Board
//

import SwiftUI

struct OnboardingWaitlistStepView: View {
    @Environment(OnboardingStore.self) private var onboarding

    @State private var appeared = false

    private var hasJoined: Bool {
        onboarding.status?.waitlistJoinedAt != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 28) {
                iconHeader
                    .scaleEffect(appeared ? 1 : 0.7)
                    .opacity(appeared ? 1 : 0)

                textBlock
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 12)

                infoChips
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 8)

                actionArea
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 8)
            }

            Spacer()
        }
        .safeAreaPadding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationBarBackButtonHidden(true)
        .onAppear {
            withAnimation(.spring(duration: 0.6, bounce: 0.2).delay(0.05)) {
                appeared = true
            }
        }
        .task(id: hasJoined) {
            // Poll while parked on the waitlist so admin approval flips the app
            // to the board without requiring a relaunch. RootView swaps this
            // view out when status turns complete, cancelling the task.
            guard hasJoined else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(45))
                guard !Task.isCancelled else { break }
                await onboarding.refresh()
            }
        }
    }

    // MARK: - Header icon

    private var iconHeader: some View {
        Group {
            if hasJoined {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 60, weight: .bold))
                    .foregroundStyle(.green)
            } else {
                BrandLogo(size: 72)
            }
        }
        .animation(.spring(duration: 0.4, bounce: 0.3), value: hasJoined)
    }

    // MARK: - Text

    private var textBlock: some View {
        VStack(spacing: 10) {
            Text(hasJoined ? "You're on the list!" : "You're almost On Board!")
                .fontStyle(.largeTitle)
                .fontWeight(.heavy)
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
    }

    // MARK: - Info chips

    @ViewBuilder
    private var infoChips: some View {
        VStack(spacing: 8) {
            if let schoolName = onboarding.status?.schoolName {
                Text(schoolName)
                    .fontStyle(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule(style: .continuous).fill(.thinMaterial))
            }

            if let handle = onboarding.status?.handle {
                Text("@\(handle)")
                    .fontStyle(.headline)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Capsule(style: .continuous).fill(.thinMaterial))
            }
        }
    }

    // MARK: - Action

    @ViewBuilder
    private var actionArea: some View {
        if !hasJoined {
            Button {
                Task { await onboarding.joinWaitlist() }
            } label: {
                LoadingButtonLabel("Join the waitlist", systemImage: "bell.badge.fill", isLoading: onboarding.isSubmitting)
            }
            .buttonStyle(.boardPrimary)
            .disabled(onboarding.isSubmitting)
        } else {
            Label("You're on the waitlist", systemImage: "checkmark.circle.fill")
                .fontStyle(.subheadline)
                .foregroundStyle(.secondary)
        }
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
