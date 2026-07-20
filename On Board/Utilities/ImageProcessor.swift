import UIKit
import ImageIO
import UniformTypeIdentifiers

enum PhotoType: Sendable {
    case profilePicture
    case postPhoto

    nonisolated var maxDimension: CGFloat {
        switch self {
        case .profilePicture: return 512
        case .postPhoto: return 2048
        }
    }

    nonisolated var compressionQuality: CGFloat {
        switch self {
        case .profilePicture: return 0.70
        case .postPhoto: return 0.82
        }
    }

    nonisolated var bucket: String {
        switch self {
        case .profilePicture: return "avatars"
        case .postPhoto: return "post-images"
        }
    }
}

enum ImageProcessor {
    /// Processes a pre-cropped UIImage for a profile picture.
    /// This respects the user's manual cropping from ImageCropView.
    nonisolated static func processProfilePicture(_ image: UIImage) -> Data? {
        let type = PhotoType.profilePicture
        let scaledImage = image.scaledDown(toMaxDimension: type.maxDimension)
        return scaledImage.jpegData(compressionQuality: type.compressionQuality)
    }

    /// Processes a pre-cropped UIImage for a post photo (e.g. output of
    /// PostImageCropView). Mirrors processProfilePicture's scale-then-encode
    /// shape but uses PhotoType.postPhoto's larger maxDimension/quality.
    nonisolated static func processPostPhoto(_ image: UIImage) -> Data? {
        let type = PhotoType.postPhoto
        let scaledImage = image.scaledDown(toMaxDimension: type.maxDimension)
        return scaledImage.jpegData(compressionQuality: type.compressionQuality)
    }

    /// Processes raw image data (from PhotosPicker) for a post.
    /// This is highly memory-efficient, extracting a downsampled thumbnail directly from the source bytes
    /// without ever decoding the full-resolution bitmap into RAM.
    nonisolated static func processPostPhoto(from rawData: Data) -> Data? {
        let type = PhotoType.postPhoto
        
        let options: [CFString: Any] = [
            kCGImageSourceShouldCache: false
        ]
        
        guard let source = CGImageSourceCreateWithData(rawData as CFData, options as CFDictionary) else {
            return nil
        }
        
        let downsampleOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true, // respects EXIF orientation
            kCGImageSourceThumbnailMaxPixelSize: type.maxDimension
        ]
        
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, downsampleOptions as CFDictionary) else {
            return nil
        }
        
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else {
            return nil
        }
        
        CGImageDestinationAddImage(destination, cgImage, [kCGImageDestinationLossyCompressionQuality: type.compressionQuality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            return nil
        }
        
        return data as Data
    }
    
    /// Extract the aspect ratio (width / height) from raw image data without
    /// fully decoding the image — fast enough to call before uploading.
    nonisolated static func aspectRatio(of data: Data) -> Double? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Double,
              let h = props[kCGImagePropertyPixelHeight] as? Double,
              h > 0 else { return nil }
        return w / h
    }
}

private extension UIImage {
    nonisolated func scaledDown(toMaxDimension maxDim: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0 // Ensure consistent scale for upload
        guard longest > maxDim else {
            // Even when no downscaling is needed, re-render at scale 1.0 so the
            // encoded pixel buffer matches `size` in points. Without this, an
            // input UIImage carrying a non-1.0 scale (e.g. device-native 3x)
            // would silently pass through with a 3x-oversized pixel buffer.
            guard scale != 1.0 else { return self }
            let renderer = UIGraphicsImageRenderer(size: size, format: format)
            return renderer.image { _ in draw(in: CGRect(origin: .zero, size: size)) }
        }
        let scale = maxDim / longest
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { _ in draw(in: CGRect(origin: .zero, size: newSize)) }
    }
}
