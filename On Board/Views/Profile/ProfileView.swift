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

enum ProfilePresentation {
    case sheet
    case navigation
}

struct ProfileView: View {
    let profile: Profile
    var presentation: ProfilePresentation = .sheet

    @Environment(BoardStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.profileFieldLimits) private var profileFieldLimits
    @Namespace private var profileNamespace
    @State private var showAvatarViewer = false
    @State private var avatarViewerPhase: ImageViewerPhase = .closed
    /// Story-ready share card, re-rendered when the profile/avatar/Pop Score
    /// change. While nil (first frame, render in flight) the share action
    /// falls back to the plain profile URL.
    @State private var shareCard: UIImage?

    @State private var editMode = false
    @State private var draft = ProfileDraft()
    @State private var alertError: PresentableAlertError?
    // Guards Save against a double-tap firing two concurrent updateProfile
    // calls for the same profile — the slower response would silently win.
    @State private var isSavingProfile = false

    // Moderation (other users' profiles only)
    @State private var reportTarget: ReportTarget?
    @State private var blockCandidate: BlockCandidate?
    @State private var isUpdatingBlock = false
    /// On this profile's birthday (if they share it), fireworks + a "Happy
    /// Birthday!" cross-fade — shown to any visitor, finite each visit.
    @State private var birthdayCelebrating = false

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
            .fullScreenCover(item: $draft.photo.uncroppedImage) { image in
                ProfileImageCropView(image: image) { cropped in
                    draft.photo.uncroppedImage = nil
                    guard let userID = store.currentUserID else { return }
                    Task {
                        await draft.photo.uploadCropped(
                            cropped,
                            userID: userID,
                            revertPreviewOnFailure: true,
                            alertOnFailure: true
                        )
                        if draft.photo.uploadedURL != nil { draft.avatarUrl = draft.photo.uploadedURL }
                    }
                } onCancel: {
                    draft.photo.uncroppedImage = nil
                    draft.photo.selectedPhotoItem = nil
                }
            }
            .interactiveDismissDisabled(editMode || showAvatarViewer)
            .navigationBarBackButtonHidden(editMode || showAvatarViewer)
            .overlay {
                ImageViewerView(
                    url: URL(string: displayedProfile.avatarUrl ?? ""),
                    namespace: profileNamespace,
                    sourceID: ProfileGeometryID.avatarImage,
                    isPresented: $showAvatarViewer,
                    aspectRatio: 1.0,
                    phase: $avatarViewerPhase
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
            // Separate task from the Pop Score fetch on purpose: two
            // independent revalidation reads, and one failing (silently, per
            // the read-vs-write rule) must not cost the other its result.
            .task(id: profile.id) {
                await store.refreshFavoriteTone(for: profile.id)
            }
            .task(id: shareCardKey) {
                shareCard = await ProfileShareCardRenderer.render(
                    profile: displayedProfile,
                    popScore: store.popScore(for: displayedProfile.id) ?? [:]
                )
            }
            .task(id: profile.id) {
                // Their birthday, shared publicly → celebrate for whoever's viewing.
                birthdayCelebrating = displayedProfile.showBirthday
                    && BirthdayCelebration.isToday(displayedProfile.birthday)
            }
            .fireworks(isActive: birthdayCelebrating)
            .presentableErrorAlert(error: $alertError)
            .presentableErrorAlert(error: $draft.photo.alertError)
    }

    /// Mock-only: replay the birthday celebration for ~10s, retriggerable.
    private func triggerBirthdayTest() {
        birthdayCelebrating = false
        Task {
            try? await Task.sleep(for: .milliseconds(50))
            birthdayCelebrating = true
            try? await Task.sleep(for: .seconds(10))
            birthdayCelebrating = false
        }
    }

    private var profileScroll: some View {
        ScrollView {
            Group {
                if editMode {
                    ProfileEditContent(
                        profile: displayedProfile,
                        namespace: profileNamespace,
                        draft: draft,
                        onCameraCapture: { draft.photo.uncroppedImage = $0 }
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
                                withAnimation(ImageViewerMotion.morphSpring) {
                                    showAvatarViewer = true
                                }
                            }
                        },
                        onUnblock: { Task { await unblockUser() } },
                        celebrateBirthday: birthdayCelebrating,
                        onTestBirthday: triggerBirthdayTest
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
        .onChange(of: draft.photo.selectedPhotoItem) { _, newItem in
            Task { await draft.photo.loadPickedPhoto(newItem) }
        }
    }

    @ToolbarContentBuilder
    private var profileToolbar: some ToolbarContent {
        if editMode {
            EditModeToolbarItems(
                canSave: draft.canSave && !isSavingProfile,
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
                    profileShareLink
                } else {
                    Menu {
                        profileShareLink
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
                        }
                    } label: {
                        Image(systemName: "ellipsis").fontWeight(.semibold)
                    }
                    .disabled(isUpdatingBlock)
                }
            }
        }

        // `.settled`, not `showAvatarViewer`: adopts the same deferred-chrome
        // behavior as PostDetailView (X arrives after the open morph, never
        // inside its transaction), which this call site previously lacked.
        if avatarViewerPhase == .settled {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    withAnimation(ImageViewerMotion.morphSpring) {
                        showAvatarViewer = false
                    }
                } label: {
                    Label("Close", systemImage: "xmark")
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                }
            }
        }
    }

    /// The share entry: the story-ready card image when rendered, else the
    /// bare profile URL. Sharing the IMAGE is the growth loop — the card
    /// carries the CTA + domain, and Instagram-story recipients get a
    /// composed asset instead of a naked link preview.
    @ViewBuilder
    private var profileShareLink: some View {
        if let shareCard {
            ShareLink(
                item: Image(uiImage: shareCard),
                subject: Text(shareSubject),
                preview: SharePreview(shareSubject, image: Image(uiImage: shareCard))
            ) {
                Label("Share Profile", systemImage: "square.and.arrow.up")
            }
        } else {
            ShareLink(item: shareURL, subject: Text(shareSubject)) {
                Label("Share Profile", systemImage: "square.and.arrow.up")
            }
        }
    }

    /// Re-render key: any of these changing invalidates the card.
    private struct ShareCardKey: Hashable {
        let id: UUID
        let handle: String
        let avatarUrl: String?
        let popScore: [Reaction: Int]
    }

    private var shareCardKey: ShareCardKey {
        ShareCardKey(
            id: displayedProfile.id,
            handle: displayedProfile.handle,
            avatarUrl: displayedProfile.avatarUrl,
            popScore: store.popScore(for: displayedProfile.id) ?? [:]
        )
    }



    // Mirrors PostDetailView+Logic.swift's `shareURL` — same domain, same
    // onOpenURL handling in On_BoardApp.swift, just a different path segment.
    // Force-unwrap is safe: a fixed HTTPS host + `/profile/` + a UUID's
    // canonical string form never contains characters `URL(string:)` rejects.
    private var shareURL: URL {
        URL(string: "https://onboardapp.org/profile/\(displayedProfile.id)")!
    }

    private var shareSubject: String {
        displayedProfile.displayNameOrHandle
    }

    // MARK: - Edit lifecycle

    private func beginEditing() {
        // Hand the (possibly remote-overridden) limits to the draft before it
        // starts validating — it's a model, not a View, so it can't read them.
        draft.displayNameLimit = profileFieldLimits.displayName
        draft.bioLimit = profileFieldLimits.bio
        draft.begin(from: displayedProfile) { candidate in
            await store.checkHandleAvailable(candidate)
        }
        withAnimation(.smooth(duration: 0.3)) { editMode = true }
    }

    private func saveProfile() {
        guard !isSavingProfile else { return }
        isSavingProfile = true
        Task {
            defer { isSavingProfile = false }
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
