//
//  Comment.swift
//  On Board
//

import Foundation

/// A comment on a `Post`, optionally with nested replies.
///
/// In Supabase, comments are stored flat with a `parent_comment_id`
/// foreign key. The client builds the recursive `replies` tree from
/// that flat list at decode-time so the UI can render threads
/// without extra plumbing.
struct Comment: Identifiable, Hashable, Codable {
    var id: UUID

    /// Foreign key into `profiles` once auth is wired. Nullable so
    /// legacy / anonymous comments still decode cleanly.
    let authorId: UUID?

    /// Denormalized display name copy for fast rendering.
    let author: String

    var body: String
    var likeCount: Int
    var dislikeCount: Int
    var replies: [Comment]
    let createdAt: Date

    init(
        id: UUID = UUID(),
        authorId: UUID? = nil,
        author: String,
        body: String,
        likeCount: Int = 0,
        dislikeCount: Int = 0,
        replies: [Comment] = [],
        createdAt: Date = .now
    ) {
        self.id = id
        self.authorId = authorId
        self.author = author
        self.body = body
        self.likeCount = likeCount
        self.dislikeCount = dislikeCount
        self.replies = replies
        self.createdAt = createdAt
    }

    static func == (lhs: Comment, rhs: Comment) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

extension Array where Element == Comment {
    func comment(with id: UUID) -> Comment? {
        for comment in self {
            if comment.id == id { return comment }
            if let match = comment.replies.comment(with: id) { return match }
        }
        return nil
    }
}

/// Like or dislike on a comment. Stored in Supabase `comment_votes.vote`.
enum CommentVote: String, Codable, CaseIterable, Identifiable {
    case like
    case dislike

    var id: String { rawValue }

    var emoji: String {
        switch self {
        case .like: "👍"
        case .dislike: "👎"
        }
    }

    var systemImage: String {
        switch self {
        case .like: "heart"
        case .dislike: "hand.thumbsdown"
        }
    }

    var selectedSystemImage: String {
        switch self {
        case .like: "heart.fill"
        case .dislike: "hand.thumbsdown.fill"
        }
    }

    var label: String {
        switch self {
        case .like: "Like"
        case .dislike: "Dislike"
        }
    }
}
