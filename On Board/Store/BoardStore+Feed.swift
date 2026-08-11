//
//  BoardStore+Feed.swift
//  On Board
//
//  Feed composition, split out of BoardStore.swift. The backing caches
//  (`postsByWeek`, `cachedFeedItemsByWeek`, `feedItemsCacheKeys`) stay as
//  stored properties in the core file; this split is the reason they are
//  `internal` rather than `private` there.
//

import Foundation

extension BoardStore {

    // MARK: - Feed composition

    func posts(for week: BoardWeek) -> [Post] {
        postsByWeek[week.id] ?? []
    }

    func feedItems(for week: BoardWeek) -> [FeedItem] {
        let weekPosts = posts(for: week)
        // The compose card shows on any interactive (active, current-board) week.
        // Once posting closes it stays put but renders disabled, so nobody is
        // mid-compose when the weekly wipe lands — and the masonry doesn't reflow the
        // way it would if the card vanished. Archived/read-only weeks show no card at
        // all. ContentView's 60s tick re-reads feedItems, so the enabled→disabled flip
        // happens within a minute of the cutoff.
        //
        // `allowsPosting` (not `!isWithinFinalHour`) because it also covers expiry —
        // otherwise the card flipped back to its tappable "+" the instant the clock hit
        // zero, inviting a post into a week that had already ended.
        let showsNewPost = canInteract(with: week)
        let newPostEnabled = showsNewPost
            && BoardSchedule.phase(weekEnd: week.endsAt, thresholds: boardThresholds).allowsPosting
        let cacheKey = FeedItemsCacheKey(
            postSignatures: weekPosts.map { "\($0.id.uuidString)-\($0.tone.rawValue)" },
            showsNewPost: showsNewPost,
            newPostEnabled: newPostEnabled,
            adsEligible: adsEligible
        )

        if feedItemsCacheKeys[week.id] == cacheKey,
           let cached = cachedFeedItemsByWeek[week.id] {
            return cached
        }

        var items: [FeedItem] = [.countdown(week: week, isArchived: week.isReadOnly)]
        if showsNewPost {
            items.append(.newPost(isEnabled: newPostEnabled, weekID: week.id))
        }
        // Promoted slots are woven into the *post run* only — never among the
        // countdown/compose header cards, which is what keeps them out of the
        // first viewport regardless of how the masonry happens to balance.
        let slots = Set(AdSlotPlanner.slotPositions(
            postCount: weekPosts.count,
            isEligible: adsEligible,
            isReadOnly: week.isReadOnly
        ))
        var slotOrdinal = 0
        for (index, post) in weekPosts.enumerated() {
            if slots.contains(index) {
                items.append(.promoted(slot: slotOrdinal, weekID: week.id))
                slotOrdinal += 1
            }
            items.append(.post(id: post.id, tone: post.tone))
        }

        cachedFeedItemsByWeek[week.id] = items
        feedItemsCacheKeys[week.id] = cacheKey
        return items
    }

    var feedItems: [FeedItem] {
        guard let activeBoardWeek else { return [] }
        return feedItems(for: activeBoardWeek)
    }

    var hasFeedPosts: Bool {
        feedItems.contains { if case .post = $0 { return true }; return false }
    }
}
