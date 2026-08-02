//
//  AdSlotPlanner.swift
//  On Board
//
//  Decides *where* promoted slots go in a week's feed. Pure and synchronous so the
//  density rules — the part users actually feel — are testable without an SDK, a
//  network, or a view.
//
//  The governing principle from the roadmap: sparse and obvious beats dense and
//  subtle. Salience is not what makes ads hated; interruption, repetition, layout
//  shift, and accidental taps are. So these rules buy visibility cheaply and spend
//  nothing on frequency.
//

import Foundation

enum AdSlotPlanner {
    /// Cards between promoted slots. The roadmap's recommended range is 8–12; 10
    /// sits in the middle and keeps a slot from appearing twice in one viewport at
    /// any plausible card height.
    static let cardsBetweenSlots = 10

    /// Post cards that must precede the first slot. The opening of a board is the
    /// product — an ad in the first viewport is the single fastest way to make the
    /// week feel like inventory rather than a campus.
    static let cardsBeforeFirstSlot = 6

    /// Upper bound per feed build. Even on a very long board the point is to be
    /// noticed a few times, not to farm impressions.
    static let maxSlotsPerFeed = 5

    /// Indices *within the post run* after which a promoted slot should follow.
    ///
    /// Returns empty when the user isn't eligible (First Class), when the board is
    /// read-only, or when the week is too short to earn a slot — each of which is a
    /// deliberate silence rather than an edge case.
    ///
    /// - Parameters:
    ///   - postCount: how many post cards the week has.
    ///   - isEligible: `AdsGateway.isEligibleForAds`.
    ///   - isReadOnly: archived weeks never carry ads.
    static func slotPositions(
        postCount: Int,
        isEligible: Bool,
        isReadOnly: Bool
    ) -> [Int] {
        guard isEligible, !isReadOnly else { return [] }
        guard postCount > cardsBeforeFirstSlot else { return [] }

        var positions: [Int] = []
        var next = cardsBeforeFirstSlot
        while next < postCount, positions.count < maxSlotsPerFeed {
            positions.append(next)
            next += cardsBetweenSlots
        }
        return positions
    }
}
