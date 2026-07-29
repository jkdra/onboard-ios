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
    @AppStorage(PendingReferralCode.key) private var referralCode = ""
    /// The current avatar URL — pre-populated from status on appear, replaced
    /// once `photo.uploadedURL` resolves. Same relationship as
    /// PostDetailView's `draftImageUrl`/`editPhoto`.
    @State private var avatarUrl: String?
    @State private var photo = PhotoAttachmentController(type: .profilePicture)
    @FocusState private var focus: Field?

    private enum Field { case displayName, bio }

    private let displayNameLimit = 50
    private let bioLimit = 300

    // Display name is optional — a user can identify by just their handle,
    // set on the next step.
    private var canContinue: Bool {
        !onboarding.isSubmitting
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
            OnboardingProgressBar(step: 3, totalSteps: 7)
                .safeAreaPadding(.horizontal)
            VStack(alignment: .leading, spacing: 14) {

                Text("This is how you'll appear on the board.")
                    .fontStyle(.subheadline)
                    .foregroundStyle(.secondary)

                VStack(alignment: .trailing, spacing: 8) {
                    TextField("Display name", text: $displayName, axis: .vertical)
                        .textFieldStyle(.boardTitle)
                        .fixedSize(horizontal: false, vertical: true)
                        .fontStyle(.largeTitle)
                        .lineLimit(1...2)
                        .keyboardType(.namePhonePad)
                        .textContentType(.name)
                        .textInputAutocapitalization(.words)
                        .focused($focus, equals: .displayName)
                    if displayName.count >= Int(Double(displayNameLimit) * 0.8) {
                        Text("\(displayName.count)/\(displayNameLimit)")
                            .fontStyle(.caption2)
                            .foregroundStyle(charCountColor(count: displayName.count, limit: displayNameLimit))
                            .monospacedDigit()
                            .animation(.easeInOut(duration: 0.15), value: displayName.count)
                    }
                }

                VStack(alignment: .trailing, spacing: 8) {
                    TextField("A short bio", text: $bio, axis: .vertical)
                        .textFieldStyle(.boardBody)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(2...5)
                        .keyboardType(.twitter)
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

                VStack(alignment: .leading, spacing: 8) {
                    TextField("Invite code (optional)", text: $referralCode)
                        .textFieldStyle(.boardBody)
                        .fontStyle(.body)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                }

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    Text("Photo")
                        .fontStyle(.subheadline)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 14) {
                        // Capture @MainActor state before the @Sendable PhotosPicker label closure.
                        // SwiftUI re-evaluates body on every state change, so captures stay fresh.
                        let photoData = photo.selectedPhotoData
                        let uploading = photo.isUploading
                        let hasPhoto = photoData != nil && avatarUrl != nil
                        let uiImage = photoData.flatMap { PhotoPreviewCache.image(for: $0) }
                        PhotoSourceButton(selection: $photo.selectedPhotoItem, onCapture: { photo.uncroppedImage = $0 }) {
                            ZStack(alignment: .bottomTrailing) {
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

                                    if let uiImage {
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
                                
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(Color(uiColor: .systemBackground))
                                    .frame(width: 22, height: 22)
                                    .background(Color.primary)
                                    .clipShape(Circle())
                                    .overlay(Circle().stroke(Color(uiColor: .systemBackground), lineWidth: 2))
                                    .offset(x: 4, y: 4)
                            }
                        }
                        .buttonStyle(.plain)

                        VStack(alignment: .leading, spacing: 4) {
                            if uploading {
                                Text("Uploading…")
                                    .fontStyle(.subheadline)
                                    .foregroundStyle(.secondary)
                            } else if photo.uploadFailed {
                                Label("Upload failed — try a different photo", systemImage: "exclamationmark.triangle.fill")
                                    .fontStyle(.footnote)
                                    .foregroundStyle(.orange)
                            } else {
                                Text(hasPhoto ? "Photo selected" : "Add a photo")
                                    .fontStyle(.subheadline)
                                    .foregroundStyle(hasPhoto ? .primary : .secondary)
                            }
                            if photo.selectedPhotoData != nil {
                                Button("Remove") {
                                    photo.removeImage()
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
                            avatarUrl: avatarUrl,
                            referralCode: referralCode.isEmpty ? nil : referralCode
                        )
                    }
                } label: {
                    LoadingButtonLabel("Continue", systemImage: "arrow.forward", isLoading: onboarding.isSubmitting, isActive: canContinue)
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
        }
        .task {
            // Deferred deep link: if this user tapped an invite link before the
            // app was installed, the web invite page stashed the code on the
            // clipboard — recover it so the field below is pre-filled. No-ops if
            // a code was already captured (installed-app universal link).
            await PendingReferralCode.hydrateFromPasteboardIfNeeded()
        }
        .presentableErrorAlert(error: $photo.alertError)
        .fullScreenCover(item: $photo.uncroppedImage) { image in
            ProfileImageCropView(image: image) { cropped in
                photo.uncroppedImage = nil
                guard let userID = onboarding.status?.id else { return }
                Task {
                    await photo.uploadCropped(
                        cropped,
                        userID: userID,
                        revertPreviewOnFailure: true,
                        alertOnFailure: false
                    )
                    if photo.uploadedURL != nil { avatarUrl = photo.uploadedURL }
                    if photo.uploadFailed { avatarUrl = nil }
                }
            } onCancel: {
                photo.uncroppedImage = nil
                photo.selectedPhotoItem = nil
            }
        }
        .onChange(of: photo.selectedPhotoItem) { _, newItem in
            photo.uploadFailed = false
            Task { await photo.loadPickedPhoto(newItem) }
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
