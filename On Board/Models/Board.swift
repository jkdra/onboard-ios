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
    /// Capitalized campus abbreviation ("IVC") for tight UI slots — widget
    /// eyebrows, Live Activity subtitles. Server column `boards.short_name`,
    /// nullable: older cache blobs and boards without one fall back to `name`
    /// via `displayShortName`.
    var shortName: String?
    /// When the board space was created. Used to mark the origin day on the archive calendar.
    var createdAt: Date?

    /// What tight UI slots should render: the abbreviation when the board has
    /// one, the full name otherwise.
    var displayShortName: String { shortName ?? name }

    init(id: UUID = UUID(), name: String, shortName: String? = nil, createdAt: Date? = nil) {
        self.id = id
        self.name = name
        self.shortName = shortName
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, shortName, createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        shortName = try container.decodeIfPresent(String.self, forKey: .shortName)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
    }
}

/// Typed navigation routes for a consistent stack:
/// This Week → Archive → Archived Week → (optional) Post / Profile
enum BoardRoute: Hashable {
    case archive
    case archivedWeek(BoardWeek)
    case post(Post.ID)
    case postFromProfile(postID: Post.ID, profileID: UUID)
    case profile(Profile)
    case settings

    /// Routes pointing at a *live* post, which stops existing the moment the board
    /// rolls over. Only these get popped on a reset — Archive, Settings, and a
    /// profile are all still perfectly valid on the new week, and evicting someone
    /// from Settings because a timer fired would be its own bug.
    var isLivePostDestination: Bool {
        switch self {
        case .post, .postFromProfile: true
        case .archive, .archivedWeek, .profile, .settings: false
        }
    }
}
