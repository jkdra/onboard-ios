import UIKit

nonisolated extension UIImage {
    /// The image's most prominent SATURATED color — used to tint a single
    /// accent (e.g. the handle on the profile share card) from an avatar.
    /// Downsamples to 24×24, buckets sufficiently-colorful pixels by hue,
    /// and averages the winning bucket. Returns nil when the image is
    /// effectively monochrome (callers fall back to a neutral), so a
    /// black-and-white avatar never produces a muddy fake accent.
    var prominentColor: UIColor? {
        let side = 24
        guard let cgImage else { return nil }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        guard let context = CGContext(
            data: &pixels, width: side, height: side,
            bitsPerComponent: 8, bytesPerRow: side * 4, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .medium
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))

        // 12 hue buckets; a pixel votes only if it's actually colorful.
        var bucketVotes = [Int](repeating: 0, count: 12)
        var bucketSums = [(h: CGFloat, s: CGFloat, b: CGFloat)](repeating: (0, 0, 0), count: 12)
        for i in stride(from: 0, to: pixels.count, by: 4) {
            guard pixels[i + 3] > 128 else { continue } // skip transparent
            let color = UIColor(
                red: CGFloat(pixels[i]) / 255,
                green: CGFloat(pixels[i + 1]) / 255,
                blue: CGFloat(pixels[i + 2]) / 255,
                alpha: 1
            )
            var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0
            color.getHue(&h, saturation: &s, brightness: &b, alpha: nil)
            guard s > 0.25, b > 0.2, b < 0.95 else { continue }
            let bucket = min(11, Int(h * 12))
            bucketVotes[bucket] += 1
            bucketSums[bucket].h += h
            bucketSums[bucket].s += s
            bucketSums[bucket].b += b
        }

        guard let winner = bucketVotes.indices.max(by: { bucketVotes[$0] < bucketVotes[$1] }),
              bucketVotes[winner] >= (side * side) / 20 else { return nil } // ≥5% colorful
        let count = CGFloat(bucketVotes[winner])
        return UIColor(
            hue: bucketSums[winner].h / count,
            // Clamp toward legible-on-white: saturated enough to read as a
            // color, dark enough to hold contrast as display type.
            saturation: min(0.85, max(0.45, bucketSums[winner].s / count)),
            brightness: min(0.72, max(0.35, bucketSums[winner].b / count)),
            alpha: 1
        )
    }
}
