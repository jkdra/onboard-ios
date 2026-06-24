//
//  CommentComposerView.swift
//  On Board
//

import SwiftUI

struct CommentComposerView: View {
    let postID: UUID
    var parentCommentID: UUID?
    var placeholder: String = "Add a comment…"
    var onPosted: () -> Void

    @Environment(BoardStore.self) private var store
    @FocusState private var isFocused: Bool
    @State private var draft = ""
    @State private var isPosting = false

    private var replyLabel: String? {
        guard let parentCommentID,
              let parent = store.comments(for: postID).comment(with: parentCommentID) else {
            return nil
        }
        return "Replying to \(parent.author)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let replyLabel {
                Text(replyLabel)
                    .fontStyle(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .center, spacing: 10) {
                TextField(placeholder, text: $draft, axis: .vertical)
                    .textFieldStyle(.board)
                    .lineLimit(1...5)
                    .focused($isFocused)

                Button {
                    Task { await post() }
                } label: {
                    if isPosting {
                        ProgressView()
                    } else {
                        Image(systemName: "paperplane.fill")
                    }
                }
                .buttonStyle(.borderless)
                .disabled(isPosting || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel("Post comment")
            }
        }
    }

    private func post() async {
        isPosting = true
        defer { isPosting = false }

        let succeeded = await store.addComment(
            postID: postID,
            body: draft,
            parentCommentID: parentCommentID
        )
        guard succeeded else { return }

        draft = ""
        onPosted()
    }
}
