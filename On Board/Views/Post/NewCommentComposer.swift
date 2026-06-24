//
//  NewCommentComposer.swift
//  On Board
//
//  Top-of-section composer for adding a new top-level comment to a post.
//

import SwiftUI

struct NewCommentComposer: View {
    @Binding var draft: String
    var isFocused: FocusState<Bool>.Binding
    let tone: PostTone
    let isDisabled: Bool
    let onPost: () async -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            TextField("Add a comment…", text: $draft, axis: .vertical)
                .fontStyle(.subheadline)
                .focused(isFocused)
                .padding(.top, 6)

            Button {
                Task { await onPost() }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title)
                    .foregroundStyle(draft.trimmed.isEmpty ? Color.secondary.opacity(0.4) : tone.color)
            }
            .buttonStyle(.plain)
            .disabled(draft.trimmed.isEmpty)
            .accessibilityLabel("Post comment")
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.secondary.opacity(0.08))
        }
        .opacity(isDisabled ? 0.32 : 1)
    }
}
