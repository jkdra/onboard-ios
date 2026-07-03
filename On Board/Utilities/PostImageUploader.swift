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
    // Decode + re-orient + downscale + WebP-encode are CPU/memory heavy (a 12MP photo
    // decodes to ~48MB). Run them OFF the main actor so the composer UI doesn't hitch;
    // only the lightweight upload await resumes back on the caller's actor.
    let encoded: (data: Data, ratio: Double)? = await Task.detached(priority: .userInitiated) {
        guard let uiImage = UIImage(data: rawData),
              let webpData = ImageEncoder.webpData(from: uiImage, quality: 0.82, maxDimension: 2048)
        else { return nil }
        return (webpData, ImageEncoder.aspectRatio(of: webpData) ?? 1.0)
    }.value

    guard let encoded else { return nil }
    guard let client = SupabaseClientFactory.client(for: .current) else { return nil }

    // Storage RLS checks the path's folder segment against `auth.uid()::text`, which
    // Postgres always renders lowercase — `UUID.uuidString` is uppercase, so an
    // un-lowercased path silently fails the policy check on every upload.
    let path = "\(userID.uuidString.lowercased())/\(UUID().uuidString).webp"
    do {
        try await client.storage
            .from("post-images")
            .upload(path, data: encoded.data, options: FileOptions(contentType: "image/webp", upsert: false))
        let publicURL = try client.storage.from("post-images").getPublicURL(path: path)
        return UploadedImageResult(url: publicURL.absoluteString, aspectRatio: encoded.ratio)
    } catch {
        return nil
    }
}
