//
//  SettingsView.swift
//  On Board
//

import SwiftUI

struct SettingsView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(BoardStore.self) private var store
    @Environment(OnboardingStore.self) private var onboarding
    @Environment(\.dynamicTypeSize) private var typeSize
    @AppStorage("appearance") private var appearance: AppearancePreference = .system
    @AppStorage("hapticsEnabled") private var hapticsEnabled: Bool = true
    @AppStorage("profanityEnabled") private var profanityEnabled: Bool = false
    @AppStorage("rotationIntensity") private var rotationIntensity: Double = 0.7
    @Environment(\.dismiss) private var dismiss

    @State private var showProfanityInfo = false
    @State private var webDocument: WebDocument?

    var body: some View {
        // No wrapping NavigationStack — this is pushed as a BoardRoute.settings
        // destination onto ContentView's existing NavigationStack. Nesting a
        // second NavigationStack inside a pushed destination is the anti-pattern
        // this avoids (double nav bars, confused back-button behavior); the
        // Form's own navigationTitle/toolbar attach directly to the outer stack.
        Form {
            SettingsHapticsPreview()

            Section {
                Picker(selection: $appearance) {
                    ForEach(AppearancePreference.allCases) { value in
                        Text(value.label).tag(value)
                    }
                } label: {
                    Text("Theme").fontStyle(.body)
                }
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Card rotation").fontStyle(.body)
                        Spacer()
                        Text(rotationIntensity == 0 || typeSize.isAccessibilitySize ? "Off" : "\(Int(rotationIntensity * 100))%")
                            .foregroundStyle(.secondary)
                            .fontStyle(.footnote)
                            .monospacedDigit()
                    }
                    Slider(value: $rotationIntensity, in: 0...1, step: 0.05)
                        .disabled(typeSize.isAccessibilitySize)
                    if typeSize.isAccessibilitySize {
                        Text("Card rotation is not available at accessibility text sizes.")
                            .fontStyle(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)

                Toggle(isOn: $hapticsEnabled) {
                    Text("Haptics").fontStyle(.body)
                }
                .tint(.primary)
                
                Toggle(isOn: $profanityEnabled) {
                    HStack(spacing: 6) {
                        Text("Profanity").fontStyle(.body)
                        Button {
                            showProfanityInfo = true
                        } label: {
                            Image(systemName: "info.circle.fill")
                                .fontStyle(.body)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .tint(.primary)
                .alert("Profanity", isPresented: $showProfanityInfo) {
                    Button("OK", role: .cancel) { }
                } message: {
                    Text("Mild profanity may be used in weekly prompts and in-app communications for a more... informal experience. This setting does not affect user-generated content that may contain profanity.")
                }
                .tint(.primary)
            } header: {
                Text("User Experience")
                    .fontStyle(.subheadline)
            } footer: {
                Text("Customize the look, feel, and content of On Board.")
                    .fontStyle(.footnote)
            }

            accountSection

            inviteSection

            Section {
                NavigationLink {
                    NotificationSettingsView()
                } label: {
                    SettingsRowLabel(title: "Notification Settings", systemImage: "bell.badge.fill")
                }
            } header: {
                Text("Notifications")
                    .fontStyle(.subheadline)
            } footer: {
                Text("Manage which notifications you want to receive.")
                    .fontStyle(.footnote)
            }

            Section {
                Link(destination: URL(string: "mailto:\(AppLinks.supportEmail)")!) {
                    SettingsRowLabel(title: "Contact Support", systemImage: "envelope.fill")
                }
                Link(destination: AppLinks.reportMailURL) {
                    SettingsRowLabel(title: "Report a Problem", systemImage: "exclamationmark.bubble.fill")
                }
            } header: {
                Text("Support")
                    .fontStyle(.subheadline)
            }

            Section {
                legalLinkRow(
                    title: "Privacy Policy",
                    systemImage: "hand.raised.fill",
                    url: AppLinks.privacyPolicyURL
                )
                legalLinkRow(
                    title: "Terms of Service",
                    systemImage: "doc.text.fill",
                    url: AppLinks.termsOfServiceURL
                )
            } header: {
                Text("Legal")
                    .fontStyle(.subheadline)
            }

            Section {
                if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
                   let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
                    LabeledContent {
                        Text("\(version) (\(build))").fontStyle(.body)
                    } label: {
                        Text("Version").fontStyle(.body)
                    }
                }
                Text("Made with love by @jawadalkhadra")
                    .fontStyle(.footnote)
                    .frame(maxWidth: .infinity)
            }
            .listRowBackground(Color.clear)
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: auth.isSignedIn) { _, isSignedIn in
            guard !isSignedIn else { return }
            dismiss()
        }
        .sheet(item: $webDocument) { document in
            WebContentSheet(document: document)
        }
    }

    // MARK: - Legal links

    private func legalLinkRow(title: String, systemImage: String, url: URL) -> some View {
        Button {
            webDocument = WebDocument(title: title, url: url)
        } label: {
            HStack(spacing: 12) {
                SettingsIconBadge(systemImage: systemImage)
                Text(title).fontStyle(.body)
                Spacer(minLength: 8)
                // Signals this row shows external (web) content, even though
                // it opens in-app rather than handing off to Safari.
                Image(systemName: "arrow.up.right")
                    .fontStyle(.footnote)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .accessibilityHint("Opens in a web view")
    }

    // MARK: - Invite section

    /// Admitted users keep sharing their code from Settings. While they have
    /// instant invites left, a signup through their code skips the waitlist
    /// entirely; at zero the code degrades to a priority referral.
    @ViewBuilder
    private var inviteSection: some View {
        if onboarding.isComplete,
           let code = onboarding.status?.referralCode,
           let url = InviteLink.url(for: code) {
            let instantRemaining = onboarding.status?.instantInvitesRemaining ?? 0
            Section {
                LabeledContent {
                    Text(code.uppercased())
                        .fontStyle(.body)
                        .monospaced()
                        .textSelection(.enabled)
                } label: {
                    Text("Your invite code").fontStyle(.body)
                }

                ShareLink(
                    item: url,
                    message: Text(InviteLink.shareMessage(code: code, hasInstantInvites: instantRemaining > 0))
                ) {
                    SettingsRowLabel(title: "Share Invite", systemImage: "square.and.arrow.up.fill")
                }
            } header: {
                Text("Invite Friends")
                    .fontStyle(.subheadline)
            } footer: {
                if instantRemaining > 0 {
                    Text("Your next \(instantRemaining) invite\(instantRemaining == 1 ? "" : "s") skip the waitlist entirely.")
                        .fontStyle(.footnote)
                } else {
                    Text("Friends who join with your code get bumped up the waitlist.")
                        .fontStyle(.footnote)
                }
            }
        }
    }

    // MARK: - Account section

    @ViewBuilder
    private var accountSection: some View {
        Section {
            if let profile = store.currentUser {
                NavigationLink {
                    ProfileView(profile: profile, presentation: .navigation)
                } label: {
                    SettingsProfilePreview(profile: profile)
                }
            }



            NavigationLink {
                AccountSecuritySettingsView()
            } label: {
                SettingsRowLabel(title: "Security", systemImage: "lock.shield.fill")
            }

            NavigationLink {
                AccountManagementSettingsView()
            } label: {
                SettingsRowLabel(title: "Account Management", systemImage: "person.crop.circle.fill.badge.checkmark")
            }

            NavigationLink {
                BlockedUsersSettingsView()
            } label: {
                SettingsRowLabel(title: "Blocked Users", systemImage: "hand.raised.fill")
            }
        } header: {
            Text("Account")
                .fontStyle(.subheadline)
        } footer: {
            if store.currentUser == nil {
                Text("Your profile will appear here once your board data loads.")
                    .fontStyle(.footnote)
            }
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
    .environment(AuthStore(service: MockAuthService()))
    .environment(BoardStore.sampleBoard(currentUserID: SampleProfileID.maya))
    .environment(OnboardingStore(
        service: MockOnboardingService(),
        auth: AuthStore(service: MockAuthService()),
        network: NetworkMonitor()
    ))
}
