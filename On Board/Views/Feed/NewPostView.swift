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
    @Environment(RemoteConfigStore.self) private var remoteConfig
    @Environment(\.photoAttachmentsEnabled) private var photoAttachmentsEnabled
    @Environment(BoardStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @AppStorage("hapticsEnabled") private var hapticsEnabled = true
    @AppStorage("profanityEnabled") private var profanityEnabled = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var content = ""
    /// The hesitation loop is the composer's real user: type, lose nerve,
    /// dismiss, come back. See PostDraftStore's header for the slot's rules
    /// (one slot, this week, expires with the final-hour lockout).
    private let draftStore = PostDraftStore()
    /// What the draft slot held when this composer opened — dismissing with
    /// content identical to it needs no dialog (nothing would be lost).
    @State private var restoredDraft = ""
    @State private var showDismissDialog = false
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

    @FocusState private var focus: Field?
    private enum Field { case content }

    private var canSubmit: Bool {
        !content.trimmed.isEmpty
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

                    // ONE field — the old required Title + required body pair
                    // bisected a ~60-character median thought and taxed every
                    // post with summarise-it-first. Structure is opt-in via
                    // markup now (spec: 2026-08-06-post-rich-text.md); the
                    // rich toolbar composer replaces this plain field next.
                    TextField("what's on your mind?", text: $content, axis: .vertical)
                        .textFieldStyle(.boardBody)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(6...14)
                        .keyboardType(.twitter)
                        .focused($focus, equals: .content)
                        .fontStyle(.body)

                    // The countdown lives on the feed; the STAKES live here.
                    // Impermanence is the app's answer to posting anxiety, and
                    // it was invisible at the exact moment of hesitation.
                    Label("clears with the board on monday — nothing here is forever", systemImage: "clock.arrow.circlepath")
                        .fontStyle(.caption)
                        .foregroundStyle(.secondary)

                    Divider()
                    
                    // Image attachment row
                    imageAttachmentRow
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .interactiveDismissDisabled(!content.trimmed.isEmpty && content != restoredDraft)
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
                    // Resigning the keyboard before the sheet's own dismiss
                    // transition starts keeps the two animations from racing —
                    // otherwise the feed underneath can inherit a stale
                    // keyboard-sized safe-area inset that pushes the next
                    // screen's bottom-pinned content up until something else
                    // forces a relayout.
                    Button {
                        // Dialog only when data would actually be lost:
                        // empty, or restored-and-untouched, dismisses silently.
                        if content.trimmed.isEmpty || content == restoredDraft {
                            KeyboardDismisser.dismiss()
                            dismiss()
                        } else {
                            showDismissDialog = true
                        }
                    } label: {
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
                let allowsPosting = BoardSchedule.phase(
                    weekEnd: store.activeBoardWeek?.endsAt,
                    thresholds: store.boardThresholds
                ).allowsPosting
                if content.isEmpty,
                   let draft = draftStore.restore(weekID: store.activeBoardWeek?.id,
                                                  allowsPosting: allowsPosting) {
                    content = draft
                    restoredDraft = draft
                }
                focus = .content
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
            .confirmationDialog(
                "Save this as a draft?",
                isPresented: $showDismissDialog,
                titleVisibility: .visible
            ) {
                Button("Save Draft") {
                    draftStore.save(content, weekID: store.activeBoardWeek?.id)
                    KeyboardDismisser.dismiss()
                    dismiss()
                }
                Button("Discard", role: .destructive) {
                    draftStore.clear()
                    KeyboardDismisser.dismiss()
                    dismiss()
                }
                Button("Keep Writing", role: .cancel) {}
            } message: {
                Text("One draft at a time — it clears an hour before the board does.")
            }
            .boardErrorHandling(alertError: $alertError)
            .presentableErrorAlert(error: $alertError)
            .presentableErrorAlert(error: $photo.alertError)
            .onChange(of: photo.selectedPhotoItem) { _, item in
                Task { await photo.loadPickedPhoto(item) }
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

    // MARK: - Image attachment

    private var imageAttachmentRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            if photoAttachmentsEnabled {
                PhotoAttachmentTile(controller: photo, onCapture: { photo.uncroppedImage = $0 })
            }

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
        isWithinFinalHour = !BoardSchedule.phase(weekEnd: weekEnd, thresholds: remoteConfig.config.boardThresholds).allowsPosting
        finalHourBannerText = BoardSchedule.finalHourBannerText(weekEnd: weekEnd, thresholds: remoteConfig.config.boardThresholds)
    }

    // MARK: - Submit

    private func submit() {
        guard canSubmit else { return }
        let resolvedTone = selectedTone ?? .random()
        isSubmitting = true
        Task {
            let succeeded = await store.addPost(
                content: content.trimmed,
                tone: resolvedTone,
                imageUrl: photo.uploadedURL,
                imageAspectRatio: photo.uploadedAspectRatio
            )
            isSubmitting = false
            guard succeeded else { return }
            didSubmit = true
            draftStore.clear()
            KeyboardDismisser.dismiss()
            dismiss()
        }
    }
}

#Preview {
    NewPostView()
        .environment(BoardStore.sampleBoard(currentUserID: SampleProfileID.maya))
        .environment(AuthStore(service: MockAuthService()))
        .environment(RemoteConfigStore())
}
