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

    @Environment(BoardStore.self) private var store
    @FocusState private var isEditorFocused: Bool
    @FocusState private var isReplyFocused: Bool
    @State private var replyDraft = ""
    @State private var isPostingReply = false
    @State private var showHeartBurst = false
    @State private var heartTapLocation: CGPoint = CGPoint(x: 50, y: 10)
    @State private var heartRotation: Double = 0

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
                                onDelete: onDelete
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
                .fontStyle(.subheadline)
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
                                    : Color.accentColor
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
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                    Text("@\(authorProfile.handle)")
                        .fontStyle(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    if isInteractive, editingCommentID == nil, canEdit {
                        Menu {
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
                        } label: {
                            Image(systemName: "ellipsis")
                                .fontStyle(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if isBeingEdited {
                    TextField("Comment", text: $draftCommentBody, axis: .vertical)
                        .fontStyle(.subheadline)
                        .foregroundStyle(.primary)
                        .textFieldStyle(.plain)
                        .lineLimit(1...8)
                        .focused($isEditorFocused)
                        .submitLabel(.done)
                        .onSubmit { onConfirmEdit?() }
                        .onChange(of: draftCommentBody) { _, newValue in
                            guard newValue.hasSuffix("\n") else { return }
                            draftCommentBody = String(newValue.dropLast())
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                            onConfirmEdit?()
                        }
                } else {
                    Text(comment.body)
                        .fontStyle(.subheadline)
                        .foregroundStyle(.primary)
                        .overlay {
                            Image(systemName: "heart.fill")
                                .font(.system(size: 36))
                                .foregroundStyle(.red)
                                .opacity(showHeartBurst ? 1 : 0)
                                .scaleEffect(showHeartBurst ? 1 : 0.3)
                                .rotationEffect(.degrees(heartRotation))
                                .animation(.spring(response: 0.3, dampingFraction: 0.55), value: showHeartBurst)
                                .allowsHitTesting(false)
                                .position(heartTapLocation)
                        }
                        .simultaneousGesture(
                            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                                .onChanged { value in heartTapLocation = value.startLocation }
                        )
                        .onTapGesture(count: 2) {
                            guard isInteractive, editingCommentID == nil else { return }
                            guard store.userCommentVote(for: comment.id) != .like else { return }
                            store.setCommentVote(commentID: comment.id, postID: postID, vote: .like)
                            heartRotation = Double.random(in: -5...5)
                            showHeartBurst = true
                            Task {
                                try? await Task.sleep(for: .milliseconds(700))
                                showHeartBurst = false
                            }
                        }
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
