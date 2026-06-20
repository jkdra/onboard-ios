//
//  ProfileView.swift
//  On Board
//

import SwiftUI

enum ProfilePresentation {
    case sheet
    case navigation
}

struct ProfileView: View {
    let profile: Profile
    var presentation: ProfilePresentation = .sheet

    @Environment(BoardStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Namespace private var profileNamespace

    @State private var editMode = false
    @State private var draftDisplayName = ""
    @State private var draftHandle = ""
    @State private var draftBio = ""

    private var canEdit: Bool { store.canEdit(profile: profile) }

    private let joinedFormatter: Date.FormatStyle = .dateTime
        .month(.wide)
        .day()
        .year()

    var body: some View {
        ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if editMode {
                        VStack(spacing: 10) {
                            EditingIndicator()
                                .fontStyle(.title)
                                .frame(maxWidth: .infinity)
                            Text("Tap any element to edit.")
                                .fontStyle(.body)
                                .multilineTextAlignment(.center)
                        }
                        .safeAreaPadding()
                        .background {
                            Color(uiColor: .systemBackground)
                        }
                        .ignoresSafeArea()
                    }

                    avatar

                    if !editMode {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(profile.displayName)
                                .fontStyle(.largeTitle)
                                .fontWeight(.heavy)
                                .matchedGeometryEffect(id: "displayName", in: profileNamespace, anchor: .leading)
                            Text("@\(profile.handle)")
                                .fontStyle(.subheadline)
                                .foregroundStyle(.secondary)
                                .matchedGeometryEffect(id: "username", in: profileNamespace, anchor: .leading)
                        }

                        if let bio = profile.bio, !bio.isEmpty {
                            Text(bio)
                                .fontStyle(.body)
                                .foregroundStyle(.primary)
                                .matchedGeometryEffect(id: "bio", in: profileNamespace, anchor: .leading)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            TextField("Display Name", text: $draftDisplayName, axis: .vertical)
                                .fontStyle(.largeTitle)
                                .fontWeight(.heavy)
                                .matchedGeometryEffect(id: "displayName", in: profileNamespace, anchor: .leading)
                            TextField("username", text: $draftHandle, axis: .vertical)
                                .fontStyle(.subheadline)
                                .foregroundStyle(.secondary)
                                .matchedGeometryEffect(id: "username", in: profileNamespace, anchor: .leading)
                        }
                        TextField("Bio", text: $draftBio, axis: .vertical)
                            .fontStyle(.body)
                            .foregroundStyle(.primary)
                            .matchedGeometryEffect(id: "bio", in: profileNamespace, anchor: .leading)
                    }

                    HStack(spacing: 6) {
                        Image(systemName: "calendar")
                        Text("joined \(profile.joinedAt.formatted(joinedFormatter).lowercased())")
                    }
                    .fontStyle(.footnote)
                    .foregroundStyle(.secondary)

                    if canEdit {
                        if editMode {
                            HStack(spacing: 12) {
                                Button { saveProfile() } label: {
                                    Label("Save", systemImage: "checkmark")
                                }
                                .buttonStyle(.boardPrimary)

                                Button { cancelEditing() } label: {
                                    Label("Cancel", systemImage: "xmark")
                                }
                                .buttonStyle(.boardSecondary)
                            }
                            .padding(.top, 4)
                        } else {
                            Button { beginEditing() } label: {
                                Label("Edit profile", systemImage: "pencil")
                            }
                            .buttonStyle(.boardSecondary)
                            .padding(.top, 4)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .safeAreaPadding()
            }
            .background {
                StripesOverlay()
                    .offset(x: editMode ? 0 : 100)
                    .opacity(editMode ? 1 : 0)
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if presentation == .sheet {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { dismiss() } label: { Label("Close", systemImage: "xmark") }
                    }
                }
            }
    }

    private var avatar: some View {
        ZStack {
            Circle()
                .fill(.thinMaterial)
                .frame(width: 92, height: 92)
                .overlay(
                    Circle().stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )
            Text(profile.avatarEmoji)
                .font(.system(size: 48))
        }
        .accessibilityLabel("\(profile.displayName) avatar")
    }

    private func beginEditing() {
        draftDisplayName = profile.displayName
        draftHandle = profile.handle
        draftBio = profile.bio ?? ""
        withAnimation(.smooth(duration: 0.3)) { editMode = true }
    }

    private func saveProfile() {
        Task {
            await store.updateProfile(
                displayName: draftDisplayName.trimmed,
                handle: draftHandle.trimmed,
                bio: draftBio.trimmed.isEmpty ? nil : draftBio.trimmed
            )
            withAnimation(.smooth(duration: 0.3)) { editMode = false }
        }
    }

    private func cancelEditing() {
        withAnimation(.smooth(duration: 0.3)) { editMode = false }
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

#Preview {
    NavigationStack {
        ProfileView(profile: .currentUser)
    }
    .environment(BoardStore.sampleBoard(currentUserID: SampleProfileID.maya))
}
