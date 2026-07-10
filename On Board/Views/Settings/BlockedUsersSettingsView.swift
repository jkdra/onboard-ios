//
//  BlockedUsersSettingsView.swift
//  On Board
//

import SwiftUI

struct BlockedUsersSettingsView: View {
    @Environment(BoardStore.self) private var store
    
    @State private var profiles: [Profile] = []
    @State private var isLoading = true
    @State private var alertError: PresentableAlertError?
    
    var body: some View {
        List {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowBackground(Color.clear)
            } else if profiles.isEmpty {
                Text("You haven't blocked anyone.")
                    .fontStyle(.body)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 40)
                    .listRowBackground(Color.clear)
            } else {
                ForEach(profiles) { profile in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(profile.displayNameOrHandle)
                                .fontStyle(.headline)
                            if !profile.displayName.isEmpty {
                                Text("@\(profile.handle)")
                                    .fontStyle(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        
                        Spacer()
                        
                        Button("Unblock") {
                            Task { await unblock(profile) }
                        }
                        .buttonStyle(.boardSecondary)
                        .tint(.primary)
                    }
                }
            }
        }
        .navigationTitle("Blocked Users")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadProfiles()
        }
        .refreshable {
            await loadProfiles()
        }
        .presentableErrorAlert(error: $alertError)
    }
    
    private func loadProfiles() async {
        isLoading = profiles.isEmpty
        defer { isLoading = false }
        do {
            profiles = try await store.blockedProfiles()
        } catch {
            alertError = store.presentableModerationError(error)
        }
    }
    
    private func unblock(_ profile: Profile) async {
        do {
            try await store.unblock(userID: profile.id)
            profiles.removeAll(where: { $0.id == profile.id })
        } catch {
            alertError = store.presentableModerationError(error)
        }
    }
}
