//
//  PostDetailView.swift
//  On Board
//

import SwiftUI

struct PostDetailView: View {
    let post: Post

    @Environment(BoardStore.self) private var store
    @State private var editMode = false
    @State private var draftTitle = ""
    @State private var draftDescription = ""
    @State private var draftTone: PostTone
    @State private var editingCommentID: UUID?
    @State private var draftCommentBody = ""
    @Environment(\.colorScheme) private var scheme
    @Namespace private var postNamespace

    init(post: Post) {
        self.post = post
        _draftTone = State(initialValue: post.tone)
        _draftTitle = State(initialValue: post.title)
        _draftDescription = State(initialValue: post.description)
    }

    private var livePost: Post {
        store.post(with: post.id) ?? post
    }

    private var tone: PostTone {
        editMode ? draftTone : livePost.tone
    }

    private var canEdit: Bool {
        store.canInteract(with: livePost) && store.canEdit(post: livePost)
    }

    private var isReadOnly: Bool {
        livePost.isReadOnly || !store.canInteract(with: livePost)
    }

    private var isCommentEditing: Bool {
        editingCommentID != nil
    }

    private var authorProfile: Profile {
        store.profile(forAuthor: livePost.author)
    }

    private var selectedReaction: Binding<Reaction?> {
        Binding(
            get: { store.userReaction(for: livePost.id) },
            set: { store.setReaction(postId: livePost.id, reaction: $0) }
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if editMode {
                    VStack(spacing: 10) {
                        EditingIndicator()
                            .fontStyle(.title)
                            .frame(maxWidth: .infinity)
                        Text("Tap any element to edit.")
                            .fontStyle(.body)
                            .multilineTextAlignment(.center)
                    }
                    .safeAreaPadding()
                    .background {
                        Color(uiColor: .systemBackground)
                        tone.color.opacity(scheme == .dark ? 0.25 : 0.3)
                    }
                    .ignoresSafeArea()
                }

                if !editMode {
                    postContent
                        .opacity(isCommentEditing ? 0.32 : 1)

                    Divider()
                        .opacity(isCommentEditing ? 0.32 : 1)

                    commentsSection
                } else {
                    TextField("Title", text: $draftTitle, axis: .vertical)
                        .fontStyle(.largeTitle)
                        .matchedGeometryEffect(id: "postTitle", in: postNamespace, anchor: .leading)

                    TextField("Description", text: $draftDescription, axis: .vertical)
                        .fontStyle(.body)
                        .matchedGeometryEffect(id: "postDescription", in: postNamespace, anchor: .leading)

                    HStack {
                        TonePicker(selection: $draftTone)
                            .matchedGeometryEffect(id: "postBar", in: postNamespace, anchor: .leading)
                        Spacer()
                    }
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
                    StripesOverlay(color: tone.color, opacity: 0.1)
                        .offset(x: editMode || isCommentEditing ? 0 : 100)
                        .opacity(editMode || isCommentEditing ? 1 : 0)
                }
        }
        .animation(.smooth(duration: 0.3), value: tone)
        .task(id: livePost.id) {
            if store.isLive, store.comments(for: livePost.id).isEmpty {
                await store.loadComments(for: livePost.id)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isReadOnly && !editMode && !isCommentEditing {
                ToolbarItem(placement: .principal) {
                    Label("Archived Post", systemImage: "archivebox")
                        .fontStyle(.caption)
                        .foregroundStyle(.secondary)
                        .labelStyle(.titleAndIcon)
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if canEdit {
                        Button {
                            beginEditing()
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                    }
                    Button {
                        // share
                    } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    if !canEdit {
                        Button(role: .destructive) {
                            // report
                        } label: {
                            Label("Report", systemImage: "flag")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .disabled(editMode || isCommentEditing)
            }

            if editMode {
                ToolbarItem(placement: .bottomBar) {
                    Button {
                        saveEdits()
                    } label: {
                        Label("Save", systemImage: "checkmark")
                    }
                }
                ToolbarItem(placement: .bottomBar) { Spacer() }
                ToolbarItem(placement: .bottomBar) {
                    Button {
                        cancelEditing()
                    } label: {
                        Label("Cancel", systemImage: "xmark")
                    }
                }
            }

            if isCommentEditing {
                ToolbarItem(placement: .bottomBar) {
                    Button {
                        confirmCommentEditing()
                    } label: {
                        Label("Save", systemImage: "checkmark")
                    }
                }
                ToolbarItem(placement: .bottomBar) { Spacer() }
                ToolbarItem(placement: .bottomBar) {
                    Button {
                        cancelCommentEditing()
                    } label: {
                        Label("Cancel", systemImage: "xmark")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var postContent: some View {
        NavigationLink(value: BoardRoute.profile(authorProfile)) {
            Text("by \(livePost.author)")
                .fontStyle(.caption)
        }
        .buttonStyle(.plain)

        Text(livePost.title)
            .fontStyle(.largeTitle)
            .matchedGeometryEffect(id: "postTitle", in: postNamespace, anchor: .leading)

        Text(livePost.description)
            .fontStyle(.body)
            .matchedGeometryEffect(id: "postDescription", in: postNamespace, anchor: .leading)

        ReactionBar(
            counts: livePost.reactionCounts,
            tone: tone,
            selected: selectedReaction,
            isInteractive: !isReadOnly && !isCommentEditing
        )
        .matchedGeometryEffect(id: "postBar", in: postNamespace, anchor: .leading)
    }

    @ViewBuilder
    private var commentsSection: some View {
        Text("Comments")
            .fontStyle(.title3)
            .foregroundStyle(.primary)
            .opacity(isCommentEditing ? 0.32 : 1)

        if store.comments(for: livePost.id).isEmpty {
            Text("no comments yet. start the thread.")
                .fontStyle(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 12)
        } else {
            LazyVStack(alignment: .leading, spacing: 18) {
                ForEach(store.comments(for: livePost.id)) { comment in
                    CommentView(
                        postID: livePost.id,
                        comment: comment,
                        isInteractive: !isReadOnly,
                        editingCommentID: editingCommentID,
                        draftCommentBody: $draftCommentBody,
                        onBeginEdit: beginCommentEditing,
                        onConfirmEdit: confirmCommentEditing
                    )
                }
            }
        }
    }

    private func beginEditing() {
        cancelCommentEditing()
        draftTitle = livePost.title
        draftDescription = livePost.description
        draftTone = livePost.tone
        withAnimation(.smooth(duration: 0.4)) { editMode = true }
    }

    private func saveEdits() {
        Task {
            await store.updatePost(
                id: livePost.id,
                title: draftTitle.trimmed,
                description: draftDescription.trimmed,
                tone: draftTone
            )
            withAnimation(.smooth(duration: 0.4)) { editMode = false }
        }
    }

    private func cancelEditing() {
        draftTitle = livePost.title
        draftDescription = livePost.description
        draftTone = livePost.tone
        withAnimation(.smooth(duration: 0.4)) { editMode = false }
    }

    private func beginCommentEditing(commentID: UUID, body: String) {
        editingCommentID = commentID
        draftCommentBody = body
    }

    private func confirmCommentEditing() {
        guard let editingCommentID else { return }
        let trimmed = draftCommentBody.trimmed
        guard !trimmed.isEmpty else { return }

        Task {
            await store.updateComment(
                postID: livePost.id,
                commentID: editingCommentID,
                body: trimmed
            )
            withAnimation(.smooth(duration: 0.35)) {
                self.editingCommentID = nil
                draftCommentBody = ""
            }
        }
    }

    private func cancelCommentEditing() {
        withAnimation(.smooth(duration: 0.35)) {
            editingCommentID = nil
            draftCommentBody = ""
        }
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

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
    }
}

#Preview("Archived Post") {
    let store = BoardStore.previewBoard()
    let archivedPost = store.posts.first { $0.isReadOnly }!

    return NavigationStack {
        PostDetailView(post: archivedPost)
    }
    .environment(store)
}
