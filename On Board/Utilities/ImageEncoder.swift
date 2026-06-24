//
//  ImageEncoder.swift
//  On Board
//
//  WebP encoding via CGImageDestination. WebP is the ideal format for
//  post images: ~30% smaller than JPEG at equivalent quality, supported
//  natively on iOS 14+ for both decode and encode.
//

import UIKit
import ImageIO
import UniformTypeIdentifiers

enum ImageEncoder {
    /// Encode a UIImage to WebP data.
    /// - Parameters:
    ///   - image: Source image (will be re-oriented to .up before encoding).
    ///   - quality: Lossy quality 0–1. 0.82 is a good default for photo content.
    ///   - maxDimension: Long edge cap in pixels. Downscales before encoding.
    /// - Returns: WebP data, or nil if encoding fails.
    static func webpData(
        from image: UIImage,
        quality: CGFloat = 0.82,
        maxDimension: CGFloat = 2048
    ) -> Data? {
        let oriented = image.normalized()
        let scaled = oriented.scaledDown(toMaxDimension: maxDimension)
        guard let cgImage = scaled.cgImage else { return nil }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.webP.identifier as CFString,
            1,
            nil
        ) else { return nil }

        CGImageDestinationAddImage(
            destination,
            cgImage,
            [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    /// Extract the aspect ratio (width / height) from raw image data without
    /// fully decoding the image — fast enough to call before uploading.
    static func aspectRatio(of data: Data) -> Double? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Double,
              let h = props[kCGImagePropertyPixelHeight] as? Double,
              h > 0 else { return nil }
        return w / h
    }
}

private extension UIImage {
    /// Re-draw into a .up orientation so CGImageDestination doesn't need EXIF.
    func normalized() -> UIImage {
        guard imageOrientation != .up else { return self }
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in draw(in: CGRect(origin: .zero, size: size)) }
    }

    func scaledDown(toMaxDimension maxDim: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxDim else { return self }
        let scale = maxDim / longest
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in draw(in: CGRect(origin: .zero, size: newSize)) }
    }
}
