//
//  ProfileEditContent.swift
//  On Board
//
//  Edit-mode half of the profile screen. ProfileView owns the mode switch,
//  the namespace, and the draft; this view renders the glass fields into the
//  same matched-geometry slots ProfileReadContent uses, so editing happens
//  visually in place.
//

import PhotosUI
import SwiftUI

struct ProfileEditContent: View {
    let profile: Profile
    let namespace: Namespace.ID
    @Bindable var draft: ProfileDraft
    var onCameraCapture: (UIImage) -> Void

    private var minBirthdayAgeDate: Date {
        Calendar.current.date(byAdding: .year, value: -16, to: Date()) ?? Date()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .center, spacing: 16) {
                avatarPicker
                identityFields
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            bioField

            ProfileMetaRow(profile: profile, showsBirthday: true)

            birthdaySection
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Identity

    @ViewBuilder
    private var identityFields: some View {
        // Panels occupy real space now, so this is the true visible gap.
        VStack(alignment: .leading, spacing: 8) {
            TextField("Display Name", text: $draft.displayName)
                .textFieldStyle(.boardTitle)
                .lineLimit(1)
                .fontStyle(.title)
                .fontWeight(.heavy)
                .keyboardType(.namePhonePad)
                .textContentType(.name)
                .textInputAutocapitalization(.words)
                .matchedFieldText(id: ProfileGeometryID.displayName, in: namespace, variant: .title)
            FieldLimitCaption(count: draft.displayName.count, limit: ProfileDraft.displayNameLimit)
            TextField("username", text: $draft.handle)
                .textFieldStyle(.boardUsername)
                .lineLimit(1)
                // Edits a size up from its subheadline display — a precision
                // target at caption scale is miserable.
                .fontStyle(.body)
                .foregroundStyle(.secondary)
                .keyboardType(.asciiCapable)
                .textContentType(.username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .matchedFieldText(id: ProfileGeometryID.username, in: namespace, variant: .username)
                .onChange(of: draft.handle) { _, _ in
                    draft.scheduleHandleAvailabilityCheck()
                }
            handleAvailabilityLabel
        }
    }

    @ViewBuilder
    private var handleAvailabilityLabel: some View {
        switch draft.handleAvailability {
        case .idle, .available:
            EmptyView()
        case .checking:
            Label("Checking availability…", systemImage: "ellipsis")
                .fontStyle(.caption2)
                .foregroundStyle(.secondary)
        case .unavailable:
            Label("Already taken", systemImage: "xmark.circle.fill")
                .fontStyle(.caption2)
                .foregroundStyle(.red)
        case .invalid:
            Label("2–32 characters: letters, numbers, . or _", systemImage: "exclamationmark.circle.fill")
                .fontStyle(.caption2)
                .foregroundStyle(.orange)
        case .offline:
            Label("Offline — connect to check availability", systemImage: "wifi.slash")
                .fontStyle(.caption2)
                .foregroundStyle(.orange)
        }
    }

    // MARK: - Bio

    @ViewBuilder
    private var bioField: some View {
        TextField("Bio", text: $draft.bio, axis: .vertical)
            .textFieldStyle(.boardBody)
            // Multi-line fields re-measure a beat after appearing; without
            // this they settle unanimated mid-morph (visible downward-then-up
            // jump). Same fix as read mode's Text (see PostDetailView+Views).
            .fixedSize(horizontal: false, vertical: true)
            .fontStyle(.body)
            .foregroundStyle(.primary)
            .keyboardType(.twitter)
            .matchedFieldText(id: ProfileGeometryID.bio, in: namespace, variant: .body)
        FieldLimitCaption(count: draft.bio.count, limit: ProfileDraft.bioLimit)
    }

    // MARK: - Birthday

    private var birthdaySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            DatePicker(
                "Birthday",
                selection: Binding(
                    get: { draft.birthday ?? minBirthdayAgeDate },
                    set: { draft.birthday = $0 }
                ),
                in: ...minBirthdayAgeDate,
                displayedComponents: .date
            )
            .datePickerStyle(.compact)
            .fontStyle(.body)
            Toggle("Show month and day on my profile", isOn: $draft.showBirthday)
                .fontStyle(.body)
                .tint(.primary)
        }
    }

    // MARK: - Avatar

    private var avatarPicker: some View {
        // Captured before the PhotosPicker label closure: that closure isn't
        // main-actor-isolated, so touching the @MainActor draft inside it
        // trips isolation warnings. (Same dance the pre-split code did.)
        let photoData = draft.selectedPhotoData
        let uploading = draft.isUploadingPhoto
        let draftUrl = draft.avatarUrl
        let currentProfile = profile
        let uiImage = photoData.flatMap { PhotoPreviewCache.image(for: $0) }

        return PhotoSourceButton(selection: $draft.selectedPhotoItem, onCapture: onCameraCapture) {
            ZStack(alignment: .bottomTrailing) {
                ZStack {
                    if let uiImage {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 92, height: 92)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.secondary.opacity(0.3), lineWidth: 1))
                            .opacity(uploading ? 0.5 : 1.0)
                    } else {
                        AvatarView(profile: draftUrl.map { url in
                            Profile(
                                id: currentProfile.id,
                                handle: currentProfile.handle,
                                displayName: currentProfile.displayName,
                                bio: currentProfile.bio,
                                avatarUrl: url
                            )
                        } ?? currentProfile, size: .large)
                        .opacity(uploading ? 0.5 : 1.0)
                    }

                    if uploading {
                        ProgressView()
                            .controlSize(.regular)
                            .tint(.primary)
                    }
                }

                Image(systemName: "camera.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color(uiColor: .systemBackground))
                    .frame(width: 28, height: 28)
                    .background(Color.primary)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color(uiColor: .systemBackground), lineWidth: 2))
                    .offset(x: 4, y: 4)
            }
        }
        .buttonStyle(.plain)
        .disabled(draft.isUploadingPhoto)
        .accessibilityLabel("Change avatar")
    }
}
