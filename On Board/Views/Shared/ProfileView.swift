//
//  ProfileView.swift
//  On Board
//

import SwiftUI
import PhotosUI
import Supabase

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

    private let displayNameLimit = 50
    private let bioLimit = 300

    @State private var editMode = false
    @State private var draftDisplayName = ""
    @State private var draftHandle = ""
    @State private var draftBio = ""
    @State private var draftAvatarUrl: String?
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var selectedPhotoData: Data?
    @State private var isUploadingPhoto = false

    private var displayedProfile: Profile {
        store.profile(id: profile.id) ?? profile
    }

    private var canEdit: Bool { store.canEdit(profile: displayedProfile) }

    private let joinedFormatter: Date.FormatStyle = .dateTime
        .month(.wide)
        .day()
        .year()

    var body: some View {
        ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(alignment: .center, spacing: 16) {
                        avatar

                        VStack(alignment: .leading, spacing: 3) {
                            if !editMode {
                                Text(displayedProfile.displayName)
                                    .fontStyle(.title)
                                    .fontWeight(.heavy)
                                    .matchedGeometryEffect(id: "displayName", in: profileNamespace, anchor: .leading)
                                Text("@\(displayedProfile.handle)")
                                    .fontStyle(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .matchedGeometryEffect(id: "username", in: profileNamespace, anchor: .leading)
                            } else {
                                TextField("Display Name", text: $draftDisplayName, axis: .vertical)
                                    .fontStyle(.title)
                                    .fontWeight(.heavy)
                                    .matchedGeometryEffect(id: "displayName", in: profileNamespace, anchor: .leading)
                                if draftDisplayName.count >= Int(Double(displayNameLimit) * 0.8) {
                                    Text("\(draftDisplayName.count)/\(displayNameLimit)")
                                        .fontStyle(.caption2)
                                        .foregroundStyle(draftDisplayName.count > displayNameLimit ? Color.red : Color.orange)
                                        .monospacedDigit()
                                }
                                TextField("username", text: $draftHandle, axis: .vertical)
                                    .fontStyle(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .matchedGeometryEffect(id: "username", in: profileNamespace, anchor: .leading)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if !editMode {
                        if let bio = displayedProfile.bio, !bio.isEmpty {
                            Text(bio)
                                .fontStyle(.body)
                                .foregroundStyle(.primary)
                                .matchedGeometryEffect(id: "bio", in: profileNamespace, anchor: .leading)
                        }
                    } else {
                        TextField("Bio", text: $draftBio, axis: .vertical)
                            .fontStyle(.body)
                            .foregroundStyle(.primary)
                            .matchedGeometryEffect(id: "bio", in: profileNamespace, anchor: .leading)
                        if draftBio.count >= Int(Double(bioLimit) * 0.8) {
                            Text("\(draftBio.count)/\(bioLimit)")
                                .fontStyle(.caption2)
                                .foregroundStyle(draftBio.count > bioLimit ? Color.red : Color.orange)
                                .monospacedDigit()
                        }
                    }

                    HStack(spacing: 6) {
                        Image(systemName: "calendar")
                        Text("joined \(displayedProfile.joinedAt.formatted(joinedFormatter).lowercased())")
                    }
                    .fontStyle(.footnote)
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .safeAreaPadding()
            }
            .scrollDismissesKeyboard(.interactively)
            .background {
                AnimatedStripesView(isActive: editMode)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if editMode {
                    Text("Tap any element to edit.")
                        .fontStyle(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
            }
            .navigationBackDisabled(editMode)
            .interactiveDismissDisabled(editMode)
            .keyboardDoneToolbar()
            .toolbar {
                if editMode {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { cancelEditing() } label: {
                            Label("Cancel", systemImage: "xmark").toolbarActionLabel()
                        }
                    }
                    ToolbarItem(placement: .principal) {
                        EditingIndicator()
                            .fontStyle(.title3)
                            .fixedSize()
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { saveProfile() } label: {
                            Label("Save", systemImage: "checkmark").toolbarActionLabel()
                        }
                        .disabled(draftDisplayName.count > displayNameLimit || draftBio.count > bioLimit)
                    }
                } else {
                    if presentation == .sheet {
                        ToolbarItem(placement: .topBarLeading) {
                            Button { dismiss() } label: { Label("Close", systemImage: "xmark") }
                        }
                    }
                    if canEdit {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button { beginEditing() } label: { Label("Edit", systemImage: "pencil") }
                        }
                    }
                }
            }
    }

    private var avatar: some View {
        ZStack(alignment: .bottomTrailing) {
            if editMode {
                if let data = selectedPhotoData, let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 92, height: 92)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.secondary.opacity(0.3), lineWidth: 1))
                } else {
                    AvatarView(profile: draftAvatarUrl.map { url in
                        Profile(id: displayedProfile.id, handle: displayedProfile.handle, displayName: displayedProfile.displayName, bio: displayedProfile.bio, avatarUrl: url)
                    } ?? displayedProfile, size: .large)
                }

                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    Image(systemName: "camera.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(Color.primary)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color(uiColor: .systemBackground), lineWidth: 2))
                }
                .offset(x: 4, y: 4)
            } else {
                AvatarView(profile: displayedProfile, size: .large)
            }
        }
        .accessibilityLabel("\(displayedProfile.displayName) avatar")
        .onChange(of: selectedPhotoItem) { _, newItem in
            Task { await loadAndUploadPhoto(newItem) }
        }
    }

    private func beginEditing() {
        draftDisplayName = displayedProfile.displayName
        draftHandle = displayedProfile.handle
        draftBio = displayedProfile.bio ?? ""
        draftAvatarUrl = displayedProfile.avatarUrl
        selectedPhotoData = nil
        selectedPhotoItem = nil
        withAnimation(.smooth(duration: 0.3)) { editMode = true }
    }

    private func saveProfile() {
        Task {
            await store.updateProfile(
                displayName: draftDisplayName.trimmed,
                handle: draftHandle.trimmed,
                bio: draftBio.trimmed.isEmpty ? nil : draftBio.trimmed,
                avatarUrl: draftAvatarUrl
            )
            withAnimation(.smooth(duration: 0.3)) { editMode = false }
        }
    }

    private func cancelEditing() {
        selectedPhotoData = nil
        selectedPhotoItem = nil
        draftAvatarUrl = nil
        withAnimation(.smooth(duration: 0.3)) { editMode = false }
    }

    private func loadAndUploadPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        guard let data = try? await item.loadTransferable(type: Data.self) else { return }
        // Decode + JPEG-encode off the main actor so picking an avatar doesn't hitch the UI.
        let jpeg: Data? = await Task.detached(priority: .userInitiated) {
            UIImage(data: data)?.jpegData(compressionQuality: 0.8)
        }.value
        guard let jpeg else { return }

        selectedPhotoData = jpeg
        isUploadingPhoto = true
        defer { isUploadingPhoto = false }

        guard let client = SupabaseClientFactory.client(for: .current),
              let userID = store.currentUserID else { return }

        let path = "\(userID.uuidString)/\(UUID().uuidString).jpg"
        do {
            try await client.storage
                .from("avatars")
                .upload(path, data: jpeg, options: FileOptions(contentType: "image/jpeg", upsert: true))
            let publicURL = try client.storage.from("avatars").getPublicURL(path: path)
            draftAvatarUrl = publicURL.absoluteString
        } catch {
            // Upload failed — the photo preview stays but won't persist; saveProfile will use nil URL
            draftAvatarUrl = nil
        }
    }
}


#Preview {
    NavigationStack {
        ProfileView(profile: .currentUser)
    }
    .environment(BoardStore.sampleBoard(currentUserID: SampleProfileID.maya))
}
