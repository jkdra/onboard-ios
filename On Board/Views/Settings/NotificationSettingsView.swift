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
                        .buttonStyle(.bordered)
                        .tint(.primary)
                    }
                    .padding(.vertical, 4)
                }
            }
            
            Section {
                if isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                } else {
                    Toggle("Reactions", isOn: $settings.pushReactions)
                        .fontStyle(.body)
                    Toggle("Comments", isOn: $settings.pushComments)
                        .fontStyle(.body)
                    Toggle("New Posts Digest", isOn: $settings.pushNewPosts)
                        .fontStyle(.body)
                    Toggle("New Posts from Followed Profiles", isOn: $settings.pushFollowedPosts)
                        .fontStyle(.body)
                }
            } header: {
                Text("Push Notifications")
                    .fontStyle(.subheadline)
            } footer: {
                Text("Choose which notifications you want to receive.")
                    .fontStyle(.footnote)
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
