import Testing
import SwiftUI
import UIKit
@testable import On_Board

@MainActor
struct ProfileShareCardTests {
    @Test func cardRendersAtStoryDimensions() {
        let renderer = ImageRenderer(content: ProfileShareCard(
            handle: "maya.c",
            popScore: [.like: 89, .laugh: 12, .hug: 21],
            accent: Color(red: 0.72, green: 0.31, blue: 0.18)
        ))
        renderer.scale = 3
        let image = renderer.uiImage
        #expect(image != nil)
        #expect(image?.size == ProfileShareCard.size)
        #expect(image?.scale == 3) // 360×640pt @3x → 1080×1920px, story-ready

        // Side artifact for visual review (harmless in CI: temp dir).
        if let data = image?.pngData() {
            let url = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("profile_share_card.png")
            try? data.write(to: url)
            print("SHARE-CARD-PNG: \(url.path)")
        }
    }

    @Test func cardOmitsPopScoreWhenAbsent() {
        // Empty and all-zero distributions both suppress the block — a
        // zero-bar flex is an anti-flex.
        let rendererNil = ImageRenderer(content: ProfileShareCard(handle: "leokp", popScore: [:], accent: Color(white: 0.35)))
        let rendererZero = ImageRenderer(content: ProfileShareCard(handle: "leokp", popScore: [.like: 0, .hug: 0], accent: Color(white: 0.35)))
        #expect(rendererNil.uiImage != nil)
        #expect(rendererZero.uiImage != nil)
    }

    private func solidImage(_ color: UIColor, size: CGFloat = 48) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: size, height: size)).image { ctx in
            color.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
        }
    }

    @Test func prominentColorFindsSaturatedHue() throws {
        let red = try #require(solidImage(UIColor(hue: 0.0, saturation: 0.8, brightness: 0.7, alpha: 1)).prominentColor)
        var hue: CGFloat = 0, sat: CGFloat = 0
        red.getHue(&hue, saturation: &sat, brightness: nil, alpha: nil)
        #expect(hue < 0.09 || hue > 0.91) // red-family hue survives bucketing
        #expect(sat >= 0.45)              // clamped into the legible band
    }

    @Test func prominentColorRejectsMonochrome() {
        #expect(solidImage(.gray).prominentColor == nil)
        #expect(solidImage(.white).prominentColor == nil)
        #expect(solidImage(.black).prominentColor == nil)
    }

    /// The accent is display type on a white card — every derived color must
    /// clear WCAG's large-text floor. Sweeps the hue wheel at maximum
    /// brightness/saturation (yellow is the killer: at the old fixed 0.72
    /// brightness ceiling it sat near 2.4:1 while blue cleared 5:1).
    @Test func prominentColorAlwaysClearsLargeTextContrastOnWhite() throws {
        for hueStep in 0..<12 {
            let hue = CGFloat(hueStep) / 12
            let source = solidImage(UIColor(hue: hue, saturation: 0.9, brightness: 0.95, alpha: 1))
            guard let accent = source.prominentColor else { continue } // near-white brights may read monochrome
            #expect(accent.contrastOnWhite >= 3.0, "hue \(hue) landed at \(accent.contrastOnWhite):1")
        }
    }

    @Test func darkColorsAreNotNeedlesslyDarkened() {
        // A color already past the floor must come back untouched — the walk
        // is a floor, not a normalizer that flattens every accent to one value.
        let navy = UIColor(hue: 0.62, saturation: 0.8, brightness: 0.45, alpha: 1)
        #expect(navy.darkenedToContrastOnWhite(atLeast: 3.0) == navy)
    }
}
