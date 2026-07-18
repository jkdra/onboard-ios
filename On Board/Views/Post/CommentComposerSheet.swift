//
//  CommentComposerSheet.swift
//  On Board
//
//  Full-screen expansion of the inline comment composer. Shares the same
//  CommentComposerState — the draft and reply target travel between the
//  inline field and the sheet untouched. Dismissing returns to the inline
//  composer; a successful post lands back in browse state (submitComposer's
//  finishPosting clears the target, which this view reads as "done").
//

import SwiftUI

struct CommentComposerSheet: View {
    @Binding var composer: CommentComposerState
    let tone: PostTone
    let onPost: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @FocusState private var isFocused: Bool
    @State private var isPosting = false

    private var trimmedEmpty: Bool { composer.draft.trimmed.isEmpty }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                if case .reply(_, let handle) = composer.target {
                    HStack(spacing: 6) {
                        Image(systemName: "arrowshape.turn.up.left.fill")
                            .fontStyle(.caption2)
                        Text("Replying to @\(handle)")
                            .fontStyle(.caption)
                    }
                    .foregroundStyle(.secondary)
                }

                TextField("Add a comment…", text: $composer.draft, axis: .vertical)
                    .fontStyle(.body)
                    .keyboardType(.twitter)
                    .focused($isFocused)
                    .disabled(isPosting)
                    .frame(maxHeight: .infinity, alignment: .top)

                Button {
                    Task {
                        isPosting = true
                        await onPost()
                        isPosting = false
                        if !composer.isComposing { dismiss() }
                    }
                } label: {
                    LoadingButtonLabel("Post", systemImage: "arrow.up", isLoading: isPosting)
                }
                .buttonStyle(.boardPrimary)
                .disabled(trimmedEmpty || isPosting)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background {
                tone.color
                    .opacity(scheme == .dark ? 0.25 : 0.20)
                    .ignoresSafeArea()
            }
            .navigationTitle(composer.target?.isReply == true ? "Reply" : "New Comment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.down")
                    }
                    .accessibilityLabel("Collapse composer")
                }
            }
            .keyboardDoneToolbar()
            .scrollDismissesKeyboard(.interactively)
            .onAppear { isFocused = true }
        }
        .interactiveDismissDisabled(isPosting)
    }
}

#Preview {
    @Previewable @State var composer: CommentComposerState = {
        var c = CommentComposerState()
        c.beginNewComment()
        return c
    }()
    CommentComposerSheet(composer: $composer, tone: .green, onPost: {})
}
