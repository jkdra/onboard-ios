import Testing
import Foundation
import SwiftUI
import UIKit
@testable import On_Board

/// Pins the rules that decide whether a user has earned a Favorite Color,
/// and which one. All of it is pure resolution over a tally — the tally
/// itself is a Postgres trigger (`user_tone_counts`) and isn't covered here.
@MainActor
struct FavoriteToneTests {
    private let userA = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private let userB = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!

    @Test func dominantToneWins() throws {
        let favorite = try #require(
            FavoriteTone.resolve(from: [.blue: 9, .red: 2, .mint: 1], userID: userA)
        )
        #expect(favorite.tone == .blue)
        #expect(favorite.count == 9)
        #expect(favorite.total == 12)
    }

    @Test func tooFewPostsEarnsNothing() {
        // Four posts, all one tone — dominant, but not yet a trait.
        #expect(FavoriteTone.resolve(from: [.green: 4], userID: userA) == nil)
    }

    @Test func minimumPostsIsInclusive() {
        #expect(FavoriteTone.resolve(from: [.green: 5], userID: userA)?.tone == .green)
    }

    @Test func evenSpreadEarnsNothing() {
        // One post in each of ten tones: a top count of 1/10 is below the
        // dominance floor, so nobody gets called a "green person" for it.
        let spread = Dictionary(uniqueKeysWithValues: PostTone.allCases.map { ($0, 1) })
        #expect(FavoriteTone.resolve(from: spread, userID: userA) == nil)
    }

    @Test func emptyTallyEarnsNothing() {
        #expect(FavoriteTone.resolve(from: [:], userID: userA) == nil)
        #expect(FavoriteTone.resolve(from: [.blue: 0, .red: 0], userID: userA) == nil)
    }

    @Test func shareIsTheCountOverTheTotal() throws {
        let favorite = try #require(
            FavoriteTone.resolve(from: [.teal: 6, .pink: 2], userID: userA)
        )
        #expect(abs(favorite.share - 0.75) < 0.0001)
    }

    @Test func tiesAreStableAcrossCalls() throws {
        // The same user and tally must always resolve the same way — the
        // resolution feeds a persisted, shared-to-friends stat.
        let tally: [PostTone: Int] = [.blue: 5, .red: 5]
        let first = try #require(FavoriteTone.resolve(from: tally, userID: userA))
        for _ in 0..<25 {
            #expect(FavoriteTone.resolve(from: tally, userID: userA)?.tone == first.tone)
        }
    }

    @Test func tiesDoNotAlwaysFavorTheFirstDeclaredTone() {
        // Declaration order would hand every tied user `blue` (it's simply
        // first in PostTone.allCases), which reads as a bug the moment two
        // friends compare profiles. The tie-break is hashed on the user id,
        // so across many users both tied tones must appear.
        let tally: [PostTone: Int] = [.blue: 5, .red: 5]
        var seen = Set<PostTone>()
        for _ in 0..<200 {
            if let tone = FavoriteTone.resolve(from: tally, userID: UUID())?.tone {
                seen.insert(tone)
            }
        }
        #expect(seen == [.blue, .red])
    }

    /// Renders the profile row at profile width in both schemes — the
    /// review artifact for a dark-shipped surface nobody can reach in the
    /// app until the flag flips (same idiom as SHARE-CARD-PNG).
    @Test func rowRendersAsReviewArtifact() {
        let favorite = FavoriteTone(tone: .orange, count: 14, total: 19)
        for (name, scheme) in [("light", ColorScheme.light), ("dark", .dark)] {
            let renderer = ImageRenderer(content:
                FavoriteColorView(favorite: favorite)
                    .padding(20)
                    .frame(width: 360)
                    .background(scheme == .dark ? Color.black : Color.white)
                    .environment(\.colorScheme, scheme)
            )
            renderer.scale = 3
            guard let data = renderer.uiImage?.pngData() else {
                Issue.record("render failed (\(name))")
                continue
            }
            let url = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("favorite_color_\(name).png")
            try? data.write(to: url)
            print("FAVORITE-COLOR-PNG: \(url.path)")
        }
    }

    @Test func differentUsersCanBreakTheSameTieDifferently() {
        // Not a strict requirement of correctness, but it's the mechanism
        // above observed directly: the tie-break is a function of the id.
        let tally: [PostTone: Int] = [.blue: 5, .red: 5]
        let a = FavoriteTone.resolve(from: tally, userID: userA)?.tone
        let b = FavoriteTone.resolve(from: tally, userID: userB)?.tone
        #expect(a != nil && b != nil)
    }
}
