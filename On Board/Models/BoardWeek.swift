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

    var isReadOnly: Bool { status == .archived }

    init(
        id: UUID = UUID(),
        boardId: UUID = SampleBoardID.main,
        startsAt: Date,
        endsAt: Date,
        status: Status,
        archivedAt: Date? = nil
    ) {
        self.id = id
        self.boardId = boardId
        self.startsAt = startsAt
        self.endsAt = endsAt
        self.status = status
        self.archivedAt = archivedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case boardId
        case startsAt
        case endsAt
        case status
        case archivedAt
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        boardId = try container.decodeIfPresent(UUID.self, forKey: .boardId) ?? SampleBoardID.main
        startsAt = try container.decode(Date.self, forKey: .startsAt)
        endsAt = try container.decode(Date.self, forKey: .endsAt)
        status = try container.decode(Status.self, forKey: .status)
        archivedAt = try container.decodeIfPresent(Date.self, forKey: .archivedAt)
    }
}
