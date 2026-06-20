//
//  NewPostView.swift
//  On Board
//
//  Composer for a new board post. Presented as a sheet from the `+`
//  card on the home grid.
//

import SwiftUI

struct NewPostView: View {
    @Environment(BoardStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @AppStorage("hapticsEnabled") private var hapticsEnabled = true

    @State private var title = ""
    @State private var content = ""
    /// `nil` ⇒ "Any Color!" — a random tone is picked at submit time.
    @State private var selectedTone: PostTone? = nil
    @State private var didSubmit = false

    @FocusState private var focus: Field?
    private enum Field { case title, content }

    private var canSubmit: Bool {
        !title.trimmed.isEmpty && !content.trimmed.isEmpty
    }

    /// Tone used for the live preview tint. Falls back to a soft
    /// neutral when the user hasn't picked one yet.
    private var previewTone: PostTone? { selectedTone }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    TextField("Title", text: $title, axis: .vertical)
                        .fontStyle(.largeTitle)
                        .lineLimit(1...3)
                        .textInputAutocapitalization(.never)
                        .focused($focus, equals: .title)

                    TextField("what's on your mind?", text: $content, axis: .vertical)
                        .lineLimit(4...12)
                        .focused($focus, equals: .content)
                        .fontStyle(.body)

                    Divider()

                    HStack {
                        TonePicker(selection: $selectedTone)
                        Spacer()
                    }

                    Button {
                        submit()
                    } label: {
                        Label("Post", systemImage: "tray.and.arrow.up.fill")
                    }
                    .buttonStyle(.boardPrimary)
                    .disabled(!canSubmit)
                    .sensoryFeedback(.success, trigger: didSubmit) { _, _ in
                        hapticsEnabled
                    }
                    .padding(.top, 4)
                }
                .padding(20)
            }
            .background {
                ZStack {
                    (previewTone?.color ?? Color.gray)
                        .opacity(previewTone == nil ? 0.06 : 0.20)
                        .ignoresSafeArea()

                    StripesOverlay(
                        color: previewTone?.color ?? .primary,
                        opacity: previewTone == nil ? 0.05 : 0.10
                    )
                }
                .animation(.smooth(duration: 0.3), value: previewTone)
            }
            .navigationTitle("New Post")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Label("Cancel", systemImage: "xmark")
                    }
                }
            }
            .onAppear { focus = .title }
        }
    }

    private func submit() {
        guard canSubmit else { return }
        let resolvedTone = selectedTone ?? .random()
        Task {
            await store.addPost(
                title: title.trimmed,
                description: content.trimmed,
                tone: resolvedTone
            )
            didSubmit = true
            dismiss()
        }
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

#Preview {
    NewPostView()
        .environment(BoardStore.sampleBoard(currentUserID: SampleProfileID.maya))
}
