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
enum FeedItem: Identifiable {
    case post(id: Post.ID, tone: PostTone)
    case countdown(week: BoardWeek?, isArchived: Bool)
    case newPost

    var id: String {
        switch self {
        case .post(let postID, let tone):
            "\(postID.uuidString)-\(tone.rawValue)"
        case .countdown(let week, _):
            if let week { "__countdown-\(week.id.uuidString)" } else { "__countdown" }
        case .newPost: "__newPost"
        }
    }

    var postID: Post.ID? {
        if case .post(let id, _) = self { id } else { nil }
    }
}
