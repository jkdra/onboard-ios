import Foundation
import UIKit
import Supabase
import Nuke
import os

struct UploadedImageResult {
    let url: String
    let aspectRatio: Double
}

/// The failure modes that aren't already a native error type from somewhere
/// else in the call chain (Supabase Functions, URLSession) — those propagate
/// as-is so `PresentableAlertError.from(error)` can unwrap them natively.
enum ImageUploadError: LocalizedError {
    case encodingFailed
    case notConfigured
    case invalidUploadURL
    case uploadRejected(statusCode: Int)

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            String(localized: "Couldn't prepare that photo for upload.")
        case .notConfigured:
            String(localized: "Image uploads aren't configured.")
        case .invalidUploadURL:
            String(localized: "The upload server returned an invalid response.")
        case .uploadRejected(let statusCode):
            String(localized: "The photo upload was rejected (status \(statusCode)).")
        }
    }
}

private let logger = Logger(subsystem: "org.onboardapp.onboard", category: "ImageUploader")

enum ImageUploader {
    /// Encodes and uploads an image to the appropriate Supabase bucket based on PhotoType.
    /// Returns the public URL + aspect ratio, or throws on any failure — callers
    /// surface the real error via `PresentableAlertError.from(error)` rather than
    /// a generic "upload failed" with no detail.
    @MainActor
    static func upload(
        input: ImageUploadInput,
        type: PhotoType,
        userID: UUID
    ) async throws -> UploadedImageResult {
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

        guard let encoded else {
            logger.error("Image upload failed: local encode/process step returned nil for \(type.uploadKind, privacy: .public)")
            throw ImageUploadError.encodingFailed
        }
        guard let client = SupabaseClientFactory.client(for: .current) else {
            logger.error("Image upload failed: no Supabase client configured")
            throw ImageUploadError.notConfigured
        }

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

            guard let uploadURL = URL(string: signed.uploadUrl) else {
                logger.error("Image upload failed: sign-image-upload returned an unparseable uploadUrl")
                throw ImageUploadError.invalidUploadURL
            }

            // 2. PUT the bytes straight to R2. Content-Type is unsigned, so we
            //    set it freely without breaking the presigned signature.
            var request = URLRequest(url: uploadURL)
            request.httpMethod = "PUT"
            request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
            let (_, response) = try await URLSession.shared.upload(for: request, from: encoded.data)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                logger.error("Image upload failed: R2 PUT returned status \(status)")
                throw ImageUploadError.uploadRejected(statusCode: status)
            }

            // 3. Prime Nuke's cache so we don't re-download our own upload.
            if let url = URL(string: signed.publicUrl) {
                let imageRequest = ImageRequest(url: url)
                ImagePipeline.shared.cache.storeCachedData(encoded.data, for: imageRequest)
            }

            return UploadedImageResult(url: signed.publicUrl, aspectRatio: encoded.ratio)
        } catch {
            logger.error("Image upload failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }
}

enum ImageUploadInput: @unchecked Sendable {
    case uiImage(UIImage)
    case rawData(Data)
}
