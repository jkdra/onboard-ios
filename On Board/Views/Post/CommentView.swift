//
//  CommentView.swift
//  On Board
//

import SwiftUI

struct CommentView: View {
    let postID: UUID
    let comment: Comment
    let tone: PostTone
    var isInteractive: Bool = true
    var editingCommentID: UUID?
    var replyTargetID: UUID?
    @Binding var draftCommentBody: String
    var onBeginEdit: ((UUID, String) -> Void)?
    var onConfirmEdit: (() -> Void)?
    var onReply: ((Comment) -> Void)?
    var onDelete: ((UUID) -> Void)?
    var onReport: ((Comment) -> Void)?
    var onBlockAuthor: ((Comment) -> Void)?

    @Environment(BoardStore.self) private var store
    @FocusState private var isEditorFocused: Bool
    @State private var isCollapsed = false
    @AppStorage("hapticsEnabled") private var hapticsEnabled: Bool = true

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

            if !comment.replies.isEmpty {
                Group {
                    if isCollapsed {
                        collapsedRepliesPill
                    } else {
                        HStack(alignment: .top, spacing: 0) {
                            threadLine

                            VStack(alignment: .leading, spacing: 14) {
                                ForEach(comment.replies) { reply in
                                    CommentView(
                                        postID: postID,
                                        comment: reply,
                                        tone: tone,
                                        isInteractive: isInteractive,
                                        editingCommentID: editingCommentID,
                                        replyTargetID: replyTargetID,
                                        draftCommentBody: $draftCommentBody,
                                        onBeginEdit: onBeginEdit,
                                        onConfirmEdit: onConfirmEdit,
                                        onReply: onReply,
                                        onDelete: onDelete,
                                        onReport: onReport,
                                        onBlockAuthor: onBlockAuthor
                                    )
                                }
                            }
                        }
                    }
                }
                .padding(.top, 8)
                .sensoryFeedback(trigger: isCollapsed) { _, _ in
                    hapticsEnabled ? .impact(weight: .light) : nil
                }
            }
        }
        .animation(.smooth(duration: 0.3), value: editingCommentID)
    }

    /// The 2pt visible capsule sits centered in a 14pt strip whose hit area is
    /// inset a further -5pt on each side (≥24pt effective target) — the line
    /// itself is far too thin to tap.
    private var threadLine: some View {
        Button {
            withAnimation(.smooth(duration: 0.3)) { isCollapsed = true }
        } label: {
            Capsule(style: .continuous)
                .fill(tone.color.opacity(isDimmed ? 0.12 : 0.30))
                .frame(width: 2)
                .frame(width: 14)
                .contentShape(Rectangle().inset(by: -5))
                .opacity(isDimmed ? 0.32 : 1)
        }
        .buttonStyle(.plain)
        .disabled(editingCommentID != nil)
        .accessibilityLabel("Collapse replies")
    }

    private var collapsedRepliesPill: some View {
        let hiddenCount = comment.threadCount - 1
        return Button {
            withAnimation(.smooth(duration: 0.3)) { isCollapsed = false }
        } label: {
            Label("Show \(hiddenCount) \(hiddenCount == 1 ? "reply" : "replies")", systemImage: "chevron.down")
                .fontStyle(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule(style: .continuous).fill(tone.color.opacity(0.12)))
        }
        .buttonStyle(.plain)
        .disabled(editingCommentID != nil)
        .accessibilityLabel("Expand \(hiddenCount) hidden \(hiddenCount == 1 ? "reply" : "replies")")
        .padding(.leading, 14)
        .opacity(isDimmed ? 0.32 : 1)
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
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(authorProfile.handle)
                            .fontStyle(.caption)
                            .fontWeight(.heavy)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        Text("· \(comment.createdAt.boardRelativeAge)")
                            .fontStyle(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .layoutPriority(1)

                        Spacer(minLength: 28)
                    }

                    if isBeingEdited {
                        TextField("Comment", text: $draftCommentBody, axis: .vertical)
                            .fontStyle(.callout)
                            .keyboardType(.twitter)
                            .foregroundStyle(.primary)
                            .textFieldStyle(.plain)
                            .lineLimit(1...8)
                            .focused($isEditorFocused)
                            .onChange(of: draftCommentBody) { _, newValue in
                                if newValue.count > 280 {
                                    draftCommentBody = String(newValue.prefix(280))
                                }
                            }
                            // Multi-line editing: confirmed via the toolbar "Save" button. Return
                            // inserts a newline instead of submitting, so a pasted line break or a
                            // deliberate paragraph no longer silently ends the edit.
                    } else {
                        Text(comment.body)
                            .fontStyle(.callout)
                            .foregroundStyle(.primary)
                    }
                }
                .doubleTapHeart(
                    size: 36,
                    isEnabled: isInteractive && editingCommentID == nil && !isBeingEdited,
                    isLiked: { store.userCommentVote(for: comment.id) == .like },
                    onLike: { store.setCommentVote(commentID: comment.id, postID: postID, vote: .like) }
                )
                .overlay(alignment: .topTrailing) {
                    // Own comments: edit/delete while the week is active.
                    // Others' comments: report/block — available even on
                    // archived weeks, since the content is still visible.
                    // Kept as a sibling overlay (not inside the doubleTapHeart-wrapped
                    // VStack above) so its tap target never competes with the
                    // double-tap gesture's arbitration.
                    if editingCommentID == nil, isInteractive, canEdit {
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
                                .frame(minWidth: 44, minHeight: 44)
                                .contentShape(.rect)
                                .accessibilityLabel("Comment options")
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
                                onReply?(comment)
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
        .background {
            if replyTargetID == comment.id {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(tone.color.opacity(0.10))
                    .padding(-6)
                    .transition(.opacity)
            }
        }
        .animation(.smooth(duration: 0.3), value: replyTargetID)
        .contextMenu {
            ShareLink(item: comment.body) {
                Label("Share Comment", systemImage: "square.and.arrow.up")
            }
            if !canEdit {
                Button(role: .destructive) {
                    onReport?(comment)
                } label: {
                    Label("Report", systemImage: "flag")
                }
            }
        }
        .id(comment.id)
        .onAppear {
            guard isBeingEdited else { return }
            isEditorFocused = true
        }
        .onChange(of: isBeingEdited) { _, editing in
            if editing { isEditorFocused = true }
        }
    }
}
