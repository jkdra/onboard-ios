import Foundation
import UIKit
import Supabase
import Nuke

struct UploadedImageResult {
    let url: String
    let aspectRatio: Double
}

enum ImageUploader {
    /// Encodes and uploads an image to the appropriate Supabase bucket based on PhotoType.
    /// Returns the public URL + aspect ratio, or nil on failure.
    @MainActor
    static func upload(
        input: ImageUploadInput,
        type: PhotoType,
        userID: UUID
    ) async -> UploadedImageResult? {
        let encoded: (data: Data, ratio: Double)? = await Task.detached(priority: .userInitiated) {
            let data: Data?
            
            switch input {
            case .uiImage(let image):
                if case .profilePicture = type {
                    data = ImageProcessor.processProfilePicture(image)
                } else {
                    // Fallback if somehow post uses UIImage
                    data = image.jpegData(compressionQuality: type.compressionQuality)
                }
            case .rawData(let raw):
                data = ImageProcessor.processPostPhoto(from: raw)
            }
            
            guard let data = data else { return nil }
            return (data, ImageProcessor.aspectRatio(of: data) ?? 1.0)
        }.value

        guard let encoded else { return nil }
        guard let client = SupabaseClientFactory.client(for: .current) else { return nil }

        let path = "\(userID.uuidString.lowercased())/\(UUID().uuidString).jpg"
        do {
            try await client.storage
                .from(type.bucket)
                .upload(path, data: encoded.data, options: FileOptions(contentType: "image/jpeg", upsert: false))
            
            let publicURL = try client.storage.from(type.bucket).getPublicURL(path: path)
            let urlString = publicURL.absoluteString
            
            // Cache the processed data into Nuke to skip downloading our own upload
            if let url = URL(string: urlString) {
                let request = ImageRequest(url: url)
                ImagePipeline.shared.cache.storeCachedData(encoded.data, for: request)
            }
            
            return UploadedImageResult(url: urlString, aspectRatio: encoded.ratio)
        } catch {
            return nil
        }
    }
}

enum ImageUploadInput: @unchecked Sendable {
    case uiImage(UIImage)
    case rawData(Data)
}
