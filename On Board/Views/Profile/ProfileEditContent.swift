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
    @Environment(\.handleChangeRule) private var handleChangeRule
    @Environment(\.profileFieldLimits) private var profileFieldLimits
    let profile: Profile
    let namespace: Namespace.ID
    @Bindable var draft: ProfileDraft
    var onCameraCapture: (UIImage) -> Void

    @State private var showHandleLockedAlert = false

    // Constructing a RelativeDateTimeFormatter isn't free — cached once
    // instead of rebuilt on every render of `handleUnlockText`.
    private static let relativeDateTimeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f
    }()

    /// Friendly "in 6 days" for when the username may next be changed.
    private var handleUnlockText: String {
        guard let at = profile.handleChangeAvailableAt(windowDays: handleChangeRule.windowDays,
                                                       maxPerWindow: handleChangeRule.maxPerWindow) else { return "soon" }
        return Self.relativeDateTimeFormatter.localizedString(for: at, relativeTo: .now)
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
        .alert("Username locked", isPresented: $showHandleLockedAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            // Interpolated from the same rule the gate reads — hardcoding
            // "twice every 14 days" here meant retuning the config made the
            // explanation lie about the limit it was explaining.
            Text("You can change your username \(handleChangeRule.maxPerWindow == 1 ? "once" : handleChangeRule.maxPerWindow == 2 ? "twice" : "\(handleChangeRule.maxPerWindow) times") every \(handleChangeRule.windowDays) days. You'll be able to change it again \(handleUnlockText).")
        }
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
            FieldLimitCaption(count: draft.displayName.count, limit: profileFieldLimits.displayName)

            if profile.canChangeHandle(windowDays: handleChangeRule.windowDays,
                                       maxPerWindow: handleChangeRule.maxPerWindow) {
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
            } else {
                lockedHandleField
            }
        }
    }

    /// Username can only change twice per 14 days. When the limit's hit, the
    /// field grays out and becomes a button that explains why.
    private var lockedHandleField: some View {
        Button {
            showHandleLockedAlert = true
        } label: {
            HStack(spacing: 6) {
                Text("@\(profile.handle)")
                    .fontStyle(.body)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Image(systemName: "lock.fill")
                    .fontStyle(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer(minLength: 0)
            }
            .contentShape(.rect)
            .opacity(0.7)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Username locked. Tap to learn why.")
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
        FieldLimitCaption(count: draft.bio.count, limit: profileFieldLimits.bio)
    }

    // MARK: - Birthday

    /// Birthday is set once during onboarding and locked after — it's the age
    /// gate, so it's read-only here. Only the visibility toggle is editable.
    private var birthdaySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let birthday = draft.birthday {
                HStack(spacing: 6) {
                    Text("Birthday").fontStyle(.body)
                    Spacer()
                    Text(birthday, format: .dateTime.month(.wide).day().year())
                        .fontStyle(.body)
                        .foregroundStyle(.secondary)
                    Image(systemName: "lock.fill")
                        .fontStyle(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
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
        let photoData = draft.photo.selectedPhotoData
        let uploading = draft.photo.isUploading
        let draftUrl = draft.avatarUrl
        let currentProfile = profile
        let uiImage = photoData.flatMap { PhotoPreviewCache.image(for: $0) }

        return PhotoSourceButton(selection: $draft.photo.selectedPhotoItem, onCapture: onCameraCapture) {
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
        .disabled(draft.photo.isUploading)
        .accessibilityLabel("Change avatar")
    }
}
