//
//  PostDetailView.swift
//  On Board
//

import SwiftUI
import PhotosUI

struct PostDetailView: View {
    let post: Post

    @Environment(BoardStore.self) var store
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var scheme
    @Environment(\.originatingProfileID) var originatingProfileID
    @Namespace var postNamespace

    // Post editing
    @State var editMode = false
    @State var draftTitle = ""
    @State var draftDescription = ""
    @State var draftTone: PostTone
    @State var draftTags: [String] = []
    @State var showingTagSelection = false

    // Comment editing / replying
    @State var editingCommentID: UUID?
    @State var draftCommentBody = ""
    @State var replyingToCommentID: UUID?
    @State var newCommentDraft = ""
    @FocusState var isNewCommentFocused: Bool

    // Image editing
    @State var selectedEditPhotoItem: PhotosPickerItem?
    @State var selectedEditPhotoData: Data?
    @State var draftImageUrl: String?
    @State var draftImageAspectRatio: Double?
    @State var isUploadingEditImage = false
    @State var uploadedEditImageUrl: String?
    @State var uploadedEditAspectRatio: Double?
    @State var editImageUploadFailed = false

    // UI
    @State var showDeleteConfirmation = false
    @State var commentPendingDeletion: UUID?
    @State var alertError: PresentableAlertError?
    @State var isLoadingComments = false
    @State var showImageViewer = false

    // Moderation
    @State var reportTarget: ReportTarget?
    @State var blockCandidate: BlockCandidate?

    init(post: Post) {
        self.post = post
        _draftTone = State(initialValue: post.tone)
        _draftTitle = State(initialValue: post.title)
        _draftDescription = State(initialValue: post.description)
        _draftTags = State(initialValue: post.tags)
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

    var isCommentEditing: Bool {
        editingCommentID != nil
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
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if !editMode {
                    postContent
                        .opacity(isCommentEditing ? 0.32 : 1)
                    Divider()
                        .opacity(isCommentEditing ? 0.32 : 1)
                    commentsSection
                } else {
                    Text("Tap any element to edit.")
                        .fontStyle(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .matchedGeometryEffect(id: "postAuthor", in: postNamespace, anchor: .leading)
                    
                    TextField("Title", text: $draftTitle, axis: .vertical)
                        .fontStyle(.largeTitle)
                        .keyboardType(.default)
                        .textInputAutocapitalization(.sentences)
                        .matchedGeometryEffect(id: "postTitle", in: postNamespace, anchor: .leading)
                    TextField("Description", text: $draftDescription, axis: .vertical)
                        .fontStyle(.body)
                        .keyboardType(.twitter)
                        .matchedGeometryEffect(id: "postDescription", in: postNamespace, anchor: .leading)
                        
                    editTagsSection
                    
                    editImageSection
                        .transition(.opacity)
                }
            }
            .safeAreaPadding(.horizontal)
            .safeAreaPadding(.top, 12)
            .safeAreaPadding(.bottom, 32)
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(.smooth(duration: 0.3), value: editingCommentID)
        }
        .scrollDismissesKeyboard(.interactively)
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
            isLoadingComments = false
        }
        .task(id: livePost.id) {
            guard let authorId = livePost.authorId else { return }
            store.prefetchPopScore(for: authorId)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !editMode {
                PostActionBar(
                    tone: tone,
                    counts: livePost.reactionCounts,
                    selectedReaction: selectedReaction,
                    isInteractive: !isReadOnly && !isCommentEditing && !editMode,
                    isRecord: isReadOnly
                )
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if let text = store.clearingBannerText {
                HStack(spacing: 8) {
                    Image(systemName: "clock.badge.exclamationmark.fill")
                        .foregroundStyle(.red)
                    Text(text)
                        .fontStyle(.footnote)
                        .foregroundStyle(.primary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.regularMaterial)
                .overlay(Rectangle().frame(height: 0.5).foregroundStyle(.red.opacity(0.4)), alignment: .bottom)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.smooth(duration: 0.3), value: store.clearingBannerText != nil)
        .boardErrorHandling(alertError: $alertError)
        .presentableErrorAlert(error: $alertError)
        .confirmationDialog(
            "Delete this post?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
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
        .sheet(isPresented: $showingTagSelection) {
            TagSelectionView(selectedTags: $draftTags)
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
        .navigationBackDisabled(editMode)
        .interactiveDismissDisabled(editMode)
        .toolbar { toolbarContent }
        .keyboardDoneToolbar()
        .fullScreenCover(isPresented: $showImageViewer) {
            if let urlString = livePost.imageUrl, let url = URL(string: urlString) {
                ImageViewerView(url: url)
                    .navigationTransition(.zoom(sourceID: "postImage", in: postNamespace))
            }
        }
        .onChange(of: selectedEditPhotoItem) { _, item in
            Task { await loadAndUploadEditImage(item) }
        }
    }
}

// MARK: - Previews

#Preview("Active Post") {
    NavigationStack {
        PostDetailView(
            post: .init(
                title: "Test Post With A Title That Wraps Across Multiple Lines",
                description: "Hello",
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
