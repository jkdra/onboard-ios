//
//  NotificationSettingsView.swift
//  On Board
//

import SwiftUI
import UserNotifications

struct NotificationSettingsView: View {
    @Environment(BoardStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase

    @State private var loadError: String?
    @State private var authorizationStatus: UNAuthorizationStatus = .notDetermined

    var body: some View {
        Form {
            if authorizationStatus == .denied {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Notifications Disabled", systemImage: "bell.slash.fill")
                            .fontStyle(.headline)
                            .foregroundStyle(.red)

                        Text("You won't receive any push notifications because they are disabled in iOS Settings. Tap below to enable them.")
                            .fontStyle(.subheadline)
                            .foregroundStyle(.secondary)

                        Button("Open Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                        .buttonStyle(.boardSecondary)
                        .tint(.primary)
                    }
                    .padding(.vertical, 4)
                }
            }

            if let loadError {
                Section {
                    Label(loadError, systemImage: "exclamationmark.triangle.fill")
                        .fontStyle(.footnote)
                        .foregroundStyle(.red)
                }
            }

            if let settings = store.notificationSettings {
                Section {
                    settingsToggle("Reactions", isOn: Binding(
                        get: { settings.pushReactions },
                        set: { store.setNotificationSettings(settings.updating(pushReactions: $0)) }
                    ))
                    settingsToggle("Comments", isOn: Binding(
                        get: { settings.pushComments },
                        set: { store.setNotificationSettings(settings.updating(pushComments: $0)) }
                    ))
                } header: {
                    Text("Your Posts")
                        .fontStyle(.subheadline)
                } footer: {
                    Text("When someone reacts to or comments on something you posted.")
                        .fontStyle(.footnote)
                }

                Section {
                    settingsToggle("New Posts Digest", isOn: Binding(
                        get: { settings.pushNewPosts },
                        set: { store.setNotificationSettings(settings.updating(pushNewPosts: $0)) }
                    ))
                } header: {
                    Text("Board Activity")
                        .fontStyle(.subheadline)
                } footer: {
                    Text("A periodic summary of new posts on your board.")
                        .fontStyle(.footnote)
                }

                Section {
                    settingsToggle("New Posts", isOn: Binding(
                        get: { settings.pushFollowedPosts },
                        set: { store.setNotificationSettings(settings.updating(pushFollowedPosts: $0)) }
                    ))
                } header: {
                    Text("People You Follow")
                        .fontStyle(.subheadline)
                } footer: {
                    Text("A push as soon as someone you follow posts.")
                        .fontStyle(.footnote)
                }
            } else {
                Section {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                }
                .listRowBackground(Color.clear)
            }
        }
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await checkStatus()
            do {
                try await store.loadNotificationSettingsIfNeeded()
            } catch {
                loadError = error.localizedDescription
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task { await checkStatus() }
            }
        }
        .presentableErrorAlert(error: saveErrorBinding)
    }

    // Manual Binding against the environment object, matching the idiom used
    // throughout ProfileView/PostDetailView (e.g. PostDetailView's
    // `selectedReaction`) rather than `@Bindable`, which isn't used anywhere
    // else in this codebase.
    private var saveErrorBinding: Binding<PresentableAlertError?> {
        Binding(
            get: { store.notificationSettingsSaveError },
            set: { store.notificationSettingsSaveError = $0 }
        )
    }

    /// Matches the toggle idiom in `SettingsView`: the label carries `.fontStyle(.body)`
    /// (not the Toggle itself) and the switch is tinted `.primary`. Without the tint
    /// these rendered in the default accent green, which is why they looked subtly
    /// different from the toggles on the main Settings screen.
    private func settingsToggle(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(title).fontStyle(.body)
        }
        .tint(.primary)
    }

    private func checkStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }
}

#Preview {
    NavigationStack {
        NotificationSettingsView()
    }
    .environment(BoardStore.sampleBoard())
}
