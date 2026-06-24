//
//  PostImageUploader.swift
//  On Board
//
//  Supabase Storage upload helper for post images. Isolated here so that
//  Views with #Preview blocks don't need to import Supabase (which bloats
//  JIT thunk compilation past the 30-second preview timeout).
//

import Foundation
import PhotosUI
import Supabase

struct UploadedImageResult {
    let url: String
    let aspectRatio: Double
}

/// Encodes `rawData` as WebP and uploads it to the `post-images` bucket.
/// Returns the public URL + aspect ratio, or nil on failure.
@MainActor
func uploadPostImageData(
    rawData: Data,
    userID: UUID
) async -> UploadedImageResult? {
    guard let uiImage = UIImage(data: rawData),
          let webpData = ImageEncoder.webpData(from: uiImage, quality: 0.82, maxDimension: 2048)
    else { return nil }

    let ratio = ImageEncoder.aspectRatio(of: webpData)

    guard let client = SupabaseClientFactory.client(for: .current) else { return nil }

    let path = "\(userID.uuidString)/\(UUID().uuidString).webp"
    do {
        try await client.storage
            .from("post-images")
            .upload(path, data: webpData, options: FileOptions(contentType: "image/webp", upsert: false))
        let publicURL = try client.storage.from("post-images").getPublicURL(path: path)
        return UploadedImageResult(url: publicURL.absoluteString, aspectRatio: ratio ?? 1.0)
    } catch {
        return nil
    }
}
