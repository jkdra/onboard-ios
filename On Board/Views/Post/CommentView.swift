//
//  CommentView.swift
//  On Board
//

import SwiftUI

struct CommentView: View {
    let postID: UUID
    let comment: Comment
    var isInteractive: Bool = true
    var editingCommentID: UUID?
    var replyingToCommentID: UUID?
    @Binding var draftCommentBody: String
    var onBeginEdit: ((UUID, String) -> Void)?
    var onConfirmEdit: (() -> Void)?
    var onReply: ((UUID) -> Void)?
    var onCancelReply: (() -> Void)?
    var onDelete: ((UUID) -> Void)?
    var onReport: ((Comment) -> Void)?
    var onBlockAuthor: ((Comment) -> Void)?

    @Environment(BoardStore.self) private var store
    @FocusState private var isEditorFocused: Bool
    @FocusState private var isReplyFocused: Bool
    @State private var replyDraft = ""
    @State private var isPostingReply = false

    private var authorProfile: Profile {
        store.profile(forAuthor: comment.author)
    }

    private var canEdit: Bool {
        store.canEdit(comment: comment)
    }

    private var isBeingEdited: Bool {
        editingCommentID == comment.id
    }

    private var isDimmed: Bool {
        guard let editingCommentID else { return false }
        return editingCommentID != comment.id
    }

    private var selectedVote: Binding<CommentVote?> {
        Binding(
            get: { store.userCommentVote(for: comment.id) },
            set: { store.setCommentVote(commentID: comment.id, postID: postID, vote: $0) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            commentContent

            if replyingToCommentID == comment.id {
                inlineReplyComposer
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if !comment.replies.isEmpty {
                HStack(alignment: .top, spacing: 12) {
                    Rectangle()
                        .fill(.secondary.opacity(isDimmed ? 0.15 : 0.25))
                        .frame(width: 1.5)
                        .opacity(isDimmed ? 0.32 : 1)

                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(comment.replies) { reply in
                            CommentView(
                                postID: postID,
                                comment: reply,
                                isInteractive: isInteractive,
                                editingCommentID: editingCommentID,
                                replyingToCommentID: replyingToCommentID,
                                draftCommentBody: $draftCommentBody,
                                onBeginEdit: onBeginEdit,
                                onConfirmEdit: onConfirmEdit,
                                onReply: onReply,
                                onCancelReply: onCancelReply,
                                onDelete: onDelete,
                                onReport: onReport,
                                onBlockAuthor: onBlockAuthor
                            )
                        }
                    }
                }
                .padding(.top, 8)
            }
        }
        .animation(.smooth(duration: 0.3), value: editingCommentID)
        .animation(.smooth(duration: 0.3), value: replyingToCommentID)
    }

    @ViewBuilder
    private var inlineReplyComposer: some View {
        HStack(alignment: .top, spacing: 8) {
            TextField("Write a reply…", text: $replyDraft, axis: .vertical)
                .fontStyle(.callout)
                .focused($isReplyFocused)

            VStack(spacing: 4) {
                Button {
                    Task { await postReply() }
                } label: {
                    if isPostingReply {
                        ProgressView().scaleEffect(0.8)
                    } else {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                            .foregroundStyle(
                                replyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    ? Color.secondary.opacity(0.4)
                                    : Color.primary
                            )
                    }
                }
                .buttonStyle(.plain)
                .disabled(replyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isPostingReply)
                .accessibilityLabel("Post reply")

                Button { onCancelReply?() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cancel reply")
            }
        }
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.secondary.opacity(0.08))
        }
        .onAppear { isReplyFocused = true }
    }

    private func postReply() async {
        let trimmed = replyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isPostingReply = true
        defer { isPostingReply = false }
        let succeeded = await store.addComment(postID: postID, body: trimmed, parentCommentID: comment.id)
        if succeeded {
            replyDraft = ""
            onCancelReply?()
        }
    }

    @ViewBuilder
    private var commentContent: some View {
        HStack(alignment: .top, spacing: 10) {
            NavigationLink(value: BoardRoute.profile(authorProfile)) {
                AvatarView(profile: authorProfile, size: .xsmall)
            }
            .buttonStyle(.plain)
            .disabled(isBeingEdited)

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text(authorProfile.displayName)
                        .fontStyle(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text("@\(authorProfile.handle)")
                        .fontStyle(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Text("· \(comment.createdAt.boardRelativeAge)")
                        .fontStyle(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .layoutPriority(1)

                    Spacer()

                    // Own comments: edit/delete while the week is active.
                    // Others' comments: report/block — available even on
                    // archived weeks, since the content is still visible.
                    if editingCommentID == nil, (isInteractive && canEdit) || !canEdit {
                        Menu {
                            if isInteractive, canEdit {
                                Button {
                                    onBeginEdit?(comment.id, comment.body)
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                Button(role: .destructive) {
                                    onDelete?(comment.id)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            if !canEdit {
                                Button {
                                    onReport?(comment)
                                } label: {
                                    Label("Report Comment", systemImage: "flag")
                                }
                                if comment.authorId != nil {
                                    Button(role: .destructive) {
                                        onBlockAuthor?(comment)
                                    } label: {
                                        Label("Block @\(comment.author)", systemImage: "hand.raised")
                                    }
                                }
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .fontStyle(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if isBeingEdited {
                    TextField("Comment", text: $draftCommentBody, axis: .vertical)
                        .fontStyle(.callout)
                        .foregroundStyle(.primary)
                        .textFieldStyle(.plain)
                        .lineLimit(1...8)
                        .focused($isEditorFocused)
                        // Multi-line editing: confirmed via the toolbar "Save" button. Return
                        // inserts a newline instead of submitting, so a pasted line break or a
                        // deliberate paragraph no longer silently ends the edit.
                } else {
                    Text(comment.body)
                        .fontStyle(.callout)
                        .foregroundStyle(.primary)
                }

                if !isBeingEdited {
                    HStack(spacing: 4) {
                        CommentVoteBar(
                            likeCount: comment.likeCount,
                            dislikeCount: comment.dislikeCount,
                            selected: selectedVote,
                            isInteractive: isInteractive && editingCommentID == nil
                        )

                        if isInteractive && editingCommentID == nil {
                            Button {
                                onReply?(comment.id)
                            } label: {
                                Label("Reply", systemImage: "arrowshape.turn.up.left")
                                    .fontStyle(.caption)
                                    .foregroundStyle(.secondary)
                                    .labelStyle(.iconOnly)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Reply")
                        }
                    }
                }
            }
            .doubleTapHeart(
                size: 36,
                isEnabled: isInteractive && editingCommentID == nil && !isBeingEdited,
                isLiked: { store.userCommentVote(for: comment.id) == .like },
                onLike: { store.setCommentVote(commentID: comment.id, postID: postID, vote: .like) }
            )
        }
        .padding(.vertical, isBeingEdited ? 10 : 0)
        .opacity(isDimmed ? 0.32 : 1)
        .onAppear {
            guard isBeingEdited else { return }
            isEditorFocused = true
        }
        .onChange(of: isBeingEdited) { _, editing in
            if editing { isEditorFocused = true }
        }
    }
}
