//
//  BlockedUsersSettingsView.swift
//  On Board
//
//  Manage blocked users: list everyone the current user has blocked and
//  allow unblocking. Blocked users' posts and comments are hidden in both
//  directions; unblocking restores visibility on the next refresh.
//

import SwiftUI

struct BlockedUsersSettingsView: View {
    @Environment(BoardStore.self) private var store

    @State private var blockedProfiles: [Profile] = []
    @State private var isLoading = true
    @State private var unblockingIDs: Set<UUID> = []
    @State private var alertError: PresentableAlertError?

    var body: some View {
        Form {
            if isLoading && blockedProfiles.isEmpty {
                Section {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Loading blocked users…")
                            .fontStyle(.body)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowBackground(Color.clear)
                }
            } else if blockedProfiles.isEmpty {
                Section {
                    VStack(spacing: 8) {
                        Image(systemName: "person.crop.circle.badge.checkmark")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("No blocked users")
                            .fontStyle(.headline)
                        Text("When you block someone, they'll show up here.")
                            .fontStyle(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                    .listRowBackground(Color.clear)
                }
            } else {
                Section {
                    ForEach(blockedProfiles) { profile in
                        HStack(spacing: 12) {
                            AvatarView(profile: profile, size: .small)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(profile.displayName)
                                    .fontStyle(.subheadline)
                                    .fontWeight(.semibold)
                                Text("@\(profile.handle)")
                                    .fontStyle(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 8)
                            Button {
                                Task { await unblock(profile) }
                            } label: {
                                if unblockingIDs.contains(profile.id) {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Text("Unblock")
                                        .fontStyle(.footnote)
                                        .fontWeight(.semibold)
                                }
                            }
                            .buttonStyle(.bordered)
                            .tint(.primary)
                            .disabled(unblockingIDs.contains(profile.id))
                        }
                    }
                } footer: {
                    Text("You won't see each other's posts or comments while someone is blocked. Unblocking restores them on the next refresh.")
                        .fontStyle(.footnote)
                }
            }
        }
        .navigationTitle("Blocked Users")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadBlockedProfiles() }
        .refreshable { await loadBlockedProfiles() }
        .presentableErrorAlert(error: $alertError)
    }

    private func loadBlockedProfiles() async {
        if let userID = store.currentUserID {
            await store.refreshBlockedUsers(for: userID)
        }
        do {
            blockedProfiles = try await store.blockedProfiles()
        } catch {
            alertError = store.presentableModerationError(error)
        }
        isLoading = false
    }

    private func unblock(_ profile: Profile) async {
        unblockingIDs.insert(profile.id)
        defer { unblockingIDs.remove(profile.id) }
        do {
            try await store.unblock(userID: profile.id)
            withAnimation(.smooth(duration: 0.25)) {
                blockedProfiles.removeAll { $0.id == profile.id }
            }
        } catch {
            alertError = store.presentableModerationError(error)
        }
    }
}

#Preview {
    NavigationStack {
        BlockedUsersSettingsView()
    }
    .environment(BoardStore.sampleBoard(currentUserID: SampleProfileID.maya))
}
