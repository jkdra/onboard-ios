//
//  FavoriteTone.swift
//  On Board
//

import Foundation

/// A user's Favorite Color: the tone they post in most, derived from a
/// server-side tally that survives the weekly clear.
///
/// This is the second piece of identity (after Pop Score) that accretes
/// while the feed stays ephemeral. The board forgets; the profile doesn't.
///
/// Pure value type with `nonisolated` resolution so it can be computed off
/// the main actor and unit-tested without a store.
struct FavoriteTone: Equatable, Sendable {
    let tone: PostTone
    /// Posts in this tone.
    let count: Int
    /// Posts across all tones — the denominator behind `share`.
    let total: Int

    /// 0…1 — how dominant this tone is. A user who posts 9 blues out of 10
    /// has a real favorite; 2 out of 10 is a coincidence, which is what
    /// `minimumShare` below exists to reject.
    nonisolated var share: Double {
        total > 0 ? Double(count) / Double(total) : 0
    }

    /// Below this many posts, a "favorite" is noise — two posts in green
    /// makes green a coincidence, not a trait.
    nonisolated static let minimumPosts = 5

    /// And below this share, no tone is dominant enough to name even with
    /// plenty of posts (a perfectly even spread over 10 tones sits at 0.1).
    nonisolated static let minimumShare = 0.25

    /// Resolves the favorite from a tone tally, or nil when the user hasn't
    /// earned one yet — too few posts, or no tone dominant enough.
    ///
    /// Ties break on a `StableHash` of the user id rather than the enum's
    /// declaration order: order would hand every tied user `blue` (it is
    /// simply first), which would read as a bug the moment two friends
    /// compared profiles. Never `hashValue` — Swift seeds that per process,
    /// so a tie would resolve to a different color on every cold launch.
    nonisolated static func resolve(from counts: [PostTone: Int], userID: UUID) -> FavoriteTone? {
        let total = counts.values.reduce(0, +)
        guard total >= minimumPosts else { return nil }

        let best = counts.filter { $0.value > 0 }.map(\.value).max() ?? 0
        guard best > 0 else { return nil }

        let tied = counts.filter { $0.value == best }.keys.sorted { $0.rawValue < $1.rawValue }
        guard let winner = tied.first else { return nil }
        let tone: PostTone
        if tied.count == 1 {
            tone = winner
        } else {
            let index = Int(StableHash.fnv1a(userID.uuidString) % UInt64(tied.count))
            tone = tied[index]
        }

        let resolved = FavoriteTone(tone: tone, count: best, total: total)
        guard resolved.share >= minimumShare else { return nil }
        return resolved
    }
}
