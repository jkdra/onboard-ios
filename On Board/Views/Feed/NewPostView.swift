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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var title = ""
    @State private var content = ""
    @State private var tags: [String] = []
    @State private var selectedTone: PostTone? = nil
    @State private var didSubmit = false
    @State private var alertError: PresentableAlertError?
    @State private var isWithinFinalHour = false
    @State private var finalHourBannerText: String?
    @State private var pulseLowOpacity = false

    // Image attachment
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var selectedPhotoData: Data?
    @State private var uploadedImageUrl: String?
    @State private var uploadedAspectRatio: Double?
    @State private var isUploadingImage = false
    @State private var uncroppedPostImage: UIImage?
    @State private var isSubmitting = false
    @State private var showingTagSelection = false

    @FocusState private var focus: Field?
    private enum Field { case title, content }

    private var canSubmit: Bool {
        !title.trimmed.isEmpty && !content.trimmed.isEmpty
            && !isUploadingImage && !isSubmitting && !isWithinFinalHour
    }

    private var previewTone: PostTone? { selectedTone }

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

//                    WeeklyPromptBanner()

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
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(60))
                    updateClearingState()
                }
            }
            .animation(.smooth(duration: 0.3), value: isWithinFinalHour)
            .boardErrorHandling(alertError: $alertError)
            .presentableErrorAlert(error: $alertError)
            .onChange(of: selectedPhotoItem) { _, item in
                Task { await loadPickedPhoto(item) }
            }
            .sheet(isPresented: $showingTagSelection) {
                TagSelectionView(selectedTags: $tags)
            }
            .fullScreenCover(item: Binding<UIImage?>(
                get: { uncroppedPostImage },
                set: { uncroppedPostImage = $0 }
            )) { image in
                PostImageCropView(image: image) { cropped in
                    uncroppedPostImage = nil
                    Task { await uploadCroppedImage(cropped) }
                } onCancel: {
                    uncroppedPostImage = nil
                    selectedPhotoItem = nil
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
            HStack(spacing: 12) {
                let hasImage = selectedPhotoData != nil
                PhotoSourceButton(selection: $selectedPhotoItem, onCapture: { uncroppedPostImage = $0 }) {
                    Label(
                        hasImage ? "Change Image" : "Add Image",
                        systemImage: "photo.badge.plus"
                    )
                }
                .buttonStyle(.boardSecondary)
                .disabled(isUploadingImage)

                if isUploadingImage {
                    ProgressView()
                } else if selectedPhotoData != nil {
                    Button(role: .destructive) {
                        removeImage()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Remove image")
                    }
                    .buttonStyle(.plain)
                }
            }

            if let data = selectedPhotoData, let uiImage = PhotoPreviewCache.image(for: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )
                    .transition(.scale(scale: 0.95).combined(with: .opacity))

                if uploadedImageUrl == nil && !isUploadingImage {
                    Label("Image couldn't be uploaded — post will be text-only.", systemImage: "exclamationmark.triangle")
                        .fontStyle(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .animation(.smooth(duration: 0.25), value: selectedPhotoData != nil)
    }

    // MARK: - Upload

    @MainActor
    private func loadPickedPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        guard let rawData = try? await item.loadTransferable(type: Data.self),
              let uiImage = UIImage(data: rawData) else { return }
        uncroppedPostImage = uiImage
    }

    private func uploadCroppedImage(_ image: UIImage) async {
        // Optimistic preview of the cropped result while it uploads.
        selectedPhotoData = image.jpegData(compressionQuality: 0.85)

        guard let userID = store.currentUserID else { return }

        isUploadingImage = true
        defer { isUploadingImage = false }

        if let result = await ImageUploader.upload(input: .uiImage(image), type: .postPhoto, userID: userID) {
            uploadedImageUrl = result.url
            uploadedAspectRatio = result.aspectRatio
        } else {
            // Upload failed — post goes text-only; preview stays so user sees their image.
            uploadedImageUrl = nil
            uploadedAspectRatio = nil
        }
    }

    private func removeImage() {
        selectedPhotoItem = nil
        selectedPhotoData = nil
        uploadedImageUrl = nil
        uploadedAspectRatio = nil
    }

    // MARK: - Clearing state

    private func updateClearingState() {
        let weekEnd = store.activeBoardWeek?.endsAt
        isWithinFinalHour = BoardSchedule.isWithinFinalHour(weekEnd: weekEnd)
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
                imageUrl: uploadedImageUrl,
                imageAspectRatio: uploadedAspectRatio,
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
