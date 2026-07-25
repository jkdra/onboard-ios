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
                switch type {
                case .profilePicture:
                    data = ImageProcessor.processProfilePicture(image)
                case .postPhoto:
                    data = ImageProcessor.processPostPhoto(image)
                }
            case .rawData(let raw):
                data = ImageProcessor.processPostPhoto(from: raw)
            }
            
            guard let data = data else { return nil }
            return (data, ImageProcessor.aspectRatio(of: data) ?? 1.0)
        }.value

        guard let encoded else { return nil }
        guard let client = SupabaseClientFactory.client(for: .current) else { return nil }

        // Response from the `sign-image-upload` Edge Function. `nonisolated
        // init(from:)` mirrors RemotePostRow/InsertedID — the module defaults to
        // MainActor isolation, but decoding happens in a concurrent context, so
        // the Decodable conformance must be nonisolated. CodingKeys are the
        // camelCase spellings the decoder produces from `upload_url`/`public_url`
        // via .convertFromSnakeCase — never the snake_case raw values (that's the
        // keyNotFound landmine).
        struct SignedUpload: Decodable {
            let uploadUrl: String
            let publicUrl: String
            nonisolated init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                uploadUrl = try c.decode(String.self, forKey: .uploadUrl)
                publicUrl = try c.decode(String.self, forKey: .publicUrl)
            }
            private enum CodingKeys: String, CodingKey { case uploadUrl, publicUrl }
        }

        do {
            // 1. Ask the server for a short-lived presigned R2 PUT URL. The
            //    Edge Function derives the user id from the JWT and owns the
            //    bucket/prefix/domain config — no R2 secrets ship in the app.
            let signed: SignedUpload = try await client.functions.invoke(
                "sign-image-upload",
                options: FunctionInvokeOptions(body: ["kind": type.uploadKind]),
                decoder: BoardJSON.decoder
            )

            guard let uploadURL = URL(string: signed.uploadUrl) else { return nil }

            // 2. PUT the bytes straight to R2. Content-Type is unsigned, so we
            //    set it freely without breaking the presigned signature.
            var request = URLRequest(url: uploadURL)
            request.httpMethod = "PUT"
            request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
            let (_, response) = try await URLSession.shared.upload(for: request, from: encoded.data)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }

            // 3. Prime Nuke's cache so we don't re-download our own upload.
            if let url = URL(string: signed.publicUrl) {
                let imageRequest = ImageRequest(url: url)
                ImagePipeline.shared.cache.storeCachedData(encoded.data, for: imageRequest)
            }

            return UploadedImageResult(url: signed.publicUrl, aspectRatio: encoded.ratio)
        } catch {
            return nil
        }
    }
}

enum ImageUploadInput: @unchecked Sendable {
    case uiImage(UIImage)
    case rawData(Data)
}
