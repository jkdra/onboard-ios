//
//  OnboardingProfileStepView.swift
//  On Board
//

import SwiftUI
import PhotosUI
import Supabase

struct OnboardingProfileStepView: View {
    @Environment(OnboardingStore.self) private var onboarding

    @State private var displayName = ""
    @State private var bio = ""
    @State private var avatarUrl: String?
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var selectedPhotoData: Data?
    @State private var isUploadingPhoto = false
    @FocusState private var focus: Field?

    private enum Field { case displayName, bio }

    private var canContinue: Bool {
        !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !onboarding.isSubmitting
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("This is how you'll appear on the board.")
                    .fontStyle(.subheadline)
                    .foregroundStyle(.secondary)

                TextField("Display name", text: $displayName, axis: .vertical)
                    .fontStyle(.largeTitle)
                    .lineLimit(1...2)
                    .focused($focus, equals: .displayName)

                TextField("A short bio", text: $bio, axis: .vertical)
                    .lineLimit(2...5)
                    .focused($focus, equals: .bio)
                    .fontStyle(.body)

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    Text("Photo")
                        .fontStyle(.subheadline)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 14) {
                        PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                            ZStack {
                                Circle()
                                    .fill(.thinMaterial)
                                    .frame(width: 64, height: 64)
                                    .overlay(
                                        Circle().stroke(
                                            selectedPhotoData != nil ? Color.accentColor : Color.secondary.opacity(0.25),
                                            lineWidth: selectedPhotoData != nil ? 2 : 1
                                        )
                                    )

                                if let data = selectedPhotoData, let uiImage = UIImage(data: data) {
                                    Image(uiImage: uiImage)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 64, height: 64)
                                        .clipShape(Circle())
                                } else if isUploadingPhoto {
                                    ProgressView()
                                } else {
                                    Image(systemName: "person.circle.fill")
                                        .font(.system(.largeTitle))
                                        .foregroundStyle(Color.secondary.opacity(0.5))
                                }
                            }
                        }
                        .buttonStyle(.plain)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(selectedPhotoData != nil ? "Photo selected" : "Add a photo")
                                .fontStyle(.subheadline)
                                .foregroundStyle(selectedPhotoData != nil ? .primary : .secondary)
                            if selectedPhotoData != nil {
                                Button("Remove") {
                                    selectedPhotoData = nil
                                    selectedPhotoItem = nil
                                    avatarUrl = nil
                                }
                                .fontStyle(.footnote)
                                .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Button {
                    Task {
                        await onboarding.submitProfile(
                            displayName: displayName,
                            bio: bio,
                            avatarUrl: avatarUrl
                        )
                    }
                } label: {
                    if onboarding.isSubmitting {
                        ProgressView().tint(.white)
                    } else {
                        Label("Continue", systemImage: "arrow.right")
                    }
                }
                .buttonStyle(.boardPrimary)
                .disabled(!canContinue)
            }
            .safeAreaPadding(.horizontal)
        }
        .navigationTitle("Set up your profile")
        .onAppear {
            if displayName.isEmpty {
                displayName = onboarding.status?.displayName ?? ""
            }
            if bio.isEmpty {
                bio = onboarding.status?.bio ?? ""
            }
            avatarUrl = onboarding.status?.avatarUrl
            focus = .displayName
        }
        .onChange(of: selectedPhotoItem) { _, newItem in
            Task { await loadAndUploadPhoto(newItem) }
        }
    }

    @MainActor
    private func loadAndUploadPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        guard let data = try? await item.loadTransferable(type: Data.self) else { return }
        guard let uiImage = UIImage(data: data),
              let jpeg = uiImage.jpegData(compressionQuality: 0.8) else { return }

        selectedPhotoData = jpeg
        isUploadingPhoto = true
        defer { isUploadingPhoto = false }

        guard let client = SupabaseClientFactory.client(for: .current),
              let userID = onboarding.status?.id else { return }

        let path = "\(userID.uuidString)/\(UUID().uuidString).jpg"
        do {
            try await client.storage
                .from("avatars")
                .upload(path, data: jpeg, options: FileOptions(contentType: "image/jpeg", upsert: true))
            let publicURL = try client.storage.from("avatars").getPublicURL(path: path)
            avatarUrl = publicURL.absoluteString
        } catch {
            avatarUrl = nil
        }
    }
}

#Preview {
    NavigationStack {
        OnboardingProfileStepView()
    }
    .environment(OnboardingStore(
        service: MockOnboardingService(),
        auth: AuthStore(service: MockAuthService()),
        network: NetworkMonitor()
    ))
}
