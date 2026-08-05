//
//  BoardWeek.swift
//  On Board
//
//  A Monday–Monday board period. Posts belong to exactly one week.
//  When a week is archived, its posts remain readable but read-only.
//

import Foundation

struct BoardWeek: Identifiable, Hashable, Codable {
    enum Status: String, Codable {
        case active
        case archived
    }

    var id: UUID
    let boardId: UUID
    let startsAt: Date
    let endsAt: Date
    let status: Status
    let archivedAt: Date?
    let promptClean: String?
    let promptProfane: String?
    /// Total posts in this week, from the `list_board_weeks` RPC's aggregate —
    /// not derived from `BoardStore.posts(for:)`, which is only populated for
    /// weeks whose feed has actually been opened/fetched.
    let postCount: Int

    var isReadOnly: Bool { status == .archived }

    init(
        id: UUID = UUID(),
        boardId: UUID = SampleBoardID.main,
        startsAt: Date,
        endsAt: Date,
        status: Status,
        archivedAt: Date? = nil,
        promptClean: String? = nil,
        promptProfane: String? = nil,
        postCount: Int = 0
    ) {
        self.id = id
        self.boardId = boardId
        self.startsAt = startsAt
        self.endsAt = endsAt
        self.status = status
        self.archivedAt = archivedAt
        self.promptClean = promptClean
        self.promptProfane = promptProfane
        self.postCount = postCount
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case boardId
        case startsAt
        case endsAt
        case status
        case archivedAt
        case promptClean
        case promptProfane
        case postCount
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        boardId = try container.decode(UUID.self, forKey: .boardId)
        startsAt = try container.decode(Date.self, forKey: .startsAt)
        endsAt = try container.decode(Date.self, forKey: .endsAt)
        status = Self.decodeStatus(from: container)
        archivedAt = try container.decodeIfPresent(Date.self, forKey: .archivedAt)
        promptClean = try container.decodeIfPresent(String.self, forKey: .promptClean)
        promptProfane = try container.decodeIfPresent(String.self, forKey: .promptProfane)
        postCount = try container.decodeIfPresent(Int.self, forKey: .postCount) ?? 0
    }

    /// Unknown statuses decode as `.archived` rather than throwing.
    ///
    /// A status added server-side would otherwise fail the whole
    /// `list_board_weeks` response and leave the app with no board at all.
    /// `.archived` (read-only) is the safer of the two landing spots: statuses
    /// get added to express *new restrictions* (frozen, locked, moderated), not
    /// new permissions, so read-only is the more likely-correct reading. It also
    /// never costs the user written work — `.active` would let them compose a
    /// post the server then rejects.
    ///
    /// The real fix for an old client seeing an unknown status is to prompt it
    /// to update; that arrives with the version gate. This keeps it alive until
    /// then.
    nonisolated private static func decodeStatus(
        from container: KeyedDecodingContainer<CodingKeys>
    ) -> Status {
        guard let raw = try? container.decode(String.self, forKey: .status) else {
            return .archived
        }
        return Status(rawValue: raw) ?? .archived
    }
}
