//
//  PostDetailView.swift
//  On Board
//

import SwiftUI
import PhotosUI
import Nuke

struct PostDetailView: View {
    let post: Post

    @Environment(BoardStore.self) var store
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var scheme
    @Environment(\.originatingProfileID) var originatingProfileID
    @Environment(\.photoAttachmentsEnabled) var photoAttachmentsEnabled
    @Namespace var postNamespace

    // Post editing
    @State var editMode = false
    @State var draftContent = ""
    /// Toolbar↔editor bridge for edit mode's rich composer.
    @State var editEditorController = MarkupEditorController()
    @State var draftTone: PostTone
    // Guards Save against a double-tap firing two concurrent updatePost
    // calls for the same post — the slower response would silently win.
    @State var isSavingEdits = false

    // Comment editing / composing
    @State var commentEdit = CommentEditState()
    @State var composer = CommentComposerState()
    @State var showExpandedComposer = false

    // Image editing. `draftImageUrl`/`draftImageAspectRatio` are the post's
    // *existing* image (pre-populated on `beginEditing`, cleared only once a
    // new upload this session succeeds) — everything about a newly-picked
    // replacement lives in `editPhoto`.
    @State var editPhoto = PhotoAttachmentController(type: .postPhoto)
    @State var draftImageUrl: String?
    @State var draftImageAspectRatio: Double?

    // UI
    @State var showDeleteConfirmation = false
    @State var commentPendingDeletion: UUID?
    @State var alertError: PresentableAlertError?
    @State var isLoadingComments = false
    @State var showImageViewer = false
    @State var imageViewerScale: CGFloat = 1.0

    // Moderation
    @State var reportTarget: ReportTarget?
    @State var blockCandidate: BlockCandidate?

    init(post: Post) {
        self.post = post
        _draftTone = State(initialValue: post.tone)
        _draftContent = State(initialValue: post.content)
    }

    // MARK: - Derived

    // Resolve through the per-post proxy, not postsByID — postsByID is a single
    // dictionary property, so reading it here would make this view re-evaluate
    // on *every* post's reaction/vote anywhere in the app, not just this one.
    // The proxy (same pattern FeedGridCard uses) only invalidates observers when
    // *this* post changes. patchPostInWeekCache keeps both in sync, so the data
    // is identical either way — this only changes what gets observed.
    // The comments section reads `store.comments(for:)` directly, so livePost
    // never needs them attached, and this property is evaluated many times per
    // body pass.
    var livePost: Post {
        store.postProxies[post.id]?.post ?? post
    }

    var tone: PostTone {
        editMode ? draftTone : livePost.tone
    }

    var canEdit: Bool {
        store.canInteract(with: livePost) && store.canEdit(post: livePost)
    }

    var isReadOnly: Bool {
        livePost.isReadOnly || !store.canInteract(with: livePost)
    }

    /// The active week's end while a *live* post's board is in the clears-soon
    /// window — drives the ticking countdown in the toolbar principal. Exposed here
    /// (not read from `store` in the +Views extension) so it clears the `private`
    /// store's file scope. Nil once read-only, so an archived post keeps the
    /// "Archived Post" principal instead.
    var clearingSoonWeekEnd: Date? {
        guard !isReadOnly,
              let endsAt = store.activeBoardWeek?.endsAt,
              BoardSchedule.isClearingSoon(weekEnd: endsAt,
                                           thresholds: store.boardThresholds) else { return nil }
        return endsAt
    }

    var isCommentEditing: Bool {
        commentEdit.isEditing
    }

    var authorProfile: Profile {
        store.profile(forAuthor: livePost.author)
    }

    var selectedReaction: Binding<Reaction?> {
        Binding(
            get: { store.userReaction(for: livePost.id) },
            set: { store.setReaction(postId: livePost.id, reaction: $0) }
        )
    }

    // MARK: - Body

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if !editMode {
                        postContent
                            .opacity(isCommentEditing ? 0.32 : 1)
                        Divider()
                            .opacity(isCommentEditing ? 0.32 : 1)
                        commentsSection
                    } else {
                        postEditContent
                    }
                }
                .safeAreaPadding(.horizontal)
                .safeAreaPadding(.top, 12)
                .safeAreaPadding(.bottom, 32)
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(.smooth(duration: 0.3), value: commentEdit.editingCommentID)
            }
            .scrollDismissesKeyboard(.interactively)
            .interactiveDismissDisabled(editMode)
            .background {
                tone.color
                    .opacity(scheme == .dark ? 0.25 : 0.20)
                    .ignoresSafeArea()
                    .overlay {
                        AnimatedStripesView(
                            color: tone.color,
                            opacity: 0.1,
                            isActive: editMode || isCommentEditing
                        )
                    }
            }
            .animation(.smooth(duration: 0.3), value: tone)
            .task(id: livePost.id) {
                isLoadingComments = true
                await store.loadComments(for: livePost.id)
                // `.task(id:)` cancels cooperatively — the awaited call above can
                // still return after a second post-switch already started a newer
                // task. Without this guard, this stale completion's `= false`
                // could hide the new task's loading skeleton while its fetch is
                // still in flight.
                guard !Task.isCancelled else { return }
                isLoadingComments = false
            }
            .task(id: livePost.imageUrl) {
                // ImageViewerView loads this same URL via a plain, unprocessed
                // ImageRequest (full resolution, so pinch-zoom stays sharp) —
                // a different Nuke cache key than BoardAsyncImage's downsampled
                // thumbnail request just above, so opening the viewer forced a
                // cold decode of a full-size (up to 2048px) photo right as the
                // tap-to-open spring animation started, competing with it for
                // frame time and reading as choppy/low-framerate mid-transition.
                // Warming that exact request here — while the post is just
                // sitting on screen, well before any tap — means it's already
                // decoded and cached by the time the user actually opens it.
                guard let urlString = livePost.imageUrl, let url = URL(string: urlString) else { return }
                _ = try? await ImagePipeline.shared.imageTask(with: url).response
            }
            .task(id: livePost.id) {
                guard let authorId = livePost.authorId else { return }
                store.prefetchPopScore(for: authorId)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if editMode {
                    ComposerToolbar(controller: editEditorController)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                // Hidden while editing a post OR a comment — both put the keyboard
                // up for a different text session, and the bar previously rode the
                // keyboard into the content (the screenshot collision).
                if !editMode && !isCommentEditing {
                    CommentComposerBar(
                        tone: tone,
                        counts: livePost.reactionCounts,
                        selectedReaction: selectedReaction,
                        composer: $composer,
                        isReadOnly: isReadOnly,
                        isRecord: isReadOnly,
                        onPost: submitComposer,
                        onExpand: { showExpandedComposer = true },
                        // Sheet presentation resigns first responder; without this
                        // flag the bar's focus-loss handler would read the expand
                        // handoff as a cancel and wipe the draft.
                        isSheetPresented: showExpandedComposer,
                        isErrorPresented: alertError != nil
                    )
                    // The bar should only ride the keyboard when it OWNS the
                    // keyboard. `CommentComposerBar` keeps `isFieldFocused` and
                    // `composer.isComposing` in lockstep (focus is set from
                    // isComposing, and losing focus clears it), so in browse mode
                    // nothing here is focused — and any bottom keyboard inset is
                    // therefore stale, inherited from a sheet (NewPostView,
                    // CommentComposerSheet) that was dismissed just before this
                    // screen was pushed. Honouring it strands the reaction bar
                    // mid-screen until something else forces a relayout.
                    //
                    // The earlier fix for this dismissed the keyboard at the
                    // *sender* before dismissing the sheet. That reduces the
                    // window but cannot close it: it races the keyboard's hide
                    // animation, which is why the symptom kept coming back
                    // intermittently. This makes position depend on state we
                    // control rather than on winning a race, and it holds no
                    // matter which screen preceded this one.
                    //
                    // An empty edge set (rather than an if/else) keeps the bar's
                    // view identity stable so the browse/compose morph animation
                    // is unaffected.
                    .ignoresSafeArea(
                        .keyboard,
                        edges: composer.isComposing ? [] : .bottom
                    )
                }
            }
            .sheet(isPresented: $showExpandedComposer) {
                CommentComposerSheet(
                    composer: $composer,
                    tone: tone,
                    onPost: submitComposer,
                    alertError: $alertError
                )
            }
            .onChange(of: composer.target) { _, target in
                guard let parentID = target?.replyParentID else { return }
                withAnimation(.smooth(duration: 0.35)) {
                    proxy.scrollTo(parentID, anchor: .center)
                }
            }
            .task(id: store.activeBoardWeek?.endsAt) {
                // Auto-dismiss a live post to the feed the instant its board clears, so
                // no now-invalid reactions/comments are possible. Driven from the post's
                // OWN lifecycle — the feed's reset task doesn't reliably fire while the
                // post covers it, so we can't lean on ContentView's path reset here.
                // Mirrors that task: sleep until endsAt (restarts when it's shortened),
                // then leave. Archived posts (read-only) are never auto-dismissed.
                guard !post.isReadOnly,
                      let endsAt = store.activeBoardWeek?.endsAt, endsAt > .now else { return }
                try? await Task.sleep(for: .seconds(endsAt.timeIntervalSinceNow))
                guard !Task.isCancelled else { return }
                dismiss()
            }
            .onChange(of: store.activeBoardWeek?.id) { _, _ in
                // Backstop for a rollover that lands a *new* week id without this view's
                // endsAt task firing — e.g. a reset that happened while backgrounded,
                // resolved by the foreground refresh. Live posts only.
                if !post.isReadOnly { dismiss() }
            }
            .boardErrorHandling(alertError: $alertError)
            .presentableErrorAlert(error: $alertError)
            .alert("Delete this post?", isPresented: $showDeleteConfirmation) {
                Button("Delete Post", role: .destructive) {
                    Task { if await store.deletePost(id: livePost.id) { dismiss() } }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently removes the post and its comments.")
            }
            .sheet(item: $reportTarget) { target in
                ReportContentSheet(target: target) {
                    // Reporting the post itself hides it — leave the empty screen.
                    if case .post = target { dismiss() }
                }
            }
            .confirmationDialog(
                "Block \(blockCandidate?.handle ?? "")?",
                isPresented: Binding(
                    get: { blockCandidate != nil },
                    set: { if !$0 { blockCandidate = nil } }
                ),
                titleVisibility: .visible,
                presenting: blockCandidate
            ) { candidate in
                Button("Block \(candidate.handle)", role: .destructive) {
                    Task { await blockUser(candidate) }
                }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("You won't see each other's posts or comments. You can unblock them anytime in Settings.")
            }
            .confirmationDialog(
                "Delete this comment?",
                isPresented: Binding(
                    get: { commentPendingDeletion != nil },
                    set: { if !$0 { commentPendingDeletion = nil } }
                ),
                titleVisibility: .visible,
                presenting: commentPendingDeletion
            ) { commentID in
                Button("Delete Comment", role: .destructive) {
                    Task { await store.deleteComment(postID: livePost.id, commentID: commentID) }
                }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("This also removes any replies to it.")
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(editMode || showImageViewer)
            .interactiveDismissDisabled(editMode || showImageViewer)
            // Keep the single-finger interactive pop (governed above), but drop the
            // zoom transition's two-finger pinch-to-dismiss — it reads as accidental.
            .disableZoomPinchToDismiss()
            .toolbar { toolbarContent }
            .overlay {
                ImageViewerView(
                    url: URL(string: livePost.imageUrl ?? ""),
                    namespace: postNamespace,
                    sourceID: "postImage",
                    isPresented: $showImageViewer,
                    aspectRatio: livePost.imageAspectRatio.map { CGFloat($0) },
                    currentScale: $imageViewerScale
                )
                .ignoresSafeArea()
                .zIndex(100)
            }
            .onChange(of: editPhoto.selectedPhotoItem) { _, item in
                Task { await editPhoto.loadPickedPhoto(item) }
            }
            .presentableErrorAlert(error: $editPhoto.alertError)
            .fullScreenCover(item: $editPhoto.uncroppedImage) { image in
                PostImageCropView(image: image) { cropped in
                    editPhoto.uncroppedImage = nil
                    guard let userID = store.currentUserID else { return }
                    Task {
                        await editPhoto.uploadCropped(
                            cropped,
                            userID: userID,
                            revertPreviewOnFailure: true,
                            alertOnFailure: false
                        )
                        if editPhoto.uploadedURL != nil { draftImageUrl = nil }
                    }
                } onCancel: {
                    editPhoto.uncroppedImage = nil
                    editPhoto.selectedPhotoItem = nil
                }
            }
        }
    }
}

// MARK: - Previews

#Preview("Active Post") {
    NavigationStack {
        PostDetailView(
            post: .init(
                content: "# Test Post With A Title That Wraps Across Multiple Lines\nHello **bold** and ~~gone~~",
                author: "author1",
                tone: .red,
                reactionCounts: [.like: 1367, .dislike: 126, .laugh: 2_200_000],
                comments: Comment.cs241MidtermComments
            )
        )
        .environment(BoardStore.previewBoard())
        .environment(AuthStore(service: MockAuthService()))
    }
}

#Preview("Archived Post") {
    let store = BoardStore.previewBoard()
    let archivedPost = store.posts.first { $0.isReadOnly }!
    return NavigationStack {
        PostDetailView(post: archivedPost)
    }
    .environment(store)
    .environment(AuthStore(service: MockAuthService()))
}
