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
    @Namespace var postNamespace

    // Post editing
    @State var editMode = false
    @State var draftTitle = ""
    @State var draftDescription = ""
    @State var draftTone: PostTone

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

    // UI
    @State var showDeleteConfirmation = false
    @State var alertError: PresentableAlertError?
    @State private var clearingBannerText: String?
    @State var showImageViewer = false
    @State var showHeartBurst = false
    @State var heartTapLocation: CGPoint = CGPoint(x: 100, y: 50)
    @State var heartRotation: Double = 0

    init(post: Post) {
        self.post = post
        _draftTone = State(initialValue: post.tone)
        _draftTitle = State(initialValue: post.title)
        _draftDescription = State(initialValue: post.description)
    }

    // MARK: - Derived

    var livePost: Post {
        store.post(with: post.id) ?? post
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

    private func updateClearingBanner() {
        clearingBannerText = BoardSchedule.finalHourBannerText(weekEnd: store.activeBoardWeek?.endsAt)
    }

    var selectedReaction: Binding<Reaction?> {
        Binding(
            get: { store.userReaction(for: livePost.id) },
            set: { store.setReaction(postId: livePost.id, reaction: $0) }
        )
    }

    // MARK: - Body

    var body: some View {
        let livePost = livePost
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
                        .matchedGeometryEffect(id: "postTitle", in: postNamespace, anchor: .leading)
                    TextField("Description", text: $draftDescription, axis: .vertical)
                        .fontStyle(.body)
                        .matchedGeometryEffect(id: "postDescription", in: postNamespace, anchor: .leading)
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
        .task(id: livePost.id) { await store.loadComments(for: livePost.id) }
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
            if let text = clearingBannerText {
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
        .animation(.smooth(duration: 0.3), value: clearingBannerText != nil)
        .onAppear { updateClearingBanner() }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                updateClearingBanner()
            }
        }
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
        .navigationBarTitleDisplayMode(.inline)
        .navigationBackDisabled(editMode)
        .toolbar { toolbarContent }
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
