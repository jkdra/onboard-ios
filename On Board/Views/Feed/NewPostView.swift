//
//  NewPostView.swift
//  On Board
//
//  Composer for a new board post. Presented as a sheet from the `+`
//  card on the home grid. Supports an optional image attachment
//  (encoded as WebP client-side before upload).
//

import SwiftUI
import PhotosUI
import Supabase

struct NewPostView: View {
    @Environment(BoardStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @AppStorage("hapticsEnabled") private var hapticsEnabled = true
    @AppStorage("profanityEnabled") private var profanityEnabled = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var title = ""
    @State private var content = ""
    @State private var tags: [String] = []
    @State private var selectedTone: PostTone? = nil
    @State private var didSubmit = false
    @State private var alertError: PresentableAlertError?
    /// True whenever posting is closed — the final hour *and* the expired window
    /// between the deadline and the new week landing. Named for the common case; see
    /// `updateClearingState`.
    @State private var isWithinFinalHour = false
    @State private var finalHourBannerText: String?
    @State private var pulseLowOpacity = false

    // Image attachment
    @State private var photo = PhotoAttachmentController(type: .postPhoto)
    @State private var isSubmitting = false
    @State private var showingTagSelection = false

    @FocusState private var focus: Field?
    private enum Field { case title, content }

    private var canSubmit: Bool {
        !title.trimmed.isEmpty && !content.trimmed.isEmpty
            && !photo.isUploading && !isSubmitting && !isWithinFinalHour
    }

    private var previewTone: PostTone? { selectedTone }

    /// The board's weekly prompt, profanity-gated exactly like `CountdownCard`.
    /// `nil` when the week has no prompt — the banner is then hidden entirely.
    private var weeklyPrompt: String? {
        let week = store.activeBoardWeek
        if profanityEnabled, let profane = week?.promptProfane, !profane.trimmed.isEmpty {
            return profane
        }
        if let clean = week?.promptClean, !clean.trimmed.isEmpty {
            return clean
        }
        return nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                // 16pt, matching the profile/post editors' rhythm — the glass
                // fields below take their true layout space (no compensated
                // padding), so this is the actual visible gap.
                VStack(alignment: .leading, spacing: 16) {
                    if let bannerText = finalHourBannerText {
                        HStack(spacing: 8) {
                            Image(systemName: "clock.badge.exclamationmark.fill")
                                .foregroundStyle(.red)
                            Text("\(bannerText) — posting is closed")
                                .fontStyle(.footnote)
                                .foregroundStyle(.primary)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.red.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.red.opacity(0.25), lineWidth: 0.8))
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    if let weeklyPrompt {
                        WeeklyPromptBanner(prompt: weeklyPrompt)
                    }

                    // Glass fields — the same "you can touch this" chrome and
                    // context-matched typography as the post/profile editors,
                    // so composing a post and editing one speak one language.
                    TextField("Title", text: $title, axis: .vertical)
                        .textFieldStyle(.boardTitle)
                        .fixedSize(horizontal: false, vertical: true)
                        .fontStyle(.largeTitle)
                        .lineLimit(1...3)
                        .keyboardType(.default)
                        .textInputAutocapitalization(.sentences)
                        .focused($focus, equals: .title)

                    TextField("what's on your mind?", text: $content, axis: .vertical)
                        .textFieldStyle(.boardBody)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(4...12)
                        .keyboardType(.twitter)
                        .focused($focus, equals: .content)
                        .fontStyle(.body)
                        
                    Divider()
                    
                    tagsRow

                    // Image attachment row
                    imageAttachmentRow
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .disabled(isSubmitting)
            .background {
                ZStack {
                    (previewTone?.color ?? Color.gray)
                        .opacity(previewTone == nil ? 0.06 : 0.20)
                        .ignoresSafeArea()
                    AnimatedStripesView(
                        color: previewTone?.color ?? .primary,
                        opacity: previewTone == nil ? 0.05 : 0.10,
                        isActive: true
                    )
                    if isWithinFinalHour {
                        LinearGradient(
                            colors: [Color.red.opacity(pulseLowOpacity ? 0.08 : 0.22), Color.clear],
                            startPoint: .top, endPoint: .bottom
                        )
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                        .onAppear {
                            guard !reduceMotion else { return }
                            withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
                                pulseLowOpacity = true
                            }
                        }
                    }
                }
                .animation(.smooth(duration: 0.3), value: previewTone)
            }
            .navigationTitle("New Post")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Label("Cancel", systemImage: "xmark").fontWeight(.semibold)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { submit() } label: {
                        if isSubmitting {
                            ProgressView()
                        } else {
                            Label("Post", systemImage: "paperplane.fill").fontWeight(.semibold)
                        }
                    }
                    .tint(previewTone?.color ?? Color(uiColor: .label))
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSubmit)
                    .sensoryFeedback(.success, trigger: didSubmit) { _, _ in hapticsEnabled }
                }
                ToolbarItem(placement: .bottomBar) {
                    TonePicker(selection: $selectedTone, showBackground: false)
                }
            }
            .keyboardDoneToolbar()
            .onAppear {
                focus = .title
                updateClearingState()
            }
            .task {
                // 15s, not 60s: at 60s the composer could sit enabled for most of a
                // minute past the cutoff. The store-side guard in `addPost` still
                // rejects a late submit, but failing an attempt is worse than never
                // offering it.
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(15))
                    updateClearingState()
                }
            }
            // The sheet deliberately survives the weekly reset — a typed draft is the
            // user's work, and silently discarding it to play an animation they can't
            // even see behind the sheet would be the worse trade. Recompute the instant
            // the week actually turns over so the composer reopens against the new board.
            .onChange(of: store.activeBoardWeek?.id) { _, _ in
                updateClearingState()
            }
            .animation(.smooth(duration: 0.3), value: isWithinFinalHour)
            .boardErrorHandling(alertError: $alertError)
            .presentableErrorAlert(error: $alertError)
            .presentableErrorAlert(error: $photo.alertError)
            .onChange(of: photo.selectedPhotoItem) { _, item in
                Task { await photo.loadPickedPhoto(item) }
            }
            .sheet(isPresented: $showingTagSelection) {
                TagSelectionView(selectedTags: $tags)
            }
            .fullScreenCover(item: $photo.uncroppedImage) { image in
                PostImageCropView(image: image) { cropped in
                    photo.uncroppedImage = nil
                    guard let userID = store.currentUserID else { return }
                    Task {
                        await photo.uploadCropped(
                            cropped,
                            userID: userID,
                            revertPreviewOnFailure: false,
                            alertOnFailure: false
                        )
                    }
                } onCancel: {
                    photo.uncroppedImage = nil
                    photo.selectedPhotoItem = nil
                }
            }
        }
    }

    // MARK: - Image attachment & Tags
    
    private var tagsRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Tags (\(tags.count)/3)", systemImage: "number")
                    .fontStyle(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(tags.isEmpty ? "Add Tags" : "Edit") {
                    showingTagSelection = true
                }
                .fontStyle(.subheadline)
            }
            
            if !tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(tags, id: \.self) { tag in
                            Text("#\(tag)")
                                .fontStyle(.caption)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.primary.opacity(0.1))
                                .clipShape(Capsule())
                        }
                    }
                }
            }
        }
    }

    private var imageAttachmentRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            PhotoAttachmentTile(controller: photo, onCapture: { photo.uncroppedImage = $0 })

            if photo.uploadFailed {
                Label("Image couldn't be uploaded — post will be text-only.", systemImage: "exclamationmark.triangle")
                    .fontStyle(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Clearing state

    private func updateClearingState() {
        let weekEnd = store.activeBoardWeek?.endsAt
        // `allowsPosting` rather than `isWithinFinalHour` so an expired week keeps the
        // composer locked. It also *reopens* the composer the moment a new week lands,
        // which is what lets a draft ride through the rollover and post to the new board.
        isWithinFinalHour = !BoardSchedule.phase(weekEnd: weekEnd).allowsPosting
        finalHourBannerText = BoardSchedule.finalHourBannerText(weekEnd: weekEnd)
    }

    // MARK: - Submit

    private func submit() {
        guard canSubmit else { return }
        let resolvedTone = selectedTone ?? .random()
        isSubmitting = true
        Task {
            let succeeded = await store.addPost(
                title: title.trimmed,
                description: content.trimmed,
                tone: resolvedTone,
                imageUrl: photo.uploadedURL,
                imageAspectRatio: photo.uploadedAspectRatio,
                tags: tags
            )
            isSubmitting = false
            guard succeeded else { return }
            didSubmit = true
            dismiss()
        }
    }
}

#Preview {
    NewPostView()
        .environment(BoardStore.sampleBoard(currentUserID: SampleProfileID.maya))
        .environment(AuthStore(service: MockAuthService()))
}
