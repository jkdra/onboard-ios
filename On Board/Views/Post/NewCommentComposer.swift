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

    // Guards against a second submit while the first is in flight — otherwise rapid
    // taps create duplicate comments (the network round-trip leaves the button live).
    @State private var isPosting = false

    private var trimmedEmpty: Bool { draft.trimmed.isEmpty }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            TextField("Add a comment…", text: $draft, axis: .vertical)
                .fontStyle(.subheadline)
                .focused(isFocused)
                .padding(.top, 6)
                .disabled(isPosting)

            Button {
                Task {
                    isPosting = true
                    await onPost()
                    isPosting = false
                }
            } label: {
                if isPosting {
                    ProgressView()
                        .scaleEffect(0.8)
                        .frame(width: 28, height: 28)
                } else {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title)
                        .foregroundStyle(trimmedEmpty ? Color.secondary.opacity(0.4) : tone.color)
                }
            }
            .buttonStyle(.plain)
            .disabled(trimmedEmpty || isPosting)
            .accessibilityLabel("Post comment")
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.secondary.opacity(0.08))
        }
        .opacity(isDisabled ? 0.32 : 1)
        .disabled(isDisabled)
    }
}
