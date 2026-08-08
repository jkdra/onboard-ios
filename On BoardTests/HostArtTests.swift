import Testing
import SwiftUI
@testable import On_Board

// Pins the Host vector data: every glyph parses to a non-empty path whose
// bounds land inside (and substantially fill) the target rect, and the
// PDF→SwiftUI y-flip puts the body's mouth notch on the correct side.
struct HostArtTests {
    private static let allArt: [(String, HostPathData)] = [
        ("bodyIdle", HostArt.bodyIdle), ("bodySpeech", HostArt.bodySpeech),
        ("eyeNeutral", HostArt.eyeNeutral), ("eyeHappy", HostArt.eyeHappy),
        ("eyeSad", HostArt.eyeSad), ("eyeAngry", HostArt.eyeAngry),
        ("eyeLove", HostArt.eyeLove), ("eyeDead", HostArt.eyeDead),
        ("eyeBugged", HostArt.eyeBugged),
        ("articleSweat", HostArt.articleSweat), ("articleAnger", HostArt.articleAnger),
    ]

    @Test func everyGlyphParsesAndFillsItsRect() {
        let rect = CGRect(x: 0, y: 0, width: 100, height: 100)
        for (name, art) in Self.allArt {
            let bounds = art.path(in: rect).boundingRect
            #expect(!bounds.isEmpty, "\(name) parsed to an empty path")
            #expect(rect.insetBy(dx: -0.5, dy: -0.5).contains(bounds), "\(name) escapes its rect: \(bounds)")
            #expect(bounds.width > 50 || bounds.height > 50, "\(name) suspiciously small: \(bounds)")
        }
    }

    @Test func yFlipPutsMouthNotchOnUpperRight() {
        // In PDF space the notch vertex (2948, 2080) sits mid-height; the
        // notch OPENS toward y=2912–1247 (upper half in PDF = y-up). After
        // the flip, the notch's inner vertex must be in the upper half of
        // SwiftUI space... it is mid-right: x far right, y near middle.
        // Cheap proxy: the path must NOT contain a point just left of the
        // right edge at 40% height (inside the notch cut), but MUST contain
        // one at 80% height (solid body).
        let rect = CGRect(x: 0, y: 0, width: 3513, height: 4267)
        let path = HostArt.bodyIdle.path(in: rect)
        let inNotch = CGPoint(x: 3400, y: 4267 * 0.40)
        let inBody = CGPoint(x: 3400, y: 4267 * 0.80)
        #expect(!path.contains(inNotch), "notch region unexpectedly solid — y-flip is wrong")
        #expect(path.contains(inBody), "body region unexpectedly empty")
    }

    @Test func speechNotchIsSmallerThanIdle() {
        // Speech = smaller mouth. The notch area difference shows up as a
        // larger filled area for the speech body at equal rect.
        let rect = CGRect(x: 0, y: 0, width: 351, height: 427)
        func filledSamples(_ art: HostPathData) -> Int {
            let path = art.path(in: rect)
            var hits = 0
            for x in stride(from: 2, to: 350, by: 7) {
                for y in stride(from: 2, to: 426, by: 7) where path.contains(CGPoint(x: x, y: y)) {
                    hits += 1
                }
            }
            return hits
        }
        #expect(filledSamples(HostArt.bodySpeech) > filledSamples(HostArt.bodyIdle))
    }
}
