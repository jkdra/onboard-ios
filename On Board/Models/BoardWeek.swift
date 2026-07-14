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
        status = try container.decode(Status.self, forKey: .status)
        archivedAt = try container.decodeIfPresent(Date.self, forKey: .archivedAt)
        promptClean = try container.decodeIfPresent(String.self, forKey: .promptClean)
        promptProfane = try container.decodeIfPresent(String.self, forKey: .promptProfane)
        postCount = try container.decodeIfPresent(Int.self, forKey: .postCount) ?? 0
    }
}
