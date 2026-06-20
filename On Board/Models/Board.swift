//
//  Board.swift
//  On Board
//
//  A distinct board space. Each board owns its own weekly archive.
//

import Foundation

struct Board: Identifiable, Hashable, Codable {
    var id: UUID
    var name: String
    /// When the board space was created. Used to mark the origin day on the archive calendar.
    var createdAt: Date?

    init(id: UUID = UUID(), name: String, createdAt: Date? = nil) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
    }
}

/// Typed navigation routes for a consistent stack:
/// This Week → Archive → Archived Week → (optional) Post / Profile
enum BoardRoute: Hashable {
    case archive
    case archivedWeek(BoardWeek)
    case post(Post.ID)
    case profile(Profile)
}
