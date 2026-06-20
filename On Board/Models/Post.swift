//
//  Post.swift
//  On Board
//

import Foundation

/// A single board post.
///
/// Posts are surfaced for the current week and cleared every Monday at
/// midnight (local time). The struct is `Codable` so it can round-trip
/// with the Supabase `posts` table — configure the decoder with
/// `.keyDecodingStrategy = .convertFromSnakeCase` and
/// `.dateDecodingStrategy = .iso8601` to map columns directly.
///
/// Equality / hashing are by `id` only so a `Post` value stays stable
/// in navigation paths and `ForEach` identities even when its content
/// (reaction counts, comments, etc.) is refreshed from the server.
struct Post: Identifiable, Hashable, Codable {
    /// Server-assigned UUID. Locally-constructed posts get a fresh UUID
    /// via the init default; the backend overwrites it on insert.
    var id: UUID

    /// Foreign key into `profiles` once auth is wired. Nullable so
    /// legacy / anonymous posts still decode cleanly.
    let authorId: UUID?

    /// The board week this post belongs to (`board_weeks.id` in Supabase).
    let boardWeekId: UUID?

    /// When true, the post is from an archived week — view-only (no react,
    /// comment, edit, or new posts on that week).
    let isReadOnly: Bool

    var title: String
    var description: String

    /// Denormalized display name copy for fast rendering without a
    /// `profiles` join. Should mirror the linked profile's display name.
    let author: String

    /// The visual tint applied to the post on the board. Picked by the
    /// composer (either explicitly or randomized client-side at submit).
    var tone: PostTone

    /// Aggregated reaction counts. Computed server-side or on the client
    /// from the raw `reactions` table; never written directly to Supabase.
    var reactionCounts: [Reaction: Int]
    var comments: [Comment]

    /// When the post was created on the server. Drives chronological
    /// sorting and the "2h ago" labels.
    let createdAt: Date

    init(
        id: UUID = UUID(),
        authorId: UUID? = nil,
        boardWeekId: UUID? = nil,
        isReadOnly: Bool = false,
        title: String,
        description: String,
        author: String,
        tone: PostTone = .random(),
        reactionCounts: [Reaction: Int] = [:],
        comments: [Comment] = [],
        createdAt: Date = .now
    ) {
        self.id = id
        self.authorId = authorId
        self.boardWeekId = boardWeekId
        self.isReadOnly = isReadOnly
        self.title = title
        self.description = description
        self.author = author
        self.tone = tone
        self.reactionCounts = reactionCounts
        self.comments = comments
        self.createdAt = createdAt
    }

    func assigning(boardWeekId: UUID?, isReadOnly: Bool) -> Post {
        Post(
            id: id,
            authorId: authorId,
            boardWeekId: boardWeekId,
            isReadOnly: isReadOnly,
            title: title,
            description: description,
            author: author,
            tone: tone,
            reactionCounts: reactionCounts,
            comments: comments,
            createdAt: createdAt
        )
    }

    static func == (lhs: Post, rhs: Post) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
