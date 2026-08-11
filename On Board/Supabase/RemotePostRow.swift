//
//  RemotePostRow.swift
//  On Board
//
//  Decodes the `posts_with_meta` view / RPC shape into app models.
//

import Foundation

struct RemotePostRow: Decodable, Sendable {
    let id: UUID
    let boardWeekId: UUID
    let authorId: UUID
    let author: String
    let title: String
    let description: String
    let tone: PostTone
    let createdAt: Date
    let isReadOnly: Bool
    let reactionCounts: [Reaction: Int]
    let imageUrl: String?
    let imageAspectRatio: Double?
    let tags: [String]

    enum CodingKeys: String, CodingKey {
        case id
        case boardWeekId
        case authorId
        case author
        case title
        case description
        case tone
        case createdAt
        case isReadOnly
        case reactionCounts
        case imageUrl
        case imageAspectRatio
        case tags
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        boardWeekId = try container.decode(UUID.self, forKey: .boardWeekId)
        authorId = try container.decode(UUID.self, forKey: .authorId)
        author = try container.decode(String.self, forKey: .author)
        title = try container.decode(String.self, forKey: .title)
        description = try container.decode(String.self, forKey: .description)
        tone = try container.decode(PostTone.self, forKey: .tone)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        isReadOnly = try container.decode(Bool.self, forKey: .isReadOnly)
        reactionCounts = Self.decodeReactionCounts(from: container)
        imageUrl = try container.decodeIfPresent(String.self, forKey: .imageUrl)
        imageAspectRatio = try container.decodeIfPresent(Double.self, forKey: .imageAspectRatio)
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
    }

    /// Joins the legacy two-column wire shape into single-field markup
    /// content. A pre-migration post's title becomes a real `# ` heading, so
    /// old posts render exactly as they used to — heading over body — through
    /// the one new pipeline. Runs until the schema migration collapses the
    /// columns server-side.
    private func joinedContent(extraTags: [String]) -> String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBody = description.trimmingCharacters(in: .whitespacesAndNewlines)
        var content: String
        if trimmedTitle.isEmpty { content = trimmedBody }
        else if trimmedBody.isEmpty { content = "# \(trimmedTitle)" }
        else { content = "# \(trimmedTitle)\n\(trimmedBody)" }
        // Legacy rows carry tags in their own column; fold them in as a
        // trailing hashtag line (mirroring the server migration) so derived
        // Post.tags sees them. Skipped if the body already contains them.
        let legacyTags = tags.isEmpty ? extraTags : tags
        if !legacyTags.isEmpty, PostMarkup.parse(content).tags.isEmpty {
            let line = legacyTags.map { "#\($0)" }.joined(separator: " ")
            content = content.isEmpty ? line : content + "\n\n" + line
        }
        return content
    }

    /// `extraTags`: the week fetch delivers tags as separate
    /// `fetch_tags_for_week` rows rather than on the post row — pass them in
    /// so a legacy post's tags still fold into its content.
    func toPost(comments: [Comment] = [], extraTags: [String] = []) -> Post {
        Post(
            id: id,
            authorId: authorId,
            boardWeekId: boardWeekId,
            isReadOnly: isReadOnly,
            content: joinedContent(extraTags: extraTags),
            author: author,
            tone: tone,
            reactionCounts: reactionCounts,
            comments: comments,
            createdAt: createdAt,
            imageUrl: imageUrl,
            imageAspectRatio: imageAspectRatio
        )
    }

    nonisolated private static func decodeReactionCounts(
        from container: KeyedDecodingContainer<CodingKeys>
    ) -> [Reaction: Int] {
        guard let raw = try? container.decode([String: Int].self, forKey: .reactionCounts) else {
            return [:]
        }
        var counts: [Reaction: Int] = [:]
        for (key, value) in raw {
            let reaction: Reaction? = switch key {
            case "like":    .like
            case "dislike": .dislike
            case "laugh":   .laugh
            case "hug":     .hug
            case "love":    .like   // legacy alias
            default:        nil
            }
            if let reaction { counts[reaction, default: 0] += value }
        }
        return counts
    }
}
