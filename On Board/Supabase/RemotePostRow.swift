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
    }

    init(from decoder: Decoder) throws {
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
    }

    func toPost(comments: [Comment] = []) -> Post {
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

    private static func decodeReactionCounts(
        from container: KeyedDecodingContainer<CodingKeys>
    ) -> [Reaction: Int] {
        guard let raw = try? container.decode([String: Int].self, forKey: .reactionCounts) else {
            return [:]
        }

        var counts: [Reaction: Int] = [:]
        for (key, value) in raw {
            switch key {
            case "love":
                counts[.like, default: 0] += value
            default:
                if let reaction = Reaction(rawValue: key) {
                    counts[reaction, default: 0] += value
                }
            }
        }
        return counts
    }
}
