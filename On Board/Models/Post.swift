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
    /// legacy / author-less rows (no attached author) still decode cleanly.
    let authorId: UUID?

    /// The board week this post belongs to (`board_weeks.id` in Supabase).
    let boardWeekId: UUID?

    /// When true, the post is from an archived week — view-only (no react,
    /// comment, edit, or new posts on that week).
    let isReadOnly: Bool

    /// The post's full text in board markup (see PostMarkup.swift and the
    /// cross-client spec). One field on purpose — the old required title +
    /// required body split bisected what was, at the median, a ~60-character
    /// thought, and made every post pay a summarise-it-first tax.
    var content: String

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

    let imageUrl: String?

    /// Width / height of the attached image — used to size the image card in
    /// the feed without waiting for the image to download.
    let imageAspectRatio: Double?
    
    /// User-defined tags for organization and discovery.
    var tags: [String]

    var hasImage: Bool { imageUrl != nil }

    /// First non-empty line of the rendered (marker-free) text — what shows in
    /// share sheets, report contexts, and anywhere else that wants "the post"
    /// as a single plain line.
    var previewLine: String {
        PostMarkup.parse(content).plainText
            .split(separator: "\n", omittingEmptySubsequences: true)
            .first.map(String.init) ?? ""
    }

    init(
        id: UUID = UUID(),
        authorId: UUID? = nil,
        boardWeekId: UUID? = nil,
        isReadOnly: Bool = false,
        content: String,
        author: String,
        tone: PostTone = .random(),
        reactionCounts: [Reaction: Int] = [:],
        comments: [Comment] = [],
        createdAt: Date = .now,
        imageUrl: String? = nil,
        imageAspectRatio: Double? = nil,
        tags: [String] = []
    ) {
        self.id = id
        self.authorId = authorId
        self.boardWeekId = boardWeekId
        self.isReadOnly = isReadOnly
        self.content = content
        self.author = author
        self.tone = tone
        self.reactionCounts = reactionCounts
        self.comments = comments
        self.createdAt = createdAt
        self.imageUrl = imageUrl
        self.imageAspectRatio = imageAspectRatio
        self.tags = tags
    }

    func assigning(boardWeekId: UUID?, isReadOnly: Bool) -> Post {
        Post(
            id: id,
            authorId: authorId,
            boardWeekId: boardWeekId,
            isReadOnly: isReadOnly,
            content: content,
            author: author,
            tone: tone,
            reactionCounts: reactionCounts,
            comments: comments,
            createdAt: createdAt,
            imageUrl: imageUrl,
            imageAspectRatio: imageAspectRatio,
            tags: tags
        )
    }

    static func == (lhs: Post, rhs: Post) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
