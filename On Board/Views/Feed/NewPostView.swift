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

    @State private var title = ""
    @State private var content = ""
    @State private var selectedTone: PostTone? = nil
    @State private var didSubmit = false
    @State private var alertError: PresentableAlertError?

    // Image attachment
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var selectedPhotoData: Data?
    @State private var uploadedImageUrl: String?
    @State private var uploadedAspectRatio: Double?
    @State private var isUploadingImage = false

    @FocusState private var focus: Field?
    private enum Field { case title, content }

    private var canSubmit: Bool {
        !title.trimmed.isEmpty && !content.trimmed.isEmpty && !isUploadingImage
    }

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

                    // Image attachment row
                    imageAttachmentRow

                    Button {
                        submit()
                    } label: {
                        Label("Post", systemImage: "tray.and.arrow.up.fill")
                    }
                    .buttonStyle(.boardPrimary)
                    .disabled(!canSubmit)
                    .sensoryFeedback(.success, trigger: didSubmit) { _, _ in hapticsEnabled }
                    .padding(.top, 4)
                }
                .padding(20)
            }
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
                }
                .animation(.smooth(duration: 0.3), value: previewTone)
            }
            .navigationTitle("New Post")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Label("Cancel", systemImage: "xmark") }
                }
                ToolbarItem(placement: .bottomBar) { Spacer() }
                ToolbarItem(placement: .bottomBar) {
                    TonePicker(selection: $selectedTone, showBackground: false)
                }
                ToolbarItem(placement: .bottomBar) { Spacer() }
            }
            .onAppear { focus = .title }
            .boardErrorHandling(alertError: $alertError)
            .presentableErrorAlert(error: $alertError)
            .onChange(of: selectedPhotoItem) { _, item in
                Task { await loadAndUpload(item) }
            }
        }
    }

    // MARK: - Image attachment

    private var imageAttachmentRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    Label(
                        selectedPhotoData == nil ? "Add Image" : "Change Image",
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
                    }
                    .buttonStyle(.plain)
                }
            }

            if let data = selectedPhotoData, let uiImage = UIImage(data: data) {
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
    private func loadAndUpload(_ item: PhotosPickerItem?) async {
        guard let item else { return }

        guard let rawData = try? await item.loadTransferable(type: Data.self),
              let uiImage = UIImage(data: rawData) else { return }

        isUploadingImage = true
        defer { isUploadingImage = false }

        // Encode as WebP client-side — smaller and faster to upload
        guard let webpData = ImageEncoder.webpData(from: uiImage, quality: 0.82, maxDimension: 2048) else {
            selectedPhotoData = rawData // still show preview, but no URL
            return
        }

        let ratio = ImageEncoder.aspectRatio(of: webpData)
        // Show preview using original data (UIImage can't display its own WebP output easily)
        selectedPhotoData = rawData

        guard let client = SupabaseClientFactory.client(for: .current),
              let userID = store.currentUserID else { return }

        let path = "\(userID.uuidString)/\(UUID().uuidString).webp"
        do {
            try await client.storage
                .from("post-images")
                .upload(path, data: webpData, options: FileOptions(contentType: "image/webp", upsert: false))
            let publicURL = try client.storage.from("post-images").getPublicURL(path: path)
            uploadedImageUrl = publicURL.absoluteString
            uploadedAspectRatio = ratio
        } catch {
            // Upload failed — post goes text-only; preview stays so user sees their image
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

    // MARK: - Submit

    private func submit() {
        guard canSubmit else { return }
        let resolvedTone = selectedTone ?? .random()
        Task {
            let succeeded = await store.addPost(
                title: title.trimmed,
                description: content.trimmed,
                tone: resolvedTone,
                imageUrl: uploadedImageUrl,
                imageAspectRatio: uploadedAspectRatio
            )
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
