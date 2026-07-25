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
            OnboardingProgressBar(step: 7, totalSteps: 7)

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

    private var inviteURL: URL? {
        guard let code = onboarding.status?.referralCode else { return nil }
        return InviteLink.url(for: code)
    }

    /// The referral elements as one visual group: pitch, code, count, and the
    /// share button that acts on them.
    @ViewBuilder
    private func referralCard(code: String) -> some View {
        VStack(spacing: 10) {
            Text("Skip the line! Invite friends using your code:")
                .fontStyle(.footnote)
                .foregroundStyle(.secondary)

            Text(code.uppercased())
                .fontStyle(.title2)
                .fontWeight(.black)
                .monospaced()
                .foregroundStyle(.primary)
                .padding(.vertical, 6)
                .padding(.horizontal, 16)
                .background(Capsule().fill(.quaternary))

            if let count = onboarding.status?.verifiedReferralCount, count > 0 {
                Text("🔥 \(count) friend\(count == 1 ? "" : "s") invited!")
                    .fontStyle(.caption)
                    .foregroundStyle(.orange)
            }

            // TODO(launch): First Class isn't fulfilled server-side yet, so its
            // referral reward is hidden. Uncomment to re-enable when the
            // subscription ships (ReferralRewards.milestoneText is left intact).
            //            if let milestone = ReferralRewards.milestoneText(for: onboarding.status?.verifiedReferralCount ?? 0) {
            //                Text(milestone)
            //                    .fontStyle(.caption2)
            //                    .foregroundStyle(.secondary)
            //                    .multilineTextAlignment(.center)
            //            }

            if let inviteURL {
                ShareLink(
                    item: inviteURL,
                    message: Text(InviteLink.shareMessage(code: code, hasInstantInvites: false))
                ) {
                    LoadingButtonLabel("Invite Friends", systemImage: "square.and.arrow.up", isLoading: false)
                }
                .buttonStyle(.boardPrimary)
                .tint(.primary)
                .padding(.top, 4)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(.thinMaterial))
    }

    @ViewBuilder
    private var actionArea: some View {
        VStack(spacing: 16) {
            // Sharing is the whole point of the waitlist screen — it's always
            // available, regardless of notification state.
            if let code = onboarding.status?.referralCode {
                referralCard(code: code)
            }

            if notificationStatus == .authorized || notificationStatus == .provisional {
                Label("Thanks for enabling notifications!", systemImage: "checkmark.circle.fill")
                    .fontStyle(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
            } else {
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
                    LoadingButtonLabel(
                        notificationStatus == .notDetermined ? "Enable Notifications" : "Open Settings",
                        systemImage: "bell.badge.fill",
                        isLoading: false
                    )
                }
                .buttonStyle(.boardPrimary)
                .tint(.primary)
            }

            if onboarding.supportsDevAdmission {
                Button("Join Board [DEV]") {
                    Task { await onboarding.devAdmit() }
                }
                .fontStyle(.footnote)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
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
