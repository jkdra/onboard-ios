//
//  NotificationSettingsView.swift
//  On Board
//

import SwiftUI
import UserNotifications

struct NotificationSettingsView: View {
    @Environment(BoardStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase

    @State private var settings = NotificationSettings()
    @State private var isLoading = true
    @State private var isSaving = false
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

            if isLoading {
                Section {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                }
                .listRowBackground(Color.clear)
            } else {
                Section {
                    settingsToggle("Reactions", isOn: $settings.pushReactions)
                    settingsToggle("Comments", isOn: $settings.pushComments)
                } header: {
                    Text("Your Posts")
                        .fontStyle(.subheadline)
                } footer: {
                    Text("When someone reacts to or comments on something you posted.")
                        .fontStyle(.footnote)
                }

                Section {
                    settingsToggle("New Posts Digest", isOn: $settings.pushNewPosts)
                } header: {
                    Text("Board Activity")
                        .fontStyle(.subheadline)
                } footer: {
                    Text("A periodic summary of new posts on your board.")
                        .fontStyle(.footnote)
                }

                Section {
                    settingsToggle("New Posts", isOn: $settings.pushFollowedPosts)
                } header: {
                    Text("People You Follow")
                        .fontStyle(.subheadline)
                } footer: {
                    Text("A push as soon as someone you follow posts.")
                        .fontStyle(.footnote)
                }
            }
        }
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if isSaving {
                ProgressView()
                    .padding()
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .onChange(of: settings) { _, newValue in
            guard !isLoading else { return }
            Task { await save(newValue) }
        }
        .task {
            await checkStatus()
            await load()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task { await checkStatus() }
            }
        }
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

    private func load() async {
        isLoading = true
        loadError = nil
        do {
            settings = try await store.fetchNotificationSettings()
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }

    private func save(_ newSettings: NotificationSettings) async {
        isSaving = true
        do {
            try await store.updateNotificationSettings(newSettings)
        } catch {
            // Revert on failure
            if let old = try? await store.fetchNotificationSettings() {
                settings = old
            }
        }
        isSaving = false
    }
}

#Preview {
    NavigationStack {
        NotificationSettingsView()
    }
    .environment(BoardStore.sampleBoard())
}
