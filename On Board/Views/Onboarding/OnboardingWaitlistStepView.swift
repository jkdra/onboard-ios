//
//  OnboardingWaitlistStepView.swift
//  On Board
//

import SwiftUI
import UserNotifications

struct OnboardingWaitlistStepView: View {
    @Environment(OnboardingStore.self) private var onboarding
    @Environment(\.scenePhase) private var scenePhase

    @State private var appeared = false
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined

    var body: some View {
        VStack(spacing: 0) {
            OnboardingProgressBar(step: 6, totalSteps: 6)

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
            withAnimation(.spring(duration: 0.6, bounce: 0.2).delay(0.05)) { appeared = true }
        }
        .task {
            // Reaching this screen means the user has verified their .edu and is
            // already on the waitlist — poll so admin approval flips the app to the
            // board while they're watching, without a relaunch. RootView swaps this
            // view out when status turns complete, cancelling the task. 20s keeps the
            // wait-and-watch latency low; refresh() coalesces, so it stays cheap.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(20))
                guard !Task.isCancelled else { break }
                await onboarding.refresh()
            }
        }
        .task {
            await checkNotificationStatus()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task { await checkNotificationStatus() }
            }
        }
    }

    private func checkNotificationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationStatus = settings.authorizationStatus
    }

    // MARK: - Header icon

    private var iconHeader: some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 60, weight: .bold))
    }

    // MARK: - Text

    private var textBlock: some View {
        VStack(spacing: 10) {
            Text("You're almost On Board!")
                .fontStyle(.largeTitle)
                .fontWeight(.heavy)
                .multilineTextAlignment(.center)

            Text("We'll let you know when your spot opens up. Stay tuned!")
                .fontStyle(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
        }
    }

    // MARK: - Info chips

    /// The signing-up account, adapted from onboarding status into the `Profile`
    /// shape `AvatarView` consumes (so the waitlist avatar renders identically to
    /// everywhere else the user's picture appears).
    private var signupProfile: Profile? {
        guard let status = onboarding.status else { return nil }
        return Profile(
            id: status.id,
            handle: status.handle,
            displayName: status.displayName,
            bio: status.bio,
            avatarUrl: status.avatarUrl
        )
    }

    @ViewBuilder
    private var infoChips: some View {
        VStack(spacing: 8) {
            if let schoolName = onboarding.status?.schoolName {
                
                Label(schoolName, systemImage: "building.columns.fill")
                    .fontStyle(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule(style: .continuous).fill(.thinMaterial))
            }

            if let profile = signupProfile {
                HStack(spacing: 8) {
                    AvatarView(profile: profile, size: .small)
                    Text(profile.handle)
                        .fontStyle(.headline)
                }
                .padding(.leading, 6)
                .padding(.trailing, 16)
                .padding(.vertical, 6)
                .background(Capsule(style: .continuous).fill(.thinMaterial))
            }
        }
    }

    // MARK: - Action

    @ViewBuilder
    private var actionArea: some View {
        if notificationStatus == .authorized || notificationStatus == .provisional {
            Label("Thanks for enabling notifications!", systemImage: "checkmark.circle.fill")
                .fontStyle(.subheadline)
                .foregroundStyle(.secondary)
        } else {
            VStack(spacing: 12) {
                Label("Notifications aren't enabled! Turn on notifications so you don't miss the moment your spot opens up!", systemImage: "exclamationmark.triangle.fill")
                    .fontStyle(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal)

                Button {
                    if notificationStatus == .notDetermined {
                        Task {
                            let center = UNUserNotificationCenter.current()
                            let granted = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
                            if granted == true {
                                UIApplication.shared.registerForRemoteNotifications()
                            }
                            await checkNotificationStatus()
                        }
                    } else {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                } label: {
                    Label(
                        notificationStatus == .notDetermined ? "Enable Notifications" : "Open Settings",
                        systemImage: "bell.badge.fill"
                    )
                }
                .buttonStyle(.boardPrimary)
                .tint(.primary)
            }
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
