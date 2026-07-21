//
//  ProfileView.swift
//  On Board
//
//  Shell for the profile screen: owns the read/edit mode switch, the shared
//  matched-geometry namespace, the draft model, and all side effects (save,
//  photo upload, moderation, presentation). The actual content lives in
//  ProfileReadContent / ProfileEditContent, which render into the same
//  namespace so editing happens visually in place.
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
    @State private var showAvatarViewer = false
    @State private var avatarViewerScale: CGFloat = 1.0

    @State private var editMode = false
    @State private var draft = ProfileDraft()
    @State private var uncroppedImage: UIImage?
    @State private var alertError: PresentableAlertError?

    // Moderation (other users' profiles only)
    @State private var reportTarget: ReportTarget?
    @State private var blockCandidate: BlockCandidate?
    @State private var isUpdatingBlock = false

    private var displayedProfile: Profile {
        store.profile(id: profile.id) ?? profile
    }

    private var isBlockedByMe: Bool { store.isBlocked(userID: displayedProfile.id) }

    var body: some View {
        // Presentation modifiers split off from the layout chain (`profileScroll`)
        // so neither expression alone exceeds the Swift type-checker's budget.
        profileScroll
            .sheet(item: $reportTarget) { target in
                ReportContentSheet(target: target)
            }
            .alert("Block \(blockCandidate?.handle ?? "")?", isPresented: Binding(
                get: { blockCandidate != nil },
                set: { if !$0 { blockCandidate = nil } }
            ), presenting: blockCandidate) { candidate in
                Button("Block \(candidate.handle)", role: .destructive) {
                    Task { await blockUser(candidate) }
                }
            } message: { _ in
                Text("You won't see each other's posts or comments. You can unblock them anytime in Settings.")
            }
            .fullScreenCover(item: Binding<UIImage?>(
                get: { uncroppedImage },
                set: { uncroppedImage = $0 }
            )) { image in
                ProfileImageCropView(image: image) { cropped in
                    uncroppedImage = nil
                    Task { await uploadCroppedPhoto(cropped) }
                } onCancel: {
                    uncroppedImage = nil
                    draft.selectedPhotoItem = nil
                }
            }
            .interactiveDismissDisabled(showAvatarViewer)
            .navigationBarBackButtonHidden(showAvatarViewer)
            .overlay {
                ImageViewerView(
                    url: URL(string: displayedProfile.avatarUrl ?? ""),
                    namespace: profileNamespace,
                    sourceID: ProfileGeometryID.avatarImage,
                    isPresented: $showAvatarViewer,
                    aspectRatio: 1.0,
                    currentScale: $avatarViewerScale
                )
                .ignoresSafeArea()
                .zIndex(100)
            }
            .task(id: profile.id) {
                // Ask directly whether a follows row exists for this one profile,
                // rather than depending on followedUserIDs from the board-wide
                // refresh cycle (which may not have run yet — e.g. right after a
                // cold launch — or may just be stale). A single targeted query is
                // the actual source of truth here.
                guard !store.canEdit(profile: displayedProfile), let boardService = store.boardService else { return }
                do {
                    if try await boardService.isFollowing(userID: profile.id) {
                        store.followedUserIDs.insert(profile.id)
                    } else {
                        store.followedUserIDs.remove(profile.id)
                    }
                } catch {
                    // Leave whatever's cached — a failed check shouldn't flip a
                    // correct "Following" state to "Follow".
                }
            }
            .task(id: profile.id) {
                await store.refreshPopScore(for: profile.id)
            }
            .presentableErrorAlert(error: $alertError)
    }

    private var profileScroll: some View {
        ScrollView {
            Group {
                if editMode {
                    ProfileEditContent(
                        profile: displayedProfile,
                        namespace: profileNamespace,
                        draft: draft,
                        onCameraCapture: { uncroppedImage = $0 }
                    )
                } else {
                    ProfileReadContent(
                        profile: displayedProfile,
                        namespace: profileNamespace,
                        isAvatarViewerOpen: showAvatarViewer,
                        isUpdatingBlock: isUpdatingBlock,
                        onEditProfile: beginEditing,
                        onAvatarTap: {
                            if displayedProfile.avatarUrl != nil {
                                withAnimation(.spring(response: 0.35, dampingFraction: 1.0)) {
                                    showAvatarViewer = true
                                }
                            }
                        },
                        onUnblock: { Task { await unblockUser() } }
                    )
                }
            }
            .safeAreaPadding()

            if !editMode, !isBlockedByMe {
                userPostsSection
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .background {
            AnimatedStripesView(isActive: editMode)
        }
        .navigationBackDisabled(editMode || showAvatarViewer)
        .interactiveDismissDisabled(editMode)
        .keyboardDoneToolbar()
        .toolbar { profileToolbar }
        .onChange(of: draft.selectedPhotoItem) { _, newItem in
            Task { await loadPickedPhoto(newItem) }
        }
    }

    @ToolbarContentBuilder
    private var profileToolbar: some ToolbarContent {
        if editMode {
            EditModeToolbarItems(
                canSave: draft.canSave,
                onCancel: cancelEditing,
                onSave: saveProfile
            )
        } else if !showAvatarViewer {
            if presentation == .sheet {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Label("Close", systemImage: "xmark").fontWeight(.semibold) }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                if store.canEdit(profile: displayedProfile) {
                    ShareLink(item: shareURL, subject: Text(shareSubject)) {
                        Label("Share Profile", systemImage: "square.and.arrow.up")
                    }
                } else {
                    Menu {
                        ShareLink(item: shareURL, subject: Text(shareSubject)) {
                            Label("Share Profile", systemImage: "square.and.arrow.up")
                        }
                        Button {
                            reportTarget = .profile(displayedProfile)
                        } label: {
                            Label("Report Profile", systemImage: "flag")
                        }
                        if store.isBlocked(userID: displayedProfile.id) {
                            Button {
                                Task { await unblockUser() }
                            } label: {
                                Label("Unblock \(displayedProfile.handle)", systemImage: "hand.raised.slash")
                            }
                        } else {
                            Button(role: .destructive) {
                                blockCandidate = BlockCandidate(
                                    userID: displayedProfile.id,
                                    handle: displayedProfile.handle
                                )
                            } label: {
                                Label("Block", systemImage: "hand.raised")
                            }
                            .tint(.red)
                        }
                    } label: {
                        Image(systemName: "ellipsis").fontWeight(.semibold)
                    }
                    .disabled(isUpdatingBlock)
                }
            }
        }

        if showAvatarViewer, avatarViewerScale == 1.0 {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 1.0)) {
                        showAvatarViewer = false
                    }
                } label: {
                    Image(systemName: "xmark")
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                }
            }
        }
    }

    // Mirrors PostDetailView+Logic.swift's `shareURL` — same domain, same
    // onOpenURL handling in On_BoardApp.swift, just a different path segment.
    private var shareURL: URL {
        URL(string: "https://onboardapp.org/profile/\(displayedProfile.id)")!
    }

    private var shareSubject: String {
        displayedProfile.displayName.isEmpty ? displayedProfile.handle : displayedProfile.displayName
    }

    // MARK: - Edit lifecycle

    private func beginEditing() {
        draft.begin(from: displayedProfile) { candidate in
            await store.checkHandleAvailable(candidate)
        }
        withAnimation(.smooth(duration: 0.3)) { editMode = true }
    }

    private func saveProfile() {
        Task {
            await store.updateProfile(
                displayName: draft.displayName.trimmed,
                handle: draft.handle.trimmed,
                bio: draft.bio.trimmed.isEmpty ? nil : draft.bio.trimmed,
                avatarUrl: draft.avatarUrl,
                birthday: draft.birthdayString,
                showBirthday: draft.showBirthday
            )
            withAnimation(.smooth(duration: 0.3)) { editMode = false }
        }
    }

    private func cancelEditing() {
        draft.cancel()
        withAnimation(.smooth(duration: 0.3)) { editMode = false }
    }

    // MARK: - Posts Section

    private var userPostsSection: some View {
        let userPosts = store.feedItems.filter { item in
            if case .post(let id, _) = item, let post = store.feedPost(id: id) {
                return post.authorId == profile.id
            }
            return false
        }

        return Group {
            if !userPosts.isEmpty {
                VStack(alignment: .leading, spacing: 16) {
                    Divider()
                        .padding(.horizontal)
                        .padding(.top, 8)

                    Text("This Week's Posts")
                        .fontStyle(.headline)
                        .padding(.horizontal)

                    // No cardNamespace override: it comes from the environment so the
                    // cards register in ContentView's namespace, which is the one
                    // routeDestination's .zoom reads. profileNamespace stays scoped to
                    // this screen's matchedGeometryEffect / avatar zoom.
                    BoardFeedView(
                        items: userPosts,
                        originatingProfileID: profile.id
                    )
                }
                .padding(.top, 8)
            }
        }
    }

    // MARK: - Moderation

    private func blockUser(_ candidate: BlockCandidate) async {
        isUpdatingBlock = true
        defer { isUpdatingBlock = false }
        do {
            try await store.block(userID: candidate.userID)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            if presentation == .sheet {
                dismiss()
            }
        } catch {
            alertError = store.presentableModerationError(error)
        }
    }

    private func unblockUser() async {
        isUpdatingBlock = true
        defer { isUpdatingBlock = false }
        do {
            try await store.unblock(userID: displayedProfile.id)
        } catch {
            alertError = store.presentableModerationError(error)
        }
    }

    // MARK: - Avatar upload

    private func loadPickedPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        guard let data = try? await item.loadTransferable(type: Data.self) else { return }
        guard let uiImage = UIImage(data: data) else { return }

        await MainActor.run {
            uncroppedImage = uiImage
        }
    }

    private func uploadCroppedPhoto(_ image: UIImage) async {
        // Optimistically set the selected data to preview
        draft.selectedPhotoData = image.jpegData(compressionQuality: 0.85)

        draft.isUploadingPhoto = true
        defer { draft.isUploadingPhoto = false }

        guard let userID = store.currentUserID else { return }

        if let result = await ImageUploader.upload(input: .uiImage(image), type: .profilePicture, userID: userID) {
            draft.avatarUrl = result.url
        } else {
            // Revert the optimistic preview so the avatar shown matches what Save
            // would actually keep, and tell the user instead of failing silently.
            draft.selectedPhotoData = nil
            draft.selectedPhotoItem = nil
            alertError = PresentableAlertError(
                message: "Your photo couldn't be uploaded.",
                recoverySuggestion: "Check your connection and try again."
            )
        }
    }
}

extension UIImage: @retroactive Identifiable {
    public var id: Int { hash }
}

#Preview {
    NavigationStack {
        ProfileView(profile: .currentUser)
    }
    .environment(BoardStore.sampleBoard(currentUserID: SampleProfileID.maya))
}
