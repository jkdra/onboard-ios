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
    @Binding var draftCommentBody: String
    var onBeginEdit: ((UUID, String) -> Void)?
    var onConfirmEdit: (() -> Void)?

    @Environment(BoardStore.self) private var store
    @FocusState private var isEditorFocused: Bool

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
                                draftCommentBody: $draftCommentBody,
                                onBeginEdit: onBeginEdit,
                                onConfirmEdit: onConfirmEdit
                            )
                        }
                    }
                }
                .padding(.top, 8)
            }
        }
        .animation(.smooth(duration: 0.3), value: editingCommentID)
    }

    @ViewBuilder
    private var commentContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                NavigationLink(value: BoardRoute.profile(authorProfile)) {
                    Text(comment.author)
                        .fontStyle(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .disabled(isBeingEdited)

                Spacer()

                if canEdit, isInteractive, editingCommentID == nil {
                    Menu {
                        Button {
                            onBeginEdit?(comment.id, comment.body)
                        } label: {
                            Label("Edit", systemImage: "pencil")
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
            }

            if !isBeingEdited {
                CommentVoteBar(
                    likeCount: comment.likeCount,
                    dislikeCount: comment.dislikeCount,
                    selected: selectedVote,
                    isInteractive: isInteractive && editingCommentID == nil
                )
            }
        }
        .padding(.vertical, isBeingEdited ? 10 : 0)
        .opacity(isDimmed ? 0.32 : 1)
        .onAppear {
            guard isBeingEdited else { return }
            isEditorFocused = true
        }
        .onChange(of: isBeingEdited) { _, editing in
            if editing {
                isEditorFocused = true
            }
        }
    }
}
