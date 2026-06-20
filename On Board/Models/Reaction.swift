//
//  Reaction.swift
//  On Board
//

import Foundation

/// The four reaction kinds a user can leave on a post.
///
/// `rawValue` is the wire format used in the Supabase `reactions.type`
/// column. `defaultOrder` is the tie-breaker used when two reactions
/// have identical counts (e.g. in the grid card's top-3 preview).
enum Reaction: String, CaseIterable, Identifiable, Codable {
    case like, dislike, laugh, hug
    var id: String { rawValue }

    /// Stable ordering for tie-breaks: when two reactions have the same
    /// count, the one appearing earlier in this list wins.
    static let defaultOrder: [Reaction] = [.like, .dislike, .laugh, .hug]

    var label: String {
        switch self {
        case .like: "Like"
        case .dislike: "Dislike"
        case .laugh: "Laugh"
        case .hug: "Hug"
        }
    }

    var emoji: String {
        switch self {
        case .like: "❤️"
        case .dislike: "👎"
        case .laugh: "💀"
        case .hug: "🫂"
        }
    }
}
