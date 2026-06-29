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
    @State private var photoUploadFailed = false
    @FocusState private var focus: Field?

    private enum Field { case displayName, bio }

    private let displayNameLimit = 50
    private let bioLimit = 300

    private var canContinue: Bool {
        !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !onboarding.isSubmitting
            && displayName.count <= displayNameLimit
            && bio.count <= bioLimit
    }

    private func charCountColor(count: Int, limit: Int) -> Color {
        let ratio = Double(count) / Double(limit)
        if ratio >= 1.0 { return .red }
        if ratio >= 0.8 { return .orange }
        return .secondary
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("This is how you'll appear on the board.")
                    .fontStyle(.subheadline)
                    .foregroundStyle(.secondary)

                VStack(alignment: .trailing, spacing: 2) {
                    TextField("Display name", text: $displayName, axis: .vertical)
                        .fontStyle(.largeTitle)
                        .lineLimit(1...2)
                        .focused($focus, equals: .displayName)
                    if displayName.count >= Int(Double(displayNameLimit) * 0.8) {
                        Text("\(displayName.count)/\(displayNameLimit)")
                            .fontStyle(.caption2)
                            .foregroundStyle(charCountColor(count: displayName.count, limit: displayNameLimit))
                            .monospacedDigit()
                            .animation(.easeInOut(duration: 0.15), value: displayName.count)
                    }
                }

                VStack(alignment: .trailing, spacing: 2) {
                    TextField("A short bio", text: $bio, axis: .vertical)
                        .lineLimit(2...5)
                        .focused($focus, equals: .bio)
                        .fontStyle(.body)
                    if bio.count >= Int(Double(bioLimit) * 0.8) {
                        Text("\(bio.count)/\(bioLimit)")
                            .fontStyle(.caption2)
                            .foregroundStyle(charCountColor(count: bio.count, limit: bioLimit))
                            .monospacedDigit()
                            .animation(.easeInOut(duration: 0.15), value: bio.count)
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    Text("Photo")
                        .fontStyle(.subheadline)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 14) {
                        // Capture @MainActor state before the @Sendable PhotosPicker label closure.
                        // SwiftUI re-evaluates body on every state change, so captures stay fresh.
                        let photoData = selectedPhotoData
                        let uploading = isUploadingPhoto
                        let hasPhoto = photoData != nil && avatarUrl != nil
                        PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                            ZStack {
                                Circle()
                                    .fill(Color(.secondarySystemFill))
                                    .frame(width: 64, height: 64)
                                    .overlay(
                                        Circle().stroke(
                                            hasPhoto ? Color.primary.opacity(0.5) : Color.secondary.opacity(0.3),
                                            lineWidth: 1
                                        )
                                    )

                                if let data = photoData, let uiImage = UIImage(data: data) {
                                    Image(uiImage: uiImage)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 64, height: 64)
                                        .clipShape(Circle())
                                        .opacity(uploading ? 0.5 : 1)
                                }

                                if uploading {
                                    ProgressView()
                                } else if photoData == nil {
                                    Image(systemName: "person.circle.fill")
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 30, height: 30)
                                        .foregroundStyle(Color.secondary.opacity(0.5))
                                }
                            }
                        }
                        .buttonStyle(.plain)

                        VStack(alignment: .leading, spacing: 4) {
                            if uploading {
                                Text("Uploading…")
                                    .fontStyle(.subheadline)
                                    .foregroundStyle(.secondary)
                            } else if photoUploadFailed {
                                Label("Upload failed — try a different photo", systemImage: "exclamationmark.triangle.fill")
                                    .fontStyle(.footnote)
                                    .foregroundStyle(.orange)
                            } else {
                                Text(hasPhoto ? "Photo selected" : "Add a photo")
                                    .fontStyle(.subheadline)
                                    .foregroundStyle(hasPhoto ? .primary : .secondary)
                            }
                            if selectedPhotoData != nil {
                                Button("Remove") {
                                    selectedPhotoData = nil
                                    selectedPhotoItem = nil
                                    avatarUrl = nil
                                    photoUploadFailed = false
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
                    LoadingButtonLabel("Continue", systemImage: "arrow.right", isLoading: onboarding.isSubmitting)
                }
                .buttonStyle(.boardPrimary)
                .disabled(!canContinue)
            }
            .safeAreaPadding(.horizontal)
        }
        .scrollDismissesKeyboard(.interactively)
        .disabled(onboarding.isSubmitting)
        .keyboardDoneToolbar()
        .navigationTitle("Set up your profile")
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            if displayName.isEmpty {
                displayName = onboarding.status?.displayName ?? ""
            }
            if bio.isEmpty {
                bio = onboarding.status?.bio ?? ""
            }
            avatarUrl = onboarding.status?.avatarUrl
            if displayName.isEmpty {
                focus = .displayName
            }
        }
        .onChange(of: selectedPhotoItem) { _, newItem in
            photoUploadFailed = false
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
            photoUploadFailed = false
        } catch {
            avatarUrl = nil
            photoUploadFailed = true
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
