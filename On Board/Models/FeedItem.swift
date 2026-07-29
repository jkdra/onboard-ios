//
//  FeedItem.swift
//  On Board
//

import Foundation

/// A single cell in the home-screen feed.
///
/// The countdown widget and the "new post" card sit inline alongside
/// posts so they share the same staggered, rotated, lazy-grid layout.
/// `id` returns stable string keys for non-post cases so `ForEach`
/// keeps view identity across rebuilds.
enum FeedItem: Identifiable, Equatable {
    case post(id: Post.ID, tone: PostTone)
    case countdown(week: BoardWeek?, isArchived: Bool)
    /// The compose card. `isEnabled` is false once posting closes (final hour and the
    /// expired window) — the card stays in place (so the masonry doesn't reflow) but
    /// renders a disabled "clears soon" state instead of disappearing.
    case newPost(isEnabled: Bool, weekID: UUID)

    var id: String {
        switch self {
        case .post(let postID, let tone):
            "\(postID.uuidString)-\(tone.rawValue)"
        case .countdown(let week, _):
            if let week { "__countdown-\(week.id.uuidString)" } else { "__countdown" }
        // Stable across the enabled→disabled flip so SwiftUI keeps view identity
        // (an in-place update, not a remove/insert that would reshuffle the grid) —
        // but scoped to the week, so the rollover remounts it. With a fully fixed id
        // the card was the one cell that *survived* the weekly reset, visibly
        // reversing its take-down animation while everything around it entered fresh.
        case .newPost(_, let weekID): "__newPost-\(weekID.uuidString)"
        }
    }

    var postID: Post.ID? {
        if case .post(let id, _) = self { id } else { nil }
    }
}
